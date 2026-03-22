# Docker — Practical Developer Guide

> Not just commands. Real-world daily usage scenarios.

---

## Table of Contents

1. [Glossary](#1-glossary)
2. [Images — Building and Managing](#2-images--building-and-managing)
3. [Dockerfile — From Bad to Right](#3-dockerfile--from-bad-to-right)
4. [Containers — Running and Managing](#4-containers--running-and-managing)
5. [Debugging Containers](#5-debugging-containers)
6. [Volumes and Bind Mounts](#6-volumes-and-bind-mounts)
7. [Networking](#7-networking)
8. [Docker Compose](#8-docker-compose)
9. [Registry — Publishing Images](#9-registry--publishing-images)
10. [System Cleanup](#10-system-cleanup)
11. [Docker in CI/CD](#11-docker-in-cicd)
12. [Useful Aliases and Scripts](#12-useful-aliases-and-scripts)

---

## 1. Glossary

| Term | What it is |
|---|---|
| **Image** | An immutable filesystem template + metadata. Made up of layers. Analogy: a disk ISO image. |
| **Container** | A running process based on an image. Has its own filesystem, network, and PID. Like a running VM, but much lighter. |
| **Layer** | Every `RUN`/`COPY`/`ADD` instruction in a Dockerfile creates a new layer. Layers are cached and reused across images. |
| **Dockerfile** | A text file with instructions for building an image. Each line is a potential layer. |
| **Registry** | An image storage server. Docker Hub is the public one. You can run a private one (Registry, Harbor, Nexus). |
| **Tag** | A version label on an image. `myapp:latest`, `myapp:v1.2.0`. `latest` is just a convention, not "the newest automatically". |
| **Volume** | A storage unit that lives outside the container. Managed by Docker, persists after the container stops. |
| **Bind mount** | Mounting a directory from the host machine into the container. Changes are immediately visible on both sides. |
| **tmpfs mount** | Mounting into RAM. Data disappears when the container stops. |
| **Docker Compose** | A tool for running multiple containers together via a single `compose.yaml`. |
| **Context** | The directory sent to the Docker daemon during a build. Everything in it is available to `COPY`/`ADD`. |
| **Multi-stage build** | A Dockerfile with multiple `FROM` statements. Build in one large image, copy only the artifact into the final one. |
| **Dangling image** | An image with no tag — left behind after a rebuild when the tag moved to a newer image. Shows as `<none>:<none>` in `docker images`. |
| **entrypoint** | The container's main command. Not replaced by `docker run myapp <cmd>`, only by `--entrypoint`. |
| **cmd** | Default arguments for the entrypoint. Replaced when you run `docker run myapp <cmd>`. |

### Image vs Container — analogy

```
Image               →    Container
──────────────────────────────────────────────
Class in OOP        →    Instance of a class
Disk ISO image      →    Running VM
Recipe              →    Cooked dish
```

### Diagram: from Dockerfile to containers

```
┌──────────────────┐  docker build  ┌────────────────────────┐
│   Dockerfile     │ ─────────────▶ │  Image  myapp:latest   │
│                  │                │  (read-only layers)    │
│  FROM python...  │                └────────────┬───────────┘
│  COPY app.py .   │                             │ docker run (×N)
│  CMD [...]       │          ┌──────────────────┼──────────────────┐
└──────────────────┘          ▼                  ▼                  ▼
                        ┌──────────┐       ┌──────────┐       ┌──────────┐
                        │Container │       │Container │       │Container │
                        │ myapp-1  │       │ myapp-2  │       │ myapp-3  │
                        │ fs / net │       │ fs / net │       │ fs / net │
                        └──────────┘       └──────────┘       └──────────┘
```

> One image — unlimited containers. Each container has its own isolated
> filesystem and network, but shares the image layers read-only (copy-on-write).

---

## 2. Images — Building and Managing

### Building

```bash
# Build image from Dockerfile in current directory
docker build -t myapp:latest .

# Build with a specific Dockerfile
docker build -t myapp:latest -f docker/Dockerfile.prod .

# Build with build args (variables available during build)
docker build -t myapp:latest \
  --build-arg NODE_ENV=production \
  --build-arg APP_VERSION=1.2.0 \
  .

# Build without cache (useful when you suspect stale cache)
docker build --no-cache -t myapp:latest .

# Build and immediately run — verify it works
docker build -t myapp:test . && docker run --rm myapp:test
```

### View images

```bash
# List images
docker images
docker image ls

# List with size of each layer
docker image history myapp:latest

# Detailed info (JSON)
docker image inspect myapp:latest

# Image size in bytes
docker image inspect myapp:latest \
  --format='{{.Size}}'
```

> **Note:** `numfmt` is handy on Linux but often missing on macOS.
> For a human-readable size, the simplest option is just `docker images`.

### Tags

```bash
# Add a tag (doesn't copy — just another pointer)
docker tag myapp:latest myapp:v1.2.0
docker tag myapp:latest registry.example.com/myapp:v1.2.0

# Remove a tag / image
docker rmi myapp:old-tag
docker rmi myapp:latest   # removes if no other tags or containers reference it
```

### Save / load image to file

```bash
# Save image to tar (for transfer without a registry)
docker save myapp:latest | gzip > myapp-v1.tar.gz

# Load from tar.gz
gunzip -c myapp-v1.tar.gz | docker load

# Import into k3s (without a registry)
docker save myapp:latest | sudo k3s ctr images import -
```

---

## 3. Dockerfile — From Bad to Right

### Bad Dockerfile (and why it's bad)

```dockerfile
# ❌ Bad — large image, slow build, security issues
FROM ubuntu:latest          # large base image (~77MB+ of dependencies)

RUN apt-get update && apt-get install -y nodejs npm  # versions not pinned

WORKDIR /app
COPY . .                    # copies EVERYTHING including node_modules, .git, .env!

RUN npm install             # dependencies after code → cache busted on any code change

CMD node server.js          # runs as root, no EXPOSE, no health check
```

### Correct Dockerfile (Node.js)

```dockerfile
# ✅ Good — lightweight, cached, secure
# Pinned version — reproducible builds
FROM node:20-alpine AS base

WORKDIR /app

# 1. Only package.json first — this layer is cached if dependencies don't change
COPY package.json package-lock.json ./
RUN npm ci --only=production    # ci instead of install — strict lockfile adherence

# 2. Then source code — this layer only busts when code changes
COPY src/ ./src/

# Run as non-root (security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

# HEALTHCHECK — Docker/k8s know whether the container is alive
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "src/server.js"]
```

### Multi-stage build (Go / any compiled language)

```dockerfile
# Stage 1: build — large image with the compiler
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download                    # dependency cache as a separate layer

COPY . .
RUN CGO_ENABLED=0 go build -o server ./cmd/server

# ─────────────────────────────────────────
# Stage 2: final image — binary only
FROM scratch                           # empty image, ~0MB base
# or: FROM alpine:3.19 — if you need a shell / certs / tools

COPY --from=builder /app/server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8080
ENTRYPOINT ["/server"]
```

```
Result:
  golang:1.22-alpine + code + deps  →  ~600MB (builder, never pushed)
  final image with binary           →  ~10MB  (what goes to the registry)
```

### Multi-stage for Node.js (frontend build)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build                      # produces /app/dist

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

### .dockerignore — must have

```
# .dockerignore
node_modules/
.git/
.gitignore
*.log
*.md
.env
.env.*
dist/
coverage/
.DS_Store
docker-compose*.yml
Dockerfile*
```

> **Without `.dockerignore`** the entire `node_modules` ends up in the build context → slow build,
> large image, and `.env` with secrets may end up baked into the image.

### Dockerfile instruction reference

| Instruction | What it does | Note |
|---|---|---|
| `FROM image AS name` | Base image / start of a stage | `AS name` for multi-stage |
| `WORKDIR /path` | Working directory (creates if missing) | Better than `RUN mkdir && cd` |
| `COPY src dst` | Copy files from context | Does not unpack archives |
| `ADD src dst` | Like COPY, but unpacks `.tar` and downloads URLs | Prefer COPY |
| `RUN cmd` | Execute command and save as a layer | Chain with `&&` |
| `ENV KEY=value` | Environment variable (in image and container) | |
| `ARG KEY=default` | Build-time variable only (`--build-arg`) | Not visible in the running container |
| `EXPOSE port` | Document a port (doesn't actually open it) | `-p` is still needed at runtime |
| `VOLUME ["/data"]` | Declare a volume | |
| `USER name` | Switch current user | Don't run as root |
| `ENTRYPOINT ["cmd"]` | Non-replaceable main command | Use exec form `[]` |
| `CMD ["arg"]` | Default arguments | Replaced by `docker run ... cmd` |
| `HEALTHCHECK` | Container liveness check | |
| `LABEL key=value` | Image metadata | |

---

## 4. Containers — Running and Managing

### Running

```bash
# Basic run
docker run myapp:latest

# Name + background + port + environment variables
docker run \
  --name myapp \
  -d \
  -p 8080:8080 \
  -e DB_HOST=postgres \
  -e DB_PASSWORD=secret \
  --restart unless-stopped \
  myapp:latest

# --rm: delete container after it stops (for one-off tasks)
docker run --rm myapp:latest ./migrate.sh

# Interactive mode
docker run -it --rm alpine sh
docker run -it --rm ubuntu bash
```

> `-d` — detached (background) mode, `-p 8080:8080` — `HOST_PORT:CONTAINER_PORT`,
> `--restart unless-stopped` — auto-restart, except on manual stop.

### Managing containers

```bash
# List running containers
docker ps

# All (including stopped)
docker ps -a

# Stop / start / restart
docker stop myapp
docker start myapp
docker restart myapp

# Force stop (SIGKILL immediately)
docker kill myapp

# Remove container (must be stopped first)
docker rm myapp
docker rm -f myapp    # stop and remove in one step
```

### Useful `docker run` flags

| Flag | What it does | Example |
|---|---|---|
| `-d` | Detached (background) mode | |
| `-it` | Interactive terminal | `-it alpine sh` |
| `--rm` | Remove after stopping | |
| `--name` | Set a name | `--name myapp` |
| `-p H:C` | Expose port host:container | `-p 8080:80` |
| `-P` | Expose all `EXPOSE` ports to random host ports | |
| `-e KEY=val` | Environment variable | |
| `--env-file` | Variables from file | `--env-file .env` |
| `-v` | Mount volume or bind mount | `-v data:/data` |
| `--network` | Connect to a network | `--network mynet` |
| `--restart` | Restart policy | `--restart unless-stopped` |
| `--memory` | RAM limit | `--memory 512m` |
| `--cpus` | CPU limit | `--cpus 0.5` |
| `--user` | Run as user | `--user 1000:1000` |
| `--read-only` | Read-only filesystem | |
| `--entrypoint` | Override entrypoint | `--entrypoint sh` |

---

## 5. Debugging Containers

### Logs

```bash
# View logs
docker logs myapp

# Follow in real time
docker logs -f myapp

# Last N lines
docker logs --tail 100 myapp

# With timestamps
docker logs -t myapp

# Combo: last 50 lines + follow
docker logs --tail 50 -f myapp
```

### Shell into a running container

```bash
# Shell inside the container
docker exec -it myapp sh    # alpine/distroless
docker exec -it myapp bash  # ubuntu/debian

# Run a single command
docker exec myapp cat /etc/hosts
docker exec myapp env | grep DB_

# As root (if container runs as a different user)
docker exec -it --user root myapp sh
```

### Container crashes before you can get in

```bash
# Option 1: override entrypoint and put the container to sleep
docker run --rm -it --entrypoint sh myapp:latest

# Option 2: use sleep as the process
docker run --rm -it --entrypoint sleep myapp:latest infinity
# then in another terminal:
docker exec -it <container_id> sh

# Option 3: check exit code and last state
docker inspect myapp --format='{{.State.ExitCode}}: {{.State.Error}}'
```

### Inspect image contents (without running)

```bash
# Copy a file out of the image (not from a running container)
docker create --name tmp myapp:latest
docker cp tmp:/app/config.yaml ./extracted-config.yaml
docker rm tmp

# Or via a temporary container
docker run --rm myapp:latest cat /app/config.yaml
docker run --rm myapp:latest ls -la /app/
```

### Inspect — detailed info

```bash
# Full container info (JSON)
docker inspect myapp

# Extract a specific field (jsonpath style)
docker inspect myapp --format='{{.State.Status}}'
docker inspect myapp --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}'
docker inspect myapp --format='{{range .Mounts}}{{.Source}} → {{.Destination}}{{"\n"}}{{end}}'

# View environment variables (careful: will show secrets!)
docker inspect myapp --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}'
```

### Resource monitoring

```bash
# CPU / RAM / network in real time
docker stats

# Specific container
docker stats myapp

# Single snapshot (no live update)
docker stats --no-stream

# Custom format
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

---

## 6. Volumes and Bind Mounts

### Comparison of mount types

```
Bind Mount                    Volume                        tmpfs
──────────────────────        ──────────────────────        ──────────────────
/home/user/data  ←──────→  /var/lib/docker/volumes/     RAM (not disk)
                              mydata/_data
You control the path          Docker controls the path      Gone on stop
Great for development         Great for production          Secrets, cache
```

### Volumes (production approach)

```bash
# Create a volume
docker volume create mydata

# List volumes
docker volume ls

# Details (physical location on disk)
docker volume inspect mydata

# Use volume when running a container
docker run -d \
  --name postgres \
  -v mydata:/var/lib/postgresql/data \
  postgres:16

# Remove volume (careful — data will be lost!)
docker volume rm mydata

# Remove all unused volumes
docker volume prune
```

> `mydata:/var/lib/postgresql/data` means `volume_name:container_path`.

### Bind mount (development — code changes without rebuilding)

```bash
# Mount current directory into the container
docker run -d \
  --name myapp-dev \
  -p 3000:3000 \
  -v "$(pwd)":/app \
  -v /app/node_modules \
  myapp:dev

# Changes in ./src are now immediately visible inside the container
```

> **Common bind mount issue:** `node_modules` or `vendor` from the host overwrites what's in the container.
> Fix: add an anonymous volume `-v /app/node_modules` — it takes priority over the bind mount.
> `$(pwd):/app` means `host_path:container_path`.

### Backup a volume

```bash
# Save volume contents to a tar archive
docker run --rm \
  -v mydata:/source:ro \
  -v $(pwd):/backup \
  alpine tar czf /backup/mydata-backup.tar.gz -C /source .

# Restore from archive
docker run --rm \
  -v mydata:/target \
  -v $(pwd):/backup \
  alpine tar xzf /backup/mydata-backup.tar.gz -C /target
```

---

## 7. Networking

### Network types

| Type | What it is | When to use |
|---|---|---|
| `bridge` | Virtual network on the host. Containers are isolated from the host. | Default. |
| `host` | Container uses the host's network stack directly. | When maximum speed is needed. |
| `none` | No network. | Isolated tasks. |
| Custom bridge | Your own bridge network. Containers find each other **by name**. | Always for multi-container setups. |
| `overlay` | Network across multiple Docker hosts (Docker Swarm). | Swarm / distributed systems. |

### Custom network (required for multi-container)

```bash
# Create a network
docker network create mynet

# Connect containers to the same network
docker run -d --name postgres --network mynet postgres:16
docker run -d --name myapp    --network mynet myapp:latest

# Now myapp can reach postgres just by its name:
# DB_HOST=postgres (no IP needed!)

# Connect an existing container to a network
docker network connect mynet myapp

# Disconnect
docker network disconnect mynet myapp

# List networks
docker network ls

# Details: who is connected
docker network inspect mynet
```

### Ports

```bash
# -p HOST:CONTAINER — specific port
docker run -p 8080:80 nginx          # localhost:8080 → container:80

# -p IP:HOST:CONTAINER — only from a specific interface
docker run -p 127.0.0.1:8080:80 nginx  # localhost only, not from outside

# -P — all EXPOSE ports mapped to random host ports
docker run -P nginx

# View mapped ports
docker port myapp
```

---

## 8. Docker Compose

### Glossary

| Term | What it is |
|---|---|
| **Service** | One type of container in the compose file. Can have multiple replicas. |
| **Project** | The group of services from one compose file. Has an isolated network and volumes. |
| `depends_on` | Startup order. Does **not** wait for the service to be ready, only for it to start. |
| `healthcheck` | Readiness check. `depends_on: condition: service_healthy` — waits for readiness. |

### Typical compose.yaml for development

```yaml
# compose.yaml (or docker-compose.yml — both are supported)
services:

  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - DB_HOST=postgres          # service name = hostname on the network
      - DB_PASSWORD=${DB_PASSWORD} # from environment variable or .env file
    volumes:
      - .:/app                    # bind mount for live reload
      - /app/node_modules         # don't overwrite node_modules with host version
    depends_on:
      postgres:
        condition: service_healthy  # wait until postgres is ready

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql  # auto-initialization
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d myapp"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    volumes:
      - redisdata:/data

volumes:
  pgdata:
  redisdata:
```

### Core Compose commands

```bash
# Start all services (build if needed)
docker compose up

# Background mode
docker compose up -d

# Rebuild images before starting
docker compose up --build

# Start only one service (+ its dependencies)
docker compose up app

# Stop (keep volumes)
docker compose stop

# Stop and remove containers + networks (keep volumes)
docker compose down

# Stop and remove EVERYTHING including volumes (careful!)
docker compose down -v

# Service status
docker compose ps

# Logs from all services
docker compose logs -f

# Logs from one service
docker compose logs -f app

# Run a command in a service
docker compose exec app sh
docker compose exec postgres psql -U user -d myapp

# Restart one service
docker compose restart app

# Stop and remove one service
docker compose rm -sf app
```

### Override files (dev vs prod)

```
compose.yaml           # base (shared across environments)
compose.override.yaml  # dev (applied automatically on top of base)
compose.prod.yaml      # prod (specified explicitly)
```

```bash
# Dev (automatic: base + override)
docker compose up

# Prod (specify files explicitly)
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

```yaml
# compose.prod.yaml — only differences from base
services:
  app:
    build:
      target: production    # multi-stage: final stage
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    # no bind mount volumes
```

---

## 9. Registry — Publishing Images

### Docker Hub

```bash
# Login
docker login

# Push image
docker tag myapp:latest username/myapp:latest
docker push username/myapp:latest

# Push with version tag
docker tag myapp:latest username/myapp:v1.2.0
docker push username/myapp:v1.2.0

# Pull image
docker pull username/myapp:v1.2.0
```

### Private Registry

```bash
# Run a local registry
docker run -d \
  --name registry \
  -p 5000:5000 \
  -v registry-data:/var/lib/registry \
  registry:2

# Push to local registry
docker tag myapp:latest localhost:5000/myapp:latest
docker push localhost:5000/myapp:latest

# Push to private registry with authentication
docker login registry.example.com
docker tag myapp:latest registry.example.com/myapp:v1.2.0
docker push registry.example.com/myapp:v1.2.0
```

### Multi-architecture images (arm64 + amd64)

```bash
# Requires buildx (built into Docker Desktop, install separately on Linux)
docker buildx create --use --name multiarch

# Build and push for both architectures at once
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t registry.example.com/myapp:v1.2.0 \
  --push \
  .
```

---

## 10. System Cleanup

```bash
# View disk usage
docker system df
docker system df -v   # detailed

# Remove everything unused (stopped containers, untagged images, networks, build cache)
docker system prune

# Same + volumes (careful — data will be lost!)
docker system prune -a --volumes

# Remove only stopped containers
docker container prune

# Remove untagged (dangling) images
docker image prune

# Remove ALL images not used by running containers
docker image prune -a

# Remove build cache
docker builder prune

# Remove unused volumes
docker volume prune
```

> **Tip:** `docker system prune` won't touch running containers or their volumes,
> but removes stopped containers, dangling images, unused networks, and build cache.
> `-a --volumes` is more aggressive and may remove data you wanted to keep.

---

## 11. Docker in CI/CD

### Layer caching in GitHub Actions

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: registry.example.com/myapp:${{ github.sha }}
    cache-from: type=gha          # GitHub Actions cache
    cache-to: type=gha,mode=max
```

### The right tag for CI (not latest!)

```bash
# Tag = commit SHA — unique, reproducible, traceable
IMAGE_TAG=${GITHUB_SHA::8}   # first 8 characters of SHA

docker build -t myapp:${IMAGE_TAG} .
docker push myapp:${IMAGE_TAG}

# Then deploy:
helm upgrade --install myapp ./helm/myapp \
  --set image.tag=${IMAGE_TAG}
```

### Vulnerability scanning

```bash
# Built-in Docker Scout (Docker Desktop)
docker scout cves myapp:latest

# Trivy (open source, popular in CI)
# brew install trivy  /  apt install trivy
trivy image myapp:latest

# In CI — fail the pipeline on HIGH/CRITICAL vulnerabilities
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:latest
```

---

## 12. Useful Aliases and Scripts

### ~/.bashrc / ~/.zshrc

```bash
# Docker shortcuts
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
alias dimg='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'

# Shell into container
dsh() { docker exec -it "$1" sh; }
dbash() { docker exec -it "$1" bash; }

# Follow logs
dlog() { docker logs -f --tail 100 "$1"; }

# Stop and remove container
drm() { docker stop "$1" && docker rm "$1"; }

# Remove all stopped containers
alias dclean='docker container prune -f'

# Stats in one line
alias dstat='docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"'

# Get container IP
dip() { docker inspect "$1" --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'; }
```

### Script: build, tag, and push

```bash
#!/bin/bash
# docker-release.sh

set -e   # stop on any error

REGISTRY=${REGISTRY:-"registry.example.com"}
IMAGE=${1:?"Specify image name: ./docker-release.sh myapp"}
TAG=${2:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}

echo "Building $REGISTRY/$IMAGE:$TAG..."
docker build -t "$REGISTRY/$IMAGE:$TAG" .
docker tag "$REGISTRY/$IMAGE:$TAG" "$REGISTRY/$IMAGE:latest"

echo "Pushing..."
docker push "$REGISTRY/$IMAGE:$TAG"
docker push "$REGISTRY/$IMAGE:latest"

echo "Done: $REGISTRY/$IMAGE:$TAG"
```

### Script: clean up old images (keep last N)

```bash
#!/bin/bash
# docker-cleanup-images.sh — keep the last 5 images of myapp

IMAGE=${1:?"Specify image name"}
KEEP=${2:-5}

echo "Removing old tags of $IMAGE (keeping $KEEP)..."
docker images "$IMAGE" --format "{{.Tag}}" \
  | grep -v '^latest$' \
  | tail -n "+$((KEEP + 1))" \
  | xargs -I{} docker rmi "$IMAGE:{}" 2>/dev/null || true

echo "Remaining:"
docker images "$IMAGE"
```

> **Limitation:** the script relies on `docker images` output order,
> so review the list manually before doing a bulk cleanup of old tags.

---

## Cheatsheet: images vs containers vs compose

```
docker build      → create an image from Dockerfile
docker pull       → download an image from a registry
docker push       → push an image to a registry
docker images     → list images
docker rmi        → remove an image

docker run        → create and start a container from an image
docker start/stop → start/stop an existing container
docker ps         → list containers
docker rm         → remove a container
docker exec       → run a command in a running container
docker logs       → view logs
docker inspect    → detailed info (JSON)
docker cp         → copy files container ↔ host

docker compose up    → start the project (all services)
docker compose down  → stop and remove
docker compose ps    → service status
docker compose exec  → run a command in a service
docker compose logs  → service logs
```

---

> **Tip:** For production deployments, don't run containers directly via `docker run`.
> Use orchestration: **k3s/Kubernetes** for serious projects,
> **Docker Compose** for simple single-host deployments.
> Docker is for packaging and building, Kubernetes is for running and managing.
