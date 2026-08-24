# Codex Sandbox Kit v2

This repository is the trusted WSL control plane for disposable Codex and
OpenCode coding containers. It replaces per-project copies of Dev Container
security controls with one versioned launcher.

The design keeps four durable boundaries:

- trusted WSL creates containers, verifies their complete configuration, and
  performs Git operations;
- a networked container can modify one public or synthetic repository but has
  no private inbox, host credentials, Docker socket, or WSL GUI socket;
- an offline container can read selected private fixtures but has no network
  and no agent installation;
- the user reviews and promotes changes manually from trusted WSL.

Codex commands are unchanged. A pinned OpenCode adapter (`run-opencode`,
`shell-opencode`, `exec-opencode`, `login-opencode`, `doctor-opencode`, ...)
runs side by side in a separate image with a separate per-project
authentication volume and the same container boundary.

The sandbox is designed for personal, reviewed projects stored in WSL where
WSL project data is disposable and GitHub is the durable source of truth.
Container boundaries isolate the agents from Windows files, the WSL home,
credentials, other projects, GitHub operations, and the Docker daemon;
repository text content itself is not treated as a security boundary (see
`docs/MAINTAINER-SECURITY.md`).

Start with [docs/OPERATOR-GUIDE.md](docs/OPERATOR-GUIDE.md). Security and
maintenance details are in
[docs/MAINTAINER-SECURITY.md](docs/MAINTAINER-SECURITY.md).

No existing project is migrated automatically. The kit is installed alongside
the older sandbox until a project is deliberately registered or migrated.

## Installation and rollback

The completed multi-agent kit is later cloned or copied side-by-side from this
source working copy (`~/src/codex-sandbox-kit-opencode-clean`) to:

```text
~/agent-sandbox-kit
```

Do not copy anything into or over `~/codex-sandbox-kit`. That directory is the
stable Codex-only fallback and must remain untouched. Rollback means stopping
use of `~/agent-sandbox-kit` and returning to `~/codex-sandbox-kit/bin/sandboxctl`;
nothing needs to be deleted, because both kits share the same
`~/agent-workspaces` project data layout.

