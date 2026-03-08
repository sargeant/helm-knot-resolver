# helm-knot-resolver

Helm chart for [Knot Resolver](https://www.knot-resolver.cz/) — a caching, DNSSEC-validating DNS resolver for Kubernetes.

Deploys as an opt-in secondary DNS alongside CoreDNS. Pods that set `dnsPolicy: None` pointing at the Knot Resolver ClusterIP get DNSSEC validation, custom forwarding, and recursive resolution.

## Quick start

```bash
helm repo add knot-resolver https://sargeant.github.io/helm-knot-resolver
helm install knot-resolver knot-resolver/knot-resolver --set service.clusterIP="10.96.0.53"
```

## Documentation

Full configuration reference and values documentation: [`charts/knot-resolver/`](charts/knot-resolver/)

## Licence

[Apache 2.0](LICENSE)
