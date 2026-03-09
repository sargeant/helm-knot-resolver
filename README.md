# helm-knot-resolver

Helm chart for [Knot Resolver](https://www.knot-resolver.cz/), a caching, DNSSEC-validating DNS resolver for Kubernetes.

Deploys as an opt-in secondary DNS alongside CoreDNS. Pods that set `dnsPolicy: None` pointing at the Knot Resolver ClusterIP get DNSSEC validation, custom forwarding, and recursive resolution.

Uses the official [`cznic/knot-resolver`](https://hub.docker.com/r/cznic/knot-resolver) image. This is a community chart, not affiliated with CZ.NIC.

## Quick start

Assign a stable ClusterIP so pods can reference it in `dnsConfig.nameservers`. The snippet below derives `.53` from your cluster's Service CIDR. Pick any unused address in range.

```bash
DNS_IP=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' | \
  awk -F. '{print $1"."$2"."$3".53"}')

helm repo add knot-resolver https://sargeant.github.io/helm-knot-resolver
helm install knot-resolver knot-resolver/knot-resolver --set service.clusterIP=$DNS_IP
helm test knot-resolver
```

To also resolve cluster-internal names (`*.svc.cluster.local`), enable kube-dns forwarding:

```bash
helm upgrade knot-resolver knot-resolver/knot-resolver \
  --set service.clusterIP=$DNS_IP \
  --set forwarding.kubeDNS.enabled=true
```

Then configure pods. Setting `dnsPolicy: "None"` stops the kubelet overriding nameservers, so the pod uses exactly the `dnsConfig` you provide:

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

## Documentation

Full configuration reference and values documentation: [`charts/knot-resolver/`](charts/knot-resolver/)

## Licence

[Apache 2.0](LICENSE)
