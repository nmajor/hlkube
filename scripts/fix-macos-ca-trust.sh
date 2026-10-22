#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This helper is only for the macOS command-line CA bundle.' >&2
  exit 1
fi

task_tmp="$(mktemp -d "${TMPDIR:-/tmp}/hlkube-macos-ca.XXXXXX")"
trap 'rm -rf "$task_tmp"' EXIT

# Preserve every existing certificate except the two incident-affected roots.
python3 - /etc/ssl/cert.pem "$task_tmp/cert.pem" <<'PY'
import hashlib, pathlib, re, ssl, sys
bad = {
    'd7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4',
    '86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b',
}
text = pathlib.Path(sys.argv[1]).read_text()
removed = []
def replace(match):
    digest = hashlib.sha256(ssl.PEM_cert_to_DER_cert(match.group())).hexdigest()
    if digest in bad:
        removed.append(digest)
        return ''
    return match.group()
fixed = re.sub(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', replace, text, flags=re.S)
if not re.search(r'-----BEGIN CERTIFICATE-----', fixed):
    raise SystemExit('Refusing to write an empty CA bundle.')
pathlib.Path(sys.argv[2]).write_text(fixed)
print(f'Removed {len(removed)} affected trust roots; other certificate bytes preserved.')
PY

backup=/etc/ssl/cert.pem.hlkube-backup-20261021
if [[ ! -e "$backup" ]]; then
  sudo cp -p /etc/ssl/cert.pem "$backup"
fi
sudo install -m 0644 "$task_tmp/cert.pem" /etc/ssl/cert.pem
echo "Updated /etc/ssl/cert.pem. Original backup: $backup"
