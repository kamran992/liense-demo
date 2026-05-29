# Linse

Linse is a web-based Kubernetes operations console for platform and DevOps teams.

## Background

It started from a practical need: we had been using Kubernetes Dashboard, but needed a maintained
web UI with LDAP/RBAC support that could run inside our platform. Headlamp and Lens were first
thoughts, but Lens is a desktop application, and the goal here was a single point of entry solution.

The first version was intentionally close to the Lens workflow and design: cluster resources, logs, events,
shell access, and service visibility in one place. Over time, Linse(renamed from lens-with-go) grew into a broader platform
operations console with ownership, GitOps visibility, onboarding workflows, auditability, and
integrations around the Kubernetes workflow.

Project status: pre-1.0, single maintainer. The demo is useful for reviewing the deployment model
and current feature surface, but some areas are still thin or not fully tested end-to-end.

This repo is the public demo/deployment repo. It includes the Helm chart, local k3d setup, demo
dependencies, and documentation. The main application source code is private.

> Naming note: the project originally started as `lens-with-go`, a Go-backed web UI inspired by
> the Lens workflow. All binary, package, image, and CRD names still use the `lens` naming but will be renamed.

## What this repo contains

- Helm chart for deploying Linse: [`charts/linse/`](charts/linse/)
- Local k3d-based demo setup: [`local/`](local/)
- Example values and demo dependencies, including Postgres, Redis, OpenLDAP, and optional GitLab CE
- Architecture, feature, and roadmap notes: [`docs/`](docs/)

The container image is `kamran420/lens-with-go`.

## What Linse does today

- Kubernetes resource browsing, manifests, logs, events, and shell access
- Service catalog views built around teams, services, environments, targets, and pipelines
- Service discovery for workloads already running in connected clusters
- GitOps visibility through Argo CD integrations
- GitLab-backed onboarding workflows
- Local/LDAP authentication, RBAC, impersonation, and audit logging
- Operational integrations around Prometheus, Grafana, Ansible, SSH, and SFTP

Some of these areas are deeper than others. The feature table below and
[`docs/FEATURES.md`](docs/FEATURES.md) call out what is working, partial, or still on the roadmap.

## Run it locally

See [`local/QUICKSTART.md`](local/QUICKSTART.md).

The local setup creates a k3d cluster, installs the required dependencies, deploys Linse with Helm,
and exposes the UI at `http://linse.localhost`.

From this repo:

```bash
./local/up.sh
```

To include the heavier GitLab CE container for onboarding flows:

```bash
./local/up.sh --with-gitlab
```

## Current status

The Kubernetes console workflows are the most established part of the
project. The platform operations layer exists, but some parts are intentionally rough while the
Kubernetes-native resource model and onboarding work continue.

The local demo is intended to show the deployment model and give reviewer a working surface to
inspect. It should not be treated as a production-ready install profile.

## Capabilities

Status tags: Working / Partial.

| Area | Status | Notes |
|---|---|---|
| Multi-cluster and cluster operations | Working | Resource explorer, manifest editor with dry-run, CRD templates, multi-pod log viewer, events |
| Service catalog and service model | Working | Service dossier views, ownership metadata, runtime topology |
| Service discovery | Working | Profile-based grouping and promote-to-catalog flow |
| Onboarding | Partial | Linear flow only; GitLab-only today; DAG-based workflow engine planned |
| GitOps | Working | Argo CD application status, sync, rollback, and multi-instance support |
| Pipelines and promotions | Partial | Pipeline views work; environment-to-environment promotion is not fully tested end-to-end |
| SRE and reliability | Partial | Early incident, SLI, and scorecard surfaces; refactor planned |
| Observability | Partial | Prometheus and Grafana integrations exist; distributed tracing is planned |
| Automation | Working | Ansible, SSH PTY, SFTP, and cloud shell workflows |
| Governance and access | Partial | Local/LDAP auth, RBAC, impersonation, and audit log are implemented; OIDC/AD are planned |
| Platform plumbing | Partial | Async outbox, job queue, and early row-level tenancy support |

Full breakdown: [`docs/FEATURES.md`](docs/FEATURES.md).

## Architecture

Linse runs in a management cluster. It has an API service, a controller, Postgres, Redis, and a
React frontend. The API talks to registered workload clusters and uses informer-backed caches for
read-heavy Kubernetes data. Most read-heavy UI flows are served from the API process cache, which
reduces repeated calls to workload-cluster apiservers.

The controller handles Kubernetes-native workflows such as shell sessions. The local demo installs
the API, controller, Postgres, Redis, CRD, RBAC, services, ingress, and a demo OpenLDAP server.

Linse integrates with tools like Argo CD, GitLab, Prometheus, Grafana, LDAP, and Ansible instead of
trying to replace them.

For details, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Caveats

The demo values are intended for local and disposable environments.

In the local setup, LDAP users may be mapped to broad platform roles and Kubernetes permissions for
convenience. Tighten these mappings before using the chart outside a demo environment(not recomended).

The application is still pre-1.0, so APIs, CRDs, and Helm values may change.

## Roadmap

The near-term focus is the Kubernetes-native resource layer, onboarding workflows, and better
policy/governance integrations. Longer-term ideas are tracked in [`docs/ROADMAP.md`](docs/ROADMAP.md).
