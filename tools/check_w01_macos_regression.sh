#!/bin/zsh
set -eu
source "${0:A:h}/shared_toolchain_env.sh"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CI=true FLUTTER_SWIFT_PACKAGE_MANAGER=true
# Missing inputs must fail; the owner's current download allowance is exhausted.
export HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9
export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY"
export NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1
python3 - "$pv_root" <<'PY'
from pathlib import Path
import subprocess,sys
app=Path(sys.argv[1])/'apps/privatevault/build/macos/Build/Products/Debug/PrivateVault W01.app'
owned={str(app/'Contents/MacOS/PrivateVault W01'),str(app/'Contents/Helpers/openlist'),str(app/'Contents/Helpers/core_supervisor')}
running=subprocess.check_output(['/bin/ps','-axo','comm='],text=True).splitlines()
if any(line.strip() in owned for line in running):
    raise SystemExit('Existing PrivateVault test instance is running; do not overwrite it.')
PY
cd "$pv_root/apps/privatevault"
"$FLUTTER_ROOT/bin/flutter" --suppress-analytics --no-version-check test --no-pub -d macos integration_test/w01_macos_test.dart
"$FLUTTER_ROOT/bin/flutter" --suppress-analytics --no-version-check build macos --debug --no-pub
