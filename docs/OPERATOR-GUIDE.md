# Operator Guide

This guide covers daily use from WSL. Keep the Agent Sandbox Kit checkout,
each project's `control` directory, and Git promotion actions outside agent
containers. Examples use the durable checkout name `agent-sandbox-kit`.

## Installation and updates

```bash
cd /path/to/agent-sandbox-kit
./install.sh
```

This creates `~/.local/bin/sbx` without root access. If needed, the installer
prints the `PATH` line to add. It never moves or renames the checkout.

After updating the checkout, rebuild the pinned images with `sbx build`.

## Project setup and daily use

```bash
sbx init my-project
git clone https://github.com/OWNER/REPOSITORY.git \
  "$HOME/agent-workspaces/my-project/repo"
sbx codex doctor my-project
sbx codex login my-project
sbx codex run my-project
sbx codex shell my-project
sbx codex exec my-project -- npm test
```

For OpenCode, replace `codex` with `opencode`. Initialize an empty `repo`
directory and create a trusted baseline commit before autonomous work. Linked
Git worktrees are not supported.

The launcher checks the container, writes a report under `control/logs`, and
then starts it. Both agents share a per-project lock. Networked runners receive
only the selected repository, outbox, scratch, internet access, and their
project login. They do not receive the private inbox, Windows drives, general
WSL home, SSH material, Docker socket, browser sessions, or editor sockets.

## Offline validation, review, and authentication maintenance

These less frequent operations remain available through the compatibility
launcher:

```bash
bin/sandboxctl offline my-project -- pytest -q
bin/sandboxctl package my-project
bin/sandboxctl auth-status my-project
bin/sandboxctl logout my-project
bin/sandboxctl destroy-auth my-project --yes
bin/sandboxctl auth-status-opencode my-project
bin/sandboxctl logout-opencode my-project
bin/sandboxctl destroy-opencode-auth my-project --yes
```

The offline runner has no Docker network or Codex installation. Source and
inbox are read-only; only its outbox persists. Review every output before
sharing, committing, or pushing.

Task, shell, and exec sessions mount authentication read-only. Cleanup helpers
prune unexpected persistent auth content before and after commands and fail
closed on errors. If a credential may have been exposed, log out and destroy
its volume.

## Settings and troubleshooting

`$HOME/agent-workspaces/<project>/control/project.env` contains fixed keys
parsed as data, not sourced as shell. Defaults are 6 CPUs and 8 GiB. Compatible
custom images must retain all labels, tools, and entrypoints verified by the
launcher. `control/protected-paths.txt` can make existing repository-relative
paths read-only.

```bash
sbx codex doctor my-project
sbx opencode doctor my-project
```

Do not bypass a failed boundary check. Inspect the layout, control file, pinned
images, and host reports under `control/logs`.

## Compatibility interface

`bin/sandboxctl` remains the underlying, fully supported launcher. `bin/sbx`
only translates the short agent/action form and preserves arguments exactly,
including everything after `--`.

```bash
bin/sandboxctl --help
```
