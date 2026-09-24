#!/usr/bin/env bash

set -euo pipefail
check-claude-networked-boundaries
exec /usr/local/bin/run-with-claude-auth "$@"
