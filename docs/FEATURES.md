# Features

This document tracks the main operator-facing capabilities in the current Linse demo.

Status tags are based on the maintainer's current assessment. They are meant to be practical, not marketing labels: some features work end-to-end locally, some are implemented but still rough, and some are only planned.

## Status legend

- ✅ **Working in demo** — implemented end-to-end and exercised locally.
- 🟡 **Partial** — implemented, but limited, rough, vendor-specific, or not fully tested.
- 🔵 **Planned** — designed or spec'd, not built yet; see [Roadmap](ROADMAP.md).

---

## 1. Multi-Cluster & Cluster Operations

Cluster-level operations for registered Kubernetes clusters. Most resource-list views are served from an informer-backed in-process cache, which reduces repeated list calls to workload-cluster apiservers.

**Context switching** — ✅ Working in demo
Switch between registered clusters within a single session; each cluster carries its own access context.

**Resource explorer** — ✅ Working in demo
Browse common Kubernetes resource types and supported CRDs across a connected cluster. Resource lists are normally served from the in-process cache; writes, exec, log streams, and cache resyncs still call the cluster API.

**Manifest editor with dry-run, diff, and confirm** — ✅ Working in demo
Edit supported resource manifests in-browser; the editor runs a server-side dry-run, shows a structured diff, and requires explicit confirmation before applying.

**Namespace picker** — ✅ Working in demo
Filter cluster views by namespace; selection persists across the session until changed.

**CRD explorer and template generator** — ✅ Working in demo
Browse installed CRDs on a connected cluster and generate a starter manifest from the CRD schema.

**Multi-pod log viewer** — ✅ Working in demo
Stream logs from multiple pods simultaneously; each stream is delivered over WebSocket.

**Events panel** — ✅ Working in demo
Surface Kubernetes Events scoped to a cluster or namespace; useful for diagnosing scheduling and controller issues without switching to `kubectl`.

---

## 2. Service Catalog & Service Model

The service model is built around ownership, environments, delivery, and runtime state. The catalog is the operator-facing list; the detail view is where those pieces come together for one service.

**Service catalog** — ✅ Working in demo
Central list of services registered with the platform; filterable by owner, environment, and labels.

**Service detail view** — ✅ Working in demo
Each service has tabs for Definition, Delivery, Runtime, and Governance.

**Service map** — ✅ Working in demo
Visual map of services and declared dependencies; useful for reviewing ownership and possible blast radius.

**Developer projects** — 🟡 Partial
Group services under a developer project with shared ownership, environment scoping, and access policies.

---

## 3. Service Discovery

Discovery finds workloads running on connected clusters that are not yet registered in the catalog. Operators review proposals and promote the ones they want to track (scan and catalog does zero mutation, both scm and cluster).

**Scan clusters** — ✅ Working in demo
Run a discovery scan against a connected cluster to detect workloads that are not yet in the catalog.

**Profile-based grouping** — 🟡 Partial
Detected workloads are grouped by inferred profile using custom, configurable signal rules.

**Promote-to-catalog flow** — ✅ Working in demo (Needs more testing)
Review discovery proposals and promote selected workloads into the service catalog.

---

## 4. Onboarding

