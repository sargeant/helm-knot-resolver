{{- define "knot-resolver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "knot-resolver.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "knot-resolver.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "knot-resolver.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "knot-resolver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "knot-resolver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "knot-resolver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "knot-resolver.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "knot-resolver.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}

{{/*
Complete chart-managed config: base settings, first-class values, and forward zones.
configOverride is applied on top of this in configmap.yaml.
*/}}
{{- define "knot-resolver.managedConfig" -}}
network:
  listen:
    - interface:
        - 0.0.0.0@{{ .Values.listenPort }}
      kind: dns
management:
  interface: 0.0.0.0@{{ .Values.managementPort }}
monitoring:
  metrics: always
cache:
  size-max: {{ .Values.cache.sizeLimit | trimSuffix "i" }}
{{- if .Values.cache.ttlMin }}
  ttl-min: {{ .Values.cache.ttlMin }}
{{- end }}
{{- if .Values.cache.ttlMax }}
  ttl-max: {{ .Values.cache.ttlMax }}
{{- end }}
{{- if .Values.cache.prefetchExpiring }}
  prefetch:
    expiring: {{ .Values.cache.prefetchExpiring }}
{{- end }}
options:
  minimize: {{ .Values.resolver.minimize }}
  rebinding-protection: {{ .Values.resolver.rebindingProtection }}
  serve-stale: {{ .Values.resolver.serveStale }}
  time-jump-detection: {{ .Values.resolver.timeJumpDetection }}
{{- if .Values.resolver.glueChecking }}
{{- $valid := list "normal" "strict" "permissive" -}}
{{- if not (has .Values.resolver.glueChecking $valid) }}
{{- fail (printf "resolver.glueChecking must be one of: normal, strict, permissive (got %q)" .Values.resolver.glueChecking) }}
{{- end }}
  glue-checking: {{ .Values.resolver.glueChecking }}
{{- end }}
{{- if .Values.resolver.violatorsWorkarounds }}
  violators-workarounds: {{ .Values.resolver.violatorsWorkarounds }}
{{- end }}
dnssec:
  enable: {{ .Values.resolver.dnssec }}
{{- if .Values.resolver.logBogus }}
  log-bogus: {{ .Values.resolver.logBogus }}
{{- end }}
{{- if .Values.resolver.negativeTrustAnchors }}
  negative-trust-anchors:
    {{- toYaml .Values.resolver.negativeTrustAnchors | nindent 4 }}
{{- end }}
{{- if or .Values.logging.level .Values.logging.groups }}
logging:
{{- if .Values.logging.level }}
  level: {{ .Values.logging.level }}
{{- end }}
{{- if .Values.logging.groups }}
  groups:
    {{- toYaml .Values.logging.groups | nindent 4 }}
{{- end }}
{{- end }}
{{- if .Values.resolver.workers }}
{{- if eq (toString .Values.resolver.workers) "auto" }}
workers: auto
{{- else }}
workers: {{ .Values.resolver.workers | int }}
{{- end }}
{{- end }}
{{ include "knot-resolver.forwardZones" . }}
{{- end }}

{{/*
Resolve the kube-dns ClusterIP. Uses the explicit value if set, otherwise attempts
lookup from the cluster. Fails if neither is available.
*/}}
{{- define "knot-resolver.kubeDNSIP" -}}
{{- if .Values.forwarding.kubeDNS.clusterIP }}
{{- .Values.forwarding.kubeDNS.clusterIP }}
{{- else }}
{{- $svc := (lookup "v1" "Service" "kube-system" "kube-dns") }}
{{- if $svc }}
{{- $svc.spec.clusterIP }}
{{- else }}
{{- fail "Cannot auto-detect kube-dns ClusterIP (lookup unavailable during template/dry-run). Set forwarding.kubeDNS.clusterIP explicitly, or disable with forwarding.kubeDNS.enabled=false." }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Build the forward zone list from kubeDNS, upstream, and user-defined zones.
*/}}
{{- define "knot-resolver.forwardZones" -}}
{{- $forwardList := list -}}
{{- if .Values.forwarding.kubeDNS.enabled }}
{{- $forwardList = append $forwardList (dict
  "subtree" "cluster.local."
  "servers" (list (dict "address" (list (printf "%s@53" (include "knot-resolver.kubeDNSIP" . | trim)))))
  "options" (dict "dnssec" false "authoritative" true)
) -}}
{{- end }}
{{- range .Values.forwarding.zones }}
{{- $forwardList = append $forwardList . -}}
{{- end }}
{{- if .Values.forwarding.upstream.enabled }}
{{- $providers := dict
  "quad9" (dict "addresses" (list "9.9.9.9" "149.112.112.112" "2620:fe::fe" "2620:fe::9") "hostname" "dns.quad9.net")
  "cloudflare" (dict "addresses" (list "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001") "hostname" "cloudflare-dns.com")
  "google" (dict "addresses" (list "8.8.8.8" "8.8.4.4" "2001:4860:4860::8888" "2001:4860:4860::8844") "hostname" "dns.google")
-}}
{{- $provider := get $providers .Values.forwarding.upstream.provider }}
{{- if not $provider }}
{{- fail (printf "forwarding.upstream.provider must be one of: quad9, cloudflare, google (got %q)" .Values.forwarding.upstream.provider) }}
{{- end }}
{{- $forwardList = append $forwardList (dict
  "subtree" "."
  "servers" (list (dict "address" $provider.addresses "transport" "tls" "hostname" $provider.hostname))
) -}}
{{- end }}
{{- if $forwardList }}
forward:
  {{- toYaml $forwardList | nindent 2 }}
{{- end }}
{{- end }}
