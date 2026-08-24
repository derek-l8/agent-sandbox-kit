#!/usr/bin/env bash

set -euo pipefail
check-login-boundaries
exec /usr/local/bin/run-with-project-auth "$@"
