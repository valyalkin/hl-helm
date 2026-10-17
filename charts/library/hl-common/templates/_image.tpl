{{/*
Fully-qualified image reference (FR-021, FR-023, FR-025). Takes a service context.
A digest wins over a tag. Without a digest the tag must be immutable-looking: set, not "latest",
and containing a digit.
*/}}
{{- define "hl-common.image" -}}
{{- $img := .v.workload.image -}}
{{- $p := printf "%s.workload.image" .name -}}
{{- if not $img.name -}}{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.name" $p)) -}}{{- end -}}
{{- if and (not $img.digest) (not $img.tag) -}}{{- include "hl-common.fail" (printf "required value %q or %q is not set in chart %q" (printf "%s.tag" $p) (printf "%s.digest" $p) .root.Chart.Name) -}}{{- end -}}
{{- if and (not $img.digest) (or (eq $img.tag "latest") (not (regexMatch "[0-9]" $img.tag))) -}}
{{- include "hl-common.fail" (printf "chart %q: image %q uses mutable tag %q (%s.tag); pin a version tag or a digest" .root.Chart.Name $img.name $img.tag $p) -}}
{{- end -}}
{{- $repo := $img.name -}}
{{- if $img.owner }}{{ $repo = printf "%s/%s" $img.owner $img.name }}{{ end -}}
{{- if $img.registry }}{{ $repo = printf "%s/%s" $img.registry $repo }}{{ end -}}
{{- if and $img.tag $img.digest -}}
{{- printf "%s:%s@%s" $repo $img.tag $img.digest -}}
{{- else if $img.digest -}}
{{- printf "%s@%s" $repo $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $repo $img.tag -}}
{{- end -}}
{{- end -}}

{{/* Value for the app.kubernetes.io/version label. */}}
{{- define "hl-common.imageVersion" -}}
{{- $img := .v.workload.image -}}
{{- if $img.tag -}}{{- $img.tag | trunc 63 | trimSuffix "-" -}}{{- else -}}{{- trimPrefix "sha256:" (default "" $img.digest) | trunc 12 -}}{{- end -}}
{{- end -}}
