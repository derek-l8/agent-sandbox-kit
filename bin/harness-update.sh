#!/usr/bin/env bash

# Shared host-side release workflow. Profile fields are an explicit allowlist.
# Keep this inode outside the replaceable runtime. The installer inherits fd 9
# when invoked by a kit update, so both operations hold the same lock.
acquire_runtime_update_lock() {
  local root="$1" lock_path
  command -v flock >/dev/null || { printf 'ERROR: required command is missing: flock\n' >&2; return 1; }
  lock_path="$(cd "$(dirname "$root")" && pwd)/.${root##*/}.runtime.lock"
  if [[ "$(readlink /proc/self/fd/9 2>/dev/null || true)" != "$lock_path" ]]; then
    exec 9>"$lock_path"
  fi
  flock -n 9 || { printf 'ERROR: another runtime installation or version update is active\n' >&2; return 1; }
}

harness_update_profile() {
  HARNESS_AGENT="$1"
  case "$1" in
    codex) HARNESS_PREFIX=CODEX; HARNESS_LABEL=Codex; HARNESS_IMAGE_KEY=NETWORK_IMAGE ;;
    opencode) HARNESS_PREFIX=OPENCODE; HARNESS_LABEL=OpenCode; HARNESS_IMAGE_KEY=OPENCODE_IMAGE ;;
    claude) HARNESS_PREFIX=CLAUDE; HARNESS_LABEL='Claude Code'; HARNESS_IMAGE_KEY=CLAUDE_IMAGE ;;
    *) die "unknown harness: $1" ;;
  esac
  HARNESS_VERSION_KEY="${HARNESS_PREFIX}_VERSION"
}

load_harness_release() {
  local agent="$1" path="$2" values key value prefix image_key
  case "$agent" in
    codex) prefix=CODEX; image_key=NETWORK_IMAGE ;;
    opencode) prefix=OPENCODE; image_key=OPENCODE_IMAGE ;;
    claude) prefix=CLAUDE; image_key=CLAUDE_IMAGE ;;
    *) die "unknown harness: $agent" ;;
  esac
  require_command python3
  values="$(python3 "$KIT_ROOT/bin/harness-release.py" --agent "$agent" load "$KIT_ROOT" "$path")" \
    || die "invalid $agent release lock: $path"
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    if [[ "$key" == "${prefix}_VERSION" || "$key" == "${prefix}_PACKAGE_INTEGRITY" \
        || "$key" == "${prefix}_LINUX_X64_INTEGRITY" || "$key" == "$image_key" ]]; then
      printf -v "$key" '%s' "$value"
    else
      die "unexpected $agent release value: $key"
    fi
  done <<< "$values"
}

resolve_harness_release() {
  require_command python3
  require_command timeout
  timeout 15s python3 "$KIT_ROOT/bin/harness-release.py" --agent "$1" resolve "${2:-latest}"
}

automatic_harness_update_check() (
  harness_update_profile "$1"
  local disable_key="SBX_DISABLE_${HARNESS_PREFIX}_UPDATE_CHECK"
  [[ "${SBX_DISABLE_UPDATE_CHECK:-0}" != 1 && "${SBX_DISABLE_HARNESS_UPDATE_CHECK:-0}" != 1 \
      && "${!disable_key:-0}" != 1 ]] || return 0
  local cache now modified=0 metadata candidate
  cache="${XDG_CACHE_HOME:-${HOME}/.cache}/agent-sandbox-kit/${HARNESS_AGENT}-update-check"
  now="$(date +%s)"
  [[ -f "$cache" ]] && modified="$(stat -c %Y "$cache" 2>/dev/null || printf 0)"
  (( now - modified >= 86400 )) || return 0
  # Failed attempts are cached too, so outages do not delay every launch.
  mkdir -p -- "$(dirname "$cache")" 2>/dev/null || return 0
  command -v flock >/dev/null || return 0
  { exec 8>"${cache}.lock"; } 2>/dev/null || return 0
  flock -n 8 || return 0
  [[ -f "$cache" ]] && modified="$(stat -c %Y "$cache" 2>/dev/null || printf 0)"
  (( now - modified >= 86400 )) || return 0
  touch "$cache" 2>/dev/null || return 0
  chmod 0600 "$cache" 2>/dev/null || true
  metadata="$(resolve_harness_release "$HARNESS_AGENT" 2>/dev/null)" || return 0
  candidate="$(sed -n "s/^${HARNESS_VERSION_KEY}=//p" <<< "$metadata")"
  python3 "$KIT_ROOT/bin/harness-release.py" newer "$candidate" "${!HARNESS_VERSION_KEY}" || return 0
  printf '%s UPDATE AVAILABLE: published CLI %s (selected: %s).\nRun: sbx %s-update --check\nThen: sbx %s-update <project>\n' \
    "$HARNESS_PREFIX" "$candidate" "${!HARNESS_VERSION_KEY}" "$HARNESS_AGENT" "$HARNESS_AGENT" >&2
)

