# Linux — Практичний довідник девелопера

> Не просто команди. Сценарії реального щоденного використання.

---

## Зміст

1. [Що таке Linux у щоденній роботі](#1-що-таке-linux-у-щоденній-роботі)
2. [Filesystem та навігація](#2-filesystem-та-навігація)
3. [Права доступу та власники](#3-права-доступу-та-власники)
4. [Процеси та фонові задачі](#4-процеси-та-фонові-задачі)
5. [Networking і перевірка з'єднання](#5-networking-і-перевірка-зєднання)
6. [systemd та керування сервісами](#6-systemd-та-керування-сервісами)
7. [Пакети та встановлення софту](#7-пакети-та-встановлення-софту)
8. [Логи та діагностика](#8-логи-та-діагностика)
9. [Дисковий простір та очищення](#9-дисковий-простір-та-очищення)
10. [SSH, curl, tar та інші щоденні інструменти](#10-ssh-curl-tar-та-інші-щоденні-інструменти)
11. [Дебаг — від хаотичного до системного](#11-дебаг--від-хаотичного-до-системного)
12. [Корисні аліаси та скрипти](#12-корисні-аліаси-та-скрипти)

---

## 1. Що таке Linux у щоденній роботі

Linux для девелопера зазвичай це:

- локальне робоче середовище
- віддалена VM через SSH
- хмарний сервер
- CI runner
- хостова ОС для Docker / Kubernetes нод

Ключова ідея:

```
Застосунок
    ↓
Процес
    ↓
Файли + порти + змінні середовища + права доступу
    ↓
Linux kernel
```

Якщо ви вмієте перевіряти:

- файли
- процеси
- порти
- логи
- сервіси
- права доступу

то зазвичай можете пояснити, чому система працює або ламається.

### Швидка ментальна модель

| Об'єкт | Що це означає на практиці |
|---|---|
| **Process** (процес) | Запущена програма з PID, змінними середовища, відкритими файлами, сокетами та користувачем. |
| **Service** (сервіс) | Процес під керуванням `systemd`, який автоматично запускається/рестартується. |
| **File descriptor** | Відкритий дескриптор до файлу, pipe або socket. |
| **User / group** | Ідентичність, під якою працює процес. Визначає доступ. |
| **Permission bits** | Права на читання/запис/виконання для owner, group та others. |
| **Package manager** | Інструмент встановлення ПЗ та оновлень: `apt`, `dnf`, `yum`, `apk` тощо. |
| **Shell** | Інтерактивне командне середовище: `bash`, `zsh`, `sh`. |
| **Daemon** | Довгоживучий фоновий сервіс. |
| **stdout / stderr** | Стандартні потоки виводу і помилок. Часто саме вони потрапляють у логи. |

---

## 2. Filesystem та навігація

### Важливі теки

| Шлях | Що це |
|---|---|
| `/` | Корінь файлової системи. |
| `/home/<user>` | Домашні теки користувачів. |
| `/root` | Домашня тека користувача `root`. |
| `/etc` | Системні конфіги. |
| `/var/log` | Логи. |
| `/var/lib` | Постійний стан застосунків. |
| `/tmp` | Тимчасові файли. Часто очищається автоматично. |
| `/usr/bin` | Встановлені виконувані файли. |
| `/opt` | Опційне / вручну встановлене ПЗ. |
| `/proc` | Віртуальна файлова система з інформацією про процеси та kernel. |

### Щоденна навігація

```bash
# Де я?
pwd

# Список файлів
ls
ls -la

# Переміщення
cd /etc
cd ~
cd -

# Створення тек
mkdir project
mkdir -p app/config/nginx

# Копіювати / переміщати / видаляти
cp file.txt backup.txt
cp -r src/ dst/
mv old.txt new.txt
rm file.txt
rm -r old-dir/
```

> `rm -r` дуже потужна команда. Перед Enter ще раз перевіряйте шлях.

### Швидко знайти файли

```bash
# Пошук за іменем
find . -name "*.log"

# Пошук великих файлів
find /var -type f -size +100M 2>/dev/null

# Швидкий пошук тексту всередині файлів
rg "DATABASE_URL"
rg "listen 8080" /etc

# Показати лише файли зі збігом
rg -l "TODO"
```

### Перегляд вмісту файлів

```bash
cat config.yaml
less /var/log/syslog
head -n 20 file.txt
tail -n 50 app.log
tail -f app.log
```

### Посилання

```bash
# Символічне посилання
ln -s /opt/myapp/current/bin/myapp /usr/local/bin/myapp

# Куди вказує symlink
ls -l /usr/local/bin/myapp
readlink -f /usr/local/bin/myapp
```

---

## 3. Права доступу та власники

### Подивитись owner і mode

```bash
ls -l deploy.sh
# -rwxr-xr-- 1 admin dev 1234 Mar 29 12:00 deploy.sh
```

Розбір:

```text
-rwxr-xr--
 ||| ||| ||
 ||| ||| |└─ others
 ||| ||| └── group
 ||| └──── owner
 └──────── тип файлу
```

### chmod

```bash
# Зробити скрипт виконуваним
chmod +x deploy.sh

# Читання/запис для owner, читання для group/others
chmod 644 config.yaml

# rwx для owner, rx для group/others
chmod 755 deploy.sh
```

### chown

```bash
# Змінити owner
sudo chown appuser config.yaml

# Змінити owner і group рекурсивно
sudo chown -R appuser:appgroup /srv/myapp
```

### sudo vs root

```bash
# Запустити одну команду від root
sudo systemctl restart nginx

# Відкрити root shell
sudo -i
```

> Краще використовувати `sudo <command>`, ніж довго працювати всередині root shell.

### Погано vs правильно

```bash
# Погано: дати всім повні права
chmod -R 777 /srv/myapp

# Правильно: виправити owner і залишити нормальні mode
sudo chown -R myapp:myapp /srv/myapp
find /srv/myapp -type d -exec chmod 755 {} \;
find /srv/myapp -type f -exec chmod 644 {} \;
chmod +x /srv/myapp/bin/start.sh
```

---

## 4. Процеси та фонові задачі

### Переглянути процеси

```bash
ps aux
ps aux | grep nginx
pgrep -a python
top
htop
```

### Зрозуміти процес

```bash
# Дерево процесів
ps -ef --forest

# Якою командою запущено PID 1234?
ps -fp 1234

# Який користувач його запускає?
ps -o user,pid,ppid,%cpu,%mem,cmd -p 1234
```

### Зупинити процес

```bash
kill 1234          # SIGTERM — м'яка зупинка
kill -9 1234       # SIGKILL — примусова зупинка
pkill -f "python app.py"
```

> `kill -9` варто використовувати тільки коли звичайне завершення не спрацювало.

### Фонові задачі в поточному shell

```bash
sleep 300 &
jobs
fg %1
bg %1
```

### Який процес зайняв порт?

```bash
ss -ltnp
sudo ss -ltnp | grep :8080
sudo lsof -i :8080
```

---

## 5. Networking і перевірка з'єднання

### Базові перевірки

```bash
# Інтерфейси та IP-адреси
ip addr

# Маршрути
ip route

# DNS-резолв
getent hosts example.com
dig example.com
nslookup example.com

# Перевірити з'єднання
ping 8.8.8.8
ping example.com
```

### Чи слухає сервіс порт

```bash
ss -ltn
ss -ltnp | grep :80
ss -lunp | grep :53
```

### Швидко протестувати HTTP

```bash
curl http://localhost:8080/health
curl -I https://example.com
curl -v https://api.example.com
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/me
```

### Перевірити віддалений порт

```bash
nc -vz example.com 443
telnet example.com 443
```

### Основи firewall

```bash
# Ubuntu / Debian
sudo ufw status
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp

# RHEL-подібні системи
sudo firewall-cmd --list-all
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload
```

---

## 6. systemd та керування сервісами

Більшість сучасних Linux-дистрибутивів використовують `systemd`.

### Основні команди

```bash
sudo systemctl status nginx
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx
sudo systemctl reload nginx
sudo systemctl enable nginx
sudo systemctl disable nginx
```

### Зрозуміти, чому сервіс впав

```bash
systemctl status myapp
journalctl -u myapp -n 100
journalctl -u myapp -f
```

### Приклад service-файлу

```ini
[Unit]
Description=My Python App
After=network.target

[Service]
User=myapp
WorkingDirectory=/srv/myapp
Environment=PORT=8080
ExecStart=/usr/bin/python3 /srv/myapp/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Зберегти як:

```text
/etc/systemd/system/myapp.service
```

Потім:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
```

### Типовий шаблон поломки

```text
systemctl status myapp
  → сервіс одразу завершується
journalctl -u myapp
  → "No such file or directory"
ps / ls / sudo -u myapp ...
  → неправильний шлях, права, env var або відсутній binary
```

---

## 7. Пакети та встановлення софту

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install curl git nginx
apt list --installed | grep nginx
sudo apt remove nginx
sudo apt purge nginx
sudo apt autoremove
```

### RHEL / Rocky / Alma / CentOS Stream / Fedora

```bash
sudo dnf install curl git nginx
sudo dnf remove nginx
sudo dnf update
```

### Alpine

```bash
sudo apk add curl git nginx
sudo apk del nginx
sudo apk update
```

### Перевірити шлях до binary

```bash
which python3
command -v kubectl
type docker
```

### Package manager vs ручне встановлення

```bash
# Краще через package manager, якщо можливо
sudo apt install jq

# Вручну бінарник ставимо тільки коли це справді потрібно
sudo install -m 0755 ./kubectl /usr/local/bin/kubectl
```

---

## 8. Логи та діагностика

### Читати системні логи

```bash
journalctl -xe
journalctl -b              # поточне завантаження
journalctl -b -1           # попереднє завантаження
journalctl -u nginx -n 100
journalctl -u nginx -f
```

### Класичні log-файли

```bash
ls /var/log
tail -f /var/log/syslog
tail -f /var/log/messages
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### Перевірити оточення і runtime-деталі

```bash
env | sort
uname -a
hostnamectl
uptime
date
timedatectl
```

### Дослідити стан процесу під час роботи

```bash
# Відкриті файли
sudo lsof -p 1234

# Змінні середовища процесу
tr '\0' '\n' < /proc/1234/environ

# Поточна робоча тека процесу
readlink /proc/1234/cwd
```

---

## 9. Дисковий простір та очищення

### Подивитись вільне місце

```bash
df -h
df -i
```

### Знайти, що займає місце

```bash
du -sh .
du -sh /var/log/*
du -sh /var/lib/*
du -xh / | sort -h | tail -n 30
```

> `du -xh /` може бути дорогим на великих системах. Використовуйте обережно.

### Великі видалені файли все ще зайняті процесом

Іноді диск повний навіть після видалення файлів. Причина:

- файл видалили з дерева каталогів
- але якийсь процес все ще тримає його відкритим

```bash
sudo lsof +L1
```

Виправлення:

- перезапустити процес
- або акуратно його зупинити

### Очищення логів

```bash
sudo journalctl --disk-usage
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=500M
```

---

## 10. SSH, curl, tar та інші щоденні інструменти

### SSH

```bash
ssh user@server
ssh -i ~/.ssh/prod.pem ubuntu@10.0.0.5
scp file.txt user@server:/tmp/
scp user@server:/etc/nginx/nginx.conf .
rsync -avz ./app/ user@server:/srv/app/
```

### tar

```bash
# Створити архів
tar -czf backup.tar.gz /etc/myapp

# Розпакувати архів
tar -xzf backup.tar.gz

# Подивитись вміст
tar -tzf backup.tar.gz
```

### curl + jq

```bash
curl -s https://api.github.com/repos/torvalds/linux | jq .
curl -s http://localhost:8080/health | jq .
```

### Обробка тексту

```bash
cat access.log | grep 500
sort users.txt | uniq
cut -d: -f1 /etc/passwd
awk '{print $1, $9}' access.log
```

> Якщо не потрібен pipeline, краще `grep pattern file`, ніж `cat file | grep pattern`.

---

## 11. Дебаг — від хаотичного до системного

### Поганий підхід

```text
Сервіс не працює
  → тричі перезапустити
  → навмання редагувати конфіги
  → chmod -R 777
  → вбити випадкові процеси
  → система все ще зламана
```

### Кращий підхід

```text
1. Чітко сформулювати симптом
   "Порт 8080 не відповідає"

2. Перевірити процес
   ps / systemctl / journalctl

3. Перевірити порт
   ss -ltnp | grep :8080

4. Перевірити локальний запит
   curl http://127.0.0.1:8080/health

5. Перевірити мережевий шлях
   ip route / firewall / reverse proxy / DNS

6. Перевірити конфіг і права доступу
   ls -l /etc/... / env / working directory / user
```

### Типові кейси з реального життя

| Симптом | Типова причина | Перші команди |
|---|---|---|
| `Permission denied` | Неправильний owner/mode, відсутній execute bit | `ls -l`, `id`, `namei -l <path>` |
| `Address already in use` | Інший процес уже слухає порт | `ss -ltnp`, `lsof -i :PORT` |
| Сервіс крутиться в restart loop | Невірний `ExecStart`, бракує файлу, поганий env var | `systemctl status`, `journalctl -u` |
| DNS-ім'я не резолвиться | Проблема з resolver або DNS-конфігом | `getent hosts`, `dig`, `cat /etc/resolv.conf` |
| Диск переповнений | Логи, кеш, видалені-але-відкриті файли | `df -h`, `du -sh`, `lsof +L1` |

---

## 12. Корисні аліаси та скрипти

### Аліаси

```bash
alias ll='ls -lah'              # детальний список файлів, включно з прихованими
alias ..='cd ..'                # піднятись на одну теку вище
alias ...='cd ../..'            # піднятись на дві теки вище
alias psg='ps aux | grep -i'    # шукати процеси за назвою
alias ports='ss -ltnp'          # показати TCP-порти, що слухають, разом із процесами
alias jfu='journalctl -fu'      # дивитись логи systemd unit у реальному часі
alias dfh='df -h'               # показати вільне місце на файлових системах у зручному форматі
alias duh='du -sh'              # показати сумарний розмір теки у зручному форматі
```

### Функція: швидка діагностика порту

```bash
portcheck() {
  local port=${1:?"Usage: portcheck <port>"}
  echo "==> Listeners on :$port"
  sudo ss -ltnp | grep ":$port" || true
  echo
  echo "==> lsof"
  sudo lsof -i :"$port" || true
}
```

### Функція: швидка діагностика сервісу

```bash
svcdiag() {
  local svc=${1:?"Usage: svcdiag <service>"}
  systemctl status "$svc" --no-pager
  echo
  journalctl -u "$svc" -n 50 --no-pager
}
```

### Фінальний принцип

Linux стає керованим, коли ви зводите будь-яку проблему до п'яти питань:

- який процес бере участь
- під яким користувачем він працює
- які файли йому потрібні
- який порт він слухає
- що кажуть логи

Цього зазвичай достатньо, щоб розв'язати 80% щоденних інфраструктурних проблем.
