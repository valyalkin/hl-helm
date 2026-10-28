# hl-budget

![Version: 0.2.4](https://img.shields.io/badge/Version-0.2.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2-548d0ff](https://img.shields.io/badge/AppVersion-2--548d0ff-informational?style=flat-square)

HL Budget, a personal budgeting app — Next.js web app at / and Kotlin/Spring API at /api on one private host.

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://../../library/hl-common | hl-common | ~0.1.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| backend.dependencies | object | `{"postgres":{"credentials":{"keys":{"password":"SPRING_DATASOURCE_PASSWORD","username":"SPRING_DATASOURCE_USERNAME"},"vaultPath":"apps/hl-budget/postgres"},"host":"postgres-rw.postgres.svc.cluster.local","port":5432}}` | OPTIONAL: Postgres, by address; credentials generated into Vault by bootstrap/install.sh |
| backend.ingress.enabled | bool | `true` | OPTIONAL: expose over HTTPS through Traefik |
| backend.ingress.host | string | `"hl-budget.home.example"` | REQUIRED when enabled: public hostname, shared with `frontend` |
| backend.ingress.path | string | `"/api"` | OPTIONAL: path prefix, not stripped; the backend serves under /api |
| backend.ingress.tls | object | `{"secretName":"hl-budget-frontend-tls"}` | OPTIONAL: certificate Secret, synced from Vault by `frontend.secrets.tls` |
| backend.service | object | `{"ports":[{"name":"http","port":80,"targetPort":8080}]}` | REQUIRED: port 80 in the cluster, the container's port as targetPort |
| backend.workload.env | list | `[{"name":"SPRING_DATASOURCE_URL","value":"jdbc:postgresql://postgres-rw.postgres.svc.cluster.local:5432/hl_budget"},{"name":"HLBUDGET_AUTH_ISSUER","value":"https://k8xv92p.ca.auth0.com/"},{"name":"HLBUDGET_AUTH_AUDIENCE","value":"https://api.hl-budget.example"},{"name":"HLBUDGET_AUTH_JWKSETURI","value":"https://k8xv92p.ca.auth0.com/.well-known/jwks.json"},{"name":"HLBUDGET_AUTH_CLAIMSNAMESPACE","value":"https://hl-budget/"},{"name":"HLBUDGET_MONEY_CURRENCY","value":"CAD"},{"name":"HLBUDGET_TIMEZONE","value":"America/Toronto"},{"name":"LOGGING_LEVEL_ROOT","value":"INFO"},{"name":"SPRINGDOC_API_DOCS_ENABLED","value":"false"},{"name":"SPRINGDOC_SWAGGER_UI_ENABLED","value":"false"}]` | OPTIONAL: plain environment variables (never secrets) |
| backend.workload.image.digest | string | `"sha256:54fc80eb2f5912e720f6c1dcd540b6265a31fe1dd817bc828cf3a364508ac663"` | REQUIRED: digest of that tag; updated by scripts/bump-image.py on every release |
| backend.workload.image.name | string | `"hl-budget-backend"` | REQUIRED: image name in ghcr.io/valyalkin. Set by the release workflow from homelab.yaml |
| backend.workload.image.tag | string | `"6-0b3f5c1"` | REQUIRED: version tag; updated by scripts/bump-image.py on every release |
| backend.workload.probes | object | `{"liveness":{"httpGet":{"path":"/healthz","port":"http"},"periodSeconds":10},"readiness":{"httpGet":{"path":"/readyz","port":"http"},"periodSeconds":5},"startup":{"failureThreshold":60,"httpGet":{"path":"/healthz","port":"http"},"periodSeconds":2}}` | OPTIONAL: HTTP probes. Startup allows 2 minutes for the JVM and Flyway |
| backend.workload.resources | object | `{"limits":{"memory":"512Mi"}}` | REQUIRED: memory limit. The JVM uses up to 75% of it (-XX:MaxRAMPercentage=75) |
| backend.workload.tmpDirs | list | `["/tmp"]` | OPTIONAL: writable directories (the root filesystem is read-only) |
| frontend.ingress.enabled | bool | `true` | OPTIONAL: expose over HTTPS through Traefik |
| frontend.ingress.host | string | `"hl-budget.home.example"` | REQUIRED when enabled: public hostname, shared with `backend` |
| frontend.ingress.path | string | `"/"` | OPTIONAL: path prefix; everything not under /api |
| frontend.ingress.tls | object | `{"secretName":"hl-budget-frontend-tls"}` | OPTIONAL: certificate Secret, synced from Vault by `secrets.tls` |
| frontend.secrets | object | `{"auth0":{"keys":{"auth0_client_secret":"AUTH0_CLIENT_SECRET","auth0_secret":"AUTH0_SECRET"},"vaultPath":"apps/hl-budget/frontend"},"tls":{"keys":{},"rolloutRestart":false,"type":"kubernetes.io/tls","vaultPath":"apps/hl-budget/tls"}}` | OPTIONAL: Vault secrets. The user writes the values; the chart only names the paths |
| frontend.service | object | `{"ports":[{"name":"http","port":80,"targetPort":8080}]}` | REQUIRED: port 80 in the cluster, the container's port as targetPort |
| frontend.workload.env | list | `[{"name":"APP_BASE_URL","value":"https://hl-budget.home.example"},{"name":"API_BASE_URL","value":"http://hl-budget-backend"},{"name":"API_TIMEOUT_MS","value":"5000"},{"name":"AUTH0_DOMAIN","value":"k8xv92p.ca.auth0.com"},{"name":"AUTH0_CLIENT_ID","value":"zvyqOJ4IaTklTQQl0lLuL1yL2reyScy4"},{"name":"AUTH0_AUDIENCE","value":"https://api.hl-budget.example"}]` | OPTIONAL: plain environment variables (never secrets) |
| frontend.workload.image.digest | string | `"sha256:4a8cbab2ded510da7b56dda75b84ec2dd85f25342c1d805a35eb5ef54ef40780"` | REQUIRED: digest of that tag; updated by scripts/bump-image.py on every release |
| frontend.workload.image.name | string | `"hl-budget-frontend"` | REQUIRED: image name in ghcr.io/valyalkin. Set by the release workflow from homelab.yaml |
| frontend.workload.image.tag | string | `"5-7e9a7e1"` | REQUIRED: version tag; updated by scripts/bump-image.py on every release |
| frontend.workload.probes | object | `{"liveness":{"httpGet":{"path":"/healthz","port":"http"},"periodSeconds":10},"readiness":{"httpGet":{"path":"/readyz","port":"http"},"periodSeconds":5},"startup":{"failureThreshold":30,"httpGet":{"path":"/healthz","port":"http"},"periodSeconds":2}}` | OPTIONAL: HTTP probes |
| frontend.workload.resources | object | `{"limits":{"memory":"256Mi"}}` | REQUIRED: memory limit for the Next.js standalone server |
| frontend.workload.tmpDirs | list | `["/tmp","/app/.next/cache"]` | OPTIONAL: writable directories (the root filesystem is read-only) |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
