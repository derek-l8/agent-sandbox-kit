#!/usr/bin/env bash

set -euo pipefail
check-opencode-networked-boundaries
exec /usr/local/bin/run-with-opencode-auth "$@"
