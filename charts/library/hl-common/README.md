# hl-common

Library chart holding every convention shared by the charts in this repository. A consuming chart
writes one template per service and one values block per service; `hl-common` renders the
Deployment/StatefulSet, Service, Ingress and ConfigMap with naming, labels, probes, resource
limits, hardened security context and TLS ingress already applied.

```yaml
# charts/apps/<app>/templates/web.yaml
{{ include "hl-common.all" (dict "root" . "name" "web" "values" .Values.web) }}
```

Values surface: see `values.yaml` (documentation) and `values.schema.json`. Defaults live in
`templates/_defaults.tpl`. Memory limit, image name and a tag or digest are required; rendering
fails naming the value path when they are absent.

## Extending a chart — the three sanctioned ways

1. **Add a resource.** Put an ordinary manifest in the chart's `templates/` and use the helpers so
   it matches foundation naming and labels:

   ```yaml
   apiVersion: batch/v1
   kind: CronJob
   metadata:
     name: {{ include "hl-common.name" (dict "root" . "name" "report") }}
     labels:
       {{- include "hl-common.labels" (dict "root" . "name" "report") | nindent 4 }}
   ```

   `hl-common.podSpec` (called with `(dict "root" . "name" "report" "v" <built values>)`) yields
   the standard hardened container for custom controllers.

2. **Override a default.** Set it in the chart's `values.yaml`, e.g. `web.workload.replicas: 2`.
   No template change.

3. **Replace a rendered section.** Declare `overrides.<section>: true` in the service block and
   define a template named `<chart>.override.<section>` (sections: `workload`, `service`,
   `ingress`, `config`). Helm cannot test whether a template exists, so the flag is the explicit
   opt-in. Record the reason in the chart's README (FR-004).

Copying a template out of `hl-common` into a chart is prohibited; policy check 2 fails it.

## Guarantees

Every workload gets requests, a memory limit, liveness and readiness probes (default: tcpSocket on
the first port), `automountServiceAccountToken: false`, a non-root read-only-root-filesystem
security context, mutable image tags rejected, and a restart when its ConfigMap changes.

## Versioning

SemVer independent of consumers. Signature or guarantee change: MAJOR. New optional value: MINOR.
Output-equivalent fix: PATCH.

