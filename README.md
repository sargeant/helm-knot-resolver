# helm-knot-resolver

Helm chart to deploy [Knot Resolver](https://www.knot-resolver.cz/), a caching, DNSSEC-validating DNS resolver on Kubernetes.

Runs as an opt-in secondary DNS alongside CoreDNS. Pods that set `dnsPolicy: None` pointing at the Knot Resolver ClusterIP get DNSSEC validation, custom forwarding, and recursive resolution.

Uses the official [`cznic/knot-resolver`](https://hub.docker.com/r/cznic/knot-resolver) image. This is a community chart, not affiliated with CZ.NIC.

Full configuration reference and values documentation: [`charts/knot-resolver/`](charts/knot-resolver/README.md)

## Quick start

```bash
DNS_IP=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' | \
  awk -F. '{print $1"."$2"."$3".53"}')

helm repo add knot-resolver https://sargeant.github.io/helm-knot-resolver
helm install knot-resolver knot-resolver/knot-resolver \
  --set service.clusterIP=$DNS_IP \
  --set forwarding.kubeDNS.enabled=true
helm test knot-resolver
```

## AI disclosure

This chart is written with AI assistance (Claude Code). I review every change and
I'm accountable for what ships. CI runs `ct lint`, kubeconform, Trivy, and a
`ct install` plus `helm test` against a kind cluster on every chart PR.

## Licence

[Apache 2.0](LICENSE)
