#!/usr/bin/env bash

# Sourced by the trusted host launcher. Paths are data, never shell code.
context_source_path() {
  local path="$1"
  path="${path%$'\r'}"
  if [[ "$path" == \"*\" ]]; then path="${path:1:${#path}-2}"; fi
  [[ -n "$path" ]] || die 'empty context path'
  if [[ "$path" =~ ^[A-Za-z]:\\ ]]; then
    require_command wslpath
    path="$(wslpath -u "$path")" || die "cannot translate Windows path: $path"
  fi
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || die "context input must be a readable regular file, not a symlink: $path"
  printf '%s' "$path"
}

context_confirm() {
  local answer
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer || return 1
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes ]]
}

context_import() {
  local raw source name destination temporary
  for raw in "$@"; do
    source="$(context_source_path "$raw")"
    name="$(basename -- "$source")"
    destination="$CONTEXT_DIR/$name"
    [[ ! -L "$destination" && ( ! -e "$destination" || -f "$destination" ) ]] \
      || die "context destination is not a regular file: $name"
    if [[ -e "$destination" ]]; then
      context_confirm "Replace imported copy $name?" || { note "Skipped: $name"; continue; }
    fi
    temporary="$(mktemp "$CONTEXT_DIR/.import.XXXXXX")"
    if ! cp -- "$source" "$temporary" || ! chmod 0644 "$temporary" \
        || ! mv -fT -- "$temporary" "$destination"; then
      rm -f -- "$temporary"
      die "failed to import: $source"
    fi
    printf 'Imported: /context/%s\n' "$name"
  done
}

context_main() {
  local slug="${1:-}" action name raw
  [[ -n "$slug" ]] || die 'usage: sbx context <project> [add [paths...] | list | remove <names...>]'
  shift
  load_project "$slug"
  ensure_project_directories
  action="${1:-add}"
  [[ $# -eq 0 ]] || shift
  case "$action" in
    list)
      [[ $# -eq 0 ]] || die 'usage: sbx context <project> list'
      find "$CONTEXT_DIR" -mindepth 1 -maxdepth 1 -type f -printf '/context/%f\n' | LC_ALL=C sort
      ;;
    add)
      local -a paths=("$@")
      if [[ ${#paths[@]} -eq 0 ]]; then
        printf 'Paste Copy as path values, one file per line. Blank line finishes.\n' >&2
        while IFS= read -r raw; do
          raw="${raw%$'\r'}"
          [[ -n "$raw" ]] || break
          paths+=("$raw")
        done
      fi
      [[ ${#paths[@]} -gt 0 ]] || die 'no context files supplied'
      acquire_session_lock context-import
      context_import "${paths[@]}"
      ;;
    remove)
      [[ $# -gt 0 ]] || die 'usage: sbx context <project> remove <names...>'
      acquire_session_lock context-remove
      for name in "$@"; do
        [[ -n "$name" && "$name" != */* && "$name" != . && "$name" != .. ]] \
          || die "expected an imported filename, not a path: $name"
        [[ -f "$CONTEXT_DIR/$name" && ! -L "$CONTEXT_DIR/$name" ]] \
          || die "imported regular file not found: $name"
        rm -- "$CONTEXT_DIR/$name"
        note "Removed imported copy: $name"
      done
      ;;
    *) die "unknown context action: $action (expected add, list, remove)" ;;
  esac
}
