# Tutorials

Practical developer guides for Linux and the modern container stack: Docker, Helm, and k3s.

Each guide is written as a real-world reference — not a list of commands, but a day-to-day companion that explains *what* things are, *why* they work the way they do, and *how* to use them effectively in real scenarios.

---

## Guides

| Guide | English | Ukrainian |
|---|---|---|
| **Docker** | [en/docker-guide.md](en/docker-guide.md) | [ua/docker-guide.md](ua/docker-guide.md) |
| **Linux** | [en/linux-guide.md](en/linux-guide.md) | [ua/linux-guide.md](ua/linux-guide.md) |
| **Helm** | [en/helm-guide.md](en/helm-guide.md) | [ua/helm-guide.md](ua/helm-guide.md) |
| **k3s** | [en/k3s-dev-guide.md](en/k3s-dev-guide.md) | [ua/k3s-dev-guide.md](ua/k3s-dev-guide.md) |
| **Demo App** (Docker → Helm → k3s) | [en/examples-guide.md](en/examples-guide.md) | [ua/examples-guide.md](ua/examples-guide.md) |
| **Compose → Helm migration** | [en/compose-to-helm.md](en/compose-to-helm.md) | [ua/compose-to-helm.md](ua/compose-to-helm.md) |

---

## What's Inside

### Docker

Covers the full day-to-day workflow: building images, writing good Dockerfiles (with a "bad vs right" comparison), multi-stage builds, container management, debugging techniques, volumes, networking, Docker Compose for local development, publishing to registries, and CI/CD integration.

### Linux

Daily Linux operations for developers and DevOps work: filesystem navigation, permissions and ownership, processes and ports, service management with systemd, package installation, logs and diagnostics, disk cleanup, networking checks, and SSH/curl/tar workflows.

### Helm

The Kubernetes package manager from the ground up: core concepts, working with repositories, installing and rolling back releases, values and environment overrides, writing your own chart with templates and helpers, debugging rendered manifests, and Helmfile for multi-release management.

### k3s

Lightweight Kubernetes in practice: installation, daily cluster diagnostics, deploying and rolling back applications, namespace and context management with kubectx/kubens, troubleshooting CrashLoopBackOff and ImagePullBackOff, Traefik Ingress, persistent storage with PVC, secrets management, and multi-node cluster operations.

### Demo App

A minimal end-to-end example — Python HTTP server built into a Docker image, packaged as a Helm chart, and deployed on k3s. Includes liveness/readiness probes, a non-root Dockerfile, a Compose file for local runs, an optional TLS-ready Ingress in the chart (Traefik ships with k3s), and a one-command deploy script. Runnable code lives in [examples/](examples/README.md).

### Compose → Helm Migration

Step-by-step guide for taking a `compose.yaml` and turning it into a Helm chart: concept mapping table, handling `build:`, `depends_on:`, secrets, named volumes, and what `kompose` does and doesn't do for you.

---

## Structure

```text
.
├── en/                      # English
│   ├── docker-guide.md
│   ├── linux-guide.md
│   ├── helm-guide.md
│   ├── k3s-dev-guide.md
│   ├── compose-to-helm.md
│   └── examples-guide.md
├── ua/                      # Ukrainian
│   ├── docker-guide.md
│   ├── linux-guide.md
│   ├── helm-guide.md
│   ├── k3s-dev-guide.md
│   ├── compose-to-helm.md
│   └── examples-guide.md
├── examples/                # Runnable demo: Docker → Helm → k3s
│   ├── docker/              # Python app + Dockerfile + compose.yaml
│   ├── helm/myapp/          # Helm chart
│   └── k3s/                 # deploy.sh
├── tests/
│   └── test_app.py          # pytest tests for the demo app
├── scripts/
│   └── lint.sh              # lint runner (markdownlint + codespell + helm + optional smoke checks)
├── pyproject.toml           # Python dev tooling dependencies
├── uv.lock                  # Locked Python dev tooling versions
└── Makefile                 # make install / lint / test / check / hooks
```

---

## Contributing

### Bootstrap

```sh
uv sync
```

### Install Git Hooks

Install `pre-commit` hooks to run lint and demo tests before each commit.

```sh
pre-commit install
```

### Run lint manually

```sh
make lint
```

### Run tests manually

```sh
make test
```

### Run all local checks

```sh
make check
```

Required tools: `uv`, `python3`, `helm`.
Optional local checks: `shellcheck`, `hadolint`, `lychee`, `docker`.
