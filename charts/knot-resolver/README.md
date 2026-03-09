# knot-resolver

![Version: 0.6.1](https://img.shields.io/badge/Version-0.6.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v6.2.0](https://img.shields.io/badge/AppVersion-v6.2.0-informational?style=flat-square)

Caching DNSSEC-validating DNS resolver

**Homepage:** <https://www.knot-resolver.cz/>

## Requirements

Kubernetes: `>=1.23.0-0`

## Overview

Opt-in DNSSEC-validating DNS alongside CoreDNS. Pods set `dnsPolicy: None` pointing at the Knot Resolver ClusterIP. Uses the official [`cznic/knot-resolver`](https://hub.docker.com/r/cznic/knot-resolver) image. Community chart, not affiliated with CZ.NIC.

## Install

Assign a stable ClusterIP so pods can reference it in `dnsConfig.nameservers`. The snippet below derives `.53` from your cluster's Service CIDR — pick any unused address in range.

```bash
DNS_IP=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' | \
  awk -F. '{print $1"."$2"."$3".53"}')

helm repo add knot-resolver https://sargeant.github.io/helm-knot-resolver
helm install knot-resolver knot-resolver/knot-resolver --set service.clusterIP=$DNS_IP
helm test knot-resolver
```

## Pod DNS configuration

Set `forwarding.kubeDNS.enabled: true` to resolve `cluster.local` via kube-dns, then configure pods:

```yaml
spec:
  dnsPolicy: "None"
  dnsConfig:
    nameservers:
      - "DNS_IP"
    searches:
      - NAMESPACE.svc.cluster.local
      - svc.cluster.local
      - cluster.local
    options:
      - name: ndots
        value: "2"
```

> [!note]
> Replace `NAMESPACE` with the pod's namespace; `DNS_IP` with the address you selected for the static ClusterIP.

Use `ndots:5` if you need short three-segment internal names like `myapp.prod.svc` to resolve without a trailing dot.

By default, pods use `dnsPolicy: ClusterFirst`, which has the kubelet inject the cluster DNS service as the sole nameserver — overriding any `dnsConfig.nameservers` you set. `dnsPolicy: "None"` stops that override, so the pod uses exactly the `dnsConfig` you provide.

## Caveats

- **Don't point your GitOps tool at Knot Resolver**. If ArgoCD/Flux deploys+queries Knot Resolver and it goes down, you can't redeploy.
- **Service mesh DNS capture**. Service mesh sidecars may intercept DNS before it reaches Knot Resolver, bypassing DNSSEC validation.
- **`cluster.local` is unsigned**. The kube-dns forward uses `dnssec: false`, so responses for internal names are not authenticated. Enabling `networkPolicy` restricts which pods can query and respond on that path.

## Values

### Forwarding

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| forwarding.kubeDNS.enabled | bool | `false` | Forward `cluster.local` queries to kube-dns |
| forwarding.kubeDNS.clusterIP | string | auto-detected | kube-dns Service IP (auto-detected from cluster; required when using `helm template` or `--dry-run`) |
| forwarding.upstream.enabled | bool | `false` | Use a DoT upstream instead of recursive resolution |
| forwarding.upstream.provider | string | `"quad9"` | DNS provider: `quad9`, `cloudflare`, or `google` |
| forwarding.zones | list | `[]` | Additional forward zones (raw Knot Resolver `forward` entries). Appended after the auto-injected `cluster.local` zone. |

### Resolver

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| resolver.rebindingProtection | bool | `false` | Enable DNS rebinding protection (blocks responses with private IPs from public names) |
| resolver.logBogus | bool | `true` | Log bogus (DNSSEC-invalid) answers |
| resolver.serveStale | bool | `true` | Serve expired cache entries when upstream fails |
| resolver.glueChecking | string | `"normal"` | Glue record checking mode: `normal`, `strict`, or `permissive` |
| resolver.dnssec | bool | `true` | Enable DNSSEC validation |
| resolver.dnssecNegativeTrustAnchors | list | `[]` | Domains to skip DNSSEC validation for (e.g. broken signed domains) |
| resolver.timeJumpDetection | string | Knot Resolver default (`true`) | Detect system clock vs DNSSEC signature time skew on root NS records |
| resolver.violatorsWorkarounds | string | Knot Resolver default (`false`) | Enable workarounds for known DNS protocol violators |
| resolver.workers | string | Knot Resolver default | Number of resolver worker processes (`auto` or a number) |
| cache.sizeLimit | string | `"128Mi"` | Size of the in-memory DNS cache (sets both `cache.size-max` and the emptyDir sizeLimit) |
| cache.ttlMin | string | Knot Resolver default | Minimum TTL for cached records (integer seconds or duration string like `60s`, `1m`) |
| cache.ttlMax | string | Knot Resolver default | Maximum TTL for cached records (integer seconds or duration string like `86400s`, `24h`) |
| cache.prefetchExpiring | bool | `false` | Proactively refresh records nearing expiry |
| cache.prefetchPrediction | bool | `false` | Enable predictive prefetch (experimental). `true` for defaults or pass an object with `window` and `period` keys. |
| cache.prefill | bool | `false` | Prefill the cache with root zone data fetched over HTTPS. Set `true` for sensible defaults or pass an object with `url`, `refreshInterval`, and optional `caFile`. |

### Logging

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| logging.level | string | Knot Resolver default (`notice`) | Global log level (`crit`, `err`, `warning`, `notice`, `info`, `debug`) |
| logging.groups | list | `[]` | Subsystems that get debug-level logging regardless of the global level (e.g. `["dnssec", "cache"]`) |

### Escape Hatch

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| configOverride | object | `{}` | Knot Resolver `config.yaml` — merged last, overrides everything |

### Network Policy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| networkPolicy.enabled | bool | `false` | Create a network policy |
| networkPolicy.flavor | string | `"cilium"` | Network policy flavor: `cilium` or `kubernetes` |
| networkPolicy.ingressNamespaces | list | `[]` | Namespaces allowed to query Knot Resolver |
| networkPolicy.metricsNamespace | string | `"monitoring"` | Namespace allowed to scrape metrics |
| networkPolicy.egressToInternet | bool | `true` | Allow outbound internet access (recursive resolution) |

### Service

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| service.clusterIP | string | auto-assigned | Static ClusterIP for use in pod `dnsConfig.nameservers` |
| service.port | int | `53` | DNS service port |

### Monitoring

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| metrics.enabled | bool | `true` | Create a metrics Service |
| metrics.port | int | `5000` | Metrics service port |
| metrics.serviceMonitor.enabled | bool | `false` | Create a Prometheus ServiceMonitor |
| metrics.serviceMonitor.namespaceSelector | object | same namespace only | Namespace selector for cross-namespace Prometheus discovery (e.g. `{matchNames: ["knot"]}`) |

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
