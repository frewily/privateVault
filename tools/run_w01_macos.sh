#!/bin/zsh
set -eu
source "${0:A:h}/shared_toolchain_env.sh"
pv_xcode="/Applications/Xcode.app/Contents/Developer"
if [[ ! -x "$pv_xcode/usr/bin/xcodebuild" ]]; then
  print -u2 '完整 Xcode 尚未就绪。请完成官方 Xcode 安装和首次启动；不要只安装命令行工具。'
  exit 2
fi
export DEVELOPER_DIR="$pv_xcode"
export CI=true
export FLUTTER_SWIFT_PACKAGE_MANAGER=true
cd "$pv_root"
python3 - "$pv_root" <<'PY'
from pathlib import Path
import subprocess,sys
app=Path(sys.argv[1])/'apps/privatevault/build/macos/Build/Products/Debug/PrivateVault W01.app'
owned={str(app/'Contents/MacOS/PrivateVault W01'),str(app/'Contents/Helpers/openlist'),str(app/'Contents/Helpers/core_supervisor')}
running=subprocess.check_output(['/bin/ps','-axo','comm='],text=True).splitlines()
if any(line.strip() in owned for line in running):
    raise SystemExit('开发版或其核心仍在运行，请先正常停止并退出，再重新构建。')
PY
python3 tools/prepare_core_macos.py --prepare-source
cd apps/privatevault
"$FLUTTER_ROOT/bin/flutter" --suppress-analytics --no-version-check build macos --debug --no-pub
pv_executable="$pv_root/apps/privatevault/build/macos/Build/Products/Debug/PrivateVault W01.app/Contents/MacOS/PrivateVault W01"
if [[ ! -x "$pv_executable" ]]; then
  print -u2 '构建尚未生成可运行的 Mac 开发版，请检查构建结果。'
  exit 2
fi
exec "$pv_executable"
