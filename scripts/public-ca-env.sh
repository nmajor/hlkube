#!/usr/bin/env sh
# Source with HLKUBE_CA_ROOT set to this repository's reviewed CA component.
# These variables select a replacement trust store, not extra trusted roots.
if [ -z "${HLKUBE_CA_ROOT:-}" ] || [ ! -r "${HLKUBE_CA_ROOT}/ca-bundle.pem" ]; then
  printf '%s\n' 'HLKUBE_CA_ROOT must name the reviewed public-ca-trust directory.' >&2
  return 1
fi
export SSL_CERT_FILE="${HLKUBE_CA_ROOT}/ca-bundle.pem"
export SSL_CERT_DIR="${HLKUBE_CA_ROOT}/empty"
export CURL_CA_BUNDLE="$SSL_CERT_FILE"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
export PIP_CERT="$SSL_CERT_FILE"
export GIT_SSL_CAINFO="$SSL_CERT_FILE"
export AWS_CA_BUNDLE="$SSL_CERT_FILE"
export HEX_CACERTS_PATH="$SSL_CERT_FILE"
case " ${NODE_OPTIONS:-} " in
  *' --use-openssl-ca '*) ;;
  *) export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--use-openssl-ca" ;;
esac
case " ${JAVA_TOOL_OPTIONS:-} " in
  *" -Djavax.net.ssl.trustStore=${HLKUBE_CA_ROOT}/cacerts "*) ;;
  *) export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }-Djavax.net.ssl.trustStore=${HLKUBE_CA_ROOT}/cacerts -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=JKS" ;;
esac
