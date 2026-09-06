# Operator Guide

This guide covers daily use from WSL. Keep the Agent Sandbox Kit checkout,
each project's `control` directory, and Git promotion actions outside agent
containers. Examples use the durable checkout name `agent-sandbox-kit`.

## Installation and updates

```bash
cd /path/to/agent-sandbox-kit
./install.sh
```

This installs the complete runtime under
`${XDG_DATA_HOME:-$HOME/.local/share}/agent-sandbox-kit` and creates the
user-facing launcher at `${XDG_BIN_HOME:-$HOME/.local/bin}/sbx`, without root
access. If needed, the installer prints the `PATH` line to add. The installed
command is independent of the checkout, and the installer never modifies or
deletes the fallback `~/codex-sandbox-kit` tree.

For an upgrade, update the reviewed checkout and use this complete sequence:

```bash
cd /path/to/agent-sandbox-kit
git pull --ff-only
./install.sh
sbx version
sbx build
sbx upgrade my-project
sbx codex doctor my-project
```

Substitute `sbx opencode doctor my-project` when appropriate. The new
runtime is copied to a temporary sibling, checked for all required runtime
files, shell syntax, and working `sbx --help`, and only then swapped into
place. A failed copy, validation, or swap leaves the prior installation in
place or restores it. `sbx` normally runs the installed runtime rather than the
current directory. `build` uses that runtime's lock file, `upgrade` backs up and
atomically migrates project image pins, and `doctor` is read-only. Authentication
schema v2 normally survives compatible patch upgrades.

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
only the selected repository, read-only `/context`, writable persistent `/data`,
internet access, and their project login. They do not receive Windows drives, general
WSL home, SSH material, Docker socket, browser sessions, or editor sockets.

## External context and data

Run `sbx context <project>` and paste Windows **Copy as path** values, one
quoted path per line; finish with a blank line. It translates paths with
`wslpath`, copies regular files to the project's WSL `context/` directory,
and prints the container paths. You can import before cloning the repository.
For arguments, use `sbx context <project> add '/wsl/path/file.pdf'`.
Use single shell quotes around Windows paths passed as arguments; the
interactive prompt accepts Explorer's double quotes literally.

Imports keep each file's basename. A name collision asks before replacing
that copy. Multiple files are processed in order; a failed import stops the
batch, preserving earlier successful imports. Directories and symlinks are
not imported. Files are copied unchanged, without format detection or parsing.

`sbx context <project> list` prints imported files. To delete only a WSL copy,
use `sbx context <project> remove 'filename.pdf'`. Source files are untouched.
Imports/removals share the agent session lock; exit the task before changing
its context. Put generated files and ongoing state in `/data`, which persists
across disposable containers. Both directories are outside `repo/` and Git.
They are still available to the networked agent, and copying content into
the repository remains possible. Back up important data separately.

## Authentication maintenance

```bash
sbx codex auth-status my-project
sbx codex logout my-project
sbx codex reset-auth my-project --yes
sbx opencode auth-status my-project
sbx opencode logout my-project
sbx opencode reset-auth my-project --yes
```

Task, shell, and exec sessions mount authentication read-only. Cleanup helpers
prune unexpected persistent auth content before and after commands and fail
closed on errors. Review and promote Git changes from the host.

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

| Error | Action |
|---|---|
| Source/installed versions differ | Run `./install.sh` from the intended checkout, then `sbx version`. |
| Image missing | Run `sbx build`. |
| Project uses an old image tag | Run `sbx upgrade <project>`. Do not edit `project.env` manually. |
| Image label differs | Run `sbx build`; never relabel an unverified image. |
| Authentication schema incompatible | Run the exact `sbx <agent> reset-auth <project> --yes` printed by the error, then login. Only that agent/project login is deleted; repository and other agent login remain. |
| Docker daemon unavailable | Start Docker Desktop and its WSL integration, then retry. |
| Smoke test stale state | Reinstall/update: current smoke tests always create unique temporary roots and cannot reuse normal projects. |
| OpenTUI executable-temp failure | Reinstall 2.0.2, rebuild, and run `bash tests/smoke-opencode.sh`; keep general `/tmp` non-executable. |

### Codex and the Bubblewrap warning

Launching Codex directly in WSL uses Codex's Linux sandbox and can warn when
Bubblewrap or unprivileged user namespaces are unavailable. `sbx codex run`
does not use that inner sandbox: it explicitly starts Codex in full-access mode
inside the already verified Docker container. The Docker launcher remains the
security boundary, including its mount allowlist, read-only root filesystem,
dropped capabilities, `no-new-privileges`, resource limits, and project lock.
Consequently the direct-WSL Bubblewrap warning is not expected for this path,
and Bubblewrap should not be added to the image as a duplicate security layer.

## Version 3 compatibility

Only canonical `sbx <agent> <action> <project>` commands are supported. The
underlying `bin/sandboxctl` accepts the same canonical arguments; old aliases,
offline execution, and review packaging have been removed. Version 3 expects
`repo/`, `context/`, `data/`, and host-only `control/`. It never deletes or
silently migrates an old layout. Initialize a new slug when necessary.
Image upgrades preserve authentication schema v2 volumes.

## Trusted-WSL validation

Run these from the reviewed host checkout, never from an agent container:

```bash
bash tests/static.sh
bash tests/smoke-codex.sh
bash tests/smoke-opencode.sh
```

The two smoke tests are Docker-based and model-free. Run them only after the
pinned images have been built; neither performs authentication.
