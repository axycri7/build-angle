#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-arm64-v8a}"

if [[ "${TARGET}" != "arm64-v8a" ]]; then
  echo "Unknown Android target \"${TARGET}\"!"
  exit 1
fi

ARCH="arm64"
OUT_DIR="android-${TARGET}"
PACKAGE_DIR="angle-android-${TARGET}"

command -v git >/dev/null || {
  echo 'ERROR: "git" not found'
  exit 1
}

command -v python3 >/dev/null || {
  echo 'ERROR: "python3" not found'
  exit 1
}

command -v zip >/dev/null || {
  echo 'ERROR: "zip" not found'
  exit 1
}

export PATH="${PWD}/depot_tools:${PATH}"

if [[ ! -d depot_tools ]]; then
  git clone --depth=1 --no-tags --single-branch https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

if [[ -z "${ANGLE_COMMIT:-}" ]]; then
  ANGLE_COMMIT="$(git ls-remote https://chromium.googlesource.com/angle/angle HEAD | awk '{ print $1 }')"
fi

if [[ ! -d angle ]]; then
  git init angle
  git -C angle remote add origin https://chromium.googlesource.com/angle/angle
fi

git -C angle fetch --no-recurse-submodules origin "${ANGLE_COMMIT}"
git -C angle reset --hard FETCH_HEAD

pushd angle >/dev/null

DEPOT_TOOLS_PYTHON_BYPASS=1 python3 scripts/bootstrap.py

GCLIENT_FILE="$(gclient root)/.gclient"
if grep -q '^target_os[[:space:]]*=' "${GCLIENT_FILE}"; then
  sed -i.bak -e "s/^target_os[[:space:]]*=.*/target_os = ['android']/" "${GCLIENT_FILE}"
else
  printf "\ntarget_os = ['android']\n" >> "${GCLIENT_FILE}"
fi

sed -i.bak \
  -e "/'third_party\/dawn'\: /,+3d" \
  -e "/'third_party\/llvm\/src'\: /,+3d" \
  -e "/'third_party\/SwiftShader'\: /,+3d" \
  -e "/'third_party\/VK-GL-CTS\/src'\: /,+3d" \
  DEPS

gclient sync -f -D -R

GN_ARGS="target_os=\"android\" target_cpu=\"${ARCH}\" arm_control_flow_integrity=\"none\" is_component_build=false angle_build_all=false is_debug=false angle_has_frame_capture=false angle_enable_gl=false angle_enable_vulkan=true angle_enable_wgpu=false angle_enable_d3d11=false angle_enable_d3d9=false angle_enable_null=false use_siso=false"
gn gen "out/${OUT_DIR}" --args="${GN_ARGS}"
autoninja --offline -C "out/${OUT_DIR}" libEGL libGLESv2 libGLESv1_CM

popd >/dev/null

rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/lib" "${PACKAGE_DIR}/include"

echo "${ANGLE_COMMIT}" > "${PACKAGE_DIR}/commit.txt"

cp "angle/out/${OUT_DIR}/libEGL_angle.so" "${PACKAGE_DIR}/lib/libEGL.so"
cp "angle/out/${OUT_DIR}/libGLESv1_CM_angle.so" "${PACKAGE_DIR}/lib/libGLESv1_CM.so"
cp "angle/out/${OUT_DIR}/libGLESv2_angle.so" "${PACKAGE_DIR}/lib/libGLESv2.so"

cp -R angle/include/KHR "${PACKAGE_DIR}/include/KHR"
cp -R angle/include/EGL "${PACKAGE_DIR}/include/EGL"
cp -R angle/include/GLES "${PACKAGE_DIR}/include/GLES"
cp -R angle/include/GLES2 "${PACKAGE_DIR}/include/GLES2"
cp -R angle/include/GLES3 "${PACKAGE_DIR}/include/GLES3"

find "${PACKAGE_DIR}/include" \( -name .clang-format -o -name '*.md' \) -delete

if [[ -n "${GITHUB_WORKFLOW:-}" ]]; then
  zip -9 -r "${PACKAGE_DIR}-${BUILD_DATE}.zip" "${PACKAGE_DIR}"
fi
