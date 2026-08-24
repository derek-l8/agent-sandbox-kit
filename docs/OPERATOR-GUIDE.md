# Operator Guide

This guide covers daily use from WSL. Read the [README](../README.md) for the
intended use and limitations. Implementation details are in the
[security notes](MAINTAINER-SECURITY.md).

Examples assume the kit is the current directory and projects use `$HOME/agent-workspaces`. Keep the kit, each project's `control` directory, and all Git promotion actions outside agent containers.

## Runner access

Networked Codex and OpenCode runners receive one repository, public or synthetic scratch, an outbox, internet access, and their project-specific login. They do not receive the private inbox, Windows drives, general WSL home, SSH material, Docker socket, browser sessions, or editor/GUI sockets. The tree is writable and `.git` is read-only.

The offline runner receives read-only source and a selected read-only private
inbox. It has no Docker network and no Codex installation. Each invocation
copies source into fresh in-memory `/workspace`; only `/agent/outbox`
persists.

## One-time setup

```bash
bin/sandboxctl build
bin/sandboxctl init my-project
git clone https://github.com/OWNER/REPOSITORY.git \
  "$HOME/agent-workspaces/my-project/repo"
bin/sandboxctl doctor my-project
bin/sandboxctl login my-project
```

After updating an existing kit checkout, rebuild the images before running a
session so the launcher and root-owned cleanup scripts match:

```bash
bin/sandboxctl build
```

For a new repository, run `git init` and `git branch -M main` in the empty `repo` directory. Create a trusted baseline commit before autonomous work. Codex login uses ChatGPT device authorization rather than an API key.

The launcher requires `repo/.git` to be a directory, so linked Git worktrees
are not supported.

## Networked sessions

```bash
bin/sandboxctl run my-project
bin/sandboxctl shell my-project
bin/sandboxctl exec my-project -- npm test
```

The launcher checks the container configuration, writes a report under
`control/logs`, and then starts it. Do not put secrets in `repo` or
`scratch`; repository files, dependencies, and tool output can influence the
agent.

OpenCode reuses the boundary with its own image and auth volume:

```bash
bin/sandboxctl doctor-opencode my-project
bin/sandboxctl login-opencode my-project
bin/sandboxctl run-opencode my-project
bin/sandboxctl shell-opencode my-project
bin/sandboxctl exec-opencode my-project -- npm test
```

Codex and OpenCode share a project lock, so their sessions cannot overlap for
one slug. OpenCode is launched with managed settings intended to disable
updates, sharing, project configuration and extensions, and selected
Git/GitHub commands. Repository instructions can still influence the agent.

## Private offline validation

Place only needed fixtures in `$HOME/agent-workspaces/my-project/inbox`, then run:

```bash
bin/sandboxctl offline my-project -- pytest -q
```

Codex is not installed. Docker networking is disabled, but offline code can
still copy private content to the persistent outbox. Inspect every outbox file
before sharing it.

## Review and promotion

```bash
cd "$HOME/agent-workspaces/my-project/repo"
git status --short
git diff --stat
git diff
cd /path/to/codex-sandbox-kit
bin/sandboxctl package my-project
```

The bundle includes status, a patch, checksums, and standard `.agent` reports
if present. Review changes and outbox files before committing or pushing from
WSL. GitHub is the durable copy; loss of the WSL tree is accepted.

## Authentication maintenance

```bash
bin/sandboxctl auth-status my-project
bin/sandboxctl logout my-project
bin/sandboxctl destroy-auth my-project --yes

bin/sandboxctl auth-status-opencode my-project
bin/sandboxctl logout-opencode my-project
bin/sandboxctl destroy-opencode-auth my-project --yes
```

Codex and OpenCode task, shell, and exec sessions mount authentication
read-only. Codex status also uses a read-only authentication mount. Codex
login/logout and the OpenCode authentication command family use writable
volumes without mounting the workspace. Before and after each command, the
launcher runs a network-disabled helper that removes everything except
`auth.json`, verifies the result, and fails the command if cleanup fails.
Post-command cleanup is attempted after successful, failed, and interrupted
commands when shell control returns to the launcher. If a credential may have
been exposed, log out and delete its volume.

Codex may refresh its copied credential during a task, but that updated copy is
discarded with the task's `CODEX_HOME`. If a later session reports that the
persisted credential is no longer valid, run `bin/sandboxctl login <slug>`
again.

## Project settings and troubleshooting

`$HOME/agent-workspaces/<slug>/control/project.env` contains only fixed keys
parsed by `sandboxctl`; it is not sourced as shell. New projects default to 6
CPUs and 8 GiB of memory. The file can select custom images, but they must
retain the labels, tools, and entrypoints checked or invoked by the launcher.
`control/protected-paths.txt` can make existing repository-relative paths
read-only, but cannot stop other repository content influencing the agent. Set
`CODEX_SANDBOX_WORKSPACES_ROOT` before every invocation to change the
workspace root.

```bash
bin/sandboxctl doctor my-project
bin/sandboxctl doctor-opencode my-project
```

Do not bypass a failed boundary check. Check the launcher, project layout,
control file, image, and host reports in `control/logs`.
