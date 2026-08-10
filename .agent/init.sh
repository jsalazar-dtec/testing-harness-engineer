#!/usr/bin/env bash
# Como se levanta y se prueba este proyecto NestJS.
set -euo pipefail

if [ ! -d node_modules ]; then
  npm install
fi

npm test --silent
