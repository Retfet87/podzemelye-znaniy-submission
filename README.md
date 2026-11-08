# Подземелье знаний

Команда «Четыре мушкетёра». Хакатон «Идея фикс», номинация «Продвинутая разработка».

MAX-бот помогает студентам следить за расписанием, заданиями и мероприятиями своей группы. Это полная поставка бота из [исходного проекта](https://github.com/Retfet87/podzemelye-znaniy), релизный commit `e03fdd4f7beb65329b99891cdab1eb4f1d448d1a`. История разработки и отдельный демонстрационный сайт остаются в исходном репозитории. Авторство и происхождение проекта сохранены; при разработке использовались инструменты ИИ.

## Возможности

- Регистрация и выбор группы, персональная сводка, расписание текущей и следующей недели, числитель/знаменатель, разделённые пары и экспорт ICS.
- XLS: предпросмотр, подтверждение супер-администратором, отдельные замены на дату и базовое расписание, история изменений.
- Общие и личные домашние задания, кнопочный календарь, необязательные сроки, файлы, сохранённые формы.
- Мероприятия, RSVP без повторной записи, полезные материалы, текст, ссылки, изображения и видео.
- Роли, контекстные вопросы, PostgreSQL-очередь уведомлений с повторами, ограничением частоты и защитой от дублей. Абсолютная exactly-once доставка не обещается.

Контакты, расписание и данные студентов не включены. Новая база изначально пустая; администратор добавляет проверенные сведения. Даты без подтверждённого расписания так и обозначаются.

## Технологии и структура

Python 3.12, MAX Bot API (Long Polling), PostgreSQL 16, psycopg, xlrd, Pillow, ffmpeg/ffprobe. Версии Python-пакетов закреплены в `requirements.txt`.

`main.py` собирает зависимости в `app/bootstrap.py`; `handlers/` обрабатывают события и проверяют права, `services/` содержат правила, `repositories/` выполняют SQL, `db/` управляет соединениями и миграциями, `notifications/` доставляет очередь, `max_api/` работает с MAX. `migrations/` содержит все семь миграций. Вложения хранятся в PostgreSQL и сохраняются вместе с томом базы.

## Требования и настройка

Для Docker нужен Docker Engine с Compose v2. Для запуска без Docker — Python 3.12, локальная PostgreSQL 16, ffmpeg и ffprobe в PATH для видео. Нужен собственный токен MAX-бота.

```sh
git clone https://github.com/Retfet87/podzemelye-znaniy-submission.git
cd podzemelye-znaniy-submission
cp .env.example .env
chmod 600 .env
```

Отредактируй `.env`: задай `POSTGRES_PASSWORD` и `MAX_BOT_TOKEN`. `MAX_SUPER_ADMIN_ID` — MAX ID единственного супер-администратора, необязателен; пустое значение никому не выдаёт эти права. Никогда не публикуй `.env`. Флаги `*_NOTIFICATIONS_ENABLED` изначально равны `0`; после проверки адресатов включи нужные в `1`. Временная зона учебных дат — Астрахань (UTC+4).

**Один токен — один Long Polling.** Не запускай копию с токеном действующего бота на другом компьютере. Блокировка PostgreSQL защищает экземпляры одной базы, но не разные базы с одним токеном.

## Сборка Docker-образа

```sh
docker build --pull --no-cache -t podzemelye-znaniy-submission:local .
```

Образ включает Python 3.12, ffmpeg/ffprobe, доверенный публичный TLS-сертификат и приветственную иллюстрацию. Работает от пользователя 10001; рабочая конфигурация и тесты в образ не копируются.

## Запуск Docker Compose и миграции

```sh
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --build migrate
docker compose --env-file .env --profile live up -d --build bot
docker compose --env-file .env logs -f bot
```

`migrate` ждёт PostgreSQL и применяет SQL-миграции до старта бота. Для повторного применения:

```sh
docker compose --env-file .env run --rm migrate
```

Том `pgdata` сохраняет базу и все вложения при перезапуске/пересоздании контейнеров. Не используй `down -v` для рабочей базы.

## Публичный образ и docker run

[GHCR package](https://github.com/Retfet87/podzemelye-znaniy-submission/pkgs/container/podzemelye-znaniy-submission): `ghcr.io/retfet87/podzemelye-znaniy-submission:latest`. Для воспроизводимого запуска выбери тег commit SHA или digest в журнале успешной GitHub Actions сборки.

Следующий вариант использует PostgreSQL из Compose; не запускай его одновременно с Compose-сервисом `bot`:

```sh
docker pull ghcr.io/retfet87/podzemelye-znaniy-submission:latest
docker compose -p jury --env-file .env up -d postgres
docker run --rm --network jury_default --env-file .env -e BOT_CONFIG_MODE=compose ghcr.io/retfet87/podzemelye-znaniy-submission:latest python manage.py migrate
docker run -d --name jury-bot --init --stop-signal SIGINT --stop-timeout 50 --network jury_default --env-file .env -e BOT_CONFIG_MODE=compose ghcr.io/retfet87/podzemelye-znaniy-submission:latest
docker logs -f jury-bot
```

## Запуск Python и подготовка данных

Для Python укажи в `.env` `DATABASE_URL` с хостом `127.0.0.1` или `::1` и своей базой; специальные символы пароля кодируются в URL. Compose не публикует PostgreSQL наружу: для этого варианта нужна отдельно настроенная локальная PostgreSQL. Не устанавливай `BOT_CONFIG_MODE=compose` вне контейнера.

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python manage.py migrate
python manage.py add-groups ВЕБ-11 ПБ-22
python main.py
```

TLS проверяется штатно. `MAX_CA_FILE` добавляет доверенный сертификат к системным, не отключая проверку.

Для XLS сначала проверь файл без записи:

```sh
python manage.py inspect-schedule /path/to/schedule.xls
python manage.py import-schedule --help
```

При импорте явно задаются область `base` или `date`, даты действия и при необходимости понедельник числителя. Без `--stage` выполняется только предпросмотр; публикация черновика требует подтверждения супер-администратором в MAX. Не копируй диапазон дат чужого учебного года. Через Compose те же команды доступны как `docker compose run --rm -v /path/to/schedule.xls:/data/schedule.xls:ro migrate python manage.py inspect-schedule /data/schedule.xls`.

## Остановка и резервная копия

```sh
docker compose --env-file .env stop bot
docker compose --env-file .env down
# Для варианта docker run:
docker stop jury-bot
```

Python в терминале останавливается Ctrl+C. Перед обновлением делай backup; приведённый сценарий не удаляет прежние архивы:

```sh
mkdir -p backups
BACKUP_UID=$(id -u) BACKUP_GID=$(id -g) docker compose --env-file .env run --rm backup
```

Проверь восстановление в отдельную новую базу, а не поверх рабочей:

```sh
docker compose exec postgres sh -c 'createdb -U "$POSTGRES_USER" restore_check'
docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d restore_check --exit-on-error' < backups/ИМЯ_АРХИВА.dump
```

## Безопасная автоматическая проверка

```sh
sh scripts/check_delivery.sh
```

Нужен Docker. Команда создаёт отдельную тестовую PostgreSQL, проверяет миграции, импорт модулей/ресурсов, сквозной сценарий с подставным MAX API, полный bootstrap и корректную остановку, сохранность данных и восстановление backup. Рабочая `.env` не читается, рабочий токен не используется, настоящие сообщения не отправляются. Временная база удаляется после проверки. В GitHub Actions дополнительно запускаются применимые регрессии исходного релиза; полный набор внутренних тестов в эту поставку не включён.

## Ссылки

[MAX-бот](https://max.ru/ideya_fiks_90_bot) · [GitHub](https://github.com/Retfet87/podzemelye-znaniy-submission) · [Docker-образ](https://github.com/Retfet87/podzemelye-znaniy-submission/pkgs/container/podzemelye-znaniy-submission).

`assets/welcome.png` — оригинальная иллюстрация проекта, созданная генератором изображений, не скачанная со стороннего сайта. Сертификат в `certificates/` — публичный корневой сертификат, не секретный ключ. Отдельная лицензия на код в исходном релизе не указана; эта поставка не добавляет новых лицензионных условий и не изменяет авторство.
