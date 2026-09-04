#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CHART_VERSION="v1.21.1"

helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "$CHART_VERSION" \
  -f values.yaml \
  --wait

kubectl apply -f clusterissuer-staging.yaml
kubectl apply -f clusterissuer-prod.yaml
