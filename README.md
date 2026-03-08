# helm-knot-resolver

Helm chart for [Knot Resolver](https://www.knot-resolver.cz/) — a caching, DNSSEC-validating DNS resolver for Kubernetes.

Deploys as an opt-in secondary DNS alongside CoreDNS. Pods that set `dnsPolicy: None` pointing at the Knot Resolver ClusterIP get DNSSEC validation, custom forwarding, and recursive resolution.

Uses the official [`cznic/knot-resolver`](https://hub.docker.com/r/cznic/knot-resolver) image. This is a community chart, not affiliated with CZ.NIC.

## Quick start

```bash
helm repo add knot-resolver https://sargeant.github.io/helm-knot-resolver
helm install knot-resolver knot-resolver/knot-resolver --set service.clusterIP="10.96.0.53"
```

Test it:

```bash
kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never \
  -- nslookup example.com 10.96.0.53
```

To also resolve cluster-internal names (`*.svc.cluster.local`), enable kube-dns forwarding:

```bash
helm upgrade knot-resolver knot-resolver/knot-resolver \
  --set service.clusterIP="10.96.0.53" \
  --set forwarding.kubeDNS.enabled=true
```

Then configure pods with a full `dnsConfig`:

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
```

## Documentation

Full configuration reference and values documentation: [`charts/knot-resolver/`](charts/knot-resolver/)

## Licence

[Apache 2.0](LICENSE)
