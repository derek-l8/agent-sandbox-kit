# Codex Sandbox Kit v2

This repository is the trusted WSL control plane for disposable Codex coding
containers. It replaces per-project copies of Dev Container security controls
with one versioned launcher.

The design keeps four durable boundaries:

- trusted WSL creates containers, verifies their complete configuration, and
  performs Git operations;
- a networked container can modify one public or synthetic repository but has
  no private inbox, host credentials, Docker socket, or WSL GUI socket;
- an offline container can read selected private fixtures but has no network
  and no Codex installation;
- the user reviews and promotes changes manually from trusted WSL.

Start with [docs/OPERATOR-GUIDE.md](docs/OPERATOR-GUIDE.md). Security and
maintenance details are in
[docs/MAINTAINER-SECURITY.md](docs/MAINTAINER-SECURITY.md).

No existing project is migrated automatically. The kit is installed alongside
the older sandbox until a project is deliberately registered or migrated.

