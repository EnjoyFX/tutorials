# Examples — Docker → Helm → k3s

Minimal end-to-end demo: Python HTTP server built into a Docker image,
packaged as a Helm chart, and deployed on k3s.

## Structure

```
examples/
├── docker/          # Python app + Dockerfile
│   ├── app.py
│   ├── Dockerfile
│   └── .dockerignore
├── helm/
│   └── myapp/       # Helm chart (Deployment + Service)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           └── service.yaml
└── k3s/
    └── deploy.sh    # Full pipeline: build → import → helm deploy
```

## Quick start

### 1. Docker only

```sh
cd examples/docker
docker build -t myapp:latest .
docker run --rm -p 8080:8080 myapp:latest

curl http://localhost:8080/
curl http://localhost:8080/health
```

### 2. Helm (local cluster / k3d / kind)

First, build the image and load it into the cluster:

```sh
docker build -t myapp:latest examples/docker/
```

**k3s** — uses containerd directly, Docker daemon is separate; image must be piped in via stdin:

```sh
docker save myapp:latest | sudo k3s ctr images import -
```

**k3d** — k3s running inside Docker containers; has a built-in import command that copies the image into the cluster's Docker network:

```sh
k3d image import myapp:latest -c <cluster-name>
```

**kind** — Kubernetes nodes run as Docker containers; image is loaded directly from the local Docker daemon:

```sh
kind load docker-image myapp:latest --name <cluster-name>
```

Then deploy:

```sh
helm upgrade --install myapp examples/helm/myapp \
  --set image.pullPolicy=Never \
  --create-namespace --namespace demo --wait

kubectl port-forward service/myapp-myapp 8080:8080 -n demo
```

### 3. k3s — full pipeline

```sh
chmod +x examples/k3s/deploy.sh
./examples/k3s/deploy.sh
```

The script:
1. Builds the Docker image
2. Imports it into k3s (no registry needed)
3. Creates the `demo` namespace
4. Deploys via Helm with `--wait`

## App endpoints

| Path      | Response                              |
|-----------|---------------------------------------|
| `GET /`   | `{"message": "...", "version": "..."}` |
| `GET /health` | `{"status": "ok"}`              |

## Override values

```sh
helm upgrade --install myapp examples/helm/myapp \
  --set env.MESSAGE="Hello, k3s!" \
  --set replicaCount=2
```
