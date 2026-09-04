#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../namespaces/

./cert-manager/install.sh
./external-secrets/install.sh
./openbao/install.sh

echo
echo "PARE AQUI."
echo "OpenBao precisa de init/unseal/login e ./openbao/bootstrap.sh"
echo "antes de instalar o authentik (ele depende do ExternalSecret)."
echo "Depois: ./authentik/install.sh"
