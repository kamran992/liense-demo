# Roadmap

## How to Read This Roadmap

Linse is a single-maintainer project, so this roadmap is intentionally not a release schedule.

It describes the current design direction, the main priorities, and the larger areas of planned work. Some design notes live outside this public demo repo, but the items below should be treated as intent, not delivery promises.

There are no dates here. The order reflects current dependencies and priorities, not a fixed version plan.

---

## Current Focus

The current focus is the application model redesign and the Kubernetes-native resource layer. Older health and scan-review paths are being replaced with a model that lines up better with Applications, Services, Environments, Targets, and Pipelines as platform resources.

Some feature areas work today, but are intentionally thin while this foundation stabilizes. That includes parts of SRE/reliability, environment promotion, and the CRD-backed resource model.

---

## Roadmap Maturity

- **Active work** - being implemented now.
- **Designed / near-term** - design exists, but implementation is not complete.
- **Planned / later** - useful direction, but depends on earlier foundation work.
- **Under consideration** - useful direction, but not committed as a near-term implementation.

---

## Active Work

<a id="1-kubernetes-native-resource-model"></a>
### Kubernetes-native resource model

Status: Active work

Linse's core model - Applications, Services, Environments, Targets, and Pipelines - is moving toward a dual representation.

Postgres remains the operational store for UI queries, jobs, audit data, and existing workflows. Kubernetes Custom Resources are added alongside it so operators can manage platform objects through `kubectl` or GitOps.

The planned split is:

- platform-owned CRs, used by Linse for coordination and projected state
- user-owned CRs, used by operators as the declarative interface to Linse

The difficult part is keeping both representations in sync. The current design uses a split write path at the entry point, plus background drift checks to detect mismatches between Postgres and Kubernetes resources.

Several later roadmap items depend on this model being stable.

---

## Designed / Near-Term

<a id="2-onboarding-refactor"></a>
### Onboarding evolution

Status: Shipped — evolving

The DAG workflow engine has landed and is the onboarding path today: a model-driven engine with explicit dependency edges, bounded-parallel execution, per-service/target fan-out (`for_each`), per-step retry/timeout, idempotency, crash-safe resume, dry-run preview, and reversible steps with rollback policies. The step handler interface is vendor-neutral (`action_type` resolved through a registry), and the default GitLab + Argo CD flow is a stored, versioned model rather than hardcoded logic.

Remaining work on top of the engine:

- **Operator-defined approval gates** — pause a flow for human sign-off mid-DAG.
- **More step handlers** — additional SCM (e.g. GitHub/Gitea), GitOps, and CI systems behind the existing registry.
- **Event-sourced execution log + discovery-driven reconciliation** — an append-only event history as the source of truth, plus reconciling onboarded resources against live discovery.
- **Conditional branches in shipped flows** — the engine supports step conditions; the default flow does not use them yet.

<a id="12-backstage-integration"></a>
### Backstage integration

Status: Designed / near-term

Backstage is the developer-facing declared catalog and portal; Linse is the runtime intelligence, team model, and operator control plane. The integration keeps each authoritative for what it owns.

Today Linse projects its catalog into Backstage one-way (teams → Groups, applications → Systems, services → Components) through a read-only export endpoint. The planned model inverts this:

- **Org/identity projection** — Linse projects its team/user model into Backstage as Groups/Users, so Backstage takes org data from Linse instead of a second source.
- **Catalog read + mapping** — Linse polls the Backstage catalog API and auto-maps declared Components to its own service model (by GitLab project, repo, Argo CD source, or labels).
- **Runtime enrichment** — Linse exposes read-only endpoints a Backstage plugin calls at view time to render live runtime status (cluster/namespace, Argo CD sync, pipeline state, version, health, drift). Linse never writes the Backstage software catalog.

<a id="3-infrastructure-intelligence"></a>
### Inventory and classification

Status: Designed / near-term

Several partial areas are moving toward the same proposal/review model used by service discovery.

The first target is host inventory. SSH and Ansible host records should become one canonical inventory with ownership, environment, connection details, trust status, and labels.

The second target is host role discovery. Linse should detect likely roles for hosts and infrastructure machines, store the evidence, and let operators confirm or override the proposal.

The third target is pipeline job classification. CI jobs should be classified into roles such as build, test, security scan, deploy, and rollback, so pipeline failures are easier to interpret in operational views.

