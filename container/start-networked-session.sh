#!/usr/bin/env bash

set -euo pipefail
check-networked-boundaries
exec /usr/local/bin/run-with-project-auth "$@"
