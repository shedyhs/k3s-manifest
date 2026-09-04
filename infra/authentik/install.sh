#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CHART_VERSION="2026.8.1"

helm repo add authentik https://charts.goauthentik.io
helm repo update authentik

helm upgrade --install authentik authentik/authentik \
  --namespace authentik \
  --create-namespace \
  --version "$CHART_VERSION" \
  -f values.yaml \
  --wait --timeout 10m

echo
echo "Pós-instalação (manual):"
echo "  - Database e user 'authentik' precisam existir no Postgres em dev"
echo "  - Segredo secret/authentik precisa existir no OpenBao"
echo "  - Primeiro acesso: https://auth.shedy.xyz/if/flow/initial-setup/"
echo "  - Para proteger apps: associar Application ao Embedded Outpost pela UI"
