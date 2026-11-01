#!/bin/zsh
# Source only from a project entrypoint. Uses the owner's shared, pinned tools.
source "${${(%):-%N}:A:h}/shared_toolchain_env.sh"
[[ -f "$pv_root/toolchains/w01-android.json" ]] || return 2
export GOTOOLCHAIN=local GOENV=off GOMAXPROCS=4
export GOFLAGS='-p=4'
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/Users/frewily/Library/Android/sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export CI=true
export PATH="$JAVA_HOME/bin:$PATH"
if [[ -n "${PV_W01_PROXY:-}" ]]; then
  [[ "$PV_W01_PROXY" == http://127.0.0.1:<-> ]] || return 2
  export HTTPS_PROXY="$PV_W01_PROXY" HTTP_PROXY="$PV_W01_PROXY"
  export https_proxy="$PV_W01_PROXY" http_proxy="$PV_W01_PROXY"
  export NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1
  export GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org
  pv_proxy_port="${PV_W01_PROXY##*:}"
  export JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=$pv_proxy_port -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=$pv_proxy_port -Dhttp.nonProxyHosts=localhost|127.*"
else
  export GOPROXY=off
fi
mkdir -p "$XDG_CONFIG_HOME" "$pv_root/.local/w01-a"