cmd_harness_update() (
  harness_update_profile "$1"
  shift
  local check=false assume_yes=false selector=latest project='' metadata candidate answer
  local release_file="$KIT_ROOT/${HARNESS_AGENT}-release.lock" temporary='' backup=''
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --check) check=true ;;
      --yes) assume_yes=true ;;
      --version)
        shift
        [[ -n "${1:-}" ]] || die 'missing exact version after --version'
        [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'expected an exact stable version after --version'
        selector="$1" ;;
      --*) die "unknown ${HARNESS_AGENT}-update option: $1" ;;
      *) [[ -z "$project" ]] || die "usage: sbx ${HARNESS_AGENT}-update [--check | --yes] [--version X.Y.Z] [<project>]"; project="$1" ;;
    esac
    shift
  done
  [[ "$check" != true || ( "$assume_yes" == false && -z "$project" ) ]] \
    || die "usage: sbx ${HARNESS_AGENT}-update --check [--version X.Y.Z]"
  if [[ "$check" == false ]]; then
    acquire_runtime_update_lock "$KIT_ROOT"
    read_versions
  fi
  if [[ -n "$project" ]]; then
    load_project "$project"
    ensure_project_layout
    session_is_active && die "cannot update project '$project' while an agent task session is active"
  fi
  metadata="$(resolve_harness_release "$HARNESS_AGENT" "$selector")" \
    || die "could not resolve published $HARNESS_LABEL release; no selection or project changed"
  candidate="$(sed -n "s/^${HARNESS_VERSION_KEY}=//p" <<< "$metadata")"
  printf 'Selected %s CLI: %s\nPublished target: %s\nRegistry: https://registry.npmjs.org\n%s\n' \
    "$HARNESS_LABEL" "${!HARNESS_VERSION_KEY}" "$candidate" "$metadata"
  if ! python3 "$KIT_ROOT/bin/harness-release.py" newer "$candidate" "${!HARNESS_VERSION_KEY}"; then
    [[ "$selector" == latest || "$candidate" == "${!HARNESS_VERSION_KEY}" ]] || die "$HARNESS_LABEL downgrades are not supported"
    if [[ "$candidate" == "${!HARNESS_VERSION_KEY}" ]]; then
      local package_key="${HARNESS_PREFIX}_PACKAGE_INTEGRITY" binary_key="${HARNESS_PREFIX}_LINUX_X64_INTEGRITY"
      [[ "$metadata" == "$(printf '%s=%s\n%s=%s\n%s=%s' "$HARNESS_VERSION_KEY" "${!HARNESS_VERSION_KEY}" "$package_key" "${!package_key}" "$binary_key" "${!binary_key}")" ]] \
        || die 'published metadata differs from the selected integrity pins'
    fi
    note "$HARNESS_LABEL update available: no"
    if [[ "$check" == false && -n "$project" ]]; then
      ensure_harness_image_for_selection "$HARNESS_AGENT"
      upgrade_project_config "$HARNESS_AGENT" "$project"
    fi
    return 0
  fi
  note "$HARNESS_LABEL update available: yes"
  [[ "$check" != true ]] || return 0
  [[ ! -L "$release_file" ]] || die 'harness release lock may not be a symbolic link'
  temporary="$(mktemp "$KIT_ROOT/.${HARNESS_AGENT}-release.XXXXXX")"
  trap '[[ -z "$temporary" ]] || rm -f -- "$temporary"' EXIT
  printf '%s\n' "$metadata" > "$temporary"
  chmod 0600 "$temporary"
  load_harness_release "$HARNESS_AGENT" "$temporary"
  printf 'Proposed image: %s\nSelection file: %s\n' "${!HARNESS_IMAGE_KEY}" "$release_file"
  if [[ "$assume_yes" != true ]]; then
    read -r -p "Build and select this exact $HARNESS_LABEL release on the host? [y/N] " answer
    [[ "$answer" == [Yy] || "$answer" == [Yy][Ee][Ss] ]] || { note 'Harness update cancelled; no selection changed.'; return 0; }
  fi
  "build_${HARNESS_AGENT}_image"
  ensure_harness_image_for_selection "$HARNESS_AGENT"
  if [[ -e "$release_file" ]]; then
    backup="${release_file}.pre-update-$(date -u +'%Y%m%dT%H%M%SZ')-$$.bak"
    cp -p -- "$release_file" "$backup"
    note "Previous selection backup: $backup"
  fi
  mv -f -- "$temporary" "$release_file"
  temporary=''
  note "Selected exact $HARNESS_LABEL CLI ${!HARNESS_VERSION_KEY}; source versions.lock was not modified."
  if [[ -n "$project" ]]; then
    upgrade_project_config "$HARNESS_AGENT" "$project"
  else
    note 'Existing projects retain their image references. Apply with: sbx upgrade <project>'
  fi
)

ensure_harness_image_for_selection() (
  PROJECT_NETWORK_IMAGE="$NETWORK_IMAGE"
  PROJECT_OPENCODE_IMAGE="$OPENCODE_IMAGE"
  PROJECT_CLAUDE_IMAGE="$CLAUDE_IMAGE"
  case "$1" in
    codex) ensure_codex_images ;;
    opencode) ensure_opencode_image ;;
    claude) ensure_claude_images ;;
    *) die "unknown harness: $1" ;;
  esac
)
