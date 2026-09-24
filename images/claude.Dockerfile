ARG BASE_IMAGE=invalid.local/claude-sandbox-base-must-be-supplied:0
FROM ${BASE_IMAGE}

ARG KIT_VERSION
ARG CLAUDE_VERSION
ARG CLAUDE_PACKAGE_INTEGRITY
ARG CLAUDE_LINUX_X64_INTEGRITY
ARG BASE_IMAGE

USER root

COPY versions.lock /tmp/toolchain-versions.lock
COPY container/install-toolchain.sh /tmp/install-toolchain.sh
RUN bash /tmp/install-toolchain.sh && rm /tmp/install-toolchain.sh

ENV UV_PYTHON_INSTALL_DIR=/data/python \
    UV_PYTHON_BIN_DIR=/data/bin \
    UV_PROJECT_ENVIRONMENT=/data/venv \
    UV_TOOL_DIR=/data/uv-tools \
    UV_TOOL_BIN_DIR=/data/bin \
    UV_CACHE_DIR=/home/node/.cache/uv \
    UV_LINK_MODE=copy

RUN test "$(npm view "@anthropic-ai/claude-code@${CLAUDE_VERSION}" dist.integrity)" = "${CLAUDE_PACKAGE_INTEGRITY}" \
    && test "$(npm view "@anthropic-ai/claude-code-linux-x64@${CLAUDE_VERSION}" dist.integrity)" = "${CLAUDE_LINUX_X64_INTEGRITY}" \
    && npm install --global "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
    && npm cache clean --force \
    && test "$(claude --version | awk '{print $1}')" = "${CLAUDE_VERSION}"

COPY config/claude-managed.json /etc/claude-code/managed-settings.json
COPY config/agent-workspace.md /etc/agent-workspace.md
COPY container/check-common.sh /usr/local/lib/codex-sandbox/check-common.sh
COPY container/check-claude-networked.sh /usr/local/bin/check-claude-networked-boundaries
COPY container/check-claude-login.sh /usr/local/bin/check-claude-login-boundaries
COPY container/prune-claude-auth-volume.sh /usr/local/lib/codex-sandbox/prune-claude-auth-volume
COPY container/run-with-claude-auth.sh /usr/local/bin/run-with-claude-auth
COPY container/start-claude-auth-session.sh /usr/local/bin/start-claude-auth-session
COPY container/start-claude-session.sh /usr/local/bin/start-claude-session

RUN chmod 0444 /etc/claude-code/managed-settings.json /etc/agent-workspace.md \
    && chmod 0555 /usr/local/lib/codex-sandbox/check-common.sh \
        /usr/local/lib/codex-sandbox/prune-claude-auth-volume \
        /usr/local/bin/check-claude-networked-boundaries \
        /usr/local/bin/check-claude-login-boundaries \
        /usr/local/bin/run-with-claude-auth \
        /usr/local/bin/start-claude-auth-session \
        /usr/local/bin/start-claude-session \
    && printf 'networked-public\n' > /etc/agent-mode \
    && chmod 0444 /etc/agent-mode \
    && mkdir -p /auth /home/node/.claude /home/node/.cache /workspace \
    && chown -R node:node /auth /home/node/.claude /home/node/.cache /workspace \
    && rm -f /etc/sudoers.d/node

LABEL org.opencontainers.image.title="Claude Code Sandbox Networked Runner" \
      io.codex-sandbox.kit.version="${KIT_VERSION}" \
      io.codex-sandbox.claude.version="${CLAUDE_VERSION}" \
      io.codex-sandbox.base.image="${BASE_IMAGE}" \
      io.codex-sandbox.mode="networked-public"

ENV CLAUDE_CONFIG_DIR=/home/node/.claude \
    DISABLE_UPDATES=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    AGENT_MODE=networked-public \
    GIT_OPTIONAL_LOCKS=0 \
    HISTFILE=/dev/null \
    XDG_CACHE_HOME=/home/node/.cache \
    NPM_CONFIG_CACHE=/home/node/.cache/npm \
    PIP_CACHE_DIR=/home/node/.cache/pip

USER node
WORKDIR /workspace
CMD ["claude", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands", "--append-system-prompt-file", "/etc/agent-workspace.md", "--dangerously-skip-permissions"]
