#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLPLANE_YAML="${CONTROLPLANE_YAML:-$ROOT_DIR/talos-cluster/controlplane.yaml}"
TALOSCONFIG_OUT="${TALOSCONFIG_OUT:-$ROOT_DIR/talos-cluster/talosconfig}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$ROOT_DIR/kubeconfig}"
TALOS_CONTEXT="${TALOS_CONTEXT:-hlkube-cluster}"
TALOS_ENDPOINTS="${TALOS_ENDPOINTS:-192.168.10.10,192.168.10.11,192.168.10.12,192.168.10.13}"
KUBECONFIG_NODE="${KUBECONFIG_NODE:-192.168.10.11}"
TALOS_CERT_HOURS="${TALOS_CERT_HOURS:-8760}"
INSTALL_HOME_TALOSCONFIG="${INSTALL_HOME_TALOSCONFIG:-1}"
INSTALL_HOME_KUBECONFIG="${INSTALL_HOME_KUBECONFIG:-0}"
VERIFY_CLUSTER="${VERIFY_CLUSTER:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd ruby
require_cmd talosctl
require_cmd base64
require_cmd openssl

if [[ "$VERIFY_CLUSTER" == "1" ]]; then
  require_cmd kubectl
fi

if [[ ! -f "$CONTROLPLANE_YAML" ]]; then
  echo "Missing control plane machine config: $CONTROLPLANE_YAML" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hlkube-auth.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
umask 077

IFS=',' read -r -a ENDPOINTS_ARRAY <<< "$TALOS_ENDPOINTS"
FIRST_ENDPOINT="${ENDPOINTS_ARRAY[0]}"

ruby -e 'require "yaml"; c=YAML.load_file(ARGV[0]); puts c.fetch("machine").fetch("ca").fetch("crt")' \
  "$CONTROLPLANE_YAML" | base64 -d > "$TMP_DIR/ca.crt"
ruby -e 'require "yaml"; c=YAML.load_file(ARGV[0]); puts c.fetch("machine").fetch("ca").fetch("key")' \
  "$CONTROLPLANE_YAML" | base64 -d > "$TMP_DIR/ca.key"

talosctl gen key --force --name "$TMP_DIR/admin" >/dev/null
talosctl gen csr --force --key "$TMP_DIR/admin.key" --ip 127.0.0.1 --roles os:admin >/dev/null
talosctl gen crt --force --ca "$TMP_DIR/ca" --csr "$TMP_DIR/admin.csr" --hours "$TALOS_CERT_HOURS" --name "$TMP_DIR/admin" >/dev/null

mkdir -p "$(dirname "$TALOSCONFIG_OUT")"
ruby -e '
  require "yaml"
  require "base64"

  endpoints = ARGV[0].split(",")
  talosconfig = {
    "context" => ARGV[1],
    "contexts" => {
      ARGV[1] => {
        "endpoints" => endpoints,
        "ca" => Base64.strict_encode64(File.binread(ARGV[2])),
        "crt" => Base64.strict_encode64(File.binread(ARGV[3])),
        "key" => Base64.strict_encode64(File.binread(ARGV[4]))
      }
    }
  }

  File.write(ARGV[5], YAML.dump(talosconfig))
  ' \
  "$TALOS_ENDPOINTS" \
  "$TALOS_CONTEXT" \
  "$TMP_DIR/ca.crt" \
  "$TMP_DIR/admin.crt" \
  "$TMP_DIR/admin.key" \
  "$TALOSCONFIG_OUT"
chmod 600 "$TALOSCONFIG_OUT"

if [[ "$INSTALL_HOME_TALOSCONFIG" == "1" ]]; then
  mkdir -p "$HOME/.talos"
  cp "$TALOSCONFIG_OUT" "$HOME/.talos/config"
  chmod 600 "$HOME/.talos/config"
fi

RAW_KUBECONFIG="$TMP_DIR/kubeconfig.raw"
NORMALIZED_KUBECONFIG="$TMP_DIR/kubeconfig"
talosctl \
  --talosconfig "$TALOSCONFIG_OUT" \
  -e "$FIRST_ENDPOINT" \
  -n "$KUBECONFIG_NODE" \
  kubeconfig "$RAW_KUBECONFIG" \
  --merge=false >/dev/null

ruby -e '
  require "yaml"

  config = YAML.load_file(ARGV[0])
  current = config.fetch("current-context")
  context = config.fetch("contexts").find { |entry| entry.fetch("name") == current } || config.fetch("contexts").last
  cluster_name = context.fetch("context").fetch("cluster")
  user_name = context.fetch("context").fetch("user")
  cluster = config.fetch("clusters").find { |entry| entry.fetch("name") == cluster_name } || config.fetch("clusters").last
  user = config.fetch("users").find { |entry| entry.fetch("name") == user_name } || config.fetch("users").last
  stable_user_name = "admin@#{cluster_name}"

  normalized = {
    "apiVersion" => "v1",
    "kind" => "Config",
    "preferences" => {},
    "clusters" => [
      {
        "name" => cluster_name,
        "cluster" => cluster.fetch("cluster")
      }
    ],
    "users" => [
      {
        "name" => stable_user_name,
        "user" => user.fetch("user")
      }
    ],
    "contexts" => [
      {
        "name" => stable_user_name,
        "context" => {
          "cluster" => cluster_name,
          "namespace" => "default",
          "user" => stable_user_name
        }
      }
    ],
    "current-context" => stable_user_name
  }

  File.write(ARGV[1], YAML.dump(normalized))
  ' \
  "$RAW_KUBECONFIG" \
  "$NORMALIZED_KUBECONFIG"

mkdir -p "$(dirname "$KUBECONFIG_OUT")"
cp "$NORMALIZED_KUBECONFIG" "$KUBECONFIG_OUT"
chmod 600 "$KUBECONFIG_OUT"

if [[ "$INSTALL_HOME_KUBECONFIG" == "1" ]]; then
  mkdir -p "$HOME/.kube"
  cp "$KUBECONFIG_OUT" "$HOME/.kube/config"
  chmod 600 "$HOME/.kube/config"
fi

echo "Refreshed Talos and Kubernetes client credentials."
echo
echo "Talos certificate:"
ruby -e 'require "yaml"; c=YAML.load_file(ARGV[0]); puts c.fetch("contexts").fetch(ARGV[1]).fetch("crt")' \
  "$TALOSCONFIG_OUT" "$TALOS_CONTEXT" | base64 -d | openssl x509 -noout -dates -subject
echo
echo "Kubernetes certificate:"
ruby -e '
  require "yaml"
  c = YAML.load_file(ARGV[0])
  current = c.fetch("current-context")
  context = c.fetch("contexts").find { |entry| entry.fetch("name") == current }
  user_name = context.fetch("context").fetch("user")
  user = c.fetch("users").find { |entry| entry.fetch("name") == user_name }
  puts user.fetch("user").fetch("client-certificate-data")
  ' "$KUBECONFIG_OUT" | base64 -d | openssl x509 -noout -dates -subject

if [[ "$VERIFY_CLUSTER" == "1" ]]; then
  echo
  echo "Talos access check:"
  talosctl --talosconfig "$TALOSCONFIG_OUT" -e "$FIRST_ENDPOINT" config info

  echo
  echo "Kubernetes access check:"
  kubectl --kubeconfig "$KUBECONFIG_OUT" get nodes -o wide
fi
