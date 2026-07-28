# Docker Compose → Helm: практична міграція

> Типовий шлях: застосунок працює локально через `compose.yaml` — потрібно задеплоїти в k3s.
> Цей гайд — покроковий перехід від Compose до Helm chart без магії.

> **Дивись також:** [Docker](docker-guide.md) · [Linux](linux-guide.md) · [Helm](helm-guide.md) · [k3s](k3s-dev-guide.md) · [Розбір демо](examples-guide.md) · [Демо-приклад](../examples/README.md)

---

## Зміст

1. [Відповідність концепцій](#1-відповідність-концепцій)
2. [Стартова точка — compose.yaml](#2-стартова-точка--composeyaml)
3. [Що не переноситься напряму](#3-що-не-переноситься-напряму)
4. [Крок 1 — образ у registry або k3s](#4-крок-1--образ-у-registry-або-k3s)
5. [Крок 2 — Deployment для кожного сервісу](#5-крок-2--deployment-для-кожного-сервісу)
6. [Крок 3 — Service для комунікації](#6-крок-3--service-для-комунікації)
7. [Крок 4 — ConfigMap для env vars](#7-крок-4--configmap-для-env-vars)
8. [Крок 5 — Secret для паролів](#8-крок-5--secret-для-паролів)
9. [Крок 6 — PVC замість named volume](#9-крок-6--pvc-замість-named-volume)
10. [Крок 7 — пакуємо в Helm chart](#10-крок-7--пакуємо-в-helm-chart)
11. [Автоматична конвертація — kompose](#11-автоматична-конвертація--kompose)
12. [Повний вигляд чарту](#12-повний-вигляд-чарту)
13. [Поширення чарту](#13-поширення-чарту)

---

## 1. Відповідність концепцій

| Docker Compose | Kubernetes / Helm |
|---|---|
| `services.app` | Deployment + Service |
| `image:` | `spec.containers[].image` |
| `build:` | ❌ немає — потрібен готовий образ |
| `ports:` | Service ports + `containerPort` |
| `environment:` (звичайні) | `env:` у Deployment або ConfigMap |
| `environment:` (секрети) | Secret → `envFrom` або `env.valueFrom` |
| `env_file:` | ConfigMap або Secret |
| `volumes:` (named) | PersistentVolumeClaim |
| `volumes:` (bind mount) | не рекомендується в k8s |
| `depends_on:` | `readinessProbe` (непрямий аналог) |
| `healthcheck:` | `livenessProbe` + `readinessProbe` |
| `restart: always` | вбудовано — `restartPolicy: Always` за замовчуванням |
| `mem_limit:` / `cpus:` | `resources.limits` |
| `networks:` | не потрібно — k8s має flat network |
| `replicas:` | `spec.replicas` у Deployment |

---

## 2. Стартова точка — compose.yaml

Реалістичний приклад: Python-застосунок + PostgreSQL.

```yaml
services:
  app:
    build: .                          # збираємо локально
    ports:
      - "8080:8080"
    environment:
      MESSAGE: "Hello from Compose!"
      DB_HOST: postgres
      DB_PASSWORD: secret123          # ❌ секрет у compose.yaml
    depends_on:
      postgres:
        condition: service_healthy
    restart: always

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: secret123    # ❌ секрет у compose.yaml
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

Мета: перенести це в k3s, зберігши ту саму поведінку.

У репозиторії також є мінімальний робочий compose-файл для демо-застосунку —
[`../examples/docker/compose.yaml`](../examples/docker/compose.yaml) — і його Helm-двійник у
[`../examples/helm/myapp`](../examples/helm/myapp), тож усю міграцію можна пройти на практиці.

---

## 3. Що не переноситься напряму

### `build:` — збірка образу

Compose вміє збирати образ на льоту. Kubernetes — ні. До деплою образ **вже мусить існувати**.

```bash
# Зібрати і запушити в registry
docker build -t my-registry/myapp:v1.0.0 .
docker push my-registry/myapp:v1.0.0

# Або для k3s без registry — імпортувати напряму
docker build -t myapp:latest .
docker save myapp:latest | sudo k3s ctr images import -
```

### `depends_on:` — порядок запуску

Compose чекає поки сервіс стане healthy перш ніж запустити залежний.
У k8s порядку запуску немає — `readinessProbe` вирішує це інакше: pod стає Ready
тільки коли застосунок готовий, і тільки тоді Service направляє на нього трафік.

```yaml
# Compose
depends_on:
  postgres:
    condition: service_healthy

# k8s — app сам перевіряє готовність через probe
# Якщо DB ще не готова — probe провалюється, pod не отримує трафік, пробує знову
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

Якщо застосунок падає при недоступній БД — використовуй `initContainer`:

```yaml
initContainers:
  - name: wait-for-postgres
    image: busybox
    command: ['sh', '-c', 'until nc -z postgres-service 5432; do sleep 2; done']
```

### `ports:` — прив'язка до хоста

Compose `"8080:8080"` публікує порт прямо на хост-машину.
У k8s порти не виставляються назовні автоматично — потрібен Service типу
`NodePort`, `LoadBalancer`, або Ingress. Для внутрішньої комунікації — `ClusterIP`.

### Секрети в `environment:`

У Compose секрети часто пишуть прямо у `compose.yaml` або `.env`.
У k8s для секретів є окремий об'єкт `Secret` — не зберігається у відкритому вигляді в маніфестах.

---

## 4. Крок 1 — образ у registry або k3s

```bash
# Варіант А: registry (рекомендовано для production)
docker build -t my-registry/myapp:v1.0.0 .
docker push my-registry/myapp:v1.0.0

# Варіант Б: напряму в k3s (dev/local, без registry)
docker build -t myapp:latest .
docker save myapp:latest | sudo k3s ctr images import -
```

Postgres — публічний образ, k3s стягне сам із Docker Hub.

---

## 5. Крок 2 — Deployment для кожного сервісу

Кожен `service:` у Compose стає окремим `Deployment`.

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
                name: app-config     # звичайні env vars
            - secretRef:
                name: app-secrets    # секрети
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

Зверни увагу на різницю між двома probe: якщо провалюється `readinessProbe` — pod
продовжує працювати, але не отримує трафік від Service; якщо провалюється `livenessProbe` —
контейнер перезапускається. Типова помилка — направити liveness на залежність
(наприклад, `/health`, який перевіряє БД): падіння БД тоді спричиняє цикл рестартів
замість спокійного очікування.

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

> ❌ **Deployment для бази даних — тільки для dev.** Production-база хоче
> `StatefulSet`: стабільне мережеве ім'я, впорядкований rollout, `volumeClaimTemplates`
> для кожної репліки. А ще краще — оператор (наприклад, CloudNativePG) або managed-база поза кластером.

### imagePullSecrets — приватний registry

Якщо образ лежить у приватному registry, кластеру потрібні креденшали, щоб його стягнути:

```bash
# Креденшали registry як Secret
kubectl create secret docker-registry regcred \
  --docker-server=my-registry.example.com \
  --docker-username=deploy \
  --docker-password='S3cret!' \
  -n my-namespace
```

```yaml
# У pod spec Deployment-а
spec:
  template:
    spec:
      imagePullSecrets:
        - name: regcred
      containers:
        - name: app
          image: my-registry.example.com/myapp:v1.0.0
```

У кроці з чартом це стає параметром у `values.yaml` (`imagePullSecrets: [{name: regcred}]`) —
для dev без registry список просто лишається порожнім.

---

## 6. Крок 3 — Service для комунікації

У Compose сервіси знаходять одне одного по імені (`DB_HOST: postgres`).
У k8s це робить `Service` — він дає стабільне DNS-ім'я всередині кластера.

```yaml
# app-service — доступний всередині кластера
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
# postgres-service — тільки для internal трафіку
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

> `DB_HOST: postgres` у Compose → `DB_HOST: postgres-service` у k8s.
> Повне DNS-ім'я: `postgres-service.my-namespace.svc.cluster.local`

---

## 7. Крок 4 — ConfigMap для env vars

Звичайні (несекретні) змінні середовища → ConfigMap.

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
  DB_HOST: postgres-service     # ← ім'я Service, не сервісу Compose
```

---

## 8. Крок 5 — Secret для паролів

Секрети → окремий об'єкт `Secret`. Значення в base64.

```bash
# Створити Secret через kubectl (не зберігається у git)
kubectl create secret generic app-secrets \
  --from-literal=DB_PASSWORD=secret123 \
  -n my-namespace

kubectl create secret generic postgres-secrets \
  --from-literal=POSTGRES_DB=myapp \
  --from-literal=POSTGRES_USER=myapp \
  --from-literal=POSTGRES_PASSWORD=secret123 \
  -n my-namespace
```

У Helm — через `values.yaml` + `--set` або зовнішній secret manager:

```yaml
# values.yaml — лише посилання, не самі секрети
postgres:
  existingSecret: postgres-secrets
```

---

## 9. Крок 6 — PVC замість named volume

`volumes: pgdata:` у Compose → `PersistentVolumeClaim` у k8s.

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

k3s автоматично задовольняє PVC через вбудований `local-path` provisioner.

---

## 10. Крок 7 — пакуємо в Helm chart

Тепер беремо всі маніфести і параметризуємо через `values.yaml`.

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

**Chart.yaml** — метадані чарту, мінімальний повний варіант:

```yaml
apiVersion: v2                # завжди v2 для Helm 3
name: myapp
description: Python app + PostgreSQL, migrated from Docker Compose
type: application
version: 0.1.0                # версія чарту — піднімай при кожній зміні чарту
appVersion: "1.0.0"           # версія застосунку — інформаційна
```

**values.yaml** — все що різниться між dev і prod:

```yaml
app:
  image:
    repository: my-registry/myapp
    tag: "v1.0.0"
    pullPolicy: IfNotPresent
  imagePullSecrets: []        # напр. [{name: regcred}] для приватного registry
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
  existingSecret: postgres-secrets   # Secret створюється окремо, поза чартом
  storage: 1Gi
```

Також варто додати `templates/NOTES.txt` — текстовий шаблон, який Helm рендерить і показує
після `helm install` / `helm upgrade`. Поклади туди найнеобхідніше після встановлення,
наприклад команду port-forward:
`kubectl port-forward service/app-service 8080:8080 -n {{ .Release.Namespace }}`.

**Деплой:**

```bash
# Створити secrets окремо (один раз)
kubectl create secret generic postgres-secrets \
  --from-literal=POSTGRES_DB=myapp \
  --from-literal=POSTGRES_USER=myapp \
  --from-literal=POSTGRES_PASSWORD=secret123 \
  -n demo

# Задеплоїти чарт
helm upgrade --install myapp ./myapp \
  --namespace demo --create-namespace \
  --wait

# Перевірити — реліз на місці, і що він створив?
helm list -n demo
kubectl get all -n demo
kubectl port-forward service/app-service 8080:8080 -n demo
```

### Перевір міграцію перед тим, як чіпати кластер

```bash
# Відрендерити шаблони локально і переглянути маніфести
helm template ./myapp | less

# Повна client-side валідація з values і хуками, без встановлення
helm install myapp ./myapp --dry-run --debug -n demo

# Server-side перевірка схеми — валідує API server, нічого не створюється
helm template ./myapp | kubectl apply --dry-run=server -f -
```

Так помилки схем і шаблонів ловляться до того, як щось потрапить у кластер.

---

## 11. Автоматична конвертація — kompose

`kompose` конвертує `compose.yaml` у k8s маніфести автоматично.

```bash
# Встановити
brew install kompose

# Конвертувати
kompose convert -f compose.yaml -o ./k8s-manifests/

# Подивитись, що згенерувалось, перш ніж щось застосовувати
ls ./k8s-manifests/

# Або одразу застосувати
kompose up
```

**Але є застереження:** `kompose` генерує плоскі маніфести, не Helm chart.
Результат потребує ручного доопрацювання:

| Що kompose робить добре | Що потребує доопрацювання |
|---|---|
| Базові Deployment і Service | Secrets (генерує у відкритому вигляді) |
| PVC для named volumes | `build:` → треба замінити на `image:` |
| Port mapping | `depends_on:` → треба додати initContainer або probe |
| Env vars | Resources (limits/requests відсутні) |

> Використовуй `kompose` як стартову точку для розуміння структури,
> але не як фінальний результат для production.

---

## 12. Повний вигляд чарту

Після міграції:

```
Compose                          Helm chart
──────────────────────────────────────────────────────
services.app                  →  app-deployment.yaml
  build: .                    →  ❌ (образ у registry)
  ports: 8080:8080             →  app-service.yaml (ClusterIP)
  environment.MESSAGE          →  app-configmap.yaml
  environment.DB_PASSWORD      →  Secret (окремо від чарту)
  depends_on: postgres         →  readinessProbe на /health

services.postgres             →  postgres-deployment.yaml
  image: postgres:16-alpine    →  без змін
  environment.POSTGRES_*       →  Secret (окремо від чарту)
  volumes: pgdata              →  postgres-pvc.yaml
  healthcheck                  →  readinessProbe (pg_isready)

volumes.pgdata                →  postgres-pvc.yaml (PVC, 1Gi)
networks (implicit)           →  ❌ не потрібно (k8s flat network)
restart: always               →  ❌ не потрібно (вбудовано)
```

**Локальний запуск залишається через Compose — нічого не змінюється:**

```bash
# Розробка — як і раніше
docker compose up

# Staging / production — через Helm
helm upgrade --install myapp ./myapp -n demo --wait
```

---

## 13. Поширення чарту

Чарт працює — де йому жити?

| Варіант | Коли підходить |
|---|---|
| У репозиторії застосунку (напр. `deploy/chart/`) | найпростіше — чарт версіонується разом з кодом |
| Класичний chart repo (`helm package` + repo index) | кілька команд / багато чартів, доступ через HTTP |
| OCI registry (`helm push`) | вже є container registry — використовуй його ж |

```bash
# Класичний chart repo: пакуємо + index
helm package ./myapp                      # → myapp-0.1.0.tgz
helm repo index . --url https://charts.example.com

# OCI registry — той самий registry, де лежать образи
helm push myapp-0.1.0.tgz oci://my-registry.example.com/helm-charts
helm install myapp oci://my-registry.example.com/helm-charts/myapp --version 0.1.0
```

Деталі OCI та глибші теми Helm — у [helm-guide.md](helm-guide.md);
деплой і траблшутинг на реальному кластері — у [k3s-dev-guide.md](k3s-dev-guide.md).
