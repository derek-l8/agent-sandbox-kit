#!/usr/bin/env bash
# Build-time only. Never run this installer in an agent session.
set -euo pipefail
source /tmp/toolchain-versions.lock
[[ "$(dpkg --print-architecture)" == amd64 ]] || { echo 'Only Linux x86_64 is supported' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  bash coreutils findutils diffutils patch git curl ca-certificates \
  ripgrep fd-find jq file tar gzip unzip zip build-essential pkg-config poppler-utils
rm -rf /var/lib/apt/lists/*
ln -sf /usr/bin/fdfind /usr/local/bin/fd

curl --fail --location --retry 3 "$UV_WHEEL_URL" -o /tmp/uv.whl
printf '%s  /tmp/uv.whl\n' "$UV_WHEEL_SHA256" | sha256sum --check --strict
mkdir /tmp/uv-wheel
unzip -q /tmp/uv.whl -d /tmp/uv-wheel
install -m 0755 "/tmp/uv-wheel/uv-${UV_VERSION}.data/scripts/uv" /usr/local/bin/uv
install -m 0755 "/tmp/uv-wheel/uv-${UV_VERSION}.data/scripts/uvx" /usr/local/bin/uvx
test "$(uv --version | awk '{print $2}')" = "$UV_VERSION"
# The pinned uv release embeds the download URL and checksum for this CPython
# distribution. The image interpreter stays root-owned; extra versions go to /data.
UV_PYTHON_INSTALL_DIR=/opt/python UV_PYTHON_BIN_DIR=/usr/local/bin \
  uv python install "$PYTHON_VERSION" --default
python3 -c 'import sys; assert sys.version.split()[0] == sys.argv[1]' "$PYTHON_VERSION"
# Populate pip from Python's bundled wheel only while building. Keep uv's
# EXTERNALLY-MANAGED marker; the override applies only to this build command.
pip_wheel="$(python3 -c 'import ensurepip,pathlib; print(next((pathlib.Path(ensurepip.__file__).parent / "_bundled").glob("pip-*.whl")))')"
uv pip install --offline --python /usr/local/bin/python3 --break-system-packages "$pip_wheel"
ln -sf "$(dirname "$(readlink -f /usr/local/bin/python3)")/pip3" /usr/local/bin/pip3
ln -sf /usr/local/bin/pip3 /usr/local/bin/pip
python -m pip --version
dpkg-query -W > /usr/local/share/agent-sandbox-packages.txt
rm -rf /tmp/uv.whl /tmp/uv-wheel /tmp/toolchain-versions.lock /root/.cache/uv
