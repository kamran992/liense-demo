# Architecture

This document describes the current Linse architecture for anyone reviewing the deployment and design.

The application source is private, so this file focuses on the parts that matter for review: runtime topology, process boundaries, persistence, multi-cluster access, authentication, integration points, and a few important runtime flows.

Some parts described here are kind of stable, while others are still evolving. The final sections call out the main trade-offs, limitations, and planned work.

---

## 1. Overview

Linse runs in a management cluster and connects to one or more workload clusters(kubeconfig). The management cluster is where the Linse API, controller, Postgres, and Redis run. Workload clusters are the Kubernetes clusters Linse surfaces and operates against.


```
Management cluster

  browser
     |
     v
  lens-with-go / lens-api
     |          |          \
     v          v           v
  Postgres    Redis    management Kubernetes API <---- lens-controller
                              |
                              v
                  ShellSession CRs, shell pods, kubeconfig Secrets

Workload clusters

  Kubernetes APIs reached through registered kubeconfigs
```

The main runtime pieces are:

- **API process**: built from `main.go` and packaged as the `lens-with-go` binary. In docs this is often described as `lens-api`, because its role is the HTTP/WebSocket API server.
- **Controller process**: built from `cmd/controller/main.go` and packaged as `lens-controller`.
- **Postgres**: the main application database.
- **Redis**: event fan-out and async coordination when configured.
- **React frontend**: built during the Docker image build, copied into `frontend/dist`, and served by the API process.

The data model is built around teams, services, environments, targets, and pipelines. These records live primarily in Postgres today. The Kubernetes-native CRD model is in progress, but the current write path is still Postgres-first.

---

## 2. Process Boundaries

### API process

The API process serves the React application, REST API, and long-lived WebSocket flows. It owns:

- authentication and request middleware
- cluster registration
- Kubernetes clients for registered clusters
- informer-backed resource caches
- log streaming, exec, cloud shell proxying, SSH PTY, and SFTP WebSockets
- service-layer calls to GitLab, Argo CD, Prometheus, Grafana, LDAP, and Ansible adapters

The API process uses the registered cluster credential to construct Kubernetes clients. For user-facing Kubernetes operations, request context includes Kubernetes impersonation headers for the authenticated user. That distinction matters: the imported kubeconfig is the transport credential, while Kubernetes authorization can still evaluate the impersonated user when the target cluster is configured for that.

### Controller process

The controller process is a controller-runtime manager pointed at the management cluster. Today its main reconciler watches `ShellSession` resources in the `lens.io/v1alpha1` API group and turns them into shell pods, kubeconfig Secrets, and status updates.

Leader election is enabled, so only one controller instance actively reconciles at a time when multiple replicas are deployed.

The controller does not serve HTTP and does not call GitLab, Argo CD, Prometheus, or Grafana. It communicates with the API process through Kubernetes objects and status fields in the management cluster.

### Postgres

Postgres is the source of truth for cluster registrations, catalog data, users, roles, onboarding jobs, audit records, registry credentials, and outbox/job state.

The code can run with no database configured, or continue after database initialization fails, but that is a degraded mode. Important features such as onboarding, saved integrations, audit history, and registered cluster persistence depend on Postgres.

### Redis

Redis is used for distributed event fan-out and async coordination. If Redis is not configured, or if the Redis bus cannot connect, the app falls back to an in-memory bus. The health endpoint reports that as degraded because in-memory fan-out is only suitable for local development or a single API replica.

Production-style deployments should configure Redis instead of relying on per-process memory.

---

## 3. Backend Structure

`internal/app` is the composition root for the API process. It wires configuration, database connections, Redis/event bus, Kubernetes provider, services, adapters, HTTP handlers, background workers, and middleware in one place.

Route mounting is organized by domain: clusters, catalog, service discovery, onboarding, GitOps, pipelines, governance, automation, observability, identity, and admin operations.

Most versioned routes share the same broad middleware shape:

1. request ID and logging
2. panic recovery
3. JWT validation
4. provenance and audit context
5. Kubernetes impersonation context
6. mutation rate limits
7. route-specific role checks

