# Demo App — Docker → Helm → k3s

> One application, three levels of deployment. From a local container to a Kubernetes cluster.

> **See also:** [Docker](docker-guide.md) · [Linux](linux-guide.md) · [Helm](helm-guide.md) · [k3s](k3s-dev-guide.md) · [Compose → Helm](compose-to-helm.md) · [Demo code](../examples/README.md)

---

## Table of Contents

1. [What we're building](#1-what-were-building)
2. [File structure](#2-file-structure)
3. [The app — app.py](#3-the-app--apppy)
4. [Docker — building the image](#4-docker--building-the-image)
5. [Helm — a chart for Kubernetes](#5-helm--a-chart-for-kubernetes)
6. [k3s — deploying to the cluster](#6-k3s--deploying-to-the-cluster)
7. [End-to-end steps](#7-end-to-end-steps)

---

## 1. What we're building

A minimal HTTP server in Python (no frameworks) that serves:

| Endpoint     | Response                                               |
|--------------|--------------------------------------------------------|
| `GET /`      | `{"message": "...", "version": "...", "hostname": "..."}` |
| `GET /health`| `{"status": "ok"}`                                     |

`/health` is used as the liveness and readiness probe in Kubernetes — k3s hits it to know whether the pod is alive and ready to accept traffic.

---

## 2. File structure

```
examples/
├── docker/
│   ├── app.py          ← the app itself
│   ├── Dockerfile      ← instructions for building the image
│   ├── compose.yaml    ← local runs via Docker Compose
│   └── .dockerignore   ← what to keep out of the image
├── helm/
│   └── myapp/
│       ├── Chart.yaml              ← chart metadata
│       ├── values.yaml             ← default variables
│       ├── values.schema.json      ← values validation schema
│       └── templates/
│           ├── _helpers.tpl        ← shared name and label templates
│           ├── deployment.yaml     ← how to run the pod
│           ├── service.yaml        ← how to reach the pod
│           └── ingress.yaml        ← optional external access
└── k3s/
    └── deploy.sh       ← script: build → import → helm deploy
```

---

## 3. The app — app.py

```python
from http.server import BaseHTTPRequestHandler, HTTPServer
```

Python ships with a built-in HTTP server. `BaseHTTPRequestHandler` is the base class where we override `do_GET` to handle GET requests.

### How it works

```python
def do_GET(self):
    if self.path == "/health":
        self._respond(200, {"status": "ok"})
    elif self.path == "/":
        self._respond(200, {
            "message": os.getenv("MESSAGE", "Hello from myapp!"),
            ...
        })
    else:
        self._respond(404, {"error": "not found"})
```

- `self.path` — the path from the request URL (`/`, `/health`, etc.)
- `os.getenv("MESSAGE", "default")` — the value comes from an environment variable, or the default if unset
- `hostname` in the response — the pod name in Kubernetes. Handy for checking which pod answered when running multiple replicas

### The `_respond` method

```python
def _respond(self, code, data):
    body = json.dumps(data).encode()
    self.send_response(code)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)
```

`Content-Length` is mandatory — without it some HTTP clients and proxies may read the response body incorrectly.

### Startup

```python
port = int(os.getenv("PORT", 8080))
server = HTTPServer(("", port), Handler)
server.serve_forever()
```

`""` as the host means "listen on all interfaces" — required for the container to be reachable from the outside.

---

## 4. Docker — building the image

### Dockerfile line by line

```dockerfile
FROM python:3-alpine
```

A minimal base image. `alpine` is a ~5MB Linux distribution. No extra utilities, smaller attack surface.

```dockerfile
WORKDIR /app
```

Sets the working directory. All subsequent `COPY`, `RUN`, `CMD` run relative to it. Better than `cd` inside `RUN`.

```dockerfile
COPY app.py .
```

Copy only what's needed. Not `COPY . .` — don't drag in extras (`.git`, local configs, etc.).

```dockerfile
RUN adduser -D -u 1001 appuser
USER appuser
```

Create an unprivileged user and switch to it. A container should not run as `root` — that's a baseline security requirement. In the Helm chart, `securityContext` reinforces this.

```dockerfile
EXPOSE 8080
```

Documents which port the app uses. It does not open the port to the outside — it's just metadata for `docker inspect` and orchestrators.

```dockerfile
CMD ["python", "app.py"]
```

The startup command. Exec form (an array) runs the process directly, without a shell. PID 1 receives `SIGTERM` correctly on `docker stop`.

### Build and run

```bash
cd examples/docker

# Build the image
docker build -t myapp:local .

# Run locally
docker run --rm -p 8080:8080 myapp:local

# Check
curl http://localhost:8080/
curl http://localhost:8080/health

# Run with a custom message
docker run --rm -p 8080:8080 \
  -e MESSAGE="Hello from Docker!" \
  -e APP_VERSION="2.0.0" \
  myapp:local
```

### .dockerignore

```
__pycache__
*.pyc
*.pyo
```

Without this file Docker would include the Python cache in the build context, polluting the image with bytecode from the local machine.

### Local runs via Docker Compose

For day-to-day development, instead of manual `docker build` + `docker run`, a single file is more convenient — [compose.yaml](../examples/docker/compose.yaml):

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      MESSAGE: "Hello from Compose!"
      APP_VERSION: "1.0.0"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/health"]
      interval: 10s
      timeout: 3s
      retries: 3
    restart: unless-stopped
```

- `build: .` — Compose builds the image itself from the Dockerfile in this directory
- `healthcheck` — the same `/health` used by the Kubernetes probes; `wget` is already present in the alpine image
- `restart: unless-stopped` — the container comes back up after a crash or a Docker restart

```bash
cd examples/docker

# Build and run (--build rebuilds the image after code changes)
docker compose up --build

# Or in the background
docker compose up --build -d

# Healthcheck status: (healthy) in the STATUS column
docker compose ps

# Check
curl http://localhost:8080/

# Stop and remove the containers
docker compose down
```

The same app then moves on to Kubernetes — how Compose fields map onto the Helm chart is covered in [Compose → Helm](compose-to-helm.md).

---

## 5. Helm — a chart for Kubernetes

Helm is the package manager for Kubernetes. A chart is manifest templates + variables.

### Chart.yaml

```yaml
apiVersion: v2
name: myapp
version: 0.1.0
appVersion: "1.0.0"
```

- `version` — the version of the chart itself (bumped when templates change)
- `appVersion` — the version of the app (informational, does not affect the deploy)

### values.yaml — the configuration entry point

```yaml
image:
  repository: myapp
  tag: "1.0.0"
  pullPolicy: IfNotPresent   # don't pull the image if it's already on the node

env:
  MESSAGE: "Hello from myapp!"
  APP_VERSION: "1.0.0"

resources:
  requests:
    cpu: 50m       # 50 millicores — guaranteed minimum
    memory: 32Mi
  limits:
    cpu: 200m      # 200 millicores — maximum
    memory: 64Mi
```

`IfNotPresent` is critical for local deploys via `k3s ctr images import` — without it k3s would try to pull the image from a registry and fail to find it.

### templates/deployment.yaml — key points

**Liveness probe** — checks whether the process is alive. If it stops responding, the pod is restarted.

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5   # give the app time to start
  periodSeconds: 10
```

**Readiness probe** — checks whether the pod is ready to accept traffic. If it fails, the pod is removed from the service rotation but not restarted.

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 3
  periodSeconds: 5
```

**securityContext** — confirms at the Kubernetes level that the process is not root and runs with restricted privileges:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  seccompProfile:
    type: RuntimeDefault
```

**Environment variables from values.yaml:**

```yaml
env:
  {{- range $key, $val := .Values.env }}
  - name: {{ $key }}
    value: {{ $val | quote }}
  {{- end }}
```

`range` iterates over the `env` map in values. `quote` wraps values in quotes — protection against YAML interpreting numbers as int.

### templates/service.yaml

```yaml
spec:
  type: ClusterIP    # reachable only inside the cluster
  ports:
    - port: 8080     # service port (what other pods connect to)
      targetPort: 8080  # container port (where the service forwards)
```

`ClusterIP` is the standard type for internal services. For external access — `port-forward` or an Ingress.

### templates/ingress.yaml — optional Ingress

The chart includes an Ingress that is **disabled by default** — the whole template is wrapped in `{{- if .Values.ingress.enabled }}`. In `values.yaml` it's driven by this block:

```yaml
ingress:
  enabled: false
  # k3s ships with Traefik; empty className = the default IngressClass
  className: ""
  annotations: {}
  host: myapp.local
  tls:
    enabled: false
    secretName: myapp-tls
```

k3s ships with Traefik as its Ingress controller out of the box, so there is nothing extra to install. Enable external access:

```bash
helm upgrade --install myapp examples/helm/myapp \
  --namespace demo --create-namespace \
  --set ingress.enabled=true \
  --set ingress.host=myapp.local \
  --wait

# Add the host to /etc/hosts (the k3s node IP) and check
curl http://myapp.local/
```

**TLS** is optional too. First create a secret with the certificate, then enable `ingress.tls.enabled`:

```bash
# The secret must exist before the deploy
kubectl create secret tls myapp-tls \
  --cert=tls.crt --key=tls.key -n demo

helm upgrade --install myapp examples/helm/myapp \
  --namespace demo \
  --set ingress.enabled=true \
  --set ingress.host=myapp.local \
  --set ingress.tls.enabled=true \
  --set ingress.tls.secretName=myapp-tls
```

All fields of the `ingress` block are described in `values.schema.json` — Helm rejects values with a wrong structure before rendering anything.

### Useful Helm commands

```bash
# Check the templates before deploying
helm template myapp examples/helm/myapp

# Check that values are applied correctly
helm template myapp examples/helm/myapp \
  --set env.MESSAGE="test" | grep -A2 "env:"

# Deploy
helm upgrade --install myapp examples/helm/myapp \
  --namespace demo --create-namespace --wait

# Check status
helm status myapp -n demo

# Remove
helm uninstall myapp -n demo
```

---

## 6. k3s — deploying to the cluster

### The problem: the image is on the local machine, not in a registry

k3s uses `containerd` as its runtime and has no access to the Docker daemon. If you run `helm install` with an image that containerd doesn't have, k3s tries to pull it from a registry and may end up with `ImagePullBackOff`.

**The solution** — import the image directly into containerd:

```bash
docker save myapp:local | sudo k3s ctr images import -
```

- `docker save` — writes the image as a tar archive to stdout
- `k3s ctr images import -` — reads the tar from stdin and adds it to k3s's containerd

After this the image is available in k3s:

```bash
sudo k3s ctr images list | grep myapp
```

### deploy.sh — step-by-step explanation

```sh
#!/bin/sh
set -e   # stop at the first error
```

```sh
# Build the image from the Dockerfile in examples/docker/
docker build -t "$IMAGE" "$SCRIPT_DIR/../docker"
```

```sh
# Import into k3s to bypass the registry
docker save "$IMAGE" | sudo k3s ctr images import -
```

```sh
# Create the namespace if it doesn't exist
# --dry-run=client -o yaml | kubectl apply — the idempotent way
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
```

```sh
# helm upgrade --install — idempotent deploy:
# if the release doesn't exist — install, if it does — upgrade
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG" \
  --set image.pullPolicy=Never \
  --atomic \
  --timeout "$TIMEOUT" \
  --wait
```

`image.pullPolicy=Never` never pulls the image from a registry, and `--wait` waits until the pod is Ready.

### Verifying after the deploy

```bash
# Pod status
kubectl get pods -n demo

# Logs
kubectl logs -l app.kubernetes.io/name=myapp -n demo

# Local access via port-forward
kubectl port-forward service/myapp-myapp 8080:8080 -n demo

# In another terminal
curl http://localhost:8080/
curl http://localhost:8080/health
```

### Common problems

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | k3s couldn't find the image | Run `docker save \| k3s ctr images import` |
| `CrashLoopBackOff` | The app crashes on startup | `kubectl logs <pod> -n demo` |
| Pod `0/1 Running` (not Ready) | Readiness probe failed | `kubectl describe pod <pod> -n demo` → Events |
| `helm: release not found` with `--wait` | Chart not found | Check the path to `examples/helm/myapp` |

---

## 7. End-to-end steps

```bash
# Clone and enter the repo
cd examples

# --- Step 1: verify locally with Docker ---
docker build -t myapp:local docker/
docker run --rm -p 8080:8080 myapp:local &
curl http://localhost:8080/
kill %1

# --- Step 2: check the Helm templates ---
helm template myapp helm/myapp

# --- Step 3: deploy to k3s ---
chmod +x k3s/deploy.sh
./k3s/deploy.sh

# --- Step 4: verify in the cluster ---
kubectl get all -n demo
kubectl port-forward service/myapp-myapp 8080:8080 -n demo &
curl http://localhost:8080/
curl http://localhost:8080/health

# --- Step 5: change the configuration without a rebuild ---
helm upgrade myapp helm/myapp \
  --namespace demo \
  --set env.MESSAGE="Updated without a rebuild!" \
  --set replicaCount=2 \
  --wait

curl http://localhost:8080/   # new message
kubectl get pods -n demo      # 2 replicas
```
