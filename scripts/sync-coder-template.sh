#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TEMPLATE_NAME="${CODER_TEMPLATE_NAME:-elixirphoenixpostgres}"
TEMPLATE_DIR="${CODER_TEMPLATE_DIR:-apps/third-party/coder/templates/elixir-phoenix-postgres}"
CODER_URL="${CODER_URL:-https://coder.nmajor.net}"
MESSAGE="${CODER_TEMPLATE_MESSAGE:-Sync ${TEMPLATE_NAME} from Git}"
VERSION_NAME="${CODER_TEMPLATE_VERSION_NAME:-manual-$(date +%Y%m%d%H%M%S)}"
ACTIVATE="${CODER_TEMPLATE_ACTIVATE:-true}"
WORKSPACE_AUTOUPDATE="${CODER_TEMPLATE_WORKSPACE_AUTOUPDATE:-true}"

for command in curl jq tar coder; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: ${command} is not installed or is not on PATH" >&2
    exit 1
  fi
done

if [[ ! -f "${REPO_ROOT}/${TEMPLATE_DIR}/main.tf" ]]; then
  echo "error: template main.tf not found at ${REPO_ROOT}/${TEMPLATE_DIR}/main.tf" >&2
  exit 1
fi

if [[ -z "${CODER_SESSION_TOKEN:-}" ]]; then
  session_file="${CODER_CONFIG_DIR:-${HOME}/Library/Application Support/coderv2}/session"
  if [[ -f "${session_file}" ]]; then
    CODER_SESSION_TOKEN="$(<"${session_file}")"
  fi
fi

if [[ -z "${CODER_SESSION_TOKEN:-}" ]]; then
  echo "error: CODER_SESSION_TOKEN is not set and no local Coder session was found" >&2
  echo "hint: run 'coder login ${CODER_URL}' or set CODER_SESSION_TOKEN" >&2
  exit 1
fi

api() {
  curl -fsS \
    -H "Coder-Session-Token: ${CODER_SESSION_TOKEN}" \
    -H "Accept: application/json" \
    "$@"
}

echo "Syncing Coder template '${TEMPLATE_NAME}' from ${TEMPLATE_DIR}"
echo "Coder URL: ${CODER_URL}"
echo "Version name: ${VERSION_NAME}"

template_json="$(api "${CODER_URL}/api/v2/templates" | jq -e --arg name "${TEMPLATE_NAME}" '.[] | select(.name == $name)')"
template_id="$(jq -r '.id' <<<"${template_json}")"
organization_id="$(jq -r '.organization_id' <<<"${template_json}")"

archive="$(mktemp -t "${TEMPLATE_NAME}.XXXXXX.tar")"
trap 'rm -f "${archive}"' EXIT

tar --format ustar -C "${REPO_ROOT}/${TEMPLATE_DIR}" -cf "${archive}" .
archive_size="$(wc -c <"${archive}" | tr -d ' ')"
if [[ "${archive_size}" == "0" ]]; then
  echo "error: generated template archive is empty" >&2
  exit 1
fi

echo "Uploading template archive (${archive_size} bytes)"
file_id="$(
  api -X POST \
    -H "Content-Type: application/x-tar" \
    --data-binary @"${archive}" \
    "${CODER_URL}/api/v2/files" |
    jq -r '.hash'
)"

echo "Creating template version"
version_json="$(
  jq -n \
    --arg file_id "${file_id}" \
    --arg message "${MESSAGE}" \
    --arg name "${VERSION_NAME}" \
    --arg template_id "${template_id}" \
    '{
      file_id: $file_id,
      message: $message,
      name: $name,
      provisioner: "terraform",
      storage_method: "file",
      template_id: $template_id
    }' |
    api -X POST \
      -H "Content-Type: application/json" \
      --data-binary @- \
      "${CODER_URL}/api/v2/organizations/${organization_id}/templateversions"
)"

version_id="$(jq -r '.id' <<<"${version_json}")"

echo "Waiting for template version import"
for _ in {1..120}; do
  version_json="$(api "${CODER_URL}/api/v2/templateversions/${version_id}")"
  status="$(jq -r '.job.status' <<<"${version_json}")"
  case "${status}" in
    succeeded)
      echo "Template version import succeeded"
      break
      ;;
    failed|canceled)
      echo "Template version import ${status}" >&2
      api "${CODER_URL}/api/v2/templateversions/${version_id}/logs?format=text" >&2 || true
      exit 1
      ;;
  esac
  sleep 2
done

if [[ "${status}" != "succeeded" ]]; then
  echo "error: timed out waiting for template version import" >&2
  exit 1
fi

if [[ "${ACTIVATE}" == "true" ]]; then
  echo "Promoting template version to active"
  jq -n --arg id "${version_id}" '{id: $id}' |
    api -X PATCH \
      -H "Content-Type: application/json" \
      --data-binary @- \
      "${CODER_URL}/api/v2/templates/${template_id}/versions" >/dev/null
fi

if [[ "${WORKSPACE_AUTOUPDATE}" == "true" ]]; then
  echo "Ensuring workspaces using ${TEMPLATE_NAME} auto-update on start"
  while IFS= read -r workspace; do
    [[ -n "${workspace}" ]] || continue
    coder --url "${CODER_URL}" autoupdate "${workspace}" always -y >/dev/null
    echo "Auto-update enabled: ${workspace}"
  done < <(
    coder --url "${CODER_URL}" list --all --output json |
      jq -r --arg template "${TEMPLATE_NAME}" '.[] | select(.template_name == $template) | "\(.owner_name)/\(.name)"'
  )
fi

echo
echo "Template versions:"
coder --url "${CODER_URL}" templates versions list "${TEMPLATE_NAME}"

echo
echo "Workspace template status:"
coder --url "${CODER_URL}" list --all \
  --column workspace \
  --column template \
  --column status \
  --column "current version" \
  --column outdated
