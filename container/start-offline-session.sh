#!/usr/bin/env bash

set -euo pipefail
check-offline-boundaries
find /workspace -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a /source/. /workspace/
exec "$@"