Domain logic lives mostly in `internal/service`. Services call interfaces rather than concrete external clients. The GitLab, Argo CD, Prometheus, Grafana, LDAP, and Ansible implementations are injected at startup.

The adapter packages are the intended extension point:

- `internal/gitops` defines the GitOps interface; Argo CD is the current implementation.
- `internal/scm` defines the SCM interface; GitLab is the current implementation.
- `internal/observability` defines metrics and dashboard interfaces; Prometheus and Grafana are the current implementations.
- `internal/plugins/ldap` handles LDAP-backed authentication.
- `internal/plugins/ansible` handles Ansible inventory, playbook, SSH, and host operations.

Adding another backend should mean implementing the relevant interface and wiring it in `internal/app`. It should not require rewriting the service layer.

Linse also exposes a read-only Backstage catalog endpoint. A pure mapper projects the service catalog into Backstage entities (owner teams → Groups, applications → Systems, services → Components), served behind a static token for a Backstage Entity Provider to ingest. It is one-way today (Linse → Backstage); the inverted "Backstage declares, Linse enriches and operates" model is planned (see ROADMAP).

---

## 4. Data Model and Persistence

Postgres stores the durable application state:

- **Cluster registry**: registered clusters, display names, kubeconfig data, labels, and notes.
- **Service catalog**: teams, applications, services, environments, targets, and pipeline relationships.
- **Service discovery**: scans, inferred groupings, evidence, proposals, and operator decisions.
- **Onboarding**: jobs, steps, state transitions, rollback status, and errors.
- **Identity and access**: users, organizations, platform roles, cluster mappings, access requests, and approvals.
- **GitOps and SCM state**: tracked Argo CD instances, snapshots, pipeline data, and repository metadata.
- **Automation**: Ansible inventory, hosts, groups, playbook runs, and SSH session metadata.
- **Audit log**: operator actions and request context.
- **Outbox and jobs**: durable records used by background workers.

Schema migrations are embedded in the API binary and run at startup through `golang-migrate`. The Postgres migrate driver uses an advisory lock, so concurrent API replicas should not apply the same migration at the same time. Migrations still need normal production care: incompatible schema changes should be planned with the deployment sequence in mind.

Tenant isolation is handled in layers. Application code carries a tenant ID in context, and the repo includes `tenancyguard`, a static analyzer that checks database-layer SQL against known tenanted tables for `tenant_id` predicates and explicit tenant handling. Postgres row-level security also exists on tenant-scoped tables, but it is not the only boundary and should not be described as fully hardened yet. Some policies depend on `current_setting('app.tenant_id', true)`, and some newer policies allow access when that setting is not present. If RLS is enabled broadly, tenant context must be set and cleared per request before pooled connections are returned.

In the normal API startup path, Linse constructs a crypto service before creating the Kubernetes provider. Imported kubeconfigs are encrypted before storage, and the provider attempts to migrate legacy plaintext kubeconfigs to the encrypted column on startup. The lower-level provider can still be constructed without crypto in tests or alternate wiring, and an encryption failure currently falls back to plaintext storage, so production deployments need a stable secret configuration.

Redis is not treated as durable application state. Durable job and workflow state belongs in Postgres; Redis is used for coordination and delivery.

The outbox pattern (store the intended external action in the same database transaction as the local change, then deliver it asynchronously) is used where a database write must trigger work in an external system. The primary write and outbox record are stored together, then a background worker delivers the external action and marks the outbox record complete. This keeps the system recoverable when an external call fails after the local transaction succeeds.

---

## 5. Multi-Cluster Access Model

Clusters are registered by importing a kubeconfig. Linse parses the kubeconfig contexts, builds Kubernetes clients, stores cluster metadata in Postgres, and persists the kubeconfig data when a database is available.

There are two identities to keep straight:

- **Registered cluster credential**: the kubeconfig credential imported during cluster registration. Linse uses it to create clients, run informers, perform SubjectAccessReview checks, provision RBAC bindings, and reach the workload-cluster API.
- **Authenticated Linse user**: the user from the Linse JWT. For user-facing Kubernetes requests, Linse adds `Impersonate-User` and `Impersonate-Group` headers based on the authenticated user.

