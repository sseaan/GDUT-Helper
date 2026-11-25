#!/usr/bin/env bash
# M0 baseline build helper.
#
# Requires DevEco Studio installed at /Applications/DevEco-Studio.app (override
# with DEVECO_HOME). The bundled SDK is API 26 Beta1 and the bundled hvigor is
# used so no network access is required for the build itself.
set -euo pipefail

DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app}"
SDK_HOME="${DEVECO_HOME}/Contents/sdk"
HVIGOR="${DEVECO_HOME}/Contents/tools/hvigor/bin/hvigorw"
JAVA_HOME="${DEVECO_HOME}/Contents/jbr/Contents/Home"
NODE_HOME="${DEVECO_HOME}/Contents/tools/node"

if [[ ! -x "${HVIGOR}" ]]; then
  echo "hvigorw not found under ${DEVECO_HOME}" >&2
  exit 1
fi

export DEVECO_SDK_HOME="${SDK_HOME}"
export JAVA_HOME
export PATH="${NODE_HOME}/bin:${JAVA_HOME}/bin:${PATH}"

BUILD_MODE="${1:-debug}"

exec "${HVIGOR}" assembleHap \
  --mode module \
  -p product=default \
  -p buildMode="${BUILD_MODE}" \
  --no-daemon
