#!/bin/zsh
set -eu
source "${0:A:h}/w01_android_env.sh"
pv_mode="${1:-release}"
[[ "$#" -le 1 && ( "$pv_mode" == release || "$pv_mode" == debug ) ]] || { print -u2 'Usage: build_w01_android_apk.sh [release|debug]'; exit 2; }
pv_task=assembleRelease
[[ "$pv_mode" != debug ]] || pv_task=assembleDebug
[[ -f "$pv_root/.local/w01-a/openlist.aar" ]] || { print -u2 'Build and verify the pinned AAR first.'; exit 2; }
[[ -x "$GRADLE_HOME/bin/gradle" ]] || { print -u2 'Prepare the pinned shared Gradle input first.'; exit 2; }
pv_installed_ndk="$(python3 - "$ANDROID_NDK_HOME/source.properties" <<'PY'
from pathlib import Path
import re,sys
metadata=Path(sys.argv[1]).read_text()
match=re.search(r'^Pkg\.Revision\s*=\s*(\S+)\s*$',metadata,re.M)
if not match or match.group(1)!='28.2.13676358':
    raise SystemExit('Pinned existing NDK metadata missing or different; do not install/upgrade automatically.')
print(match.group(1))
PY
)"
python3 "$pv_root/tools/check_w01_android_artifacts.py"
pv_network_args=(--offline)
if [[ -n "${PV_W01_PROXY:-}" ]]; then
  python3 - "$pv_root/.local/w01-a/network-budget.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
if data['accounted_bytes'] >= data['limit_bytes']:
    raise SystemExit('Owner download allowance exhausted; do not reset it automatically.')
PY
  pv_network_args=()
fi
if [[ ! -f "$pv_root/.local/w01-a/debug.keystore" ]]; then
  [[ "$pv_mode" == debug ]] || { print -u2 'Restore the existing W01 signing key for compatible updates; do not replace it.'; exit 2; }
  keytool -genkeypair -keystore "$pv_root/.local/w01-a/debug.keystore" \
    -storepass android -keypass android -alias privatevault-w01 -keyalg RSA -keysize 2048 \
    -validity 3650 -dname 'CN=PrivateVault W01 Debug' -noprompt
  chmod 600 "$pv_root/.local/w01-a/debug.keystore"
fi
python3 - "$pv_root" "$FLUTTER_ROOT" "$ANDROID_HOME" "$pv_mode" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
(root/'apps/privatevault/android/local.properties').write_text(
    'sdk.dir='+sys.argv[3]+'\nflutter.sdk='+sys.argv[2]+
    '\nflutter.buildMode='+sys.argv[4]+'\nflutter.versionName=0.1.0-w01a.2\nflutter.versionCode=2\n')
PY
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  "--packages=$FLUTTER_ROOT/packages/flutter_tools/.dart_tool/package_config.json" \
  "$pv_root/tools/generate_w01_android_plugins.dart" "$pv_root/apps/privatevault" "$pv_mode"
"$GRADLE_HOME/bin/gradle" -p "$pv_root/apps/privatevault/android" \
  --no-daemon --console=plain "${pv_network_args[@]}" \
  "-Pflutter.androidSdkRoot=$ANDROID_HOME" "-Pflutter.installedNdkVersions=$pv_installed_ndk" \
  -Ptarget-platform=android-arm64 "-Pbuild-mode=$pv_mode" -Ptarget=lib/main.dart ":app:$pv_task"
python3 "$pv_root/tools/check_w01_android_apk.py" --mode "$pv_mode"
