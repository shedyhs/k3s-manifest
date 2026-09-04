#!/usr/bin/env bash
# Configura auth, policies e secrets engines do OpenBao.
# Requer: cofre inicializado, desselado e login feito com root token.
# Idempotente: pode rodar novamente sem quebrar.
set -euo pipefail

NS=openbao
POD=openbao-0

bao() { kubectl exec -n "$NS" -i "$POD" -- bao "$@"; }

echo "==> KV v2 em secret/"
bao secrets list -format=json | grep -q '"secret/"' \
  || bao secrets enable -path=secret kv-v2

echo "==> auth kubernetes"
bao auth list -format=json | grep -q '"kubernetes/"' \
  || bao auth enable kubernetes

echo "==> config do auth kubernetes"
kubectl exec -n "$NS" -i "$POD" -- sh -c '
bao write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
'

echo "==> policy postgres-read"
kubectl exec -n "$NS" -i "$POD" -- sh -c '
bao policy write postgres-read - <<POLICY
path "secret/data/postgres" {
  capabilities = ["read"]
}
POLICY
'

echo "==> role postgres-role"
bao write auth/kubernetes/role/postgres-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=postgres-read \
  ttl=1h

echo "==> pronto"
