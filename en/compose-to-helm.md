# Docker Compose → Helm: a practical migration

> A typical developer journey: the app runs locally via `compose.yaml` — now it needs to go into k3s.
> This guide is a step-by-step transition from Compose to a Helm chart, without magic.

> **See also:** [Docker](docker-guide.md) · [Linux](linux-guide.md) · [Helm](helm-guide.md) · [k3s](k3s-dev-guide.md) · [Demo walkthrough](examples-guide.md) · [Runnable demo](../examples/README.md)

---

## Table of Contents

1. [Concept mapping](#1-concept-mapping)
2. [Starting point — compose.yaml](#2-starting-point--composeyaml)
3. [What doesn't map directly](#3-what-doesnt-map-directly)
4. [Step 1 — image in registry or k3s](#4-step-1--image-in-registry-or-k3s)
5. [Step 2 — Deployment for each service](#5-step-2--deployment-for-each-service)
6. [Step 3 — Service for communication](#6-step-3--service-for-communication)
7. [Step 4 — ConfigMap for env vars](#7-step-4--configmap-for-env-vars)
8. [Step 5 — Secret for passwords](#8-step-5--secret-for-passwords)
9. [Step 6 — PVC instead of named volume](#9-step-6--pvc-instead-of-named-volume)
10. [Step 7 — package as a Helm chart](#10-step-7--package-as-a-helm-chart)
11. [Automatic conversion — kompose](#11-automatic-conversion--kompose)
12. [Full chart overview](#12-full-chart-overview)
13. [Distributing the chart](#13-distributing-the-chart)

---

## 1. Concept mapping

| Docker Compose | Kubernetes / Helm |
|---|---|
| `services.app` | Deployment + Service |
| `image:` | `spec.containers[].image` |
| `build:` | ❌ not available — image must be pre-built |
| `ports:` | Service ports + `containerPort` |
| `environment:` (plain) | `env:` in Deployment or ConfigMap |
| `environment:` (secrets) | Secret → `envFrom` or `env.valueFrom` |
| `env_file:` | ConfigMap or Secret |
| `volumes:` (named) | PersistentVolumeClaim |
| `volumes:` (bind mount) | not recommended in k8s |
| `depends_on:` | `readinessProbe` (indirect equivalent) |
| `healthcheck:` | `livenessProbe` + `readinessProbe` |
| `restart: always` | built-in — `restartPolicy: Always` by default |
| `mem_limit:` / `cpus:` | `resources.limits` |
| `networks:` | not needed — k8s has a flat network |
| `replicas:` | `spec.replicas` in Deployment |

---

## 2. Starting point — compose.yaml

A realistic example: Python app + PostgreSQL.

```yaml
services:
  app:
    build: .                          # build locally
    ports:
      - "8080:8080"
    environment:
      MESSAGE: "Hello from Compose!"
      DB_HOST: postgres
      DB_PASSWORD: secret123          # ❌ secret in compose.yaml
    depends_on:
      postgres:
        condition: service_healthy
    restart: always

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: secret123    # ❌ secret in compose.yaml
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "myapp"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

Goal: bring this into k3s while keeping the same behaviour.

The repo also ships a runnable minimal compose file for the demo app —
[`../examples/docker/compose.yaml`](../examples/docker/compose.yaml) — and its Helm-chart twin at
[`../examples/helm/myapp`](../examples/helm/myapp), so you can do the whole migration hands-on.

---

## 3. What doesn't map directly

### `build:` — image building

Compose can build an image on the fly. Kubernetes cannot. Before deploying, the image
**must already exist**.

```bash
# Option A: registry (recommended for production)
docker build -t my-registry/myapp:v1.0.0 .
docker push my-registry/myapp:v1.0.0

# Option B: directly into k3s (dev/local, no registry)
docker build -t myapp:latest .
docker save myapp:latest | sudo k3s ctr images import -
```

### `depends_on:` — startup order

Compose waits for a service to become healthy before starting a dependent one.
k8s has no startup ordering — `readinessProbe` solves this differently: a pod only
becomes Ready when the app is ready, and only then does the Service route traffic to it.

```yaml
# Compose
depends_on:
  postgres:
    condition: service_healthy

# k8s — app checks its own readiness via probe
# if DB is not ready yet — probe fails, pod gets no traffic, retries
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

If the app crashes when the DB is unavailable, use an `initContainer`:

```yaml
initContainers:
  - name: wait-for-postgres
    image: busybox
    command: ['sh', '-c', 'until nc -z postgres-service 5432; do sleep 2; done']
```

### `ports:` — binding to the host

Compose `"8080:8080"` publishes the port directly to the host machine.
In k8s, ports are not exposed externally by default — you need a `NodePort`,
`LoadBalancer` Service, or an Ingress. For internal communication, use `ClusterIP`.

### Secrets in `environment:`

In Compose, secrets often end up directly in `compose.yaml` or `.env`.
In k8s, there is a dedicated `Secret` object — not stored in plain text in manifests.

---

## 4. Step 1 — image in registry or k3s

```bash
# Option A: registry (recommended for production)
docker build -t my-registry/myapp:v1.0.0 .
docker push my-registry/myapp:v1.0.0

# Option B: directly into k3s (dev/local, no registry)
docker build -t myapp:latest .
docker save myapp:latest | sudo k3s ctr images import -
```

Postgres is a public image — k3s will pull it from Docker Hub automatically.

---

## 5. Step 2 — Deployment for each service

Each `service:` in Compose becomes a separate `Deployment`.

**app:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: app
          image: my-registry/myapp:v1.0.0
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: app-config      # plain env vars
            - secretRef:
                name: app-secrets     # secrets
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
```

Note the difference between the two probes: a failing `readinessProbe` keeps the pod
running but takes it out of Service traffic; a failing `livenessProbe` restarts the container.
Typical mistake — pointing liveness at a dependency (e.g. a `/health` that checks the DB):
a DB outage then causes restart loops instead of a graceful wait.

**postgres:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-secrets
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "myapp"]
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: pgdata
          persistentVolumeClaim:
            claimName: postgres-pvc
```

> ❌ **A Deployment for the database is fine for dev only.** A production database wants a
> `StatefulSet`: stable network identity, ordered rollout, `volumeClaimTemplates` per replica.
> Better still — a database operator (e.g. CloudNativePG) or a managed DB outside the cluster.

### imagePullSecrets — private registry

If the image lives in a private registry, the cluster needs credentials to pull it:

```bash
# Registry credentials as a Secret
kubectl create secret docker-registry regcred \
  --docker-server=my-registry.example.com \
  --docker-username=deploy \
  --docker-password='S3cret!' \
  -n my-namespace
```

```yaml
# In the pod spec of the Deployment
spec:
  template:
    spec:
      imagePullSecrets:
        - name: regcred
      containers:
        - name: app
          image: my-registry.example.com/myapp:v1.0.0
```

In the chart step this becomes a `values.yaml` knob (`imagePullSecrets: [{name: regcred}]`) —
for dev without a registry the list simply stays empty.

---

## 6. Step 3 — Service for communication

In Compose, services find each other by name (`DB_HOST: postgres`).
In k8s, a `Service` does this — it provides a stable DNS name inside the cluster.

```yaml
# app-service — accessible inside the cluster
apiVersion: v1
kind: Service
metadata:
  name: app-service
spec:
  selector:
    app: myapp
  ports:
    - port: 8080
      targetPort: 8080
---
# postgres-service — internal traffic only
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

> `DB_HOST: postgres` in Compose → `DB_HOST: postgres-service` in k8s.
> Full DNS name: `postgres-service.my-namespace.svc.cluster.local`

---

## 7. Step 4 — ConfigMap for env vars

Plain (non-secret) environment variables → ConfigMap.

```yaml
# Compose
environment:
  MESSAGE: "Hello!"
  DB_HOST: postgres

# k8s ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  MESSAGE: "Hello from k8s!"
  DB_HOST: postgres-service     # ← Service name, not the Compose service name
```

---

## 8. Step 5 — Secret for passwords

Secrets → a dedicated `Secret` object. Values stored as base64.

```bash
# Create Secret via kubectl (not stored in git)
kubectl create secret generic app-secrets \
  --from-literal=DB_PASSWORD=secret123 \
  -n my-namespace

kubectl create secret generic postgres-secrets \
  --from-literal=POSTGRES_DB=myapp \
  --from-literal=POSTGRES_USER=myapp \
  --from-literal=POSTGRES_PASSWORD=secret123 \
  -n my-namespace
```

In Helm — reference via `values.yaml` + `--set` or an external secret manager:

```yaml
# values.yaml — reference only, not the secret itself
postgres:
  existingSecret: postgres-secrets
```

---

## 9. Step 6 — PVC instead of named volume

`volumes: pgdata:` in Compose → `PersistentVolumeClaim` in k8s.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

k3s automatically satisfies PVCs via the built-in `local-path` provisioner.

---

## 10. Step 7 — package as a Helm chart

Now take all the manifests and parameterise them through `values.yaml`.

```
myapp/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── NOTES.txt
    ├── app-deployment.yaml
    ├── app-service.yaml
    ├── app-configmap.yaml
    ├── postgres-deployment.yaml
    ├── postgres-service.yaml
    └── postgres-pvc.yaml
```

**Chart.yaml** — chart metadata, the minimal complete version:

```yaml
apiVersion: v2                # always v2 for Helm 3
name: myapp
description: Python app + PostgreSQL, migrated from Docker Compose
type: application
version: 0.1.0                # chart version — bump on every chart change
appVersion: "1.0.0"           # app version — informational
```

**values.yaml** — everything that differs between dev and prod:

```yaml
app:
  image:
    repository: my-registry/myapp
    tag: "v1.0.0"
    pullPolicy: IfNotPresent
  imagePullSecrets: []        # e.g. [{name: regcred}] for a private registry
  replicaCount: 1
  message: "Hello from Helm!"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

postgres:
  image: postgres:16-alpine
  database: myapp
  user: myapp
  existingSecret: postgres-secrets   # Secret created separately, outside the chart
  storage: 1Gi
```

Also worth adding `templates/NOTES.txt` — a plain-text template Helm renders and prints
after `helm install` / `helm upgrade`. Put the post-install essentials there, e.g. the
port-forward command:
`kubectl port-forward service/app-service 8080:8080 -n {{ .Release.Namespace }}`.

**Deploy:**

```bash
# Create secrets separately (once)
kubectl create secret generic postgres-secrets \
  --from-literal=POSTGRES_DB=myapp \
  --from-literal=POSTGRES_USER=myapp \
  --from-literal=POSTGRES_PASSWORD=secret123 \
  -n demo

# Deploy the chart
helm upgrade --install myapp ./myapp \
  --namespace demo --create-namespace \
  --wait

# Verify — the release is there, and what did it create?
helm list -n demo
kubectl get all -n demo
kubectl port-forward service/app-service 8080:8080 -n demo
```

### Verify the migration before touching the cluster

```bash
# Render the templates locally and eyeball the manifests
helm template ./myapp | less

# Full client-side validation with values and hooks, no install
helm install myapp ./myapp --dry-run --debug -n demo

# Server-side schema check — the API server validates, nothing is created
helm template ./myapp | kubectl apply --dry-run=server -f -
```

This catches schema and template errors before anything reaches the cluster.

---

## 11. Automatic conversion — kompose

`kompose` converts `compose.yaml` into k8s manifests automatically.

```bash
# Install
brew install kompose

# Convert
kompose convert -f compose.yaml -o ./k8s-manifests/

# See what was generated before applying anything
ls ./k8s-manifests/

# Or apply directly
kompose up
```

**But there are caveats:** `kompose` generates flat manifests, not a Helm chart.
The output needs manual clean-up:

| What kompose does well | What needs fixing |
|---|---|
| Basic Deployment and Service | Secrets (generated in plain text) |
| PVC for named volumes | `build:` → must be replaced with `image:` |
| Port mapping | `depends_on:` → add initContainer or probe |
| Env vars | Resources (limits/requests are missing) |

> Use `kompose` as a starting point to understand the structure,
> not as a final production result.

---

## 12. Full chart overview

After migration:

```
Compose                          Helm chart
──────────────────────────────────────────────────────
services.app                  →  app-deployment.yaml
  build: .                    →  ❌ (image in registry)
  ports: 8080:8080             →  app-service.yaml (ClusterIP)
  environment.MESSAGE          →  app-configmap.yaml
  environment.DB_PASSWORD      →  Secret (outside the chart)
  depends_on: postgres         →  readinessProbe on /health

services.postgres             →  postgres-deployment.yaml
  image: postgres:16-alpine    →  unchanged
  environment.POSTGRES_*       →  Secret (outside the chart)
  volumes: pgdata              →  postgres-pvc.yaml
  healthcheck                  →  readinessProbe (pg_isready)

volumes.pgdata                →  postgres-pvc.yaml (PVC, 1Gi)
networks (implicit)           →  ❌ not needed (k8s flat network)
restart: always               →  ❌ not needed (built-in)
```

**Local development stays through Compose — nothing changes:**

```bash
# Development — same as before
docker compose up

# Staging / production — via Helm
helm upgrade --install myapp ./myapp -n demo --wait
```

---

## 13. Distributing the chart

The chart works — where should it live?

| Option | When it fits |
|---|---|
| In the app repo (e.g. `deploy/chart/`) | simplest — chart is versioned together with the code |
| Classic chart repo (`helm package` + repo index) | several teams / many charts, shared over HTTP |
| OCI registry (`helm push`) | you already have a container registry — reuse it |

```bash
# Classic chart repo: package + index
helm package ./myapp                      # → myapp-0.1.0.tgz
helm repo index . --url https://charts.example.com

# OCI registry — the same registry that stores your images
helm push myapp-0.1.0.tgz oci://my-registry.example.com/helm-charts
helm install myapp oci://my-registry.example.com/helm-charts/myapp --version 0.1.0
```

OCI details and deeper Helm topics — in [helm-guide.md](helm-guide.md);
deploying and troubleshooting on a real cluster — in [k3s-dev-guide.md](k3s-dev-guide.md).
