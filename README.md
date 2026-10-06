# Agent Sandbox Kit

Agent Sandbox Kit runs Codex, OpenCode, and Claude Code from WSL in disposable
Docker containers. Each task session receives one Git repository, supplied reference
files, persistent output storage, and a separate project login.

This is an experimental personal project for repositories you own and review.
Docker provides the boundary; read the [trust model](#trust-model) before use.

## Quick start

Run host commands in a Linux x86_64 WSL distribution with Bash, Git,
Python 3.11 or newer, GNU command-line utilities, and `flock`. Ubuntu normally
includes the command-line utilities. Docker Desktop must be running with WSL
integration enabled. Use an account supported by your chosen harness;
[Claude authentication](docs/CLAUDE.md) has additional limits.

Clone and install the kit, then build its three pinned images. Each `&&`
stops the sequence if the preceding command fails:

```bash
git clone https://github.com/derek-l8/agent-sandbox-kit.git &&
cd agent-sandbox-kit &&
./install.sh &&
export PATH="${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH" &&
sbx build
```

The installer copies the runtime to
`${XDG_DATA_HOME:-$HOME/.local/share}/agent-sandbox-kit` and links `sbx` from
`${XDG_BIN_HOME:-$HOME/.local/bin}`. The export above sets up this shell. Follow
the installer's shell-profile instruction if that directory is missing from
`PATH` in new shells.

Choose a project name using lowercase letters, numbers, and hyphens, up to
63 characters, starting with a letter or number. Replace `<repo-url>` with a
repository you own that already has a reviewed commit. This example starts
Codex; replace `codex` with
`opencode` or `claude` to use another harness.

```bash
project=my-project
repo_url='<repo-url>'
sbx init "$project" &&
git clone "$repo_url" "${CODEX_SANDBOX_WORKSPACES_ROOT:-$HOME/agent-workspaces}/$project/repo" &&
sbx codex doctor "$project" &&
sbx codex login "$project" &&
sbx codex run "$project"
```

`init` creates the project folders, `doctor` checks the layout and image pins,
and `login` starts the chosen harness's authentication flow. Each harness has
its own login for the project. For a fresh repository, create a reviewed
baseline commit on the host before starting an agent. Linked Git worktrees
are not supported.

## Everyday use

Use the same project name and harness you selected during setup:

```bash
sbx codex run my-project
```

For a diagnostic shell, use `sbx codex shell my-project`. To run a specific
command, use `sbx codex exec my-project -- npm test`. Review and promote Git
changes from WSL, outside the container. Exit the current session before
starting another harness on the same project.

See the [Operator Guide](docs/OPERATOR-GUIDE.md) for authentication maintenance,
resource settings, and troubleshooting. `sbx --help` lists the command syntax;
`sbx version` shows the active runtime, CLI versions, and image selections.

## Updates

Before `run`, the host checks the kit's tracked Git remote and each harness's
published CLI release when its last check is at least 24 hours old. Notices
allow the selected CLI to run and leave versions unchanged. Checks run
concurrently with up to 15 seconds of network waiting; failed automatic checks
stay silent and are cached for 24 hours. Explicit checks always retry.
See [automatic-check controls](docs/OPERATOR-GUIDE.md#automatic-checks) to disable them.

To update Codex and continue on one project:

```bash
sbx codex-update --check &&
sbx codex-update my-project &&
sbx codex doctor my-project &&
sbx codex run my-project
```

Use `sbx opencode-update` or `sbx claude-update` for the other harnesses.
Each update proposes an exact release, asks for confirmation, and builds and
verifies its image before selecting it. Only that harness's image reference
in the named project changes. A failed build preserves the previous selection
and project. Model access follows your account and the service's availability.

To update the kit itself, use `sbx update --check`, then `sbx update my-project`.
This requires a clean kit checkout on a tracked branch. Review the printed
commits and diff before confirming. The command fast-forwards the source,
tests and installs the runtime, rebuilds changed image inputs, and applies
the selected images to the named project.

| Command | Effect |
| --- | --- |
| `sbx <agent>-update my-project` | Discovers and builds a CLI release; switches that harness in the project. |
| `sbx update my-project` | Updates kit source, runtime, and changed images; switches all project image references. |
| `sbx build` | Rebuilds the selected images. |
| `sbx upgrade my-project` | Switches all project references to the current selections without building or downloading. |

Here `<agent>` means `codex`, `opencode`, or `claude`. If startup reports a stale
project image, use the printed recovery command. New-release notices alone
do not require `upgrade`. The [update guide](docs/OPERATOR-GUIDE.md#installation-and-updates)
covers failed updates, saved selections, and reinstalling from a moved checkout.

## Project files and context

Projects default to `$HOME/agent-workspaces/<project>` in WSL. Set
`CODEX_SANDBOX_WORKSPACES_ROOT` to another WSL location before initializing a project.

| Host folder | Container path | Agent access |
| --- | --- | --- |
| `repo/` | `/workspace` | Writable; `.git` stays read-only |
| `context/` | `/context` | Read-only reference files |
| `data/` | `/data` | Writable, persistent outputs and state |
| `control/` | Not mounted | Host configuration and reports |

To supply reference files, select them in Windows Explorer, use **Copy as path**,
then run this in WSL:

```bash
sbx context my-project
```

Paste the quoted paths, one per line, and finish with a blank line. The command
copies the files into WSL and prints their `/context/...` paths. Originals stay
unchanged. Use `sbx context my-project list` to see the copies. See
[context management](docs/OPERATOR-GUIDE.md#external-context-and-data) for importing
WSL files, replacement, and deletion.

`context/` and `data/` are outside the repository, so `git add .` in `repo/`
does not stage them. The agent can read and upload their contents or copy them
into the repository. Back up important `/data` state separately from Git.

## Trust model

The host verifies container mounts and security settings before startup.
Sessions run as a non-root user with a read-only root filesystem, dropped
Linux capabilities, resource limits, and a shared project lock. Task, shell,
and exec sessions mount the harness's saved authentication read-only.

Containers receive no Windows drive, general WSL home, host credentials, or
Docker socket. The running agent can read its own login and supplied files,
and has internet access. The kit does not guarantee protection from Docker or
kernel vulnerabilities or preservation of writable repository and `/data` contents.
See the [security reference](docs/MAINTAINER-SECURITY.md) and [security policy](SECURITY.md).

## Included tools

All three images include Python **3.14.7**, pinned `uv`, Node.js/npm, Git,
Bash, search and archive utilities, C/C++ build tools, and Poppler PDF tools.
Project libraries are installed separately. See [Python and shared tools](docs/TOOLCHAIN.md)
for virtual environments, alternate Python versions, and persistent storage.

## Tests

From the kit checkout in WSL, run the complete Docker-free suite:

```bash
bash tests/static.sh
```

After building the pinned images, these smoke checks use disposable projects
and require no real credentials or model requests:

```bash
bash tests/smoke-codex.sh
bash tests/smoke-opencode.sh
bash tests/smoke-claude.sh
bash tests/smoke-toolchain.sh
```

For adapter implementation details, see [Adding an Agent](docs/ADDING-AN-AGENT.md).

## License

MIT. See [LICENSE](LICENSE).
