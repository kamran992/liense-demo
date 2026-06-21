#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="$ROOT_DIR/local"
CHART_DIR="$ROOT_DIR/charts/linse"

CLUSTER_NAME="${CLUSTER_NAME:-linse-demo}"
RELEASE_NAME="${RELEASE_NAME:-linse}"
NAMESPACE="${NAMESPACE:-linse}"
APP_HOST="${APP_HOST:-linse.localhost}"
DOCKER_COMPOSE_BIN="${DOCKER_COMPOSE_BIN:-docker-compose}"
INGRESS_NGINX_URL="${INGRESS_NGINX_URL:-https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml}"
GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-Demo1234!}"

WITH_GITLAB=0
WAIT_GITLAB=0
INSTALL_INGRESS=1
HELM_EXTRA_ARGS=()

usage() {
  cat <<EOF
Usage: local/up.sh [options]

Options:
  --with-gitlab   Start GitLab CE and wire gitlab.local into the Linse pod.
  --wait-gitlab   Also wait for GitLab's HTTP readiness endpoint.
  --skip-ingress  Do not install ingress-nginx.
  -h, --help      Show this help.

Environment:
  CLUSTER_NAME=$CLUSTER_NAME
  RELEASE_NAME=$RELEASE_NAME
  NAMESPACE=$NAMESPACE
  APP_HOST=$APP_HOST
  DOCKER_COMPOSE_BIN=$DOCKER_COMPOSE_BIN
EOF
}

say() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-gitlab)
      WITH_GITLAB=1
      ;;
    --wait-gitlab)
      WITH_GITLAB=1
      WAIT_GITLAB=1
      ;;
    --skip-ingress)
      INSTALL_INGRESS=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

need_cmd docker
need_cmd k3d
need_cmd kubectl
need_cmd helm

if [ "$WITH_GITLAB" -eq 1 ]; then
  need_cmd "$DOCKER_COMPOSE_BIN"
fi

if [ "$WAIT_GITLAB" -eq 1 ]; then
  need_cmd curl
fi

say "Creating or reusing k3d cluster: $CLUSTER_NAME"
if k3d cluster list "$CLUSTER_NAME" --no-headers >/dev/null 2>&1; then
  printf 'Cluster already exists.\n'
else
  k3d cluster create "$CLUSTER_NAME" --config "$LOCAL_DIR/k3d-cluster.yaml"
fi

k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context >/dev/null

if [ "$INSTALL_INGRESS" -eq 1 ]; then
  say "Installing ingress-nginx"
  kubectl apply -f "$INGRESS_NGINX_URL"
  kubectl rollout status deployment/ingress-nginx-controller \
    --namespace ingress-nginx \
    --timeout=180s
fi

if [ "$WITH_GITLAB" -eq 1 ]; then
  say "Starting GitLab CE container"
  export K3D_NETWORK="k3d-$CLUSTER_NAME"
  export GITLAB_ROOT_PASSWORD
  "$DOCKER_COMPOSE_BIN" -f "$LOCAL_DIR/docker-compose.yml" up -d

  GITLAB_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$K3D_NETWORK\"}}{{.IPAddress}}{{end}}" linse-gitlab)"
  [ -n "$GITLAB_IP" ] || die "Could not find linse-gitlab IP on Docker network $K3D_NETWORK"

  HELM_EXTRA_ARGS+=(
    --set "hostAliases[0].ip=$GITLAB_IP"
    --set "hostAliases[0].hostnames[0]=gitlab.local"
  )

  printf 'GitLab is starting at http://localhost:8929 and is mapped in-cluster as gitlab.local -> %s\n' "$GITLAB_IP"

  if [ "$WAIT_GITLAB" -eq 1 ]; then
    say "Waiting for GitLab readiness"
    for _ in $(seq 1 90); do
      if curl -fsS "http://localhost:8929/-/readiness" >/dev/null 2>&1; then
        break
      fi
      sleep 10
    done
  fi
fi

say "Installing Linse Helm release"
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  -n "$NAMESPACE" \
  --create-namespace \
  -f "$CHART_DIR/values.yaml" \
  -f "$LOCAL_DIR/values-local.yaml" \
  "${HELM_EXTRA_ARGS[@]}"

say "Deploying local OpenLDAP"
kubectl apply -f "$LOCAL_DIR/ldap/deployment.yaml"

say "Waiting for local stack"
kubectl rollout status deployment/openldap -n "$NAMESPACE" --timeout=180s
kubectl rollout status statefulset/linse-postgres -n "$NAMESPACE" --timeout=180s
kubectl rollout status deployment/linse-redis -n "$NAMESPACE" --timeout=180s
kubectl rollout status deployment/linse-controller -n "$NAMESPACE" --timeout=180s
kubectl rollout status deployment/linse -n "$NAMESPACE" --timeout=180s

printf '\nLinse is ready: http://%s\n' "$APP_HOST"
printf 'Demo users: alice, bob, carol / %s\n' "Demo1234!"
printf 'Check pods: kubectl get pods -n %s\n' "$NAMESPACE"