**Golden-path onboarding workflow** — 🟡 Partial
Automates the initial setup for a service across GitLab, Argo CD, Kubernetes namespace/RBAC, and registry credentials.
Notes: Linear flow only. GitLab-only today. DAG-based workflow engine planned wich will support custom flows, N:M scm mapping ([Roadmap](ROADMAP.md#2-onboarding-refactor)).

**Known bugs / rough edges** — 🟡
The golden path completes, but these are sharp edges hit during demo prep:

- **Custom Helm values must satisfy the default chart templates.** Custom values (`valuesTemplate`) and chart files (`chartFiles`) are independent overrides, and the chart ships no base `values.yaml`. If custom values omit a key the default templates reference (e.g. `smb.enabled`), `helm template` fails with a nil-pointer at Argo CD app-create time and the step errors. Workaround: keep every key the default templates expect (e.g. set `smb.enabled: false`).
- **`secrets.data` must be a base64 map, not a list.** The default `secrets.yaml` renders `secrets.data` straight into a Kubernetes `Secret`, so an array of `{name, valueFrom}` references yields `cannot unmarshal array into Secret.data` at sync time. Workaround: set `secrets.enabled: false` and inject existing secrets via env `valueFrom.secretKeyRef`.
- **An unreachable registered cluster can delay/prevent backend startup.** Informer cache init synchronously probes ~20 core GVRs at a 3s timeout each per cluster *before* the HTTP server binds; one unreachable cluster blocks ~60s and can crash-loop the pod against its startup probe. Workaround: remove/disable unreachable clusters (or temporarily disable the readiness probe) until the pod is up. (Platform-startup issue; surfaces when onboarding has added clusters.)

---

## 5. GitOps

**Argo CD multi-instance support** — ✅ Working in demo
Connect multiple Argo CD instances; Linse resolves applications across configured instances.

**Application status, sync, and rollback** — ✅ Working in demo
View application sync state and history; trigger a sync or roll back to a previous revision.

---

## 6. Pipelines & Promotions

**Pipeline views** — ✅ Working in demo
Display pipeline runs from connected GitLab projects; operators can see run history, status, and job-level detail.

**Environment-to-environment promotion** — 🟡 Partial
Promotes an artifact from one environment to the next by updating the GitOps manifest and triggering a sync.
Notes: Implemented, but still needs end-to-end validation before it should be considered stable.

**Pipeline job classification** — 🔵 Planned ([Roadmap](ROADMAP.md#3-infrastructure-intelligence))
Classifies CI jobs into roles such as build, test, security scan, deploy, and rollback, so failed pipelines are easier to interpret.

---

## 7. SRE & Reliability

**Incident tracking, SLI windows, and alert correlation** — 🟡 Partial
Surfaces active incidents and correlated alerts alongside service ownership and recent deployment history.
Notes: Early UI surfaces over existing incident, SLI, and alert data.

**Reliability scorecards** — 🟡 Partial
Computes a reliability score per service based on SLI coverage, recent incident history, and alert configuration.
Notes: Implemented, but the scoring model and background computation path still need cleanup and UI wiring.

This section covers incident context and reliability signals. It is not a replacement for a dedicated incident management product such as PagerDuty.

---

## 8. Observability

**Prometheus query panel** — ✅ Working in demo
Run ad-hoc PromQL queries against a connected Prometheus instance; results are displayed as time-series charts.

**Grafana dashboard discovery** —  🟡 Partial
Grafana dashboards discovered from a connected Grafana instance; Not wired in UI.

**Internal distributed tracing** — 🔵 Planned ([Roadmap](ROADMAP.md#11-observability))
OpenTelemetry tracing export/integration for existing backends such as Jaeger, Tempo, or Elastic APM; Linse is not planned to store traces itself.

---

## 9. Automation

Automation features are optional and apply when Linse is configured with host inventory and Ansible/SSH access. Linse acts as the control plane for targeting, approval, history, and audit; execution is delegated to Ansible or runs over SSH.

**Ansible host, group, and playbook management** — ✅ Working in demo
Register hosts and groups, browse available playbooks, and trigger playbook runs with targeting and approval from within the platform.

**SSH terminal (PTY)** — ✅ Working in demo
Open an interactive terminal session to a registered host over SSH; the PTY is bridged through the API over WebSocket.

**SFTP browser** — ✅ Working in demo
Browse and transfer files on a registered host via SFTP; no separate client required.

**Cloud shell** — ✅ Working in demo
Provision a shell pod in the management cluster with a generated kubeconfig for the user's accessible clusters and a persistent home directory.
Notes: Treat as a privileged feature. Production use should enforce strict RBAC, resource limits, shell image controls, network policies, and cleanup policies.

Notes: There is a bug where saved hosts cause crash when application restarted because ssh creds can't be decrypted, passing static key is temporary fix. 

---

## 10. Governance & Access

**LDAP-compatible directory auth and local auth** — ✅ Working in demo
Authenticate against LDAP-compatible directories, including Active Directory over LDAP, or a local user database; JWT sessions support key rotation.

**OIDC / native AD or Azure AD-style login** — 🔵 Planned ([Roadmap](ROADMAP.md#10-identity))
Native OIDC and AD/Azure AD-style login are planned as additional identity backend implementations.

**RBAC roles and Kubernetes impersonation** — ✅ Working in demo
Define platform and cluster roles. For Kubernetes operations, Linse can send impersonation headers for the authenticated user so workload-cluster RBAC participates in authorization.

**Audit log (30-day retention)** — ✅ Working in demo
Write actions and access-request events are recorded with actor, timestamp, and target resource; retained for 30 days.

**Access requests** — ✅ Working in demo
Users request elevated access through a structured workflow; approvers review and grant or deny from within the platform.

**Permission manager** — ✅ Working in demo
Manage RBAC role assignments and cluster-level permissions from a single view; changes are applied and recorded in the audit log.

**Registry credentials** — ✅ Working in demo
Store container registry credentials for onboarding and deployment flows.
Notes: Credentials are encrypted at rest when stable crypto configuration is available.

---

## 11. Platform Foundation

Internal behavior that supports the user-facing features above. These are not visible as standalone UI features, but they affect reliability and multi-tenancy across the platform.

**Async outbox** — ✅ Working in demo
Cross-system writes are recorded in Postgres before being delivered to external systems, so failed deliveries can be retried.

**Job queue** — ✅ Working in demo
Background work such as discovery scans and onboarding steps runs through Redis Streams when configured. Local single-node setups can use an in-memory queue.

**Tenant isolation with PostgreSQL RLS** — 🟡 Partial
Tenant isolation uses tenant-scoped queries, the `tenancyguard` static analyzer, and PostgreSQL row-level security on tenant-scoped tables. This area is still being tightened.

**Identity auto-provisioning** — ✅ Working in demo
When access is granted or a cluster is added, Linse can provision Kubernetes `ClusterRoleBinding` objects for the authenticated user so impersonated requests have matching workload-cluster RBAC.

---

## Out of scope today

- Does not replace Backstage (developer self-service portal).
- Does not replace PagerDuty (incident management product).
- Does not ship a policy engine. OPA / Kyverno integration is planned ([Roadmap](ROADMAP.md#6-opa--kyverno-integration)); Linse will surface violations, not enforce them.
- Does not ship cloud-resource provisioners. Crossplane integration is planned for cloud resources ([Roadmap](ROADMAP.md#5-cloud-resource-management-via-crossplane)); on-prem automation is handled through Ansible/SSH integrations.
- Does not integrate with NetBox today; planned ([Roadmap](ROADMAP.md#4-netbox-integration)).
- Does not currently provide a fleet view across database servers and managed endpoints; planned ([Roadmap](ROADMAP.md#8-database-fleet-monitoring)).
