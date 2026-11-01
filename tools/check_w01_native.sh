#!/bin/zsh
set -eu
pv_root="${0:A:h:h}"
cd "$pv_root"
mkdir -p .local/w01/swift-cache
if [[ "${PV_W01_SUPERVISED:-0}" == "1" ]]; then
  swiftc -parse-as-library -swift-version 5 -module-cache-path .local/w01/swift-cache \
    apps/privatevault/macos/Helpers/CoreSupervisor.swift -o .local/w01/core_supervisor
  export PV_W01_SUPERVISOR_PATH="$pv_root/.local/w01/core_supervisor"
fi
swiftc -swift-version 5 -module-cache-path .local/w01/swift-cache \
  apps/privatevault/macos/Runner/CoreTypes.swift \
  apps/privatevault/macos/Runner/CoreController.swift \
  apps/privatevault/test/native/CoreHostSmoke.swift \
  -o .local/w01/native-check
.local/w01/native-check \
  "$pv_root/.tools/core/v4.2.8/openlist" \
  "$pv_root/.local/w01/native-runtime" \
  "$pv_root/apps/privatevault/assets/w01_sample.png" "${1:-suite}"