That means workload-cluster audit logs and RBAC behavior depend on Kubernetes impersonation being allowed for the registered credential. If impersonation is not configured correctly in the target cluster, operations may fail or run only under the registration credential.

Identity provisioning is used to make impersonation useful. When enabled, Linse creates or updates Kubernetes `ClusterRoleBinding` objects for users based on configured LDAP group mappings. The binding subject is a Kubernetes `User`, not a per-user ServiceAccount. Cloud shell has an additional token flow described in section 8.

Most read-heavy resource views use shared informer caches. The cache reduces repeated list calls against workload-cluster apiservers, but it does not remove apiserver traffic entirely. Writes, exec, log streams, SubjectAccessReview checks, cache startup, resyncs, and fallback paths still call the relevant workload cluster directly.

Cache reads are still authorization-aware. Resource cache access checks the requesting user with SubjectAccessReview before serving cached objects. If the cache is unavailable or not synced, resource views can fall back to live API calls.

Cluster credential rotation is not a full first-class workflow yet. The practical path today is to remove and re-register a cluster, or otherwise update the stored registration data so clients can be rebuilt with the new kubeconfig.

---

## 6. Authentication and Authorization

Linse supports local authentication and LDAP authentication.

LDAP mode works with LDAP-compatible directories, including Active Directory when it is configured through LDAP bind and group lookup. Native OIDC or Azure AD-style login is planned but not implemented yet.

After login, the API issues a signed JWT containing the user's identity, organization, roles, groups, and related claims. JWT signing keys support a `kid` field, so keys can be rotated without immediately invalidating every active session. New tokens are signed with the active key; previous keys can remain valid during a rotation window and then be removed.

Platform roles such as `viewer`, `operator`, `admin`, and `platform_admin` are enforced in API middleware and route groups. Cluster access is a separate concern from platform access: a user can be a platform admin for Linse configuration while still having limited access to a specific workload cluster.

The impersonation middleware does not mean "an admin logs in as another user." It means Kubernetes API requests carry impersonation headers for the authenticated user, so workload-cluster RBAC can participate in authorization.

Mutation routes are audited through API middleware. Cloud shell session create/delete operations are covered as API mutations, but the contents typed inside an interactive shell are not treated as structured audit events by the API yet.

---

## 7. Frontend Architecture

The frontend is a React and TypeScript single-page application. It is built during the Docker image build and copied into the final image at `frontend/dist`. The API process serves those static assets and handles API routes from the same container image.

The UI is organized as a tabbed workspace. Operators can keep long-running views such as logs, shell sessions, SFTP, and onboarding progress open while moving through other parts of the console.

Frontend state is split by domain using Zustand stores rather than one large global store. API calls go through domain-specific client modules. WebSockets are used for flows where polling is a poor fit: pod logs, cloud shell, SSH, SFTP, onboarding progress, and notifications.

The browser does not receive Kubernetes, GitLab, Argo CD, Prometheus, or Grafana credentials. Those integrations are proxied through the API process, where auth, RBAC, tenant checks, and response normalization can be applied.

---

## 8. Runtime Flows

### Login and cluster context

A login request is handled by the auth service. In LDAP mode, the service binds against the configured directory and reads group membership. In local mode, it verifies the stored password hash. On success, the API resolves the user's Linse roles and returns a JWT.

For cluster-scoped requests, the frontend sends the target cluster as part of the URL or query. The API resolves the registered cluster, checks the user's Linse-side access, attaches Kubernetes impersonation context, and then calls the Kubernetes provider.

The handler receives an already-authenticated request with the target cluster resolved. It should not need to parse a raw kubeconfig or repeat the top-level role check.

### Onboarding workflow engine

Onboarding runs on a model-driven DAG workflow engine. A flow is a stored, versioned model whose steps declare explicit dependencies; the engine expands the model for the request, validates it (cycle detection), and executes it. The flow is persisted as a job in Postgres with one row per step.

The default model provisions a service across GitLab (SCM groups, code + chart repositories), the service catalog, Helm chart rendering, and Argo CD (project + applications), then registers identity keys.

