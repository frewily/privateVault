#!/bin/zsh
set -eu
pv_root="${0:A:h:h}"
exec python3 "$pv_root/tools/prepare_core_macos.py" "$@"
