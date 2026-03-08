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
Base config managed by the chart. Ports are derived from values to stay in sync
with containerPort definitions. Can be overridden via configOverride.
*/}}
{{- define "knot-resolver.baseConfig" -}}
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
{{- end }}

{{/*
Resolve the kube-dns ClusterIP. Uses the explicit value if set, otherwise attempts
lookup from the cluster, falling back to the conventional 10.96.0.10.
*/}}
{{- define "knot-resolver.kubeDNSIP" -}}
{{- if .Values.forwarding.kubeDNS.clusterIP }}
{{- .Values.forwarding.kubeDNS.clusterIP }}
{{- else }}
{{- $svc := (lookup "v1" "Service" "kube-system" "kube-dns") }}
{{- if $svc }}
{{- $svc.spec.clusterIP }}
{{- else }}
{{- "10.96.0.10" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Build the kube-dns forward subtree for cluster.local when forwarding.kubeDNS.enabled is true.
Returns a dict with a forward list entry, ready to merge into the config.
*/}}
{{- define "knot-resolver.kubeDNSForward" -}}
{{- if .Values.forwarding.kubeDNS.enabled }}
forward:
  - subtree: cluster.local.
    servers:
      - address:
          - {{ printf "%s@53" (include "knot-resolver.kubeDNSIP" . | trim) | quote }}
    options:
      dnssec: false
      authoritative: true
{{- end }}
{{- end }}

{{/*
Build an upstream DoT forward subtree for a well-known provider.
Returns a forward list entry with transport: tls when forwarding.upstream.enabled is true.
*/}}
{{- define "knot-resolver.upstreamForward" -}}
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
forward:
  - subtree: "."
    servers:
      - address:
          {{- range $provider.addresses }}
          - {{ . | quote }}
          {{- end }}
        transport: tls
        hostname: {{ $provider.hostname }}
{{- end }}
{{- end }}

{{/*
Build resolver config from first-class values. Boolean toggles are always
emitted explicitly to avoid depending on upstream defaults.
*/}}
{{- define "knot-resolver.firstClassConfig" -}}
{{- $cfg := dict -}}
{{- $_ := set $cfg "options" (mustMergeOverwrite (default dict (get $cfg "options")) (dict "rebinding-protection" .Values.resolver.rebindingProtection)) -}}
{{- $_ := set $cfg "options" (mustMergeOverwrite (default dict (get $cfg "options")) (dict "serve-stale" .Values.resolver.serveStale)) -}}
{{- $glue := .Values.resolver.glueChecking -}}
{{- if kindIs "bool" $glue -}}
{{- $glue = ternary "normal" "permissive" $glue -}}
{{- end -}}
{{- $_ := set $cfg "options" (mustMergeOverwrite (default dict (get $cfg "options")) (dict "glue-checking" $glue)) -}}
{{- $_ := set $cfg "dnssec" (mustMergeOverwrite (default dict (get $cfg "dnssec")) (dict "log-bogus" .Values.resolver.logBogus)) -}}
{{- $_ := set $cfg "dnssec" (mustMergeOverwrite (default dict (get $cfg "dnssec")) (dict "enable" .Values.resolver.dnssec)) -}}
{{- if .Values.resolver.dnssecNegativeTrustAnchors }}
{{- $_ := set $cfg "dnssec" (mustMergeOverwrite (default dict (get $cfg "dnssec")) (dict "negative-trust-anchors" .Values.resolver.dnssecNegativeTrustAnchors)) -}}
{{- end }}
{{- if .Values.logging.level }}
{{- $_ := set $cfg "logging" (mustMergeOverwrite (default dict (get $cfg "logging")) (dict "level" .Values.logging.level)) -}}
{{- end }}
{{- if .Values.logging.groups }}
{{- $_ := set $cfg "logging" (mustMergeOverwrite (default dict (get $cfg "logging")) (dict "groups" .Values.logging.groups)) -}}
{{- end }}
{{- if .Values.cache.ttlMin }}
{{- $ttlMin := .Values.cache.ttlMin -}}
{{- if not (regexMatch "[a-z]+$" (toString $ttlMin)) -}}{{- $ttlMin = printf "%ds" (int (toString $ttlMin)) -}}{{- end -}}
{{- $_ := set $cfg "cache" (mustMergeOverwrite (default dict (get $cfg "cache")) (dict "ttl-min" $ttlMin)) -}}
{{- end }}
{{- if .Values.cache.ttlMax }}
{{- $ttlMax := .Values.cache.ttlMax -}}
{{- if not (regexMatch "[a-z]+$" (toString $ttlMax)) -}}{{- $ttlMax = printf "%ds" (int (toString $ttlMax)) -}}{{- end -}}
{{- $_ := set $cfg "cache" (mustMergeOverwrite (default dict (get $cfg "cache")) (dict "ttl-max" $ttlMax)) -}}
{{- end }}
{{- $prefetch := dict "expiring" .Values.cache.prefetchExpiring -}}
{{- if .Values.cache.prefetchPrediction -}}
{{- $prediction := .Values.cache.prefetchPrediction -}}
{{- if kindIs "bool" $prediction -}}
{{- $prediction = dict -}}
{{- end -}}
{{- $_ := set $prefetch "prediction" $prediction -}}
{{- end -}}
{{- $_ := set $cfg "cache" (mustMergeOverwrite (default dict (get $cfg "cache")) (dict "prefetch" $prefetch)) -}}
{{- if .Values.resolver.workers }}
{{- if eq (typeOf .Values.resolver.workers) "string" }}
{{- if eq .Values.resolver.workers "auto" }}
{{- $_ := set $cfg "workers" "auto" -}}
{{- end }}
{{- else }}
{{- $_ := set $cfg "workers" (.Values.resolver.workers | int) -}}
{{- end }}
{{- end }}
{{- toYaml $cfg -}}
{{- end }}
