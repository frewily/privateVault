#!/bin/zsh
set -eu
source "${0:A:h}/shared_toolchain_env.sh"
export CI=true
mkdir -p "$XDG_CONFIG_HOME"
cd "$pv_root/apps/privatevault"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" --suppress-analytics analyze
"$FLUTTER_ROOT/bin/flutter" --suppress-analytics --no-version-check test --no-pub
