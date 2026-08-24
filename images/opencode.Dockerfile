ARG BASE_IMAGE=invalid.local/codex-sandbox-base-must-be-supplied:0
FROM ${BASE_IMAGE}

ARG KIT_VERSION
ARG OPENCODE_VERSION
ARG OPENCODE_PACKAGE_INTEGRITY
ARG OPENCODE_LINUX_X64_INTEGRITY
ARG BASE_IMAGE

USER root

RUN test "$(npm view "opencode-ai@${OPENCODE_VERSION}" dist.integrity)" = "${OPENCODE_PACKAGE_INTEGRITY}" \
    && test "$(npm view "opencode-linux-x64@${OPENCODE_VERSION}" dist.integrity)" = "${OPENCODE_LINUX_X64_INTEGRITY}" \
    && npm install --global "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force \
    && test "$(opencode --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)" = "${OPENCODE_VERSION}"

COPY config/opencode-managed.json /etc/opencode/opencode.json
COPY container/check-common.sh /usr/local/lib/codex-sandbox/check-common.sh
COPY container/prune-auth-volume.sh /usr/local/lib/codex-sandbox/prune-auth-volume
COPY container/check-opencode-networked.sh /usr/local/bin/check-opencode-networked-boundaries
COPY container/check-opencode-login.sh /usr/local/bin/check-opencode-login-boundaries
COPY container/run-with-opencode-auth.sh /usr/local/bin/run-with-opencode-auth
COPY container/start-opencode-auth-session.sh /usr/local/bin/start-opencode-auth-session
COPY container/start-opencode-session.sh /usr/local/bin/start-opencode-session

RUN chmod 0555 /etc/opencode \
    && chmod 0444 /etc/opencode/opencode.json \
    && chmod 0555 /usr/local/lib/codex-sandbox/check-common.sh \
        /usr/local/lib/codex-sandbox/prune-auth-volume \
        /usr/local/bin/check-opencode-networked-boundaries \
        /usr/local/bin/check-opencode-login-boundaries \
        /usr/local/bin/run-with-opencode-auth \
        /usr/local/bin/start-opencode-auth-session \
        /usr/local/bin/start-opencode-session \
    && printf 'networked-public\n' > /etc/agent-mode \
    && chmod 0444 /etc/agent-mode \
    && mkdir -p /auth /workspace \
        /home/node/.cache /home/node/.config \
        /home/node/.local/share/opencode \
        /home/node/.local/state \
    && chown -R node:node /auth /home/node/.cache /home/node/.config \
        /home/node/.local/share/opencode /home/node/.local/state /workspace \
    && rm -f /etc/sudoers.d/node

LABEL org.opencontainers.image.title="Codex Sandbox OpenCode Runner" \
      io.codex-sandbox.kit.version="${KIT_VERSION}" \
      io.codex-sandbox.opencode.version="${OPENCODE_VERSION}" \
      io.codex-sandbox.opencode.package-integrity="${OPENCODE_PACKAGE_INTEGRITY}" \
      io.codex-sandbox.opencode.linux-x64-integrity="${OPENCODE_LINUX_X64_INTEGRITY}" \
      io.codex-sandbox.base.image="${BASE_IMAGE}" \
      io.codex-sandbox.mode="networked-public"

ENV AGENT_MODE=networked-public \
    GIT_OPTIONAL_LOCKS=0 \
    HISTFILE=/dev/null \
    XDG_CACHE_HOME=/home/node/.cache \
    XDG_CONFIG_HOME=/home/node/.config \
    NPM_CONFIG_CACHE=/home/node/.cache/npm \
    PIP_CACHE_DIR=/home/node/.cache/pip \
    OPENCODE_DISABLE_AUTOUPDATE=true \
    OPENCODE_DISABLE_DEFAULT_PLUGINS=true \
    OPENCODE_DISABLE_LSP_DOWNLOAD=true \
    OPENCODE_DISABLE_PROJECT_CONFIG=1

USER node
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/start-opencode-session"]
CMD ["opencode", "--pure"]
