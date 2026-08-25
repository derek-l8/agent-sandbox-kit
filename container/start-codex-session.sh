#!/usr/bin/env bash

set -euo pipefail
check-codex-networked-boundaries
exec /usr/local/bin/run-with-codex-auth "$@"
