# knot-resolver

![Version: 0.4.0](https://img.shields.io/badge/Version-0.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v6.2.0](https://img.shields.io/badge/AppVersion-v6.2.0-informational?style=flat-square)

Knot Resolver — caching DNSSEC-validating DNS resolver

**Homepage:** <https://www.knot-resolver.cz/>

## Requirements

Kubernetes: `>=1.23.0-0`

## Overview

[Knot Resolver](https://www.knot-resolver.cz/) is a **caching, DNSSEC-validating DNS resolver** built by [CZ.NIC](https://www.nic.cz). This Helm chart deploys it as an opt-in secondary DNS alongside CoreDNS. Pods that set `dnsPolicy: None` pointing at the Knot Resolver ClusterIP get DNSSEC validation, custom forwarding, and recursive resolution.

Uses the official [`cznic/knot-resolver:v6.x.x`](https://hub.docker.com/r/cznic/knot-resolver) image. This is a community Helm chart and not affiliated with Knot Resolver.

## Installing the Chart

```bash
helm repo add knot-resolver https://sargeant.github.io/helm-knot-resolver
helm install knot-resolver knot-resolver/knot-resolver --set service.clusterIP="10.96.0.53"
```

Verify with `helm test knot-resolver`.

## Configure Pods to use DNS-SEC with Knot Resolver

For pods to use Knot Resolver, set `dnsPolicy: "None"` with a full `dnsConfig`.

```yaml
spec:
  dnsPolicy: "None"
  dnsConfig:
    nameservers:
      - "10.96.0.53"
```

> [!note]
> This will only use the Internet's root name-servers and be cut off from your cluster's internal service discovery.

To also resolve cluster-internal names, set `forwarding.kubeDNS.enabled: true` which will forward `cluster.local` to kube-dns, then update your `dnsConfig:`

```yaml
spec:
  dnsPolicy: "None"
  dnsConfig:
    nameservers:
      - "10.96.0.53"
    searches:
      - NAMESPACE.svc.cluster.local
      - svc.cluster.local
      - cluster.local
    options:
      - name: ndots
        value: "2"
```

> [!warning]
> Replace `NAMESPACE` with your pod's namespace. The `searches` block is required for short names like `my-service`. `ndots:2` avoids wasted search-domain lookups for external names; use `ndots:5` if you need three-segment internal names like `my-service.my-namespace.svc` to resolve without a trailing dot.

## Caveats

- **Don't change your deployment tool's DNS**. If ArgoCD/Flux itself uses Knot Resolver and Knot Resolver goes down, you can't redeploy. Same for alerting stacks.
- **Service mesh DNS capture**. Istio sidecars can intercept DNS before it reaches Knot Resolver, silently bypassing DNSSEC validation.
- **`cluster.local` spoofing**. If `kubeDNS.enabled` is true, kube-dns doesn't sign responses, so the forward uses `dnssec: false`. An attacker who can spoof the kube-dns ClusterIP could poison internal DNS. Enabling `networkPolicy` mitigates this.

## Values

### Forwarding

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| forwarding.kubeDNS.enabled | bool | `false` | Auto-inject a cluster.local forward subtree pointing at the kube-dns Service |
| forwarding.kubeDNS.clusterIP | string | auto-detected | kube-dns Service IP (auto-detected if empty, falls back to 10.96.0.10) |
| forwarding.upstream.enabled | bool | `false` | Forward all queries to a well-known encrypted DNS provider over DoT instead of doing recursive resolution |
| forwarding.upstream.provider | string | `"quad9"` | DNS provider: `quad9`, `cloudflare`, or `google` |
| forwarding.zones | list | `[]` | Additional forward zones (list of Knot Resolver forward subtree objects). The chart auto-injects `cluster.local` when `forwarding.kubeDNS.enabled` is true; entries here are appended after it. |

### Resolver

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| resolver.rebindingProtection | bool | `false` | Enable DNS rebinding protection (blocks responses with private IPs from public names) |
| resolver.logBogus | bool | `true` | Log domains that fail DNSSEC validation |
| resolver.serveStale | bool | `true` | Serve expired cache entries when upstream is unreachable |
| resolver.glueChecking | string | `"normal"` | Glue record checking mode: `normal`, `strict`, or `permissive` (boolean `true`/`false` maps to `normal`/`permissive`) |
| resolver.dnssec | bool | `true` | Enable DNSSEC validation |
| resolver.dnssecNegativeTrustAnchors | list | `[]` | Domains to skip DNSSEC validation for (e.g. broken signed domains) |
| resolver.workers | string | Knot Resolver default | Number of resolver worker processes (`auto` or a number) |
| cache.sizeLimit | string | `"128Mi"` | Size of the in-memory DNS cache (sets both `cache.size-max` and the emptyDir sizeLimit) |
| cache.ttlMin | string | Knot Resolver default | Minimum TTL in seconds for cached records |
| cache.ttlMax | string | Knot Resolver default | Maximum TTL in seconds for cached records |
| cache.prefetchExpiring | bool | `false` | Prefetch expiring records before they expire |
| cache.prefetchPrediction | bool | `false` | Enable predictive prefetch (learns query patterns, experimental). Set `true` for defaults or pass an object with `window` and `period` keys. |
| configOverride | object | `{}` | Raw Knot Resolver configuration. Use as an escape hatch when you need full control. Merged last: any key you set here overrides the chart. |

### Logging

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| logging.level | string | Knot Resolver default (`notice`) | Global log level (`crit`, `err`, `warning`, `notice`, `info`, `debug`) |
| logging.groups | list | `[]` | Subsystems that get debug-level logging regardless of the global level (e.g. `["dnssec", "cache"]`) |

### Network Policy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| networkPolicy.enabled | bool | `false` | Create a network policy |
| networkPolicy.flavor | string | `"cilium"` | Network policy flavour: `cilium` for CiliumNetworkPolicy, `kubernetes` for NetworkPolicy |
| networkPolicy.ingressNamespaces | list | `[]` | Namespaces allowed to query Knot Resolver |
| networkPolicy.metricsNamespace | string | `"monitoring"` | Namespace allowed to scrape metrics |
| networkPolicy.egressToInternet | bool | `true` | Allow recursive resolution to the internet |

### Service

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| service.clusterIP | string | auto-assigned | Static ClusterIP, pin to well-known IP address from ServiceCIDR |
| service.port | int | `53` | DNS service port |

### Monitoring

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| metrics.enabled | bool | `true` | Create a metrics Service |
| metrics.port | int | `5000` | Metrics service port |
| metrics.serviceMonitor.enabled | bool | `false` | Create a Prometheus ServiceMonitor |

### Deployment

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| replicaCount | int | `1` | Number of Knot Resolver pods to run |
| extraVolumes | list | `[]` | Extra volumes for the pod (e.g. RPZ blocklists, custom Lua scripts, TLS certs) |
| extraVolumeMounts | list | `[]` | Extra volume mounts for the resolver container |
| podDisruptionBudget.enabled | bool | `false` | Create a PodDisruptionBudget |
| podDisruptionBudget.minAvailable | int | `1` | Minimum number of available pods |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Sam Sargeant | <sam@sargeant.net.nz> | <https://github.com/sargeant> |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
