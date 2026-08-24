#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/adapters/registry.sh"

[[ "${SBX_AGENTS[*]}" == 'codex opencode' ]] \
  || { echo 'FAIL: registry allowlist changed unexpectedly' >&2; exit 1; }

for agent in "${SBX_AGENTS[@]}"; do
  for field in DISPLAY IMAGE_KEY VERSION_KEY EXECUTABLE AUTH CONFIG_VALIDATOR ACTIONS; do
    declare -n values="SBX_ADAPTER_${field}"
    [[ -n "${values[$agent]-}" ]] \
      || { printf 'FAIL: %s lacks %s\n' "$agent" "$field" >&2; exit 1; }
  done
  for action in run login doctor shell exec; do
    legacy="$(sbx_adapter_legacy_command "$agent" "$action")"
    [[ -n "$legacy" ]] \
      || { printf 'FAIL: %s lacks %s behavior\n' "$agent" "$action" >&2; exit 1; }
    grep -qE "^[[:space:]]+${legacy//-/\\-}\) cmd_" "$root/bin/sandboxctl" \
      || { printf 'FAIL: %s route targets missing sandboxctl command %s\n' "$agent" "$legacy" >&2; exit 1; }
  done
  grep -qE "^${SBX_ADAPTER_CONFIG_VALIDATOR[$agent]}\(\)" "$root/bin/sandboxctl" \
    || { printf 'FAIL: %s names a missing image/config validator\n' "$agent" >&2; exit 1; }
  printf 'PASS: %s adapter supplies required metadata and behaviors\n' "$agent"
done

# Registry metadata cannot express Docker flags or shell fragments.
for agent in "${SBX_AGENTS[@]}"; do
  combined="${SBX_ADAPTER_IMAGE_KEY[$agent]} ${SBX_ADAPTER_VERSION_KEY[$agent]} ${SBX_ADAPTER_EXECUTABLE[$agent]} ${SBX_ADAPTER_AUTH[$agent]} ${SBX_ADAPTER_CONFIG_VALIDATOR[$agent]} ${SBX_ADAPTER_ACTIONS[$agent]}"
  [[ "$combined" != *'--mount'* && "$combined" != *'--privileged'* && "$combined" != *';'* ]] \
    || { printf 'FAIL: %s adapter contains boundary configuration\n' "$agent" >&2; exit 1; }
done
printf 'PASS: adapter schema cannot configure the shared Docker boundary\n'
