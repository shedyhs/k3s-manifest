#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CHART_VERSION="2.10.0"

helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version "$CHART_VERSION" \
  -f values.yaml \
  --wait
