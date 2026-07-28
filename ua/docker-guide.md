# Docker — Практичний довідник девелопера

> Не просто команди. Сценарії реального щоденного використання.

> **Дивись також:** [Linux](linux-guide.md) · [Helm](helm-guide.md) · [k3s](k3s-dev-guide.md) · [Compose → Helm](compose-to-helm.md) · [Розбір демо](examples-guide.md) · [Демо-приклад](../examples/README.md)

---

## Зміст

1. [Терміни — словник](#1-терміни--словник)
2. [Образи — збірка та керування](#2-образи--збірка-та-керування)
3. [Dockerfile — від поганого до правильного](#3-dockerfile--від-поганого-до-правильного)
4. [Контейнери — запуск та керування](#4-контейнери--запуск-та-керування)
5. [Налагодження контейнерів](#5-налагодження-контейнерів)
6. [Volumes та bind mounts](#6-volumes-та-bind-mounts)
7. [Networking](#7-networking)
8. [Docker Compose](#8-docker-compose)
9. [Registry — публікація образів](#9-registry--публікація-образів)
10. [Очищення системи](#10-очищення-системи)
11. [Docker у CI/CD](#11-docker-у-cicd)
12. [Корисні аліаси та скрипти](#12-корисні-аліаси-та-скрипти)

- [Шпаргалка: образи vs контейнери vs compose](#шпаргалка-образи-vs-контейнери-vs-compose)

---

## 1. Терміни — словник

| Термін | Що це |
|---|---|
| **Image** (образ) | Незмінний шаблон файлової системи + метадані. Складається з шарів. Аналог ISO-образу. |
| **Container** (контейнер) | Запущений процес на основі образу. Має власний filesystem, мережу, PID. Аналог запущеної VM, але легший. |
| **Layer** (шар) | Кожна інструкція `RUN`/`COPY`/`ADD` у Dockerfile створює новий шар. Шари кешуються і перевикористовуються між образами. |
| **Dockerfile** | Текстовий файл з інструкціями для збірки образу. Кожен рядок — потенційний шар. |
| **Registry** | Сховище образів. Docker Hub — публічний. Можна підняти приватний (Registry, Harbor, Nexus). |
| **Tag** | Мітка версії образу. `myapp:latest`, `myapp:v1.2.0`. `latest` — просто конвенція, не "найновіший автоматично". |
| **Volume** | Том для зберігання даних поза контейнером. Керується Docker, живе після зупинки контейнера. |
| **Bind mount** | Монтування теки з хост-машини всередину контейнера. Зміни відразу видні з обох боків. |
| **tmpfs mount** | Монтування в оперативну пам'ять. Дані зникають при зупинці контейнера. |
| **Docker Compose** | Інструмент для запуску кількох контейнерів разом через один `compose.yaml`. |
| **Context** | Тека, що передається Docker daemon при збірці. Все з неї доступно в `COPY`/`ADD`. |
| **Multi-stage build** | Dockerfile з кількома `FROM`. Дозволяє зібрати в одному образі, а в фінальний покласти тільки артефакт. |
| **Dangling image** | Образ без тегу — лишається після перезбірки якщо тег перемістився на новий. `<none>:<none>` у `docker images`. |
| **entrypoint** | Головна команда контейнера. Не замінюється `docker run myapp <cmd>`, тільки з `--entrypoint`. |
| **cmd** | Аргументи за замовчуванням для entrypoint. Замінюються при `docker run myapp <cmd>`. |

### Образ vs Контейнер — аналогія

```
Image (образ)      →    Container (контейнер)
────────────────────────────────────────────
Клас в ООП         →    Екземпляр класу
ISO-образ диску    →    Запущена VM
Рецепт             →    Приготована страва
```

### Схема: від Dockerfile до контейнерів

```
┌──────────────────┐  docker build  ┌────────────────────────┐
│   Dockerfile     │ ─────────────▶ │  Image  myapp:latest   │
│                  │                │  (read-only шари)      │
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

> Один образ — необмежена кількість контейнерів. Кожен контейнер має власний
> ізольований filesystem і мережу, але читає шари образу спільно (copy-on-write).

---

## 2. Образи — збірка та керування

### Збірка

```bash
# Зібрати образ з Dockerfile у поточній теці
docker build -t myapp:latest .

# Зібрати з конкретним Dockerfile
docker build -t myapp:latest -f docker/Dockerfile.prod .

# Зібрати з build args (змінні під час збірки)
docker build -t myapp:latest \
  --build-arg NODE_ENV=production \
  --build-arg APP_VERSION=1.2.0 \
  .

# Зібрати без кешу (корисно коли підозрюєш застарілий кеш)
docker build --no-cache -t myapp:latest .

# Зібрати та одразу запустити — перевірити що працює
docker build -t myapp:test . && docker run --rm myapp:test
```

### Переглянути образи

```bash
# Список образів
docker images
docker image ls

# Список з розміром кожного шару
docker image history myapp:latest

# Детальна інформація (JSON)
docker image inspect myapp:latest

# Розмір образу в байтах
docker image inspect myapp:latest \
  --format='{{.Size}}'
```

> **Примітка:** `numfmt` зручний на Linux, але часто відсутній на macOS.
> Якщо потрібен "людяний" формат, найпростіше подивитись `docker images`.

### Теги

```bash
# Додати тег (не копіює — просто додатковий покажчик)
docker tag myapp:latest myapp:v1.2.0
docker tag myapp:latest registry.example.com/myapp:v1.2.0

# Видалити тег / образ
docker rmi myapp:old-tag
docker rmi myapp:latest   # видалить якщо немає інших тегів або контейнерів
```

### Зберегти / завантажити образ у файл

```bash
# Зберегти образ у tar (для передачі без registry)
docker save myapp:latest | gzip > myapp-v1.tar.gz

# Завантажити з tar.gz
gunzip -c myapp-v1.tar.gz | docker load

# Імпортувати в k3s (без registry)
docker save myapp:latest | sudo k3s ctr images import -
```

---

## 3. Dockerfile — від поганого до правильного

### Поганий Dockerfile (і чому він поганий)

```dockerfile
# ❌ Погано — великий образ, довга збірка, security-проблеми
FROM ubuntu:latest          # великий базовий образ (~77MB+ залежностей)

RUN apt-get update && apt-get install -y nodejs npm  # версії не зафіксовані

WORKDIR /app
COPY . .                    # копіює ВСЕ включно з node_modules, .git, .env!

RUN npm install             # залежності після коду → кеш скидається при будь-якій зміні коду

CMD node server.js          # запуск від root, немає EXPOSE, нема health check
```

### Правильний Dockerfile (Node.js)

```dockerfile
# ✅ Добре — легкий, кешований, безпечний
# Зафіксована версія — відтворювані збірки
FROM node:20-alpine AS base

WORKDIR /app

# 1. Спочатку тільки package.json — шар кешується якщо залежності не змінились
COPY package.json package-lock.json ./
RUN npm ci --only=production    # ci замість install — суворо за lock-файлом

# 2. Потім вихідний код — цей шар скидається тільки при зміні коду
COPY src/ ./src/

# Запуск не від root (security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

# HEALTHCHECK — Docker/k8s знають чи живий контейнер
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "src/server.js"]
```

### Multi-stage build (Go / будь-яка компільована мова)

```dockerfile
# Stage 1: збірка — великий образ з компілятором
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download                    # кеш залежностей окремим шаром

COPY . .
RUN CGO_ENABLED=0 go build -o server ./cmd/server

# ─────────────────────────────────────────
# Stage 2: фінальний образ — тільки бінарник
FROM scratch                           # порожній образ, ~0MB базовий
# або: FROM alpine:3.19 — якщо потрібні shell / certs / інструменти

COPY --from=builder /app/server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8080
ENTRYPOINT ["/server"]
```

```
Результат:
  golang:1.22-alpine + код + залежності  →  ~600MB (builder, не публікується)
  фінальний образ з бінарником           →  ~10MB  (те що йде в registry)
```

### Multi-stage для Node.js (збірка фронтенду)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build                      # генерує /app/dist

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

### BuildKit: кеш-маунти та секрети збірки

> BuildKit — білдер за замовчуванням у сучасному Docker, нічого налаштовувати не треба.
> Дві фічі, які варто використовувати з першого дня: cache mounts і build secrets.

```dockerfile
# Cache mount — кеш пакетного менеджера переживає перезбірки,
# але НЕ потрапляє в шари образу (образ лишається малим)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Те саме для npm
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# І для apt
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y curl
```

```dockerfile
# Build secret — доступний тільки під час цього RUN,
# не записується в жоден шар (на відміну від ARG/ENV, які лишаються в історії образу!)
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm ci
```

```bash
# Передати секрет зі змінної середовища під час збірки
docker build --secret id=npm_token,env=NPM_TOKEN -t myapp .
```

> **Навіщо:** без cache mount кожна зміна залежностей перекачує все заново;
> з ним кеш зберігається між збірками і не роздуває образ.
> Секрети через `--build-arg` назавжди видні в `docker history` — `--secret` там не з'являється.

### .dockerignore — обов'язково мати

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

> **Без `.dockerignore`** весь `node_modules` потрапляє в build context → збірка повільна,
> образ великий, `.env` з секретами може потрапити в образ.

### Корисні інструкції Dockerfile

| Інструкція | Що робить | Примітка |
|---|---|---|
| `FROM image AS name` | Базовий образ / початок stage | `AS name` для multi-stage |
| `WORKDIR /path` | Робоча тека (створює якщо нема) | Краще ніж `RUN mkdir && cd` |
| `COPY src dst` | Копіювати файли з context | Без розпаковки архівів |
| `ADD src dst` | Як COPY, але розпаковує `.tar` і завантажує URL | Краще використовувати COPY |
| `RUN cmd` | Виконати команду і зберегти шар | Об'єднуйте через `&&` |
| `ENV KEY=value` | Змінна середовища (в образі і контейнері) | |
| `ARG KEY=default` | Змінна тільки під час збірки (`--build-arg`) | Не видно в запущеному контейнері |
| `EXPOSE port` | Документація порту (не відкриває реально) | Потрібен `-p` при запуску |
| `VOLUME ["/data"]` | Оголосити том | |
| `USER name` | Змінити поточного користувача | Запускайте не від root |
| `ENTRYPOINT ["cmd"]` | Незамінна головна команда | Використовуйте exec-форму `[]` |
| `CMD ["arg"]` | Аргументи за замовчуванням | Замінюється при `docker run ... cmd` |
| `HEALTHCHECK` | Перевірка живості контейнера | |
| `LABEL key=value` | Метадані образу | |

---

## 4. Контейнери — запуск та керування

### Запуск

```bash
# Базовий запуск
docker run myapp:latest

# Назва + фоновий режим + порт + змінні середовища
docker run \
  --name myapp \
  -d \
  -p 8080:8080 \
  -e DB_HOST=postgres \
  -e DB_PASSWORD=secret \
  --restart unless-stopped \
  myapp:latest

# --rm: видалити контейнер після зупинки (для одноразових задач)
docker run --rm myapp:latest ./migrate.sh

# Інтерактивний режим
docker run -it --rm alpine sh
docker run -it --rm ubuntu bash
```

> `-d` — detached (фоновий режим), `-p 8080:8080` — `HOST_PORT:CONTAINER_PORT`,
> `--restart unless-stopped` — автоперезапуск, крім ручної зупинки.

### Керування контейнерами

```bash
# Список запущених контейнерів
docker ps

# Всі (включно зі зупиненими)
docker ps -a

# Зупинити / запустити / перезапустити
docker stop myapp
docker start myapp
docker restart myapp

# Зупинити примусово (SIGKILL одразу)
docker kill myapp

# Видалити контейнер (треба спочатку зупинити)
docker rm myapp
docker rm -f myapp    # зупинити і видалити одразу
```

### Корисні флаги `docker run`

| Флаг | Що робить | Приклад |
|---|---|---|
| `-d` | Фоновий (detached) режим | |
| `-it` | Інтерактивний термінал | `-it alpine sh` |
| `--rm` | Видалити після зупинки | |
| `--name` | Задати ім'я | `--name myapp` |
| `-p H:C` | Прокинути порт host:container | `-p 8080:80` |
| `-P` | Прокинути всі `EXPOSE`-порти на випадкові | |
| `-e KEY=val` | Змінна середовища | |
| `--env-file` | Змінні з файлу | `--env-file .env` |
| `-v` | Монтувати volume або bind mount | `-v data:/data` |
| `--network` | Підключити до мережі | `--network mynet` |
| `--restart` | Політика перезапуску | `--restart unless-stopped` |
| `--memory` | Ліміт RAM | `--memory 512m` |
| `--cpus` | Ліміт CPU | `--cpus 0.5` |
| `--user` | Від якого користувача | `--user 1000:1000` |
| `--read-only` | Filesystem тільки читання | |
| `--entrypoint` | Замінити entrypoint | `--entrypoint sh` |

---

## 5. Налагодження контейнерів

### Не знаєш імені контейнера? Спершу discovery

Команди нижче припускають, що ім'я контейнера відоме. На чужій машині його
зазвичай не знаєш — почни з `docker ps` і звужуй пошук:

```bash
# Хто зайняв цей порт?
docker ps --filter publish=8080

# Який контейнер щойно впав?
docker ps -a --latest
docker ps --filter status=exited

# Всі контейнери, запущені з певного образу
docker ps -a --filter ancestor=myapp:latest

# Ім'я → образ → статус одним поглядом
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

### Логи

```bash
# Переглянути логи
docker logs myapp

# Слідкувати в реальному часі
docker logs -f myapp

# Останні N рядків
docker logs --tail 100 myapp

# З часовими мітками
docker logs -t myapp

# Комбо: останні 50 рядків + follow
docker logs --tail 50 -f myapp
```

### Зайти всередину запущеного контейнера

```bash
# Shell всередині контейнера
docker exec -it myapp sh    # alpine/distroless
docker exec -it myapp bash  # ubuntu/debian

# Виконати одну команду
docker exec myapp cat /etc/hosts
docker exec myapp env | grep DB_

# Від root (якщо контейнер запущено від іншого user)
docker exec -it --user root myapp sh
```

### Контейнер падає до того як зайти

```bash
# Варіант 1: перевизначити entrypoint і покласти контейнер спати
docker run --rm -it --entrypoint sh myapp:latest

# Варіант 2: запустити з нескінченним sleep замість основного процесу
docker run --rm -it --entrypoint sleep myapp:latest infinity
# потім в іншому терміналі:
docker exec -it <container_id> sh

# Варіант 3: переглянути exit code і останній стан
docker inspect myapp --format='{{.State.ExitCode}}: {{.State.Error}}'
```

### Переглянути що всередині образу (без запуску)

```bash
# Скопіювати файл з образу (не з запущеного контейнера)
docker create --name tmp myapp:latest
docker cp tmp:/app/config.yaml ./extracted-config.yaml
docker rm tmp

# Або через тимчасовий контейнер
docker run --rm myapp:latest cat /app/config.yaml
docker run --rm myapp:latest ls -la /app/
```

### Inspect — детальна інформація

```bash
# Вся інформація про контейнер (JSON)
docker inspect myapp

# Витягти конкретне поле (jsonpath-стиль)
docker inspect myapp --format='{{.State.Status}}'
docker inspect myapp --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}'
docker inspect myapp --format='{{range .Mounts}}{{.Source}} → {{.Destination}}{{"\n"}}{{end}}'

# Переглянути змінні середовища (обережно: покаже секрети!)
docker inspect myapp --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}'
```

### Моніторинг ресурсів

```bash
# CPU / RAM / мережа в реальному часі
docker stats

# Конкретний контейнер
docker stats myapp

# Один знімок (без оновлення)
docker stats --no-stream

# Кастомний формат
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

---

## 6. Volumes та bind mounts

### Порівняння типів монтування

```
Bind Mount                    Volume                        tmpfs
──────────────────────        ──────────────────────        ──────────────────
/home/user/data  ←──────→  /var/lib/docker/volumes/     RAM (не диск)
                              mydata/_data
Ти контролюєш шлях            Docker контролює шлях         Зникає при зупинці
Зручно для розробки           Зручно для продакшну          Секрети, кеш
```

### Volumes (продакшн-підхід)

```bash
# Створити volume
docker volume create mydata

# Список volumes
docker volume ls

# Деталі (де фізично на диску)
docker volume inspect mydata

# Які контейнери використовують цей volume?
docker ps -a --filter volume=mydata

# Осиротілі volumes (не прив'язані до жодного контейнера)
docker volume ls -f dangling=true

# Використати volume при запуску
docker run -d \
  --name postgres \
  -v mydata:/var/lib/postgresql/data \
  postgres:16

# Видалити volume (обережно — дані зникнуть!)
docker volume rm mydata

# Видалити всі невикористовувані volumes
docker volume prune
```

> `mydata:/var/lib/postgresql/data` означає `volume_name:container_path`.

### Bind mount (розробка — зміни в коді без перебудови образу)

```bash
# Монтувати поточну теку всередину контейнера
docker run -d \
  --name myapp-dev \
  -p 3000:3000 \
  -v "$(pwd)":/app \
  -v /app/node_modules \
  myapp:dev

# Тепер зміни у ./src автоматично видні в контейнері
```

> **Типова проблема bind mount:** `node_modules` або `vendor` з хосту перекриває те що в контейнері.
> Рішення: додати анонімний volume `-v /app/node_modules` — він має пріоритет над bind mount.
> `$(pwd):/app` означає `host_path:container_path`.

### Резервна копія volume

```bash
# Зберегти вміст volume у tar-архів
docker run --rm \
  -v mydata:/source:ro \
  -v $(pwd):/backup \
  alpine tar czf /backup/mydata-backup.tar.gz -C /source .

# Відновити з архіву
docker run --rm \
  -v mydata:/target \
  -v $(pwd):/backup \
  alpine tar xzf /backup/mydata-backup.tar.gz -C /target
```

---

## 7. Networking

### Типи мереж

| Тип | Що це | Коли використовувати |
|---|---|---|
| `bridge` | Віртуальна мережа на хості. Контейнери ізольовані від хосту. | За замовчуванням. |
| `host` | Контейнер використовує мережевий стек хосту напряму. | Коли потрібна максимальна швидкість. |
| `none` | Без мережі. | Ізольовані задачі. |
| Custom bridge | Своя bridge-мережа. Контейнери знаходять один одного **за іменем**. | Завжди для multi-container. |
| `overlay` | Мережа між кількома Docker-хостами (Docker Swarm). | Swarm / розподілені системи. |

### Кастомна мережа (обов'язково для multi-container)

```bash
# Створити мережу
docker network create mynet

# Підключити контейнери до однієї мережі
docker run -d --name postgres --network mynet postgres:16
docker run -d --name myapp    --network mynet myapp:latest

# Тепер myapp може звертатись до postgres просто за іменем:
# DB_HOST=postgres (не треба IP!)

# Підключити існуючий контейнер до мережі
docker network connect mynet myapp

# Відключити
docker network disconnect mynet myapp

# Список мереж
docker network ls

# Деталі: хто підключений
docker network inspect mynet
```

### Порти

```bash
# -p HOST:CONTAINER — конкретний порт
docker run -p 8080:80 nginx          # localhost:8080 → контейнер:80

# -p IP:HOST:CONTAINER — тільки з певного інтерфейсу
docker run -p 127.0.0.1:8080:80 nginx  # тільки localhost, не ззовні

# -P — всі EXPOSE на випадкові порти хосту
docker run -P nginx

# Переглянути прокинуті порти
docker port myapp
```

---

## 8. Docker Compose

> **`docker compose` vs `docker-compose`:** `docker compose` (через пробіл) — це плагін
> v2, який іде в комплекті з Docker — сучасний стандарт. Окремий `docker-compose`
> (через дефіс) — застарілий v1 на Python, deprecated і вже не підтримується.
> Скрізь у цьому довіднику — тільки `docker compose`.

### Терміни

| Термін | Що це |
|---|---|
| **Service** | Один тип контейнера в compose-файлі. Може мати кілька реплік. |
| **Project** | Група сервісів з одного compose-файлу. Ізольовані мережа і volumes. |
| `depends_on` | Порядок запуску. **Не чекає** поки сервіс готовий, тільки поки запущений. |
| `healthcheck` | Перевірка готовності. `depends_on: condition: service_healthy` — чекає готовності. |

### Типовий compose.yaml для розробки

```yaml
# compose.yaml (або docker-compose.yml — обидва підтримуються)
services:

  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - DB_HOST=postgres          # ім'я сервісу = hostname в мережі
      - DB_PASSWORD=${DB_PASSWORD} # зі змінних оточення або .env файлу
    volumes:
      - .:/app                    # bind mount для live reload
      - /app/node_modules         # не перетирати node_modules
    depends_on:
      postgres:
        condition: service_healthy  # чекати поки postgres готовий

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql  # авто-ініціалізація
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

### Основні команди Compose

```bash
# Запустити всі сервіси (збудувати якщо треба)
docker compose up

# Фоновий режим
docker compose up -d

# Перебудувати образи перед запуском
docker compose up --build

# Запустити тільки один сервіс (+ його залежності)
docker compose up app

# Зупинити (зберегти volumes)
docker compose stop

# Зупинити і видалити контейнери + мережі (зберегти volumes)
docker compose down

# Зупинити і видалити ВСЕ включно з volumes (обережно!)
docker compose down -v

# Статус сервісів
docker compose ps

# Всі Compose-проєкти на цій машині (працює з будь-якої директорії)
docker compose ls

# Логи всіх сервісів
docker compose logs -f

# Логи одного сервісу
docker compose logs -f app

# Виконати команду в сервісі
docker compose exec app sh
docker compose exec postgres psql -U user -d myapp

# Перезапустити один сервіс
docker compose restart app

# Зупинити і видалити тільки один сервіс
docker compose rm -sf app
```

### Оверрайд файли (dev vs prod)

```
compose.yaml           # base (спільне для всіх середовищ)
compose.override.yaml  # dev (застосовується автоматично поверх base)
compose.prod.yaml      # prod (вказується явно)
```

```bash
# Dev (автоматично: base + override)
docker compose up

# Prod (явно вказати файли)
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

```yaml
# compose.prod.yaml — тільки відмінності від base
services:
  app:
    build:
      target: production    # multi-stage: фінальний stage
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    # немає volumes з bind mount
```

### Profiles — сервіси, що запускаються за умовою

Сервіси з profile не стартують за замовчуванням — зручно для debug-інструментів,
які потрібні лише інколи.

```yaml
services:
  app:
    build: .

  pgadmin:
    image: dpage/pgadmin4
    profiles: [debug]     # стартує тільки коли активовано профіль debug
```

```bash
# Звичайний запуск — pgadmin не стартує
docker compose up -d

# Запуск разом з профілем debug
docker compose --profile debug up -d
```

### compose watch — авто-синхронізація під час розробки

Замість bind mount Compose може сам стежити за файлами: миттєво синхронізувати
змінений код у контейнер, а перезбирати образ тільки при зміні залежностей.

```yaml
services:
  app:
    build: .
    develop:
      watch:
        - action: sync        # копіювати змінені файли в запущений контейнер
          path: ./src
          target: /app/src
        - action: rebuild     # перезібрати образ при зміні залежностей
          path: package.json
```

```bash
# Запустити сервіси та стежити за змінами файлів
docker compose up --watch

# Або окремою командою (сервіси мають бути вже описані)
docker compose watch
```

---

## 9. Registry — публікація образів

### Docker Hub

```bash
# Увійти
docker login

# Запушити образ
docker tag myapp:latest username/myapp:latest
docker push username/myapp:latest

# Запушити з версійним тегом
docker tag myapp:latest username/myapp:v1.2.0
docker push username/myapp:v1.2.0

# Витягнути образ
docker pull username/myapp:v1.2.0
```

### Приватний Registry

```bash
# Запустити локальний registry
docker run -d \
  --name registry \
  -p 5000:5000 \
  -v registry-data:/var/lib/registry \
  registry:2

# Запушити в локальний registry
docker tag myapp:latest localhost:5000/myapp:latest
docker push localhost:5000/myapp:latest

# Запушити в приватний registry з авторизацією
docker login registry.example.com
docker tag myapp:latest registry.example.com/myapp:v1.2.0
docker push registry.example.com/myapp:v1.2.0
```

### Multi-architecture образи (arm64 + amd64)

> **Коли потрібен multi-arch?** Коли машина збірки і цільові машини мають різні
> архітектури CPU: Mac на Apple Silicon (arm64) у команді, сервери AWS Graviton,
> Raspberry Pi. Збери `amd64` + `arm64` один раз — Docker сам витягне потрібний варіант.

```bash
# buildx іде в комплекті з Docker починаючи з 20.10 — створюємо multi-arch білдер
docker buildx create --use --name multiarch

# Зібрати і запушити для обох архітектур одразу
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t registry.example.com/myapp:v1.2.0 \
  --push \
  .
```

---

## 10. Очищення системи

```bash
# Переглянути використання диску
docker system df
docker system df -v   # деталізовано

# Видалити все невикористовуване (зупинені контейнери, образи без тегів, мережі, кеш збірки)
docker system prune

# Те саме + volumes (обережно — дані!)
docker system prune -a --volumes

# Видалити тільки зупинені контейнери
docker container prune

# Видалити образи без тегів (dangling)
docker image prune

# Видалити ВСІ образи не у запущених контейнерах
docker image prune -a

# Видалити build cache
docker builder prune

# Видалити невикористовувані volumes
docker volume prune
```

> **Порада:** `docker system prune` не чіпає запущені контейнери і їх volumes,
> але видаляє зупинені контейнери, dangling images, невикористані мережі й build cache.
> `-a --volumes` ще агресивніший і може прибрати дані, які ви хотіли зберегти.

---

## 11. Docker у CI/CD

### Кешування шарів у GitHub Actions

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

### Правильний тег для CI (не latest!)

```bash
# Тег = SHA коміту — унікальний, відтворюваний, відстежуваний
IMAGE_TAG=${GITHUB_SHA::8}   # перші 8 символів SHA

docker build -t myapp:${IMAGE_TAG} .
docker push myapp:${IMAGE_TAG}

# Потім деплой:
helm upgrade --install myapp ./helm/myapp \
  --set image.tag=${IMAGE_TAG}
```

> Про сам Helm (чарти, values, rollback) — дивись [helm-guide.md](helm-guide.md).

### Сканування вразливостей

```bash
# Вбудований Docker Scout (Docker Desktop)
docker scout cves myapp:latest

# Trivy (open source, популярний у CI)
# brew install trivy  /  apt install trivy
trivy image myapp:latest

# У CI — зупинити pipeline при HIGH/CRITICAL вразливостях
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:latest
```

---

## 12. Корисні аліаси та скрипти

### ~/.bashrc / ~/.zshrc

```bash
# Скорочення Docker
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
alias dimg='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'

# Зайти в контейнер
dsh() { docker exec -it "$1" sh; }
dbash() { docker exec -it "$1" bash; }

# Логи з follow
dlog() { docker logs -f --tail 100 "$1"; }

# Зупинити і видалити контейнер
drm() { docker stop "$1" && docker rm "$1"; }

# Видалити всі зупинені контейнери
alias dclean='docker container prune -f'

# Статистика одним рядком
alias dstat='docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"'

# Переглянути IP контейнера
dip() { docker inspect "$1" --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'; }
```

### Скрипт: зібрати, протегувати і запушити

```bash
#!/bin/bash
# docker-release.sh

set -e   # зупинитись при будь-якій помилці

REGISTRY=${REGISTRY:-"registry.example.com"}
IMAGE=${1:?"Вкажи назву образу: ./docker-release.sh myapp"}
TAG=${2:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}

echo "Збираємо $REGISTRY/$IMAGE:$TAG..."
docker build -t "$REGISTRY/$IMAGE:$TAG" .
docker tag "$REGISTRY/$IMAGE:$TAG" "$REGISTRY/$IMAGE:latest"

echo "Пушимо..."
docker push "$REGISTRY/$IMAGE:$TAG"
docker push "$REGISTRY/$IMAGE:latest"

echo "Готово: $REGISTRY/$IMAGE:$TAG"
```

### Скрипт: очистити старі образи (залишити останні N)

```bash
#!/bin/bash
# docker-cleanup-images.sh — залишити останні 5 образів myapp

IMAGE=${1:?"Вкажи назву образу"}
KEEP=${2:-5}

echo "Видаляємо старі теги $IMAGE (залишаємо $KEEP)..."
docker images "$IMAGE" --format "{{.Tag}}" \
  | grep -v '^latest$' \
  | tail -n "+$((KEEP + 1))" \
  | xargs -I{} docker rmi "$IMAGE:{}" 2>/dev/null || true

echo "Залишились:"
docker images "$IMAGE"
```

> **Обмеження:** скрипт орієнтується на порядок виводу `docker images`,
> тому перед масовим видаленням старих тегів список краще перевірити вручну.

---

## Шпаргалка: образи vs контейнери vs compose

```
docker build      → створити образ з Dockerfile
docker pull       → завантажити образ з registry
docker push       → запушити образ у registry
docker images     → список образів
docker rmi        → видалити образ

docker run        → створити і запустити контейнер з образу
docker start/stop → запустити/зупинити існуючий контейнер
docker ps         → список контейнерів
docker rm         → видалити контейнер
docker exec       → виконати команду в запущеному контейнері
docker logs       → переглянути логи
docker inspect    → детальна інформація (JSON)
docker cp         → копіювати файли контейнер ↔ хост

docker compose up    → запустити проект (всі сервіси)
docker compose down  → зупинити і видалити
docker compose ps    → статус сервісів
docker compose exec  → виконати команду в сервісі
docker compose logs  → логи сервісів
```

---

> **Порада:** Для продакшн-деплою не запускайте контейнери напряму через `docker run`.
> Використовуйте оркестрацію: **k3s/Kubernetes** для серйозних проектів,
> **Docker Compose** для простих single-host деплоїв.
> Docker — це пакування і збірка, Kubernetes — це запуск і керування.
