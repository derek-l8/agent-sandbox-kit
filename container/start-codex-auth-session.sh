#!/usr/bin/env bash

set -euo pipefail
check-codex-login-boundaries
exec /usr/local/bin/run-with-codex-auth "$@"
