#!/usr/bin/env bash

set -euo pipefail

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_bin="${HOME}/.local/bin"
target="${user_bin}/sbx"
source_command="${kit_root}/bin/sbx"

mkdir -p "$user_bin"
if [[ -e "$target" && ! -L "$target" ]]; then
  printf 'ERROR: refusing to overwrite existing file: %s\n' "$target" >&2
  exit 1
fi
ln -sfn "$source_command" "$target"
printf 'Installed sbx: %s -> %s\n' "$target" "$source_command"

case ":${PATH}:" in
  *":${user_bin}:"*) printf 'Run: sbx --help\n' ;;
  *)
    cat <<EOF

${user_bin} is not on PATH. Add this line to your shell profile, then open a
new shell (or run the export in the current shell):

  export PATH="\$HOME/.local/bin:\$PATH"
EOF
    ;;
esac
