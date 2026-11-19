#!/usr/bin/env bash
set -Eeuo pipefail
work=${1:?Provide an empty build directory}
output=${2:?Provide an output directory}
test ! -e "$work"
mkdir -p "$work" "$output"
export CARGO_HOME="$work/cargo-home"
export CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=2
export PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig:/usr/lib/pkgconfig
export SSL_CERT_FILE="$GITHUB_WORKSPACE/components/public-ca-trust/ca-bundle.pem"
export SSL_CERT_DIR="$work/empty-ca-directory"
export CARGO_HTTP_CAINFO="$SSL_CERT_FILE"
mkdir "$SSL_CERT_DIR"

python -I - "$work" <<'PY'
import hashlib, io, pathlib, sys, tarfile, urllib.request
work = pathlib.Path(sys.argv[1])
url = 'https://codeload.github.com/Ntarasiuk/glass/tar.gz/7e79ded5790090c4bfd7f7701dc00143e4a61b88'
data = urllib.request.urlopen(url, timeout=60).read()
assert hashlib.sha256(data).hexdigest() == '348c69e4d779ff6b72a343ebbbc20491c5a7cdfc0f8919a4d1bc6720e6e13ecb'
with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
    archive.extractall(work, filter='data')
PY
source="$work/glass-7e79ded5790090c4bfd7f7701dc00143e4a61b88"
cd "$source"
cp Cargo.lock "$work/Cargo.lock.original"
cargo update -p webpki-roots@1.0.10 --precise 1.0.11
python -I - "$work/Cargo.lock.original" <<'PY'
import pathlib, sys, tomllib
old = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
new = tomllib.loads(pathlib.Path('Cargo.lock').read_text())
def packages(lock, version):
    result = [dict(p) for p in lock['package'] if not (p['name'] == 'webpki-roots' and p['version'] == version)]
    for package in result:
        if 'dependencies' in package:
            package['dependencies'] = [d.replace('webpki-roots 1.0.10', 'webpki-roots 1.0.11') for d in package['dependencies']]
    return result
assert packages(old, '1.0.10') == packages(new, '1.0.11'), 'Unexpected dependency changes'
assert any(p['name'] == 'webpki-roots' and p['version'] == '1.0.11' for p in new['package'])
assert not any(p['name'] == 'webpki-roots' and p['version'] == '1.0.10' for p in new['package'])
print('PASS only webpki-roots 1.0.10 -> 1.0.11 changed')
PY
cargo build --locked --release -p glass-host -p glass-gst
cargo tree --locked -e normal -p glass-host -i webpki-roots@1.0.11
cargo test --locked --release -p glass-host remote::tests
python -I - "$CARGO_HOME" <<'PY'
import pathlib, sys
roots = list(pathlib.Path(sys.argv[1]).glob('registry/src/*/webpki-roots-1.0.11/src/lib.rs'))
assert len(roots) == 1
text = roots[0].read_text()
assert 'ISRG Root X1' in text, 'Positive control trust anchor was not found'
for label in ['emSign Root CA - C1', 'emSign ECC Root CA - C3']:
    assert label not in text, f'Excluded trust anchor remains: {label}'
print('PASS both excluded certificate authorities are absent')
PY
target/release/glass-host --version
stage="$output/stage/glass"
mkdir -p "$stage/bin" "$stage/share/glass"
install -m 0755 target/release/glass-host "$stage/bin/glass"
install -m 0755 target/release/libglass_gst.so "$stage/share/glass/"
cp -R web "$stage/share/glass/web"
cp LICENSE "$stage/share/glass/LICENSE.upstream"
cp Cargo.lock "$output/Cargo.lock"
diff -u "$work/Cargo.lock.original" Cargo.lock > "$output/Cargo.lock.patch" || test "$?" = 1
archive=glass-starport-0.15.3-roots1-linux-x86_64.tar.gz
tar -C "$output/stage" -czf "$output/$archive" glass
(cd "$output" && sha256sum "$archive" > "$archive.sha256")
rm -rf "$output/stage"
printf 'upstream=7e79ded5790090c4bfd7f7701dc00143e4a61b88\nsource_commit=%s\nwebpki_roots=1.0.11\n' "$GITHUB_SHA" > "$output/build-info.txt"
