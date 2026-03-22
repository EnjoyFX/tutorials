# Tutorials

Practical developer guides for the modern container stack: Docker, Helm, and k3s.

Each guide is written as a real-world reference — not a list of commands, but a day-to-day companion that explains *what* things are, *why* they work the way they do, and *how* to use them effectively in real scenarios.

---

## Guides

| Guide | English | Ukrainian |
|---|---|---|
| **Docker** | [en/docker-guide.md](en/docker-guide.md) | [ua/docker-guide.md](ua/docker-guide.md) |
| **Helm** | [en/helm-guide.md](en/helm-guide.md) | [ua/helm-guide.md](ua/helm-guide.md) |
| **k3s** | [en/k3s-dev-guide.md](en/k3s-dev-guide.md) | [ua/k3s-dev-guide.md](ua/k3s-dev-guide.md) |
| **Demo App** (Docker → Helm → k3s) | [examples/README.md](examples/README.md) | [ua/examples-guide.md](ua/examples-guide.md) |

---

## What's Inside

### Docker

Covers the full day-to-day workflow: building images, writing good Dockerfiles (with a "bad vs right" comparison), multi-stage builds, container management, debugging techniques, volumes, networking, Docker Compose for local development, publishing to registries, and CI/CD integration.

### Helm

The Kubernetes package manager from the ground up: core concepts, working with repositories, installing and rolling back releases, values and environment overrides, writing your own chart with templates and helpers, debugging rendered manifests, and Helmfile for multi-release management.

### k3s

Lightweight Kubernetes in practice: installation, daily cluster diagnostics, deploying and rolling back applications, namespace and context management with kubectx/kubens, troubleshooting CrashLoopBackOff and ImagePullBackOff, Traefik Ingress, persistent storage with PVC, secrets management, and multi-node cluster operations.

---

## Structure

```
.
├── en/                      # English
│   ├── docker-guide.md
│   ├── helm-guide.md
│   └── k3s-dev-guide.md
├── ua/                      # Ukrainian
│   ├── docker-guide.md
│   ├── helm-guide.md
│   ├── k3s-dev-guide.md
│   └── examples-guide.md   # Demo app walkthrough
├── examples/                # Runnable demo: Docker → Helm → k3s
│   ├── docker/              # Python app + Dockerfile
│   ├── helm/myapp/          # Helm chart
│   └── k3s/                 # deploy.sh
└── scripts/
    └── lint.sh              # Local lint (PyMarkdownLnt + codespell + helm lint + ...)
```

---

## Contributing

### Install the pre-push hook

The hook runs `scripts/lint.sh` automatically before every `git push`,
catching lint and spelling issues locally before they reach CI.

```sh
git clone https://github.com/EnjoyFX/tutorials.git
cd tutorials
ln -sf ../../scripts/lint.sh .git/hooks/pre-push
```

### Run lint manually

```sh
python3 -m pip install -r requirements-dev.txt
sh scripts/lint.sh
```

Required tools: `python3`, `helm`.
Python lint tools: `pip install -r requirements-dev.txt`
Optional: `shellcheck` — `brew install shellcheck`.
