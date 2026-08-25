#!/usr/bin/env bash

set -euo pipefail

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_bin="${XDG_BIN_HOME:-${HOME}/.local/bin}"
data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
runtime_root="${data_home}/agent-sandbox-kit"
target="${user_bin}/sbx"
runtime_items=(bin adapters config container images versions.lock)

mkdir -p "$user_bin" "$data_home"
if [[ -e "$target" && ! -L "$target" ]]; then
  printf 'ERROR: refusing to overwrite existing file: %s\n' "$target" >&2
  exit 1
fi
if [[ -L "$runtime_root" || ( -e "$runtime_root" && ! -d "$runtime_root" ) ]]; then
  printf 'ERROR: refusing to replace non-directory runtime: %s\n' "$runtime_root" >&2
  exit 1
fi

stage="$(mktemp -d "${data_home}/.agent-sandbox-kit.install.XXXXXX")"
backup=''
committed=false
installed_new=false
link_stage="${user_bin}/.sbx.install.$$"
cleanup() {
  local status=$?
  if [[ "$committed" != true && "$installed_new" == true && -d "$runtime_root" ]]; then
    failed_runtime="${data_home}/.agent-sandbox-kit.failed.$$"
    if mv "$runtime_root" "$failed_runtime"; then
      if [[ -n "$backup" && -d "$backup" ]]; then
        mv "$backup" "$runtime_root" || true
      fi
      rm -rf -- "$failed_runtime"
    fi
  elif [[ "$committed" != true && -n "$backup" && -d "$backup" && ! -e "$runtime_root" ]]; then
    mv "$backup" "$runtime_root" || true
  fi
  [[ ! -d "$stage" ]] || rm -rf -- "$stage"
  [[ ! -L "$link_stage" ]] || rm -- "$link_stage"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

for item in "${runtime_items[@]}"; do
  [[ -e "${kit_root}/${item}" ]] || {
    printf 'ERROR: source runtime item is missing: %s\n' "${kit_root}/${item}" >&2
    exit 1
  }
  cp -a -- "${kit_root}/${item}" "$stage/"
done

for required in \
  bin/sbx bin/sandboxctl adapters/registry.sh adapters/codex.sh adapters/opencode.sh \
  config/codex-config.toml config/codex-requirements.toml config/opencode-managed.json \
  images/codex-networked.Dockerfile images/offline.Dockerfile images/opencode.Dockerfile \
  container/check-common.sh container/check-codex-networked.sh container/check-offline.sh \
  container/check-codex-login.sh container/check-opencode-networked.sh container/check-opencode-login.sh \
  container/prune-auth-volume.sh container/run-with-codex-auth.sh \
  container/run-with-opencode-auth.sh container/start-codex-auth-session.sh \
  container/start-codex-session.sh container/start-offline-session.sh \
  container/start-opencode-auth-session.sh container/start-opencode-session.sh versions.lock; do
  [[ -f "${stage}/${required}" ]] || {
    printf 'ERROR: staged runtime is incomplete: %s\n' "$required" >&2
    exit 1
  }
done
bash -n "$stage/bin/sbx"
bash -n "$stage/bin/sandboxctl"
"$stage/bin/sbx" --help >/dev/null
ln -s "${runtime_root}/bin/sbx" "$link_stage"

if [[ -d "$runtime_root" ]]; then
  backup="$(mktemp -d "${data_home}/.agent-sandbox-kit.backup.XXXXXX")"
  rmdir "$backup"
  mv "$runtime_root" "$backup"
fi
mv "$stage" "$runtime_root"
stage=''
installed_new=true

mv -Tf "$link_stage" "$target"
committed=true
if [[ -n "$backup" ]]; then
  rm -rf -- "$backup"
  backup=''
fi
trap - EXIT HUP INT TERM

printf 'Installed runtime: %s\n' "$runtime_root"
printf 'Installed sbx: %s -> %s\n' "$target" "${runtime_root}/bin/sbx"

case ":${PATH}:" in
  *":${user_bin}:"*) printf 'Run: sbx --help\n' ;;
  *)
    cat <<EOF

${user_bin} is not on PATH. Add this line to your shell profile, then open a
new shell (or run the export in the current shell):

  export PATH="${user_bin}:\$PATH"
EOF
    ;;
esac
