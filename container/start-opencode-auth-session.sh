#!/usr/bin/env bash

set -euo pipefail
check-opencode-login-boundaries
exec /usr/local/bin/run-with-opencode-auth "$@"
