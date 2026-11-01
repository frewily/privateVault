#!/bin/zsh
# Machine-shared SDKs, project-pinned versions. No installation or downloads here.
pv_root="${${(%):-%N}:A:h:h}"
export FLUTTER_ROOT="$HOME/Library/Developer/flutter/3.47.5"
export PV_GO_ROOT="$HOME/Library/Developer/go/1.27.3"
export GOBIN="$HOME/Library/Developer/gomobile/197770444867"
export GRADLE_HOME="$HOME/Library/Developer/gradle/9.3.1"
export PUB_CACHE="$HOME/.pub-cache"
export GOPATH="$HOME/go"
export GOMODCACHE="$GOPATH/pkg/mod"
export GOCACHE="$HOME/Library/Caches/go-build"
export GRADLE_USER_HOME="$HOME/.gradle"
export GRADLE_RO_DEP_CACHE="$HOME/Library/Caches/Gradle/dependency-seed"
export XDG_CONFIG_HOME="$pv_root/.local/w01/flutter-config"
export PATH="$GOBIN:$PV_GO_ROOT/bin:$GRADLE_HOME/bin:$FLUTTER_ROOT/bin:$PATH"
python3 - "$FLUTTER_ROOT" "$pv_root/toolchains/shared-local.json" <<'PY'
from pathlib import Path
import json,subprocess,sys
sdk=Path(sys.argv[1]); pins=json.loads(Path(sys.argv[2]).read_text())['flutter']
metadata=json.loads((sdk/'bin/cache/flutter.version.json').read_text())
commit=subprocess.check_output(['git','-C',str(sdk),'rev-parse','HEAD'],text=True).strip()
if metadata['frameworkRevision'] != pins['commit'] or commit != pins['commit']:
    raise SystemExit('Shared Flutter differs from the project pin; review instead of upgrading automatically.')
PY
mkdir -p "$XDG_CONFIG_HOME"
