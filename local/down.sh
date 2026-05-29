#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_DIR="$ROOT_DIR/demo/local"

CLUSTER_NAME="${CLUSTER_NAME:-linse-demo}"
DOCKER_COMPOSE_BIN="${DOCKER_COMPOSE_BIN:-docker-compose}"

WITH_GITLAB=0
REMOVE_GITLAB_VOLUMES=0

usage() {
  cat <<EOF
Usage: demo/local/down.sh [options]

Options:
  --with-gitlab  Stop the GitLab CE container before deleting the cluster.
  --volumes      Also remove GitLab volumes. Implies --with-gitlab.
  -h, --help     Show this help.

Environment:
  CLUSTER_NAME=$CLUSTER_NAME
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
    --volumes)
      WITH_GITLAB=1
      REMOVE_GITLAB_VOLUMES=1
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

if [ "$WITH_GITLAB" -eq 1 ]; then
  need_cmd "$DOCKER_COMPOSE_BIN"
  say "Stopping GitLab CE container"
  export K3D_NETWORK="k3d-$CLUSTER_NAME"
  if [ "$REMOVE_GITLAB_VOLUMES" -eq 1 ]; then
    "$DOCKER_COMPOSE_BIN" -f "$LOCAL_DIR/docker-compose.yml" down -v
  else
    "$DOCKER_COMPOSE_BIN" -f "$LOCAL_DIR/docker-compose.yml" down
  fi
fi

need_cmd k3d

say "Deleting k3d cluster: $CLUSTER_NAME"
k3d cluster delete "$CLUSTER_NAME"
