# Codex Sandbox v2: Operator Guide

This is the daily-use guide. It assumes the kit is installed at
`~/codex-sandbox-kit` and its images have been built.

## What the sandbox does

The networked runner gives Codex one disposable/public repository, public
scratch space, an outbox, and internet access. It does not receive your private
inbox, Windows drives, SSH agent, Docker socket, VS Code sockets, browser
sessions, or general WSL home directory.

The offline runner receives a read-only source snapshot and a deliberately
selected private inbox. It has no network and does not contain Codex. Every
offline invocation starts from a fresh in-memory copy of the current source.

The Codex login is the one intentional credential in the networked runner. It
is stored in a project-specific Docker volume. Do not treat the networked
runner as credential-free.

## One-time project setup

```bash
cd ~/codex-sandbox-kit
bin/sandboxctl init my-project

# Clone an existing repository:
git clone https://github.com/OWNER/REPOSITORY.git \
  ~/agent-workspaces/my-project/repo

# Or initialize a new repository:
cd ~/agent-workspaces/my-project/repo
git init
git branch -M main
```

Create a trusted baseline commit before starting autonomous work. The agent can
modify the working tree, but `.git` is mounted read-only.

Then verify the project and authenticate:

```bash
~/codex-sandbox-kit/bin/sandboxctl doctor my-project
~/codex-sandbox-kit/bin/sandboxctl login my-project
```

Login uses ChatGPT device authorization and therefore uses subscription access,
not an API key.

## Run a networked coding task

From trusted WSL:

```bash
~/codex-sandbox-kit/bin/sandboxctl run my-project
```

The launcher creates the container without VS Code, verifies the exact mount
allowlist and security flags, stores a host-side report under
`~/agent-workspaces/my-project/control/logs`, and only then starts Codex.

Do not place secrets or private files in `repo` or `scratch`. Repository files,
dependencies, test fixtures, web pages, and tool output are untrusted inputs.

## Run private validation

Place only the necessary fixture files in:

```text
~/agent-workspaces/my-project/inbox
```

Then run a reviewed deterministic command:

```bash
~/codex-sandbox-kit/bin/sandboxctl offline my-project -- pytest -q
```

The source and inbox mounts are read-only. The test runs in a new tmpfs copy at
`/workspace`. Only files deliberately written to `/agent/outbox` persist.

Offline code cannot transmit data over the network, but it can copy private
content into the outbox. Inspect every outbox file before moving or sharing it.

## Review and promote

Back in trusted WSL:

```bash
cd ~/agent-workspaces/my-project/repo
git status --short
git diff --stat
git diff

~/codex-sandbox-kit/bin/sandboxctl package my-project
```

Read the diff, new files, `.agent` reports, test results, source log, host-side
boundary reports, and every outbox file. Commit, push, deploy, and open pull
requests only from trusted WSL or Windows.

## Authentication maintenance

```bash
# Report the active login mode without starting a model task:
~/codex-sandbox-kit/bin/sandboxctl auth-status my-project

# Remove credentials using Codex:
~/codex-sandbox-kit/bin/sandboxctl logout my-project

# Delete the entire project auth volume after logout or an incident:
~/codex-sandbox-kit/bin/sandboxctl destroy-auth my-project --yes
```

The volume persists only `auth.json`. Codex configuration, rules, sessions,
logs, and caches are recreated for every container invocation.

After suspected prompt injection, dependency compromise, or credential
exposure, stop the container, log out, delete the auth volume, and rebuild from
the pinned kit before continuing.

## Diagnostics

```bash
~/codex-sandbox-kit/bin/sandboxctl doctor my-project
~/codex-sandbox-kit/bin/sandboxctl shell my-project
```

Do not work around a failed host or container boundary check. Fix the trusted
launcher, project control file, or image and rerun the check.
