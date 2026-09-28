# server-administration-lab-1

### Администрирование серверов - Лабораторная работа 1

> Попова Мария Вячеславовна ИКС-23-1б

## Задача

Написать `backup.sh`, который архивирует каталог и загружает архив на FTP-сервер в заданной подсети.

```
backup.sh <dir> <ip>/<n>
backup.sh <dir> <ip> <маска>
```

## Требования

- `dir` — абсолютный путь к существующему каталогу. IP, префикс и маску проверять на корректность.
- В архиве только `dir/*`, без полного пути (`tar -C "$(dirname "$dir")" "$(basename "$dir")"`).
- По IP и маске вычислить диапазон адресов, перебирать хосты и проверять порт 21.
- Архив загрузить на первый ответивший FTP-сервер, после этого завершиться.
- Скрипт должен работать из **cron** и из **systemd** (`.service` + `.timer`).

## Стенд

Клиент, на котором запускается скрипт, и FTP-сервер, на котором хранятся копии.

Стенд поднимается через Docker Compose (`docker-compose.yml`) в сети `172.28.0.0/28`:

| Сервис  | IP          | Роль                                               |
|---------|-------------|-----------------------------------------------------|
| client  | 172.28.0.2  | клиент с полноценным systemd (PID 1) + cron         |
| decoy1  | 172.28.0.3  | хост без открытого 21 порта (для проверки перебора) |
| decoy2  | 172.28.0.4  | хост без открытого 21 порта                         |
| ftp     | 172.28.0.5  | `fauria/vsftpd`, логин/пароль `backupuser`/`backuppass` |

### Запуск

```sh
docker compose up -d --build
docker compose exec client systemctl is-system-running   # ожидаем running/degraded
```

### Ручной прогон

```sh
docker compose exec -e FTP_USER=backupuser -e FTP_PASS=backuppass \
  client backup.sh /data/mydir 172.28.0.0/28
```

Скрипт перебирает `172.28.0.1`–`172.28.0.14`, пропускает decoy-хосты (порт 21 закрыт) и заливает архив на первый ответивший — `172.28.0.5`.

### Через systemd

`docker/client/backup.service` + `docker/client/backup.timer` устанавливаются и включаются прямо в образе (`systemctl enable backup.timer`), креды берутся из `/etc/backup.env` (`EnvironmentFile=`).

```sh
docker compose exec client systemctl list-timers
docker compose exec client journalctl -u backup.service -n 20
```

### Через cron

`docker/client/crontab.example` — пример строки для `crontab -u root -`. Так как cron не читает systemd `EnvironmentFile`, креды передаются инлайн в самой строке crontab.

```sh
docker compose exec client bash -c "crontab -u root -" < docker/client/crontab.example
docker compose exec client cat /var/log/backup-cron.log
```
