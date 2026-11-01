#!/bin/zsh
set -eu
source "${0:A:h}/w01_android_env.sh"
pv_mode="${1:-debug}"
[[ "$#" -le 1 && ( "$pv_mode" == release || "$pv_mode" == debug ) ]] || { print -u2 'Usage: check_w01_android_unit.sh [release|debug]'; exit 2; }
pv_task=testDebugUnitTest
[[ "$pv_mode" != release ]] || pv_task=testReleaseUnitTest
pv_network_args=(--offline)
if [[ -n "${PV_W01_PROXY:-}" ]]; then
  python3 - "$pv_root/.local/w01-a/network-budget.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]))
if value['accounted_bytes']>=value['limit_bytes']:
    raise SystemExit('Owner download allowance exhausted.')
PY
  pv_network_args=()
fi
pv_ndk_version="$(python3 - "$ANDROID_NDK_HOME/source.properties" <<'PY'
from pathlib import Path
import re,sys
match=re.search(r'^Pkg\.Revision\s*=\s*(\S+)\s*$',Path(sys.argv[1]).read_text(),re.M)
if not match or match.group(1)!='28.2.13676358':
    raise SystemExit('Pinned existing NDK metadata differs.')
print(match.group(1))
PY
)"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  "--packages=$FLUTTER_ROOT/packages/flutter_tools/.dart_tool/package_config.json" \
  "$pv_root/tools/generate_w01_android_plugins.dart" "$pv_root/apps/privatevault" "$pv_mode"
exec "$GRADLE_HOME/bin/gradle" -p "$pv_root/apps/privatevault/android" \
  --no-daemon --console=plain "${pv_network_args[@]}" \
  "-Pflutter.androidSdkRoot=$ANDROID_HOME" "-Pflutter.installedNdkVersions=$pv_ndk_version" \
  -Ptarget-platform=android-arm64 "-Pbuild-mode=$pv_mode" -Ptarget=lib/main.dart ":app:$pv_task"
