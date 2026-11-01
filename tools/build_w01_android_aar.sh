#!/bin/zsh
set -eu
source "${0:A:h}/w01_android_env.sh"
pv_mobile=v0.0.0-20261011034528-197770444867
[[ -x "$PV_GO_ROOT/bin/go" ]] || { print -u2 'Prepare the pinned shared Go input first.'; exit 2; }
[[ -d "$pv_root/.tools/src/openlist-v4.2.8" ]] || { print -u2 'Prepare the pinned source input first.'; exit 2; }
for pv_tool in gomobile gobind; do
  if [[ ! -x "$GOBIN/$pv_tool" ]]; then
    go install "golang.org/x/mobile/cmd/$pv_tool@$pv_mobile"
  fi
done
python3 "$pv_root/tools/stage_w01_android_bridge.py"
cd "$pv_root/.tools/src/openlist-v4.2.8"
[[ "$(go list -m -f '{{.Version}}' golang.org/x/mobile)" == "$pv_mobile" ]] || exit 2
# Only modules reachable from this binding are acquired; never download all.
export GOFLAGS='-p=4 -mod=readonly'
pv_build_id="$(python3 -c 'import json; print(json.load(open(".privatevault-overlay.json"))["build_id"])')"
gomobile bind -target=android/arm64 -androidapi=24 \
  -bootclasspath="$ANDROID_HOME/platforms/android-36/android.jar" \
  -javapkg=dev.privatevault.nativebridge -tags=sqlite_cgo_compat -trimpath \
  -ldflags="-X github.com/OpenListTeam/OpenList/v4/internal/conf.Version=v4.2.8 -X github.com/OpenListTeam/OpenList/v4/internal/conf.GitCommit=25e4eb663ffb73991a68d85df4f690d48ad137a6 -X github.com/OpenListTeam/OpenList/v4/privatevault/pvcore.buildIdentity=$pv_build_id" \
  -o "$pv_root/.local/w01-a/openlist.aar" ./privatevault/pvcore
