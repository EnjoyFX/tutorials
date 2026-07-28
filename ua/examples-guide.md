# Demo App — Docker → Helm → k3s

> Один застосунок, три рівні деплою. Від локального контейнера до Kubernetes-кластера.

---

## Зміст

1. [Що ми будуємо](#1-що-ми-будуємо)
2. [Структура файлів](#2-структура-файлів)
3. [Застосунок — app.py](#3-застосунок--apppy)
4. [Docker — збірка образу](#4-docker--збірка-образу)
5. [Helm — чарт для Kubernetes](#5-helm--чарт-для-kubernetes)
6. [k3s — деплой у кластер](#6-k3s--деплой-у-кластер)
7. [Кроки кінцево до кінця](#7-кроки-кінцево-до-кінця)

---

## 1. Що ми будуємо

Мінімальний HTTP-сервер на Python (без фреймворків), який:

| Endpoint     | Відповідь                                              |
|--------------|--------------------------------------------------------|
| `GET /`      | `{"message": "...", "version": "...", "hostname": "..."}` |
| `GET /health`| `{"status": "ok"}`                                     |

`/health` використовується як liveness і readiness probe в Kubernetes — k3s перевіряє його, щоб знати чи pod живий і чи готовий приймати трафік.

---

## 2. Структура файлів

```
examples/
├── docker/
│   ├── app.py          ← сам застосунок
│   ├── Dockerfile      ← інструкція для збірки образу
│   └── .dockerignore   ← що не класти в образ
├── helm/
│   └── myapp/
│       ├── Chart.yaml              ← метадані чарту
│       ├── values.yaml             ← змінні за замовчуванням
│       └── templates/
│           ├── _helpers.tpl        ← спільні шаблони імен та лейблів
│           ├── deployment.yaml     ← як запустити pod
│           └── service.yaml        ← як дістатися до pod
└── k3s/
    └── deploy.sh       ← скрипт: build → import → helm deploy
```

---

## 3. Застосунок — app.py

```python
from http.server import BaseHTTPRequestHandler, HTTPServer
```

Python має вбудований HTTP-сервер. `BaseHTTPRequestHandler` — базовий клас, в якому ми перевизначаємо `do_GET` для обробки GET-запитів.

### Як це працює

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

- `self.path` — шлях з URL запиту (`/`, `/health`, тощо)
- `os.getenv("MESSAGE", "default")` — значення береться зі змінної середовища, або default якщо не задано
- `hostname` у відповіді — ім'я pod у Kubernetes. Зручно для перевірки, який саме pod відповів при кількох репліках

### Метод `_respond`

```python
def _respond(self, code, data):
    body = json.dumps(data).encode()
    self.send_response(code)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)
```

`Content-Length` обов'язковий — без нього деякі HTTP-клієнти та проксі можуть некоректно читати тіло відповіді.

### Запуск

```python
port = int(os.getenv("PORT", 8080))
server = HTTPServer(("", port), Handler)
server.serve_forever()
```

`""` як хост означає "слухати на всіх інтерфейсах" — потрібно щоб контейнер був доступний ззовні.

---

## 4. Docker — збірка образу

### Dockerfile розібраний по рядках

```dockerfile
FROM python:3-alpine
```

Мінімальний базовий образ. `alpine` — дистрибутив Linux ~5MB. Без зайвих утиліт, менша поверхня атаки.

```dockerfile
WORKDIR /app
```

Встановлює робочу директорію. Всі наступні `COPY`, `RUN`, `CMD` виконуються відносно неї. Краще ніж `cd` у `RUN`.

```dockerfile
COPY app.py .
```

Копіюємо тільки те що потрібно. Не `COPY . .` — не тягнемо зайве (`.git`, локальні конфіги, тощо).

```dockerfile
RUN adduser -D -u 1001 appuser
USER appuser
```

Створюємо непривілейованого користувача і перемикаємося на нього. Контейнер не повинен запускатись від `root` — це базова вимога безпеки. У Helm-чарті `securityContext` додатково це підтверджує.

```dockerfile
EXPOSE 8080
```

Документує який порт використовує застосунок. Не відкриває порт назовні — це лише метадата для `docker inspect` і оркестраторів.

```dockerfile
CMD ["python", "app.py"]
```

Команда запуску. Exec-форма (масив) — запускає процес напряму, без shell. PID 1 отримує `SIGTERM` коректно при `docker stop`.

### Збірка та запуск

```bash
cd examples/docker

# Зібрати образ
docker build -t myapp:local .

# Запустити локально
docker run --rm -p 8080:8080 myapp:local

# Перевірити
curl http://localhost:8080/
curl http://localhost:8080/health

# Запустити з кастомним повідомленням
docker run --rm -p 8080:8080 \
  -e MESSAGE="Привіт з Docker!" \
  -e APP_VERSION="2.0.0" \
  myapp:local
```

### .dockerignore

```
__pycache__
*.pyc
*.pyo
```

Без цього файлу Docker включить кеш Python у build context, що забруднить образ байт-кодом з локальної машини.

---

## 5. Helm — чарт для Kubernetes

Helm — менеджер пакетів для Kubernetes. Чарт — це шаблони маніфестів + змінні.

### Chart.yaml

```yaml
apiVersion: v2
name: myapp
version: 0.1.0
appVersion: "1.0.0"
```

- `version` — версія самого чарту (змінюється при зміні шаблонів)
- `appVersion` — версія застосунку (для інформації, не впливає на деплой)

### values.yaml — точка конфігурації

```yaml
image:
  repository: myapp
  tag: "1.0.0"
  pullPolicy: IfNotPresent   # не тягти образ якщо він вже є на ноді

env:
  MESSAGE: "Hello from myapp!"
  APP_VERSION: "1.0.0"

resources:
  requests:
    cpu: 50m       # 50 мілікор — мінімум гарантований
    memory: 32Mi
  limits:
    cpu: 200m      # 200 мілікор — максимум
    memory: 64Mi
```

`IfNotPresent` критичний для локального деплою через `k3s ctr images import` — без нього k3s спробує тягнути образ з registry і не знайде.

### templates/deployment.yaml — ключові моменти

**Liveness probe** — перевіряє чи процес живий. Якщо не відповідає — pod перезапускається.

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5   # дати час застосунку запуститись
  periodSeconds: 10
```

**Readiness probe** — перевіряє чи pod готовий приймати трафік. Якщо не відповідає — pod виключається з rotation сервісу, але не перезапускається.

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 3
  periodSeconds: 5
```

**securityContext** — підтверджує на рівні Kubernetes що процес не root і працює з обмеженими правами:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  seccompProfile:
    type: RuntimeDefault
```

**Змінні середовища з values.yaml:**

```yaml
env:
  {{- range $key, $val := .Values.env }}
  - name: {{ $key }}
    value: {{ $val | quote }}
  {{- end }}
```

`range` ітерує по мапі `env` у values. `quote` огортає значення в лапки — захист від YAML-інтерпретації чисел як int.

### templates/service.yaml

```yaml
spec:
  type: ClusterIP    # доступний тільки всередині кластера
  ports:
    - port: 8080     # порт сервісу (куди звертаються інші pod)
      targetPort: 8080  # порт контейнера (куди форвардить сервіс)
```

`ClusterIP` — стандартний тип для внутрішніх сервісів. Для доступу ззовні — `port-forward` або Ingress.

### Корисні команди Helm

```bash
# Перевірити шаблони перед деплоєм
helm template myapp examples/helm/myapp

# Перевірити що values правильно застосовуються
helm template myapp examples/helm/myapp \
  --set env.MESSAGE="test" | grep -A2 "env:"

# Задеплоїти
helm upgrade --install myapp examples/helm/myapp \
  --namespace demo --create-namespace --wait

# Переглянути статус
helm status myapp -n demo

# Видалити
helm uninstall myapp -n demo
```

---

## 6. k3s — деплой у кластер

### Проблема: образ на локальній машині, не в registry

k3s використовує `containerd` як runtime і не має доступу до Docker daemon. Якщо запустити `helm install` з образом, якого немає в containerd, k3s спробує тягнути його з registry і може отримати `ImagePullBackOff`.

**Рішення** — імпортувати образ напряму в containerd:

```bash
docker save myapp:local | sudo k3s ctr images import -
```

- `docker save` — зберігає образ у tar-архів у stdout
- `k3s ctr images import -` — читає tar з stdin і додає в containerd k3s

Після цього образ доступний в k3s:

```bash
sudo k3s ctr images list | grep myapp
```

### deploy.sh — покрокове пояснення

```sh
#!/bin/sh
set -e   # зупинитись при першій помилці
```

```sh
# Збираємо образ з Dockerfile у examples/docker/
docker build -t "$IMAGE" "$SCRIPT_DIR/../docker"
```

```sh
# Імпортуємо в k3s, щоб оминути registry
docker save "$IMAGE" | sudo k3s ctr images import -
```

```sh
# Створюємо namespace якщо не існує
# --dry-run=client -o yaml | kubectl apply — ідемпотентний варіант
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
```

```sh
# helm upgrade --install — ідемпотентний деплой:
# якщо release не існує — install, якщо існує — upgrade
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG" \
  --set image.pullPolicy=Never \
  --atomic \
  --timeout "$TIMEOUT" \
  --wait
```

`image.pullPolicy=Never` не тягне образ з registry, а `--wait` чекає поки pod стане Ready.

### Перевірка після деплою

```bash
# Статус pod
kubectl get pods -n demo

# Логи
kubectl logs -l app.kubernetes.io/name=myapp -n demo

# Локальний доступ через port-forward
kubectl port-forward service/myapp-myapp 8080:8080 -n demo

# В іншому терміналі
curl http://localhost:8080/
curl http://localhost:8080/health
```

### Типові проблеми

| Симптом | Причина | Рішення |
|---------|---------|---------|
| `ImagePullBackOff` | k3s не знайшов образ | Запустити `docker save \| k3s ctr images import` |
| `CrashLoopBackOff` | Застосунок падає при старті | `kubectl logs <pod> -n demo` |
| Pod `0/1 Running` (не Ready) | Readiness probe не пройшла | `kubectl describe pod <pod> -n demo` → Events |
| `helm: release not found` при `--wait` | Чарт не знайдено | Перевірити шлях до `examples/helm/myapp` |

---

## 7. Кроки кінцево до кінця

```bash
# Клонувати та перейти в репо
cd examples

# --- Крок 1: перевірити локально через Docker ---
docker build -t myapp:local docker/
docker run --rm -p 8080:8080 myapp:local &
curl http://localhost:8080/
kill %1

# --- Крок 2: перевірити Helm-шаблони ---
helm template myapp helm/myapp

# --- Крок 3: задеплоїти на k3s ---
chmod +x k3s/deploy.sh
./k3s/deploy.sh

# --- Крок 4: перевірити в кластері ---
kubectl get all -n demo
kubectl port-forward service/myapp-myapp 8080:8080 -n demo &
curl http://localhost:8080/
curl http://localhost:8080/health

# --- Крок 5: змінити конфігурацію без перезбірки ---
helm upgrade myapp helm/myapp \
  --namespace demo \
  --set env.MESSAGE="Оновлено без rebuild!" \
  --set replicaCount=2 \
  --wait

curl http://localhost:8080/   # нове повідомлення
kubectl get pods -n demo      # 2 репліки
```
