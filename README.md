# k3s-manifest

Manifests do cluster k3s rodando em `shedy.xyz` (VPS única, 4 GB RAM).

## O que roda aqui

| Domínio | Aplicação | Namespace |
|---|---|---|
| `app.shedy.xyz` | nginx (teste) | `dev` |
| `shedy.xyz` | nginx (teste) | `dev` |
| `o11y.shedy.xyz` | nginx (reservado p/ observabilidade) | `dev` |
| `draw.shedy.xyz` | Excalidraw + room (atrás do authentik) | `dev` |
| `auth.shedy.xyz` | authentik | `authentik` |
| — | PostgreSQL | `dev` |
| — | OpenBao | `openbao` |

## Versões

| Componente | Chart | App |
|---|---|---|
| k3s | — | `v1.36.4+k3s1` |
| Traefik (gerenciado pelo k3s) | `traefik-40.1.4+up40.1.0` | `v3.7.1` |
| cert-manager | `v1.21.1` | `v1.21.1` |
| external-secrets | `2.10.0` | `v2.10.0` |
| OpenBao | `0.29.4` | `v2.6.2` |
| authentik | `2026.8.1` | `2026.8.1` |

Imagens: `postgres:16-alpine`, `nginx:1.27-alpine`, `excalidraw/excalidraw:latest`,
`excalidraw/excalidraw-room:latest`.

> As duas imagens do Excalidraw usam `latest` — ainda não pinadas.

## Estrutura

```
namespaces/     Namespaces (cluster-scoped, aplicar primeiro)
infra/          Infraestrutura compartilhada: charts Helm + bootstrap
apps/           Aplicações, uma pasta por app, cada uma com kustomization
```

## Instalação do zero

```bash
# 1. Namespaces + charts de infraestrutura
./infra/install-all.sh

# 2. OpenBao: init, unseal e configuração (manual — ver abaixo)

# 3. authentik
./infra/authentik/install.sh

# 4. Aplicações
kubectl apply -k apps/postgres
kubectl apply -k apps/web
kubectl apply -k apps/excalidraw
kubectl apply -f infra/authentik/outpost/ingress.yaml
```

## Passos manuais

Tudo que não está em YAML e vai ser esquecido.

### OpenBao — primeira instalação

```bash
kubectl exec -n openbao openbao-0 -- \
  bao operator init -key-shares=3 -key-threshold=2 > ~/openbao-keys.txt
chmod 600 ~/openbao-keys.txt
```

As unseal keys **não são recuperáveis**. Sem elas o cofre fica selado para sempre.
Guardar em gerenciador de senhas, nunca no git.

### OpenBao — após todo restart do pod ou da VPS

```bash
kubectl exec -n openbao -it openbao-0 -- bao operator unseal   # 2x, chaves diferentes
```

Enquanto selado: o ESO para de sincronizar, mas as Secrets já existentes no cluster
continuam válidas e as aplicações seguem rodando.

Não há auto-unseal: exigiria delegar a chave mestra a um KMS externo, que não existe
neste setup.

### OpenBao — configuração

```bash
kubectl exec -n openbao -it openbao-0 -- bao login   # root token
./infra/openbao/bootstrap.sh                          # idempotente
```

Segredos (fora do git, criar manualmente):

```bash
kubectl exec -n openbao -it openbao-0 -- bao kv put secret/postgres \
  POSTGRES_USER=admin POSTGRES_PASSWORD='...' POSTGRES_DB=appdb

kubectl exec -n openbao -it openbao-0 -- bao kv put secret/authentik \
  postgresql-password='...' secret-key='...' redis-password='...'
```

### PostgreSQL — database do authentik

O authentik usa o Postgres de `dev`, não sobe um próprio. Criar antes de instalá-lo,
com a **mesma** senha que está em `secret/authentik`:

```sql
CREATE USER authentik WITH PASSWORD '...';
CREATE DATABASE authentik OWNER authentik;
```

### authentik — primeiro acesso

```
https://auth.shedy.xyz/if/flow/initial-setup/
```

A barra final é obrigatória. Define a senha do `akadmin`.

### authentik — proteger uma aplicação com forward auth

1. **Providers → Create → Proxy Provider**
   - Mode: `Forward auth (single application)`
   - External host: `https://<app>.shedy.xyz`
2. **Applications → Create**, vinculada ao provider
3. **Outposts → editar `authentik Embedded Outpost`** → adicionar a Application → **Save**
   (sem este passo o endpoint `/outpost.goauthentik.io/auth/traefik` retorna 404)
4. `Middleware` do Traefik no namespace da app (ver `apps/excalidraw/middleware.yaml`)
5. Annotation no Ingress: `traefik.ingress.kubernetes.io/router.middlewares: <ns>-authentik@kubernetescrd`
6. Ingress em `authentik` roteando `/outpost.goauthentik.io` (ver `infra/authentik/outpost/`)

## Decisões

**Postgres compartilhado.** O authentik usa o Postgres de `dev` em vez do embutido no
chart. Economiza ~300 MB de RAM, que é escassa aqui. O chart avisa que o Postgres dele
é para demonstração.

**StatefulSet + volumeClaimTemplates no Postgres.** Cada réplica ganha PVC próprio e
identidade estável. Deletar o StatefulSet não apaga o PVC — proteção deliberada.

**Segredos via OpenBao + ESO.** Nenhuma credencial em arquivo versionado. O ESO
materializa Secrets nativas, e as aplicações usam `envFrom` normalmente, sem saber
do cofre.

**Selector declarado à mão.** O `labels` do Kustomize não injeta em selectors por
padrão (e não deve — selector é imutável, e injeção automática quebra o `apply`
quando as labels comuns mudam).

**Excalidraw com patch via `sed`.** As variáveis `VITE_*` são build-time; a imagem
oficial tem `oss-collab.excalidraw.com` compilada no bundle. O container roda `sed`
nos assets no startup, antes do nginx. Sem persistência no servidor — links
compartilháveis dependeriam de um fork mantido, que não existe hoje.

**Ingress do outpost em namespace separado.** O Traefik bloqueia Services do tipo
`ExternalName` por padrão (proteção contra SSRF), então o roteamento do outpost é
feito por um Ingress em `authentik` em vez de um alias em `dev`.

**Swap de 2 GB.** Não substitui RAM e o kubelet ignora swap para pods, mas dá margem
para o sistema não entrar em OOM kill por picos.

## Notas operacionais

- `refreshInterval` dos ExternalSecrets é `1h`. Após corrigir um SecretStore com erro,
  forçar: `kubectl annotate externalsecret <nome> -n <ns> force-sync=$(date +%s) --overwrite`
- O Excalidraw é PWA: o service worker cacheia o bundle. Após atualizar a imagem,
  limpar em DevTools → Application → Service Workers → Unregister.
- Let's Encrypt: 5 certificados por semana para `shedy.xyz` (conta o domínio, não o
  subdomínio). Testar no staging antes.
- Selector de Deployment/StatefulSet é imutável. Ao mudá-lo, deletar e recriar.

## Segredos

O `.gitignore` cobre `*.env`. **Nunca** commitar:

- `~/openbao-keys.txt` (fora do repo)
- Qualquer `.env`
- Root token do OpenBao
