# Codex Sandbox v2: Operator Guide

This is the daily-use guide. It assumes the completed multi-agent kit has been
cloned or copied side-by-side from the source working copy at
`~/src/codex-sandbox-kit-opencode-clean` to `~/agent-sandbox-kit`, and that
its images have been built there.

Do not copy anything into or over `~/codex-sandbox-kit`. That directory is the
stable Codex-only fallback and must remain untouched.

Rollback means stopping use of `~/agent-sandbox-kit` and returning to the
fallback launcher:

```bash
~/agent-sandbox-kit/bin/sandboxctl <command> <slug>
```

No files are removed by rolling back; project data under
`~/agent-workspaces` is independent of either kit installation.

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
cd ~/agent-sandbox-kit

# Build the three pinned images (Codex networked, offline, OpenCode):
bin/sandboxctl build

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
~/agent-sandbox-kit/bin/sandboxctl doctor my-project
~/agent-sandbox-kit/bin/sandboxctl login my-project
```

Login uses ChatGPT device authorization and therefore uses subscription access,
not an API key.

## Run a networked coding task

From trusted WSL:

```bash
~/agent-sandbox-kit/bin/sandboxctl run my-project
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
~/agent-sandbox-kit/bin/sandboxctl offline my-project -- pytest -q
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

~/agent-sandbox-kit/bin/sandboxctl package my-project
```

Read the diff, new files, `.agent` reports, test results, source log, host-side
boundary reports, and every outbox file. Commit, push, deploy, and open pull
requests only from trusted WSL or Windows.

## Authentication maintenance

```bash
# Report the active login mode without starting a model task:
~/agent-sandbox-kit/bin/sandboxctl auth-status my-project

# Remove credentials using Codex:
~/agent-sandbox-kit/bin/sandboxctl logout my-project

# Delete the entire project auth volume after logout or an incident:
~/agent-sandbox-kit/bin/sandboxctl destroy-auth my-project --yes
```

The volume persists only `auth.json`. Codex configuration, rules, sessions,
logs, and caches are recreated for every container invocation.

After suspected prompt injection, dependency compromise, or credential
exposure, stop the container, log out, delete the auth volume, and rebuild from
the pinned kit before continuing.

## Diagnostics

```bash
~/agent-sandbox-kit/bin/sandboxctl doctor my-project
~/agent-sandbox-kit/bin/sandboxctl shell my-project
```

Do not work around a failed host or container boundary check. Fix the trusted
launcher, project control file, or image and rerun the check.

## OpenCode sessions

The same project boundary can be run with OpenCode instead of Codex. OpenCode
is pinned at 1.18.21 in `versions.lock` and ships in its own image
(`local/codex-sandbox-opencode:2.0.0`), built by the same
`sandboxctl build`. It uses its own per-project authentication volume, separate
from the Codex one.

```bash
# One-time checks including the OpenCode image:
~/agent-sandbox-kit/bin/sandboxctl doctor-opencode my-project

# Authenticate (device/browser flow) into the project auth volume:
~/agent-sandbox-kit/bin/sandboxctl login-opencode my-project

# Interactive autonomous session:
~/agent-sandbox-kit/bin/sandboxctl run-opencode my-project

# Diagnostic shell or a single noninteractive command:
~/agent-sandbox-kit/bin/sandboxctl shell-opencode my-project
~/agent-sandbox-kit/bin/sandboxctl exec-opencode my-project -- pytest -q

# Maintenance:
~/agent-sandbox-kit/bin/sandboxctl auth-status-opencode my-project
~/agent-sandbox-kit/bin/sandboxctl logout-opencode my-project
~/agent-sandbox-kit/bin/sandboxctl destroy-opencode-auth my-project --yes
```

OpenCode sessions enforce exactly the same container boundary as Codex: only
the repository, outbox, scratch, and protected paths are mounted; `.git` stays
read-only; capabilities are dropped; the root filesystem is read-only; and no
Windows drive, WSL home, SSH material, inbox, or Docker socket is present.
Task sessions mount the authentication volume read-only; only login/logout/
auth-status containers can modify it. Only `auth.json` is ever persisted.

Codex and OpenCode share one lock per project: while an OpenCode session runs,
`run`, `shell`, and `exec` refuse to start for the same slug, and vice versa.
Normal manual Git operations from trusted WSL are unaffected.

Managed policy baked into the image disables automatic updates, sharing,
snapshots, MCP servers, external-directory access, repository plugins,
default plugins, and plugin/LSP downloads, and denies `git push`, `git commit`,
`git remote`, `git submodule`, and `gh` commands inside the container. Project
`opencode.json` files cannot override this (`OPENCODE_DISABLE_PROJECT_CONFIG=1`),
and a repository `.opencode/` directory is shadowed with an empty tmpfs.

Accepted limitation: the pinned OpenCode release may still discover some nested
repository instruction files such as `AGENTS.md`, `CLAUDE.md`, or `CONTEXT.md`
and treat them as guidance. This is accepted because repositories in this kit
are personal and reviewed. The kit does not modify, chmod, hide, delete, or
scan those files, and it does not claim that repository text can be prevented
from influencing the model.