Execution properties:

- **DAG, not a chain.** A step runs once its dependencies are satisfied; independent steps run concurrently through a bounded worker pool. The default flow has real parallelism (e.g. namespace creation alongside repository creation) and later steps that join multiple branches.
- **Fan-out.** A step can expand per item (`for_each`) — per service, per deployment target, per namespace — so one job onboards N services across M targets.
- **Idempotent + resumable.** Steps inspect their recorded outputs before any external write, so a restarted worker resumes from the last incomplete step without repeating work.
- **Retry, timeout, optional steps.** Each step has max-attempts and a timeout; optional steps degrade to a warning instead of failing the job.
- **Reversible steps + rollback policy.** Steps declare a rollback contract; on a non-retryable failure the engine rolls back completed reversible steps in reverse order, under the model's rollback policy (pause / best-effort / halt / compensate).
- **Dry-run preview.** The engine can resolve the full plan — which steps will run and their resolved config — without creating a job or touching anything.
- **Vendor-neutral.** `action_type` is opaque to the engine and resolved through a handler registry. The shipped handlers target GitLab and Argo CD; the engine itself is not tied to either.

The engine emits lifecycle events (job/step started, completed, failed, rolled back) for progress streaming and audit. It is **not** event-sourced — state lives in the job/step rows; the events are for observability. Human approval gates are not implemented yet.

### Cloud shell

Cloud shell gives an operator a browser terminal with kubeconfig access to registered clusters and a persistent home directory.

The flow is split between the API and controller:

1. The operator creates a cloud shell session from the UI.
2. The API writes a `ShellSession` CR in the management cluster.
3. The controller reconciles the CR into a shell pod and kubeconfig Secret.
4. The controller updates status when the pod is ready.
5. The API bridges the browser WebSocket to pod exec.
6. Deleting the session removes the shell pod; the home PVC is retained.

The shell kubeconfig is generated from the user's accessible clusters. The API creates short-lived ServiceAccount tokens for shell contexts and refreshes the kubeconfig Secret while the session is active.

The controller adds several basic controls: a dedicated shell namespace, a pod quota, resource requests and limits, non-root execution for the main container, disabled automount of the pod ServiceAccount token, and an idle timeout. Production deployments should still review this feature carefully: allowed shell images, network policies, stale PVC cleanup, audit expectations, and RBAC mappings all matter.

---

## 9. Design Trade-Offs and Current Limitations

Some parts of the architecture are intentionally simple at this stage:

- Onboarding has no human approval gates yet, and its shipped step handlers target GitLab + Argo CD only.
- Postgres remains the main source of truth while the CRD-based resource model is introduced.
- Redis fallback to memory is useful for local development, but it is not appropriate for multiple API replicas.
- The API can run in a degraded no-database mode, but most platform features need Postgres.
- RLS and tenant isolation exist in the schema, but the enforcement model is still being tightened across all tables and pooled connections.
- Cloud shell is powerful and should be treated as a privileged feature.
- Cluster credential rotation is not yet a polished operator workflow.
- The frontend and backend ship in one image, but the frontend assets are file-based image contents rather than Go-embedded assets.

These are the areas a reviewer should treat as active engineering concerns rather than finished claims.

---

## 10. Planned Architecture Work

The following items are not implemented in the current version. They are tracked in the roadmap and should be treated as future work, not behavior available today.

- On top of the onboarding DAG engine (parallel steps, reusable handlers, rollback, resume — already shipped): human approval gates, additional SCM/CI step handlers, and an event-sourced execution log with discovery-driven reconciliation.
- Applications, Services, Environments, Targets, and Pipelines currently live primarily in Postgres. The Kubernetes-native CRD model is in progress, but the write path and reconcilers are not shipped yet.
- NetBox integration is not implemented.
- Crossplane integration for cloud resource lifecycle is not implemented.
- OPA/Kyverno integration is not implemented.
- Database fleet monitoring is not implemented.
- The AI assistant is not implemented.
- Distributed tracing across API service boundaries is not implemented.

See [ROADMAP.md](ROADMAP.md) for the planned sequencing and rationale.
