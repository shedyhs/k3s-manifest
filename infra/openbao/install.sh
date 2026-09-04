#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CHART_VERSION="0.29.4"   # app v2.6.2

helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update openbao

helm upgrade --install openbao openbao/openbao \
  --namespace openbao \
  --create-namespace \
  --version "$CHART_VERSION" \
  -f values.yaml

echo
echo "Pós-instalação (manual):"
echo "  1. bao operator init -key-shares=3 -key-threshold=2   (só na primeira vez)"
echo "  2. bao operator unseal   (2x, após todo restart)"
echo "  3. bao login"
echo "  4. ./bootstrap.sh"
