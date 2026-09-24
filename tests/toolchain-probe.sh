#!/usr/bin/env bash
# Runs inside the actual restricted task container. No network required.
set -euo pipefail
for tool in git bash find diff patch rg fd curl jq file tar gzip unzip zip cc c++ make pkg-config pdftotext pdftoppm node npm python python3 pip pip3 uv; do
  command -v "$tool" >/dev/null
done
python -c 'import sys,ssl,sqlite3,ctypes,bz2,lzma; assert sys.version_info[:2] == (3,14)'
test "$(python --version)" = "$(python3 --version)"
python -m pip --version
pip3 --version
uv --version
test ! -w /usr/local/bin
test ! -w /opt/python
mkdir -p /data/toolchain
printf '#include <stdio.h>\nint main(void){puts("compiler-ok");return 0;}\n' > /data/toolchain/probe.c
cc /data/toolchain/probe.c -o /data/toolchain/probe
test "$(/data/toolchain/probe)" = compiler-ok
printf '#include <iostream>\nint main(){std::cout << "cpp-ok";}\n' > /data/toolchain/probe.cpp
c++ /data/toolchain/probe.cpp -o /data/toolchain/cpp
test "$(/data/toolchain/cpp)" = cpp-ok
printf '{"ok":true}\n' | jq -e .ok
printf 'search-ok\n' > /data/toolchain/search.txt
rg -q search-ok /data/toolchain/search.txt
fd --base-directory /data/toolchain search | grep -qx search.txt
(cd /data/toolchain; zip -q probe.zip search.txt; unzip -p probe.zip search.txt | grep -qx search-ok)
uv venv --offline --python 3.14 /data/venv
/data/venv/bin/python -m ensurepip --default-pip
# Build a tiny pure-Python wheel locally to verify installation without PyPI.
python - <<'PY'
from pathlib import Path
from zipfile import ZipFile
p=Path('/data/toolchain/probe_pkg-1.0-py3-none-any.whl')
with ZipFile(p,'w') as z:
    z.writestr('probe_pkg.py','VALUE = 42\n')
    z.writestr('probe_pkg-1.0.dist-info/METADATA','Metadata-Version: 2.1\nName: probe-pkg\nVersion: 1.0\n')
    z.writestr('probe_pkg-1.0.dist-info/WHEEL','Wheel-Version: 1.0\nGenerator: smoke\nRoot-Is-Purelib: true\nTag: py3-none-any\n')
    z.writestr('probe_pkg-1.0.dist-info/RECORD','')
# Valid minimal PDF for actual extraction and rendering.
objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
 b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
 b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
stream=b'BT /F1 12 Tf 20 100 Td (pdf-ok) Tj ET'
objects.append(b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream')
out=bytearray(b'%PDF-1.4\n'); offsets=[0]
for i,obj in enumerate(objects,1):
    offsets.append(len(out)); out.extend(f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n')
xref=len(out); out.extend(b'xref\n0 6\n0000000000 65535 f \n')
for offset in offsets[1:]: out.extend(f'{offset:010d} 00000 n \n'.encode())
out.extend(f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
Path('/data/toolchain/probe.pdf').write_bytes(out)
PY
uv pip install --offline --python /data/venv/bin/python /data/toolchain/probe_pkg-1.0-py3-none-any.whl
/data/venv/bin/python -c 'import probe_pkg; assert probe_pkg.VALUE == 42'
/data/venv/bin/python -m pip check
pdftotext /data/toolchain/probe.pdf - | grep -q pdf-ok
pdftoppm -singlefile -scale-to 200 -png /data/toolchain/probe.pdf /data/toolchain/page
test -s /data/toolchain/page.png
# An older project can explicitly select the image's distro Python.
uv venv --offline --python /usr/bin/python3 /data/legacy-venv
/data/legacy-venv/bin/python -c 'import sys; assert sys.version_info[:2] != (3,14)'
mkdir /data/toolchain/project
printf '[project]\nname="smoke-project"\nversion="0.0.0"\nrequires-python=">=3.14"\ndependencies=[]\n' > /data/toolchain/project/pyproject.toml
(cd /data/toolchain/project; UV_PROJECT_ENVIRONMENT=/data/project-venv uv sync --offline)
test -x /data/project-venv/bin/python
test ! -d /data/toolchain/project/.venv
mkdir -p /home/node/.cache/uv
touch /home/node/.cache/uv/CACHED_SENTINEL
printf 'PASS: Python 3.14, uv/pip, project override, compilers, archives, search and PDF tools\n'
