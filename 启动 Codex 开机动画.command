#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -x build/CodexBootAnimation.app/Contents/MacOS/CodexBootAnimation ]]; then
  bash scripts/build.sh
fi
open "$PWD/build/CodexBootAnimation.app" --args --settings
