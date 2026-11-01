#!/bin/zsh
set -eu
source "${0:A:h}/w01_android_env.sh"
python3 "$pv_root/tools/stage_w01_android_bridge.py"
cd "$pv_root/.tools/src/openlist-v4.2.8"
export PV_W01_FIXTURE_PATH="$pv_root/apps/privatevault/assets/w01_sample.png"
pv_build_id="$(python3 -c 'import json; print(json.load(open(".privatevault-overlay.json"))["build_id"])')"
go test -count=1 -timeout=90s -tags=sqlite_cgo_compat \
  -ldflags="-X github.com/OpenListTeam/OpenList/v4/internal/conf.Version=v4.2.8 -X github.com/OpenListTeam/OpenList/v4/internal/conf.GitCommit=25e4eb663ffb73991a68d85df4f690d48ad137a6 -X github.com/OpenListTeam/OpenList/v4/privatevault/pvcore.buildIdentity=$pv_build_id" \
  ./privatevault/pvcore
