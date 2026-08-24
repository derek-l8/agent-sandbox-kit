#!/usr/bin/env bash

# Public agent registry.  This file contains routing metadata only: adapters
# cannot add Docker arguments, mounts, capabilities, or other boundary policy.

declare -ag SBX_AGENTS=()
declare -Ag SBX_ADAPTER_DISPLAY=()
declare -Ag SBX_ADAPTER_IMAGE_KEY=()
declare -Ag SBX_ADAPTER_VERSION_KEY=()
declare -Ag SBX_ADAPTER_EXECUTABLE=()
declare -Ag SBX_ADAPTER_AUTH=()
declare -Ag SBX_ADAPTER_CONFIG_VALIDATOR=()
declare -Ag SBX_ADAPTER_ACTIONS=()
declare -Ag SBX_ADAPTER_LEGACY_COMMAND=()

register_sbx_agent() {
  local id="$1" display="$2" image_key="$3" version_key="$4"
  local executable="$5" auth="$6" config_validator="$7" actions="$8"
  [[ "$id" =~ ^[a-z][a-z0-9-]*$ ]] || return 1
  [[ -z "${SBX_ADAPTER_DISPLAY[$id]+x}" ]] || return 1
  [[ "$image_key" =~ ^[A-Z][A-Z0-9_]*$ ]] || return 1
  [[ "$version_key" =~ ^[A-Z][A-Z0-9_]*$ ]] || return 1
  [[ "$executable" =~ ^[a-zA-Z0-9._+-]+$ ]] || return 1
  [[ "$auth" =~ ^[a-z0-9-]+$ ]] || return 1
  [[ "$config_validator" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
  SBX_AGENTS+=("$id")
  SBX_ADAPTER_DISPLAY[$id]="$display"
  SBX_ADAPTER_IMAGE_KEY[$id]="$image_key"
  SBX_ADAPTER_VERSION_KEY[$id]="$version_key"
  SBX_ADAPTER_EXECUTABLE[$id]="$executable"
  SBX_ADAPTER_AUTH[$id]="$auth"
  SBX_ADAPTER_CONFIG_VALIDATOR[$id]="$config_validator"
  SBX_ADAPTER_ACTIONS[$id]="$actions"
}

register_sbx_route() {
  local agent="$1" action="$2" legacy_command="$3"
  [[ -n "${SBX_ADAPTER_DISPLAY[$agent]+x}" ]] || return 1
  [[ " ${SBX_ADAPTER_ACTIONS[$agent]} " == *" $action "* ]] || return 1
  [[ "$legacy_command" =~ ^[a-z][a-z-]*$ ]] || return 1
  SBX_ADAPTER_LEGACY_COMMAND["$agent:$action"]="$legacy_command"
}

sbx_adapter_is_registered() {
  [[ -n "${SBX_ADAPTER_DISPLAY[$1]+x}" ]]
}

sbx_adapter_legacy_command() {
  printf '%s' "${SBX_ADAPTER_LEGACY_COMMAND["$1:$2"]-}"
}

sbx_validate_registry() {
  local agent action
  ((${#SBX_AGENTS[@]} > 0)) || return 1
  for agent in "${SBX_AGENTS[@]}"; do
    [[ -n "${SBX_ADAPTER_DISPLAY[$agent]}" ]]
    [[ -n "${SBX_ADAPTER_IMAGE_KEY[$agent]}" ]]
    [[ -n "${SBX_ADAPTER_VERSION_KEY[$agent]}" ]]
    [[ -n "${SBX_ADAPTER_EXECUTABLE[$agent]}" ]]
    [[ -n "${SBX_ADAPTER_AUTH[$agent]}" ]]
    [[ -n "${SBX_ADAPTER_CONFIG_VALIDATOR[$agent]}" ]]
    for action in ${SBX_ADAPTER_ACTIONS[$agent]}; do
      [[ -n "${SBX_ADAPTER_LEGACY_COMMAND["$agent:$action"]-}" ]] || return 1
    done
  done
}

# The allowlist is explicit. Adding a file to adapters/ does not register it.
source "${BASH_SOURCE[0]%/*}/codex.sh"
source "${BASH_SOURCE[0]%/*}/opencode.sh"
sbx_validate_registry
