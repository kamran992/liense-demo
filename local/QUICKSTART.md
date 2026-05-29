# Linse Local Demo Quickstart

This quickstart runs Linse in a local k3d cluster with Postgres, Redis, and
OpenLDAP demo users. GitLab CE can be added for onboarding flows, but the core
app, login, health checks, and Kubernetes-backed runtime views do not require
GitLab to be running.

Run commands from the repository root unless a step says otherwise.

## What Starts

```text
Docker host
|-- k3d cluster
|   |-- linse
|   |-- linse-controller
|   |-- linse-postgres
|   |-- linse-redis
|   `-- openldap
`-- linse-gitlab container, optional, port 8929
```

## Prerequisites

- Docker with at least 4 GiB memory for the Kubernetes-only demo.
- 6-8 GiB Docker VM memory if you also start GitLab CE.
- `kubectl`
- `helm` 3.x
- `k3d`
- Docker Compose, available as `docker-compose`

On macOS with the Homebrew Docker CLI:

```bash
brew install k3d helm docker-compose
docker-compose version
```

If `docker-compose version` is not found, add the Homebrew plugin directory to
`~/.docker/config.json`:

```json
{
  "cliPluginsExtraDirs": [
    "/opt/homebrew/lib/docker/cli-plugins"
  ]
}
```

## 1. Create The Cluster

```bash
k3d cluster create --config demo/local/k3d-cluster.yaml
```

Install nginx ingress:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
```

## 2. Deploy Linse And OpenLDAP

```bash
helm install linse ./demo/charts/linse \
  -n linse \
  --create-namespace \
  -f demo/charts/linse/values.yaml \
  -f demo/local/values-local.yaml

kubectl apply -f demo/local/ldap/deployment.yaml
kubectl rollout status deployment/linse -n linse
kubectl rollout status deployment/openldap -n linse
```

Add the local hostname:

```text
127.0.0.1  linse.localhost
```

Open:

```text
http://linse.localhost
```

Demo users all use password `Demo1234!`.

| Username | Name |
| --- | --- |
| `alice` | Alice Admin |
| `bob` | Bob Developer |
| `carol` | Carol Ops |

This local LDAP config grants demo users `platform_admin` and Kubernetes
`cluster-admin`. Tighten `auth.role_mappings` and `identity.group_mappings`
before using the chart outside a disposable environment.

## 3. Optional GitLab For Onboarding

GitLab CE is heavy. If Docker/Colima has less than about 6 GiB memory, the
container can be OOM-killed during boot.

Start GitLab:

```bash
cd demo/local
docker-compose up -d
```

Watch startup:

```bash
docker logs -f linse-gitlab
```

Get the initial root password:

```bash
docker exec linse-gitlab cat /etc/gitlab/initial_root_password
```

Open `http://localhost:8929`, log in as `root`, then create a Personal Access
Token with the `api` scope. Put it in `demo/local/values-local.yaml` under
`gitlab.token`, then upgrade:

```bash
helm upgrade linse ./demo/charts/linse \
  -n linse \
  -f demo/charts/linse/values.yaml \
  -f demo/local/values-local.yaml
```

For GitLab webhooks, enable local network requests in GitLab:

```text
Admin -> Settings -> Network -> Outbound requests
```

Then allow requests to the local network.

## Useful Checks

```bash
kubectl get pods -n linse
kubectl get ingress -n linse
curl -i http://linse.localhost/api/v2/healthz
```

## Teardown

```bash
k3d cluster delete linse-demo
```

If you started GitLab:

```bash
cd demo/local
docker-compose down
docker-compose down -v
```
