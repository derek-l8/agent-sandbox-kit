#!/usr/bin/env bash

set -u

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

expect_file_value() {
  local path="$1"
  local expected="$2"
  local label="$3"
  local actual
  actual="$(cat "$path" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

expect_absent() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

expect_not_mountpoint() {
  local path="$1"
  local label="$2"
  if ! mountpoint -q "$path" 2>/dev/null; then
    pass "$label"
  else
    fail "$label"
  fi
}

expect_mount_mode() {
  local path="$1"
  local expected="$2"
  local label="$3"
  local options
  if [[ ! -e "$path" ]]; then
    fail "${label}: path is missing"
    return
  fi
  options="$(findmnt -n -T "$path" -o OPTIONS 2>/dev/null || true)"
  if [[ -z "$options" ]]; then
    fail "${label}: mount options unavailable"
    return
  fi
  case ",$options," in
    *,"$expected",*) pass "$label" ;;
    *) fail "$label" ;;
  esac
}

check_common_container_boundary() {
  if [[ -e /.dockerenv ]]; then
    pass "running inside Docker"
  else
    fail "Docker marker is absent"
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    pass "runtime user is non-root"
  else
    fail "runtime user is root"
  fi

  local cap_eff
  cap_eff="$(awk '/^CapEff:/ { print $2 }' /proc/self/status 2>/dev/null || true)"
  if [[ -n "$cap_eff" && "$cap_eff" =~ ^0+$ ]]; then
    pass "effective Linux capabilities are empty"
  else
    fail "effective Linux capabilities are not empty"
  fi

  local no_new_privs
  no_new_privs="$(awk '/^NoNewPrivs:/ { print $2 }' /proc/self/status 2>/dev/null || true)"
  if [[ "$no_new_privs" == "1" ]]; then
    pass "no-new-privileges is active"
  else
    fail "no-new-privileges is inactive"
  fi

  expect_absent /var/run/docker.sock "Docker socket is absent"
  expect_absent /mnt/c "Windows C drive is absent"
  expect_absent /home/node/.ssh "SSH directory is absent"

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    pass "SSH agent forwarding is absent"
  else
    fail "SSH agent forwarding is present"
  fi

  local secret_names
  secret_names="$(env | cut -d= -f1 | grep -E '^(AWS_|AZURE_|GOOGLE_|GITHUB_TOKEN$|GH_TOKEN$|OPENAI_API_KEY$|.*_SECRET$|.*_TOKEN$)' || true)"
  if [[ -z "$secret_names" ]]; then
    pass "common secret environment variables are absent"
  else
    fail "secret-like environment variable names are present: ${secret_names//$'\n'/,}"
  fi

  expect_mount_mode / ro "container root filesystem is read-only"
}

finish_boundary_check() {
  local label="$1"
  if [[ "$failures" -eq 0 ]]; then
    printf 'RESULT: all %s boundary checks passed\n' "$label"
    return 0
  fi
  printf 'RESULT: %d %s boundary check(s) failed\n' "$failures" "$label" >&2
  return 1
}