Automation will continue to be delegated to existing tools such as Ansible or Power Automate. Linse should provide targeting, approvals, history, output, conflict detection, and audit.

<a id="7-sre-and-reliability-surfaces"></a>
### SRE and reliability cleanup

Status: Designed / near-term

The current SRE and reliability surfaces exist, but today they mostly expose raw incident, SLI, alert, and deployment data.

The next step is to connect that data to service ownership, deployment history, monitoring coverage gaps, alert-to-owner mapping, and reliability trends.

The goal is not to replace PagerDuty or a dedicated incident management product. The goal is to help an operator correlate external alerts with deployment history and service ownership without opening several separate tools just to identify the source.

Reliability scorecards exist today, but need cleanup. The plan is to move scorecard computation off the request path and make default SLI/scorecard setup part of onboarding.

<a id="10-identity"></a>
### Identity providers

Status: Designed / near-term

LDAP-compatible directory auth and local auth are the two modes that ship today. That can include Active Directory when it is used through LDAP bind and group lookup.

Planned identity work is focused on OIDC and native integrations such as Azure AD / Entra ID or AD FS, depending on what environments need.

Identity providers should remain behind the same auth interface, so authorization logic does not need to change for each provider.

<a id="11-observability"></a>
### Tracing and internal observability

Status: Designed / near-term

Prometheus query panels and Grafana dashboard discovery work today for user-facing observability in some builds.

The first missing piece is tracing inside Linse itself. The plan is to emit OpenTelemetry spans from the API process, background workers, outbox dispatch, and controller reconciliation.

The second piece is integration with existing trace backends such as Jaeger, Tempo, or Elastic APM. Linse is not planned to store traces itself.

The same plugin approach may also cover ingress and proxy telemetry where useful, for example Envoy or supported ingress controllers.

This becomes more useful as async paths grow.

---

## Planned / Later

<a id="4-netbox-integration"></a>
### NetBox integration

Status: Planned / later

NetBox integration would bring network and infrastructure source-of-truth data into Linse. Hosts, devices, racks, IP addresses, network relationships, ownership, and location metadata could enrich inventory, topology, and operational views.

Teams that already run NetBox could connect it for richer context. Teams that do not run NetBox should not be blocked; the integration is additive.

<a id="6-opa--kyverno-integration"></a>
### OPA / Kyverno integration

Status: Planned / later

Policy integration would connect Linse with OPA, Gatekeeper, and Kyverno so operators can see which applications, deployments, clusters, and resources are out of compliance.

Linse should not become a policy engine. It should integrate with existing policy tools and surface violations in context - tied to service ownership, deployment events, onboarding, or promotion.

Policy checks may also become gates in onboarding and promotion workflows.

<a id="5-cloud-resource-management-via-crossplane"></a>
### Cloud resource management via Crossplane

Status: Planned / later

For cloud infrastructure, the goal is to let Crossplane handle resource lifecycle while Linse handles ownership, approval, and operational visibility.

Linse should not build its own database provisioner or cloud-resource operator. It should connect provisioned resources back to application ownership, enforce approval gates before creation, and track lifecycle state.

For on-prem infrastructure, Linse continues to rely on its integrations.

<a id="8-database-fleet-monitoring"></a>
### Database fleet monitoring

Status: Planned / later

The idea is to provide a fleet view for self-hosted database servers and managed database endpoints across environments.

Useful signals would include reachability, authentication status, replication lag, connection pressure, long-running queries, ownership, and service impact.

---

## Under Consideration

<a id="9-ai-assistant"></a>
### AI assistant

Status: Under consideration

An AI assistant is being considered for read-only investigation first. The useful version would help operators understand service state, deployment history, pipeline failures, ownership, and related infrastructure context.

The assistant should use typed tools against Linse's own data model rather than unrestricted access to Kubernetes or external systems.

A later phase could support approval-based actions, such as preparing an onboarding change, access request, or operational check. The assistant would prepare the proposed action, but a human would approve it before anything is executed.

Local-model support is part of the design because air-gapped environments are a target use case.

---

## What This Roadmap Is Not

This is not a commitment schedule. There are no dates, and the order should not be read as a delivery promise.

The order reflects current dependencies and priorities. Several items depend on foundation work landing first, especially the Kubernetes-native resource model and onboarding refactor.

A single-maintainer project moves when design and implementation allow, not according to a calendar.
