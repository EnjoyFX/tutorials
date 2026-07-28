# Helm — Practical Developer Guide

> Not just commands. Real-world daily usage scenarios.

> **See also:** [Docker](docker-guide.md) · [Linux](linux-guide.md) · [k3s](k3s-dev-guide.md) · [Compose → Helm](compose-to-helm.md) · [Demo walkthrough](examples-guide.md) · [Runnable demo chart](../examples/helm/myapp)

---

## Table of Contents

1. [What is Helm and Why Use It](#1-what-is-helm-and-why-use-it)
2. [Installation and First Run](#2-installation-and-first-run)
3. [Glossary](#3-glossary)
4. [Working with Repositories](#4-working-with-repositories)
5. [Installing and Upgrading Releases](#5-installing-and-upgrading-releases)
6. [Values — Configuring Charts](#6-values--configuring-charts) ✦ [anti-patterns](#values--bad-vs-right)
7. [Creating Your Own Chart](#7-creating-your-own-chart)
8. [Templates — How It Works](#8-templates--how-it-works) ✦ [anti-patterns](#templates--bad-vs-right)
9. [Debugging](#9-debugging)
10. [Helm in CI/CD](#10-helm-in-cicd)
11. [Useful Aliases and Scripts](#11-useful-aliases-and-scripts)

---

## 1. What is Helm and Why Use It

```
Without Helm:                    With Helm:
  deployment.yaml                  myapp/
  service.yaml          →            Chart.yaml
  ingress.yaml                       values.yaml
  configmap.yaml                     values-prod.yaml
  secret.yaml                        templates/
  hpa.yaml                             deployment.yaml
  pvc.yaml                             service.yaml
  ...                                  ...

kubectl apply -f ./              helm install myapp ./myapp -f values-prod.yaml
```

**Helm solves three problems:**

1. **Packaging** — all application YAML files in one package (chart).
2. **Configuration** — same templates, different values for dev/staging/prod.
3. **Versioning** — every deploy is a numbered release, rollback is built in.

### Diagram: chart → render → release

```mermaid
flowchart LR
    A["Chart\n(templates/)"] --> C
    B["values.yaml\n(or -f override)"] --> C
    C["helm template\n(render)"] --> D["Rendered YAML\nmanifests"]
    D --> E["kubectl apply\n(via Helm)"]
    E --> F[("Kubernetes\nAPI")]
    F --> G["Release\n(stored as Secret\nin the cluster)"]
```

> `helm rollback` re-applies the rendered YAML from a previous revision,
> stored as a Secret named `sh.helm.release.v1.<name>.v<N>`.

---

## 2. Installation and First Run

```bash
# macOS
brew install helm

# Linux (script)
# Caution: review the script or verify its checksum first — don't blindly pipe remote code to bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify version
helm version
```

### Enable shell completion (zsh / bash)

```bash
# zsh
echo 'source <(helm completion zsh)' >> ~/.zshrc

# bash
echo 'source <(helm completion bash)' >> ~/.bashrc
```

---

## 3. Glossary

| Term | What it is |
|---|---|
| **Chart** | A Helm package — a directory with YAML templates + `Chart.yaml` + `values.yaml`. Like an npm package. |
| **Release** | A specific installed instance of a chart in the cluster. One chart → many releases (myapp-dev, myapp-prod). |
| **Revision** | The update number of a release. Every `helm upgrade` increments the revision by 1. Enables rollback. |
| **Repository** | A chart storage server. Like an npm registry or apt repo. Contains an index and chart tar archives. |
| **Values** | A set of variables that parameterize a chart. Defined in `values.yaml` or via `--set`. |
| **Template** | A YAML file with `{{ .Values.xxx }}` placeholders. Helm substitutes values and generates the final YAML. |
| **Subchart** | A dependency chart nested inside another chart (in the `charts/` directory). |
| **Hooks** | Special Jobs or Pods that run before/after install/upgrade/delete. |
| **OCI registry** | Storing charts in a Docker registry (instead of a classic Helm repo). Helm 3.8+. |
| **`helm upgrade --install`** | Idempotent command: installs if absent, upgrades if present. The CI/CD standard. |
| **Release namespace** | The namespace where the release lives. Passed via `-n`. |

---

## 4. Working with Repositories

```bash
# Add a repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add stable  https://charts.helm.sh/stable

# Update index (like apt-get update)
helm repo update

# List added repositories
helm repo list

# Remove a repository
helm repo remove bitnami
```

### Searching for charts

```bash
# Search in added repositories
helm search repo postgres
helm search repo redis --versions   # show all versions

# Search on Artifact Hub (public catalog of all charts)
helm search hub wordpress
```

### Inspect a chart before installing

```bash
# View values (all settings with comments)
helm show values bitnami/postgresql

# View chart README
helm show readme bitnami/postgresql

# View Chart.yaml (metadata, version, dependencies)
helm show chart bitnami/postgresql

# Download chart locally to explore
helm pull bitnami/postgresql --untar
```

### OCI registries — charts in a container registry

Since Helm 3.8+, charts can live in any OCI-compatible container registry
(Docker Hub, GHCR, Harbor, ECR...). This is the modern default for private chart
distribution: no separate chart server to run — auth and storage reuse the
registry you already have for images.

```bash
# Log in (same credentials as docker login)
helm registry login registry.example.com

# Package and push a chart
helm package ./mychart                # produces mychart-0.1.0.tgz
helm push mychart-0.1.0.tgz oci://registry.example.com/charts

# Install straight from the registry — no helm repo add needed
helm install myapp oci://registry.example.com/charts/mychart --version 0.1.0
```

---

## 5. Installing and Upgrading Releases

### Basic commands

```bash
# Install a chart
# helm install <release-name> <chart> [flags]
kubectl create namespace database
helm install my-postgres bitnami/postgresql -n database

# Install or upgrade (idempotent) — the CI/CD standard
helm upgrade --install my-postgres bitnami/postgresql -n database --create-namespace

# List all releases
helm list -A          # all namespaces
helm list -n database # specific namespace

# Release status
helm status my-postgres -n database
```

### Upgrade a release

```bash
# Upgrade with new values or a new chart version
helm upgrade my-postgres bitnami/postgresql \
  -n database \
  -f values.yaml \
  --version 13.2.0      # specific chart version (omitting = latest)
```

### Rollback

```bash
# View release history
helm history my-postgres -n database
# REVISION  STATUS      CHART                  DESCRIPTION
# 1         superseded  postgresql-13.1.0      Install complete
# 2         deployed    postgresql-13.2.0      Upgrade complete

# Roll back to a specific revision
# Check the number in helm history first
helm rollback my-postgres 1 -n database

# Roll back to a different revision
helm rollback my-postgres 3 -n database
```

### Delete a release

```bash
# Delete (all cluster resources are removed)
helm uninstall my-postgres -n database

# Delete but keep history
helm uninstall my-postgres -n database --keep-history
```

### Useful flags for install / upgrade

| Flag | What it does |
|---|---|
| `--install` | Install if it doesn't exist (used with `upgrade`) |
| `--atomic` | If upgrade fails — automatically roll back |
| `--wait` | Wait until all pods are Ready |
| `--timeout 5m` | Timeout for `--wait` |
| `--dry-run` | Don't apply, just show what would happen |
| `--debug` | Verbose output + rendered templates |
| `--create-namespace` | Create namespace if it doesn't exist |
| `--version 13.2.0` | Specific chart version |

---

## 6. Values — Configuring Charts

### Three ways to pass values (lowest to highest priority)

```
1. values.yaml in the chart       (lowest priority — defaults)
         ↓ overridden by
2. -f my-values.yaml              (your values file)
         ↓ overridden by
3. --set key=value                (highest priority — inline)
```

```bash
# -f: pass a values file
helm upgrade --install myapp ./myapp -f values-prod.yaml

# Multiple files — merged left to right
helm upgrade --install myapp ./myapp \
  -f values-base.yaml \
  -f values-prod.yaml

# --set: single value
helm upgrade --install myapp ./myapp \
  --set image.tag=v2.0.0

# --set: nested keys
helm upgrade --install myapp ./myapp \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=myapp.example.com

# --set-string: force string type (so "true" doesn't become a boolean)
helm upgrade --install myapp ./myapp --set-string someFlag=true

# --set-file: value from file (e.g. a certificate)
helm upgrade --install myapp ./myapp --set-file tls.cert=./cert.pem
```

### View the final values of a release

```bash
# Values the release was installed with (your overrides only)
helm get values my-postgres -n database

# All values including defaults
helm get values my-postgres -n database --all
```

### Typical values.yaml for your own chart

```yaml
# values.yaml
replicaCount: 2

image:
  repository: my-registry/myapp
  tag: "latest"          # quoted — so it doesn't get parsed as a number
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: false
  host: myapp.local

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

env:
  DB_HOST: "postgres-service"
  DB_PORT: "5432"

secrets:
  DB_PASSWORD: ""        # pass via --set or sealed secrets
```

### Values — bad vs right

```yaml
# ❌ Bad — flat structure, secret in file, env hardcoded
image: myapp:v1.0.0           # repo and tag merged — impossible to override separately
replicas: 1                   # no structure, everything at the top level
db_password: "mysecret"       # ❌ secret in values.yaml — will end up in git
prod_db_host: "prod.db.local" # env hardcoded — can't override without editing the file
resources_cpu: "500m"         # flat key instead of nested resources object — hard to read
```

```yaml
# ✅ Good — nested structure, secret by reference, env overrides via -f
image:
  repository: my-registry/myapp  # repo and tag separate — each can be overridden
  tag: "1.0.0"
  pullPolicy: IfNotPresent

replicaCount: 1

db:
  host: "postgres-service"
  port: 5432
  passwordSecretRef: "app-db-secret"  # reference to a k8s Secret, not the value itself

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# Secret is passed outside the repo:
# helm upgrade --install myapp ./myapp --set db.password=$DB_PASS
# or via sealed-secrets / external-secrets-operator
```

> **Rule:** if a value differs between dev and prod — it belongs in values, not hardcoded
> in the template. If it's a secret — it should not be in values.yaml at all.

---

## 7. Creating Your Own Chart

### Scaffold a new chart

```bash
helm create myapp
# Creates the structure:
# myapp/
#   Chart.yaml            — chart metadata
#   values.yaml           — default values
#   templates/            — YAML templates
#     deployment.yaml
#     service.yaml
#     ingress.yaml
#     hpa.yaml
#     serviceaccount.yaml
#     _helpers.tpl        — reusable template helpers
#     NOTES.txt           — text displayed after helm install
#   charts/               — dependent subcharts
#   .helmignore           — like .gitignore
```

> A real minimal chart lives in this repo at [`../examples/helm/myapp`](../examples/helm/myapp):
> deployment + service + optional ingress, with security contexts and probes —
> a working reference for everything described below.

### Chart.yaml — metadata

```yaml
apiVersion: v2         # Helm API version (v2 = Helm 3)
name: myapp
description: My application chart
type: application      # or "library" — chart with no resources, only helpers
version: 0.1.0         # chart version (SemVer)
appVersion: "1.0.0"    # application version (informational, doesn't affect Helm)

dependencies:          # dependencies (subcharts)
  - name: postgresql
    version: "13.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled   # only enable if postgresql.enabled=true
```

```bash
# After changing dependencies — download subcharts
helm dependency update ./myapp
# Downloads to myapp/charts/postgresql-13.x.x.tgz
```

### Subcharts: overriding values and locking versions

Values for a subchart are set under a key named after the dependency —
everything under `postgresql:` in the parent's values is passed down to the
postgresql chart:

```yaml
# values.yaml of the parent chart
postgresql:
  enabled: true                 # matched by condition: in Chart.yaml
  auth:
    username: myapp
    password: ""                # override at deploy time, not in git
    database: myapp_db
```

```bash
# Disable the subchart entirely (e.g. prod uses a managed database):
helm upgrade --install myapp ./myapp --set postgresql.enabled=false
# Works because Chart.yaml declares condition: postgresql.enabled
```

`helm dependency update` also writes `Chart.lock` — the exact resolved versions
(`13.x.x` → `13.2.24`). Commit it: teammates and CI then run
`helm dependency build`, which installs exactly the locked versions instead of
re-resolving the ranges. Same idea as package-lock.json.

```bash
helm dependency update ./myapp   # re-resolve version ranges, rewrite Chart.lock
helm dependency build  ./myapp   # install exactly what Chart.lock says (use in CI)
```

### values.schema.json — validating values

Put a JSON Schema next to values.yaml and Helm validates the merged values on
every `helm install`, `helm upgrade` and `helm lint` — automatically, no flags
needed. It catches typos (`replicas` vs `replicaCount`) and wrong types
(`port: "8080"` as a string) before anything reaches the cluster, where they
would fail in far more confusing ways.

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "image": {
      "type": "object",
      "required": ["tag"],
      "properties": {
        "tag": { "type": "string", "minLength": 1 }
      }
    },
    "service": {
      "type": "object",
      "properties": {
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
      }
    }
  }
}
```

```bash
# Schema violations fail fast with a readable message
helm lint ./myapp --set image.tag=""
# [ERROR] values don't meet the specifications of the schema(s):
# image.tag: String length must be greater than or equal to 1
```

> A complete working schema is at
> [`../examples/helm/myapp/values.schema.json`](../examples/helm/myapp/values.schema.json).

---

## 8. Templates — How It Works

### Basic syntax

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  # Release.Name — release name (helm install <release-name>)
  # Release.Namespace — release namespace
  # Chart.Name — chart name from Chart.yaml
  name: {{ .Release.Name }}-{{ .Chart.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    # include calls a helper from _helpers.tpl
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.port }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          env:
            {{- range $key, $val := .Values.env }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
```

### Conditional blocks

```yaml
# Ingress only if enabled
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}

# With default value (if not set — "default-value")
{{ .Values.someKey | default "default-value" }}

# Check if a key exists
{{- if hasKey .Values "optionalSection" }}
  ...
{{- end }}
```

### _helpers.tpl — reusable snippets

```yaml
# templates/_helpers.tpl
{{/*
Full name for resources
*/}}
{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Standard labels
*/}}
{{- define "myapp.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

```yaml
# Using in a template
name: {{ include "myapp.fullname" . }}
labels:
  {{- include "myapp.labels" . | nindent 4 }}
```

### Important template functions

| Function | What it does | Example |
|---|---|---|
| `\| nindent N` | Add N-space indent (with leading newline) | `toYaml .Values.x \| nindent 8` |
| `\| indent N` | Add indent without leading newline | |
| `\| quote` | Wrap in quotes | `{{ .Values.tag \| quote }}` |
| `\| default "x"` | Default value | `{{ .Values.x \| default "foo" }}` |
| `\| upper` / `\| lower` | Change case | |
| `\| b64enc` | Base64 encode (for secrets) | `{{ .Values.pass \| b64enc }}` |
| `toYaml` | Convert object to YAML | `{{- toYaml .Values.resources \| nindent 12 }}` |
| `tpl` | Render a value as a template | `{{ tpl .Values.someTemplate . }}` |
| `trunc 63` | Truncate string (for resource names) | `{{ .Release.Name \| trunc 63 }}` |
| `{{-` / `-}}` | Strip whitespace / newline | |

### Templates — bad vs right

```yaml
# ❌ Bad — hardcoded names, duplicated labels, resources not from values
metadata:
  name: myapp-deployment        # ❌ breaks on second helm install or rename
  labels:
    app: myapp                  # ❌ copy-pasted in deployment.yaml, service.yaml, ingress.yaml...
    version: "1.0.0"            # ❌ hardcoded — won't update when values change
spec:
  replicas: 2                   # ❌ not from values — can't change without editing the template
  template:
    spec:
      containers:
        - name: myapp
          image: myapp:latest   # ❌ not from values — CI can't override the tag
          resources:
            limits:
              memory: 128Mi     # ❌ same for dev and prod — not flexible
```

```yaml
# ✅ Good — names via helper, labels centralised, everything parameterised
metadata:
  name: {{ include "myapp.fullname" . }}        # from _helpers.tpl — Release.Name + Chart.Name
  labels:
    {{- include "myapp.labels" . | nindent 4 }}  # defined once in _helpers.tpl
spec:
  replicas: {{ .Values.replicaCount }}           # from values — override with -f or --set
  template:
    metadata:
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"  # from values
          resources:
            {{- toYaml .Values.resources | nindent 12 }}  # fully from values — different per env
```

> **Rule:** if a string appears in two templates — it belongs in `_helpers.tpl`.
> If a value changes between runs — it belongs in `values.yaml`.

### Hooks — Jobs around the release lifecycle

A hook is a regular manifest with a `helm.sh/hook` annotation. Helm renders it
with the rest of the chart but applies it at a specific lifecycle point — here,
DB migrations run *before* the new app version rolls out. The upgrade waits for
the Job to succeed; if migrations fail, the release fails and the old version
keeps running.

```yaml
# templates/migrate-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-upgrade                 # run before upgrade applies the manifests
    "helm.sh/hook-weight": "0"                  # order among hooks (lower runs first)
    # delete the previous hook Job before creating a new one; clean up on success
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0            # don't blindly retry a failed migration
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["./manage.py", "migrate"]
```

Other hook points: `pre-install`, `post-install`, `post-upgrade`, `pre-delete`, etc.

`helm test` uses the same mechanism: a Pod annotated `"helm.sh/hook": test`
lives in the chart and runs only when you call `helm test <release>` —
a built-in smoke test right after deploy.

---

## 9. Debugging

### Preview what Helm will generate (without applying)

```bash
# Render templates locally
helm template myapp ./myapp -f values-prod.yaml

# Render + local kubectl syntax check
helm template myapp ./myapp -f values-prod.yaml | kubectl apply --dry-run=client -f -

# If you have cluster access — validate against the Kubernetes API
helm template myapp ./myapp -f values-prod.yaml | kubectl apply --dry-run=server -f -

# --debug shows values and rendered output during install/upgrade
helm upgrade --install myapp ./myapp --debug --dry-run
```

### Check chart syntax

```bash
# Lint — check the chart for errors and best practices
helm lint ./myapp
helm lint ./myapp -f values-prod.yaml

# Typical errors lint catches:
# - missing Chart.yaml
# - invalid template syntax
# - resource missing namespace
```

### A resource in the cluster — which release owns it?

The reverse of `helm list`: you found a Deployment (or Service, ConfigMap...)
and want to know which Helm release manages it — or whether it is
Helm-managed at all. Helm 3 stamps every resource it creates:

```bash
# Helm-managed at all? ("Helm" — yes; empty — created outside Helm)
kubectl get deployment myapp -n my-namespace \
  -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'

# Which release owns it — and in which namespace that release lives
kubectl get deployment myapp -n my-namespace \
  -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}'
kubectl get deployment myapp -n my-namespace \
  -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}'

# Now see everything else that release owns
helm get manifest <release> -n <namespace>
```

### Inspect what's deployed

```bash
# Manifests currently in the cluster (as Helm sees them)
helm get manifest my-postgres -n database

# All values including defaults
helm get values my-postgres -n database --all

# Notes (NOTES.txt) displayed after deploy
helm get notes my-postgres -n database

# Full info (values + manifest + hooks)
helm get all my-postgres -n database
```

### Error: "release already exists" on first install

```bash
# If the previous install got stuck in pending state
helm list -A --all   # --all shows even failed releases

# Delete the broken release
helm uninstall my-postgres -n database --no-hooks

# Or just use upgrade --install from the start (won't fail if it exists)
helm upgrade --install my-postgres bitnami/postgresql -n database
```

### Error: template won't render

```bash
# Render a single template in isolation
helm template myapp ./myapp \
  --show-only templates/deployment.yaml \
  -f values.yaml

# Check a specific value
helm template myapp ./myapp -f values.yaml \
  | grep -A5 "image:"
```

### helm-diff — preview what an upgrade will change

```bash
# Install the plugin
helm plugin install https://github.com/databus23/helm-diff

# Exact diff between the live release and what the upgrade would apply
helm diff upgrade myapp ./myapp -f values-prod.yaml
```

`helm template` shows *everything*; `helm diff` shows only what *changes* —
which is what you actually want to review before an upgrade. In CI it's the
de-facto standard "approve before apply" step: post the diff to the PR,
apply only after review.

---

## 10. Helm in CI/CD

### Typical pipeline (GitHub Actions / GitLab CI)

```yaml
# .github/workflows/deploy.yaml (simplified)
- name: Deploy
  run: |
    helm upgrade --install myapp ./helm/myapp \
      --namespace production \
      --create-namespace \
      --atomic \
      --timeout 5m \
      --wait \
      -f helm/myapp/values-prod.yaml \
      --set image.tag=${{ github.sha }}
```

### Passing secrets in CI — safely

```bash
# DON'T: --set DB_PASSWORD=plaintext directly in the command or in values.yaml in Git
# Better: inject from CI variables, but note the value may still appear in runner logs

# variables come from vault / CI secrets store
helm upgrade --install myapp ./myapp \
  --set secrets.DB_PASSWORD="${DB_PASSWORD}" \
  --set secrets.API_KEY="${API_KEY}"
```

> **Important:** `--set` is not a fully secure way to pass secrets.
> For production, prefer External Secrets, Sealed Secrets, Vault, or SOPS.

### Secrets in Git — three working approaches

**Sealed Secrets** — encrypt with the cluster's public key and commit the
encrypted manifest; only the in-cluster controller can decrypt it:

```bash
# One-time: install the controller into the cluster
helm install sealed-secrets sealed-secrets \
  --repo https://bitnami-labs.github.io/sealed-secrets -n kube-system

# Encrypt a regular Secret manifest → SealedSecret manifest
kubectl create secret generic app-db-secret \
  --from-literal=password=S3cret --dry-run=client -o yaml \
  | kubeseal -o yaml > sealed-secret.yaml

git add sealed-secret.yaml            # safe to commit — only the controller can decrypt
kubectl apply -f sealed-secret.yaml   # controller creates the real Secret in-cluster
```

**SOPS + helm-secrets** — encrypt a whole values file with an age or cloud KMS
key; Helm decrypts it transparently at deploy time:

```bash
helm plugin install https://github.com/jkroepke/helm-secrets
sops --encrypt --age <public-key> secrets.yaml > secrets.enc.yaml   # commit this file
helm secrets upgrade --install myapp ./myapp -f values-prod.yaml -f secrets.enc.yaml
```

**External Secrets Operator (ESO)** — secrets live in Vault / AWS Secrets
Manager / GCP SM; an `ExternalSecret` manifest (safe for git) syncs them into
k8s Secrets:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-db-secret
spec:
  secretStoreRef: { name: vault-backend, kind: ClusterSecretStore }
  target: { name: app-db-secret }     # the k8s Secret ESO creates and keeps in sync
  data:
    - secretKey: password
      remoteRef: { key: myapp/db, property: password }
```

> **Which to pick:** small team, git-centric workflow → Sealed Secrets or SOPS
> (no extra infrastructure). Company already runs Vault / AWS SM / GCP SM → ESO,
> so secrets keep a single source of truth outside the cluster.

### Different values per environment

```
helm/myapp/
  values.yaml          # defaults (dev)
  values-staging.yaml  # overrides for staging
  values-prod.yaml     # overrides for prod
```

```bash
# dev
helm upgrade --install myapp ./helm/myapp

# staging
helm upgrade --install myapp ./helm/myapp -f helm/myapp/values-staging.yaml

# prod
helm upgrade --install myapp ./helm/myapp \
  -f helm/myapp/values-prod.yaml \
  --set image.tag=v1.2.3
```

### Helmfile — managing multiple releases (recommended for larger projects)

```yaml
# helmfile.yaml
repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami

releases:
  - name: postgres
    namespace: database
    chart: bitnami/postgresql
    version: "13.2.0"
    values:
      - values/postgres.yaml

  - name: myapp
    namespace: production
    chart: ./helm/myapp
    values:
      - values/myapp-prod.yaml
    needs:
      - database/postgres     # deploy after postgres
```

```bash
# Install helmfile
brew install helmfile

# Apply all releases
helmfile sync

# Dry-run
helmfile diff
```

---

## 11. Useful Aliases and Scripts

### ~/.bashrc / ~/.zshrc

```bash
# Helm shortcuts
alias h='helm'
alias hls='helm list -A'
alias hst='helm status'
alias hup='helm upgrade --install'

# View all releases with chart versions
alias hla='helm list -A -o table'

# Function: quick local chart deploy
hdeploy() {
  local name=$1
  local chart=${2:-./helm/$1}
  local ns=${3:-default}
  local values_file="$chart/values.yaml"
  helm upgrade --install "$name" "$chart" \
    -n "$ns" --create-namespace \
    -f "$values_file" \
    --atomic --wait --timeout 5m
}
# Usage: hdeploy myapp ./helm/myapp production

# Function: rollback a release
hrollback() {
  local name=$1
  local ns=${2:-default}
  echo "Revision history for $name:"
  helm history "$name" -n "$ns"
  echo -n "Enter revision number to roll back to: "
  read rev
  [ -z "$rev" ] && return 1
  helm rollback "$name" "$rev" -n "$ns" --wait
}
```

### Script: full release status

```bash
#!/bin/bash
# helm-status.sh — detailed release information

RELEASE=$1
NS=${2:-default}

echo "=== Release: $RELEASE (namespace: $NS) ==="
helm status "$RELEASE" -n "$NS"

echo -e "\n=== History ==="
helm history "$RELEASE" -n "$NS"

echo -e "\n=== Values (overrides) ==="
helm get values "$RELEASE" -n "$NS"

echo -e "\n=== Pods ==="
kubectl get pods -n "$NS" -l "app.kubernetes.io/instance=$RELEASE"
```

> **Note:** the pod filter works if the chart uses standard Helm labels.
> Custom or older charts may use different labels.

---

## Command Cheatsheet

| Command | What it does |
|---|---|
| `helm repo add <name> <url>` | Add a repository |
| `helm repo update` | Update repository index |
| `helm search repo <term>` | Search for a chart in repos |
| `helm show values <chart>` | View chart values |
| `helm pull <chart> --untar` | Download chart locally |
| `helm install <rel> <chart>` | Install a release |
| `helm upgrade --install <rel> <chart>` | Install or upgrade (idempotent) |
| `helm list -A` | List all releases |
| `helm status <rel>` | Release status |
| `helm history <rel>` | Revision history |
| `helm rollback <rel> [rev]` | Roll back to revision |
| `helm uninstall <rel>` | Delete a release |
| `helm get values <rel>` | Current release values |
| `helm get manifest <rel>` | Release YAML manifests |
| `helm template <rel> <chart>` | Render without applying |
| `helm lint <chart>` | Check chart for errors |
| `helm create <name>` | Scaffold a new chart |
| `helm dependency update` | Download subcharts |
| `helm upgrade ... --atomic` | Auto-rollback on failure |
| `helm upgrade ... --debug --dry-run` | Debug without applying |

---

> **Tip:** Keep `values-<env>.yaml` in Git alongside your application code.
> Secrets — via [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or Vault, never in plain-text values.
