#!/usr/bin/env bash

set -euo pipefail
check-claude-login-boundaries
exec /usr/local/bin/run-with-claude-auth "$@"
