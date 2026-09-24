# Agent Sandbox Kit

Agent Sandbox Kit runs Codex, OpenCode, and Claude Code in disposable Docker containers from
WSL. Each agent receives one selected Git working tree without mounts for the
rest of the WSL home, Windows files, host credentials, or the Docker socket.

The durable repository and installation name is `agent-sandbox-kit`. This is
an experimental personal project for repositories you own and review, not a
general sandbox for untrusted repositories.

## Quick start

Run these commands in WSL with Docker Desktop running and WSL integration
enabled. The images support Linux x86_64.

Replace every `<placeholder>` before running a command; the angle brackets
are documentation notation, not shell syntax.

| Placeholder | Meaning |
| --- | --- |
| `<agent>` | `codex`, `opencode`, or `claude`; choose explicitly |
| `<project>` | A project slug: lowercase letters, numbers, and hyphens, starting with a letter or number; maximum 63 characters |
| `<repo-url>` | Clone URL of the repository you want the agent to work on |
| `<kit-directory>` | Path to your local `agent-sandbox-kit` checkout |
| `<command>` | A shell command and its arguments to run inside the container |
| `<file-path>` | Path to a reference file you want to import |
| `<file-name>` | Name of an imported file, as shown by `sbx context <project> list` |

```bash
git clone https://github.com/derek-l8/agent-sandbox-kit.git
cd agent-sandbox-kit
./install.sh
sbx build
sbx init <project>
git clone "<repo-url>" "$HOME/agent-workspaces/<project>/repo"
sbx <agent> doctor <project>
sbx <agent> login <project>
sbx <agent> run <project>
```

Use the same `<project>` throughout and select the `<agent>` you want to run.
Each agent has a separate login for that project. Create a trusted baseline
commit before an agent session; review, commit, and push from WSL, outside the
container.

The installer copies a self-contained runtime to
`${XDG_DATA_HOME:-$HOME/.local/share}/agent-sandbox-kit` and links `sbx` from
`${XDG_BIN_HOME:-$HOME/.local/bin}` without root access. The installed command
does not depend on the checkout remaining in place. If the command directory
is not on `PATH`, the installer prints the exact shell setup line to add.

Running `./install.sh` again stages and validates a complete new runtime before
replacing the installed one. If copying, validation, or replacement fails, the
previous runtime is retained or restored. The installer does not modify or
remove `~/codex-sandbox-kit`.

## Updates

Updating the kit and an existing project:

```bash
cd "<kit-directory>"
git pull --ff-only
./install.sh
sbx version
sbx build
sbx upgrade <project>
sbx <agent> doctor <project>
```

The installer copies the reviewed source into a staged, validated installed
runtime. `sbx` normally runs that installed runtime, `build` builds its pinned
images, `upgrade` atomically
updates only the project's image references, and `doctor` verifies without
repairing. Compatible authentication schema v2 volumes survive patch upgrades.

## Everyday commands

| Purpose | Command (`<agent>` = `codex`, `opencode`, or `claude`) |
| --- | --- |
| Start agent | `sbx <agent> run <project>` |
| Log in | `sbx <agent> login <project>` |
| Check login | `sbx <agent> auth-status <project>` |
| Log out | `sbx <agent> logout <project>` |
| Validate | `sbx <agent> doctor <project>` |
| Diagnostic shell | `sbx <agent> shell <project>` |
| Run a command | `sbx <agent> exec <project> -- <command>` |

Shared setup commands are `sbx init <project>` and `sbx build`.

The CLI uses an explicit allowlisted adapter registry. Agent-specific image,
executable, version, authentication, configuration-validation, and command
routing metadata is kept under `adapters/`. Docker isolation, verified mounts,
resource limits, project locking, cleanup, and protected paths remain in the
common launcher and cannot be configured by an adapter. See
[Adding an Agent](docs/ADDING-AN-AGENT.md).

## Trust model

The trusted WSL launcher creates containers directly and checks their final
configuration before startup. The repository is writable while `.git` is
read-only. Agents have separate pinned images and authentication volumes, and
a shared project lock prevents concurrent sessions on one tree. Authentication
is mounted read-only during task, shell, and exec sessions.

The kit does not guarantee protection from Docker or kernel vulnerabilities,
safe handling of arbitrary malicious repositories, protection of an active
agent credential from repository code, or preservation of the writable tree.
See the [operator guide](docs/OPERATOR-GUIDE.md) and
[security reference](docs/MAINTAINER-SECURITY.md).

## Files outside Git

Each project lives entirely in WSL under `~/agent-workspaces/<project>`:

| Host folder | Container path | Agent access |
| --- | --- | --- |
| `repo/` | `/workspace` | Writable; `.git` stays read-only |
| `context/` | `/context` | Read-only reference files |
| `data/` | `/data` | Writable, persistent outputs and state |
| `control/` | Not mounted | Host configuration and reports |

In Windows Explorer, select files and use **Copy as path**. In WSL run:

```bash
sbx context <project>
```

Paste the quoted paths, one per line, then enter a blank line. The command
copies the files into WSL and prints their `/context/...` paths. Windows
originals are untouched; no Windows folder is mounted into the container.

You can also import WSL paths and manage copies explicitly:

```bash
sbx context <project> add "<file-path>"
sbx context <project> list
sbx context <project> remove "<file-name>"
```

To import multiple files, supply each path as a separate quoted argument.
Replacement requires confirmation. Removal deletes only the named imported
copy. Imports and removals refuse to run while a project task is active.
All agents receive guidance about `/context` and `/data`; document parsing
and viewing depend on the harness's available tools.

Neither folder is in the Git working tree: `git add .` in `repo/` cannot stage
them. An agent can still copy content into the repository. These files are
accessible to a networked agent; outside Git does not mean isolated from the
network. Back up important `/data` state separately from Git.

The workspace root defaults to `$HOME/agent-workspaces`; set
`CODEX_SANDBOX_WORKSPACES_ROOT` to another WSL location. Linked Git worktrees
are not supported.

## Version 3 layout

Version 3 removes the offline runner, packaging command, and implicit/suffixed
legacy agent commands. Use the explicit agent commands listed above.
Existing old-layout projects are not automatically migrated or deleted.
`sbx upgrade` updates image pins for the current layout; it is not a layout
migration command. Initialize a new slug if an old layout is still present.
Authentication schema v2 and its volume names remain unchanged.

## Included tools

All three Linux x86_64 images provide Python **3.14.7** as `python` and
`python3`, pinned `uv`, pip compatibility, Node.js/npm, Git, Bash, coreutils,
find/diff/patch, ripgrep (`rg`), `fd`, curl/CA certificates, jq, file,
tar/gzip/zip/unzip, C/C++ build tools, pkg-config, and Poppler PDF utilities.
Tools are installed during image construction; runtime privileges and mounts
are unchanged. See [Python and shared tools](docs/TOOLCHAIN.md).

## Tests

Complete Docker-free, authentication-free, and model-free suite:

```bash
bash tests/static.sh
```

Docker-based, model-free smoke checks:

```bash
bash tests/smoke-codex.sh
bash tests/smoke-opencode.sh
bash tests/smoke-claude.sh
bash tests/smoke-toolchain.sh
```

## License

MIT. See [LICENSE](LICENSE).
