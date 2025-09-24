RBAC Deployment Models for CIS (Cluster-Wide vs Namespace-Scoped)

Purpose
Provide guidance to choose and implement the appropriate RBAC scope for the F5 Container Ingress Services (CIS) controller while applying least privilege.

Files in this directory
- ClusterWide-RBAC/k8s_rbac.yml (broad legacy example; intentionally permissive)
- Namespace-Scoped-RBAC/least-privilege-example.yaml (recommended starting point for production hardening)

Two Models
1. Cluster-Wide RBAC
   - Single ClusterRole + ClusterRoleBinding.
   - Simpler to install; broader access surface.
   - Grants read of all namespaces and objects, plus updates on multiple resources.
   - Suitable for: rapid evaluation, clusters where CIS must dynamically discover many namespaces, legacy setups, or when you consciously accept broader privileges.

2. Namespace-Scoped (Least Privilege) RBAC
   - Minimal ClusterRole (only unavoidable cluster-scoped reads) + per-namespace Roles.
   - Secrets, ConfigMaps, Services, CRs limited to explicitly watched namespaces.
   - Recommended for: regulated environments, principle-of-least-privilege enforcement, multi-tenant clusters.

Decision Checklist
Answer YES / NO:
- Need to watch all (or many dynamic) namespaces without maintaining a list? -> Cluster-Wide (or keep namespace discovery rule only)
- Strict tenant isolation required? -> Namespace-Scoped
- Must restrict which Secrets CIS can read? -> Namespace-Scoped
- Using Calico static routes (blockaffinities)? -> Add that rule (either model) else drop.
- OpenShift network CIDR auto-discovery needed? -> Keep config.openshift.io network rule else drop.
- IPAM CR (fic.f5.com) requires write/delete? -> Only if observed; otherwise keep read-only.

Least Privilege Tuning Steps (Namespace-Scoped)
1. Enumerate watched namespaces (environment variable, CLI flag, or configuration you use for CIS); replicate Role/RoleBinding blocks accordingly.
2. Trim optional cluster rules you do not use: nodes, namespaces, blockaffinities, network, CRD reads.
3. Review code paths that update status: if you disable status updates, remove update/patch verbs for services/status, ingresses/status, cis CR statuses.
4. Keep patch/update only where controller actually mutates (see searches: UpdateStatus, .Patch in source).
5. Restrict Secrets to needed namespaces; avoid cluster-wide secret access.

Secrets Guidance
- Namespace-scoped example already limits Secrets to watched namespaces.
- If only specific Secret names are required, consider an external secret sync process into a dedicated namespace watched by CIS.
- Never grant create/delete on Secrets to CIS unless explicitly required (not typical).

Optional Rules Summary (Namespace-Scoped file comments align):
- nodes: remove if not using node-based address discovery / VXLAN / monitoring node labels.
- namespaces: remove if you statically list all watched namespaces (no dynamic label-based discovery).
- blockaffinities: only for Calico static routing integration.
- config.openshift.io network: OpenShift only; remove on vanilla Kubernetes.
- customresourcedefinitions: remove after install if you are certain runtime never needs to read CRD definitions.

Migrating From Cluster-Wide to Namespace-Scoped
1. Identify namespaces currently referenced by VirtualServer / TransportServer / Ingress / ConfigMap resources.
2. Deploy ServiceAccount (same name) and new minimal ClusterRole + Binding.
3. Create Role and RoleBinding per namespace before removing old ClusterRoleBinding to avoid downtime.
4. Remove the old broad ClusterRoleBinding and (optionally) ClusterRole once traffic is stable.
5. Audit with: kubectl auth can-i --as=system:serviceaccount:kube-system:bigip-ctlr <verb> <resource> -n <ns>

Multi-Cluster Considerations
- Each cluster needs its own reduced RBAC set; do not reuse broad manifests.
- If employing external cluster service discovery, verify only required verbs are granted in the source clusters.

Troubleshooting RBAC
Common symptoms and corrective verbs:
- Forbidden updating services/status -> add update on services/status.
- Forbidden patching virtualservers -> add patch (and update if status updated) on cis.f5.com resources.
- Cannot list blockaffinities warning -> add get,list,watch for crd.projectcalico.org blockaffinities or ignore if feature unused.
- Cannot read nodes -> add get,list,watch nodes (only if needed).

Security Validation Tips
- Run: kubectl auth can-i --list --as=system:serviceaccount:kube-system:bigip-ctlr
- Periodically review logs for RBAC denial warnings; adjust minimally.
- Keep manifests in version control; require PR review for RBAC changes.

Minimal Baseline (If all optional features removed and status updates disabled):
- ClusterRole: (possibly empty) or only customresourcedefinitions if you insist on runtime presence check.
- Per-namespace Role verbs: get,list,watch on services,endpoints,pods,ingresses,ingressclasses,configmaps,secrets + (optionally) cis.f5.com, fic.f5.com CRs.

Hardening Next Steps (Beyond Scope of Examples)
- Use dedicated Namespace for CIS-managed Secrets.
- Employ Admission Policies (OPA/Gatekeeper/Kyverno) to prevent privilege regression.
- Monitor RBAC via audit logs or specialized tooling.

Maintenance Guidance
- Reassess after upgrading CIS: diff new CRDs or added status updates; adjust verbs narrowly.
- Add verbs only after observing a concrete forbidden error.

Disclaimer
These examples are templates; validate against your operational requirements and security policies before production use.


