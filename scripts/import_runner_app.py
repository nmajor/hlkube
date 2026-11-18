#!/usr/bin/env python3
"""Import the organization runner App without printing or persisting API tokens."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ORG = "nmajorstudios"
ROOT = Path(__file__).resolve().parents[1]
SECRET = ROOT / "runners" / ORG / "github-app.secret"
REQUIRED_PERMISSION = "organization_self_hosted_runners"


def api(method, path, token, data=None):
    request = urllib.request.Request(
        "https://api.github.com" + path,
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/vnd.github+json",
                 "Content-Type": "application/json",
                 "User-Agent": "hlkube-runner-app-setup"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        # Never include response bodies or credentials in diagnostics.
        raise RuntimeError(f"GitHub API {method} {path}: HTTP {error.code}") from None
    except urllib.error.URLError:
        raise RuntimeError("Unable to reach the GitHub API") from None


def validate_permissions(permissions):
    if permissions.get(REQUIRED_PERMISSION) != "write":
        raise RuntimeError("App needs Organization permissions: Self-hosted runners Read and write")
    allowed = {REQUIRED_PERMISSION: "write", "metadata": "read"}
    if any(value not in (None, "none") and allowed.get(key) != value
           for key, value in permissions.items()):
        raise RuntimeError("App has additional permissions; remove them before importing")


def jwt(app_id, key):
    def encode(value):
        return base64.urlsafe_b64encode(value).rstrip(b"=")
    now = int(time.time())
    header = encode(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    payload = encode(json.dumps({"iat": now - 60, "exp": now + 540, "iss": app_id}).encode())
    unsigned = header + b"." + payload
    result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key)],
                            input=unsigned, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("OpenSSL could not sign with the supplied private key")
    return (unsigned + b"." + encode(result.stdout)).decode()


def verify_runner_group(token, configure):
    def workflow_restricted(group):
        # Some plans omit workflow-restriction fields entirely.
        return group.get("restricted_to_workflows", bool(group.get("selected_workflows")))

    path = f"/orgs/{ORG}/actions/runner-groups"
    groups = api("GET", path + "?per_page=100", token)["runner_groups"]
    defaults = [group for group in groups if group.get("default")]
    if len(defaults) != 1:
        raise RuntimeError("Expected one default organization runner group")
    group = defaults[0]
    desired = {"visibility": "all", "allows_public_repositories": False,
               "restricted_to_workflows": False}
    # 'private' already covers all future private repositories too.
    changes = {key: value for key, value in desired.items()
               if (workflow_restricted(group) if key == "restricted_to_workflows" else group.get(key)) != value
               and not (key == "visibility" and group.get(key) == "private")}
    if changes:
        if not configure:
            raise RuntimeError("Runner group needs configuration; rerun with --configure-runner-group")
        api("PATCH", path + f"/{group['id']}", token, changes)
        group = api("GET", path + f"/{group['id']}", token)
    if (group.get("visibility") not in ("all", "private")
            or group.get("allows_public_repositories") is not False
            or workflow_restricted(group) is not False):
        raise RuntimeError("Runner group must allow all private repos, exclude public repos and have no workflow allowlist")
    return group


def write_secret(path, app_id, installation_id, pem):
    content = ("apiVersion: v1\nkind: Secret\nmetadata:\n"
               "  name: nmajorstudios-runner-app\n  namespace: arc-nmajorstudios\n"
               "type: Opaque\nstringData:\n"
               f'  github_app_id: "{app_id}"\n'
               f'  github_app_installation_id: "{installation_id}"\n'
               "  github_app_private_key: |\n"
               + "".join("    " + line + "\n" for line in pem.splitlines()))
    # Atomic replacement: plaintext is never created with permissive file modes.
    # This ignored suffix is also excluded from seal-secrets.sh's *.secret scan
    # if a hard-killed import leaves its temporary file behind.
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent,
                                     prefix=".runner-app-import-", suffix=".secret.yaml", delete=False) as handle:
        temporary = Path(handle.name)
        try:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--configure-runner-group", action="store_true")
    args = parser.parse_args()
    if not args.app_id.isdigit():
        parser.error("--app-id must be the numeric GitHub App ID")
    key = args.private_key.expanduser().resolve(strict=True)
    if subprocess.run(["git", "check-ignore", "--quiet", str(SECRET)], cwd=ROOT).returncode:
        raise RuntimeError("Refusing to write a credential that is not gitignored")
    app_jwt = jwt(args.app_id, key)
    app = api("GET", "/app", app_jwt)
    if app["owner"]["login"].lower() != ORG or str(app["id"]) != args.app_id:
        raise RuntimeError("App must be owned by nmajorstudios and match the supplied App ID")
    validate_permissions(app["permissions"])
    installations = api("GET", "/app/installations?per_page=100", app_jwt)
    installations = [item for item in installations if item["account"]["login"].lower() == ORG]
    if len(installations) != 1 or installations[0].get("suspended_at"):
        raise RuntimeError("Install and enable this App on nmajorstudios before importing")
    installation = installations[0]
    validate_permissions(installation["permissions"])
    token = api("POST", f"/app/installations/{installation['id']}/access_tokens", app_jwt,
                {"permissions": {REQUIRED_PERMISSION: "write"}})["token"]
    try:
        group = verify_runner_group(token, args.configure_runner_group)
        write_secret(SECRET, args.app_id, installation["id"], key.read_text())
        print(f"Verified App {app['slug']} and installation {installation['id']}")
        print(f"Runner group {group['name']}: all private repositories; public repositories disabled")
        print(f"Credential saved with mode 0600: {SECRET.relative_to(ROOT)}")
        print("Next: run ./seal-secrets.sh and commit only the generated sealed YAML")
    finally:
        try:
            api("DELETE", "/installation/token", token)
        except RuntimeError:
            print("Temporary setup token could not be revoked; it expires automatically", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, KeyError) as error:
        raise SystemExit(str(error)) from None
