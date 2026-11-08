#!/bin/sh
# Используется отдельный проект Compose, без чтения рабочей конфигурации и MAX.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "Docker Engine недоступен. Запусти эту проверку на машине с Docker или в Actions." >&2
    exit 2
fi
project="jury-check-$$"
export POSTGRES_DB=podzemelye_test POSTGRES_USER=podzemelye
export POSTGRES_PASSWORD=isolated-delivery-test-password
export MAX_BOT_TOKEN= MAX_SUPER_ADMIN_ID= COMPOSE_PROFILES=
export SCHEDULE_NOTIFICATIONS_ENABLED=0 HOMEWORK_NOTIFICATIONS_ENABLED=0 EVENT_NOTIFICATIONS_ENABLED=0
compose() { docker compose --env-file /dev/null -p "$project" -f "$root/docker-compose.yml" "$@"; }
probe="${project}-offline"
cleanup() {
    docker rm -f "$probe" >/dev/null 2>&1 || true
    compose down --volumes --remove-orphans
}
trap cleanup EXIT HUP INT TERM
compose config --quiet
compose build --pull --no-cache migrate
compose up -d migrate
compose run --rm -T migrate python manage.py migrate
image=$(compose images -q migrate | head -n 1)
database=$(compose ps -q postgres)
test_url="postgresql://podzemelye:$POSTGRES_PASSWORD@127.0.0.1:5432/podzemelye_test"
run_test() {
    docker run --rm --network "container:$database" \
      --volume "$root/tests:/app/tests:ro" --volume "$root/scripts:/app/scripts:ro" \
      --env "TEST_DATABASE_URL=$test_url" "$image" "$@"
}
run_test python -m unittest tests.test_delivery -v
run_test python -m scripts.smoke_test
if [ -d "$root/.validation-tests" ]; then
    docker run --rm --network "container:$database" \
      --volume "$root/.validation-tests:/app/tests:ro" --volume "$root/scripts:/app/scripts:ro" \
      --env "TEST_DATABASE_URL=$test_url" "$image" python -m unittest discover -s tests -v
fi
# Полный entrypoint, настоящий lease, обработчик SIGINT и закрытие соединений.
docker run -d --name "$probe" --stop-signal SIGINT --stop-timeout 10 \
  --network "container:$database" --volume "$root/tests:/app/tests:ro" \
  --volume "$root/scripts:/app/scripts:ro" --env "TEST_DATABASE_URL=$test_url" \
  "$image" python -m tests.offline_bot >/dev/null
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if docker logs "$probe" 2>&1 | grep -q OFFLINE_READY; then ready=1; break; fi
    sleep 1
done
test "$ready" -eq 1
docker stop "$probe" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "$probe")" -eq 0
docker logs "$probe" 2>&1 | grep -q 'Бот остановлен'
docker rm "$probe" >/dev/null
run_test python -m unittest tests.test_delivery -v
# Содержимое файла в БД и сохранённая форма переживают пересоздание сервера.
compose exec -T postgres psql -U podzemelye -d podzemelye_test -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE delivery_probe (id int primary key, data bytea);
INSERT INTO delivery_probe VALUES (1,decode('68656c6c6f','hex'));
INSERT INTO form_drafts VALUES (900000001,'homework','{"group_id":1,"shared":false,"body":"delivery-test"}',clock_timestamp()+interval '1 hour');
SQL
compose down
compose up -d migrate
test "$(compose exec -T postgres psql -U podzemelye -d podzemelye_test -Atc "SELECT encode(data,'hex') FROM delivery_probe")" = 68656c6c6f
test "$(compose exec -T postgres psql -U podzemelye -d podzemelye_test -Atc "SELECT count(*) FROM form_drafts")" = 1
compose exec -T postgres pg_dump -U podzemelye -d podzemelye_test -Fc > "$root/.delivery-backup.dump"
compose exec -T postgres createdb -U podzemelye restore_test
compose exec -T postgres pg_restore -U podzemelye -d restore_test --exit-on-error < "$root/.delivery-backup.dump"
test "$(compose exec -T postgres psql -U podzemelye -d restore_test -Atc "SELECT encode(data,'hex') FROM delivery_probe")" = 68656c6c6f
test "$(compose exec -T postgres psql -U podzemelye -d restore_test -Atc "SELECT count(*) FROM form_drafts")" = 1
rm "$root/.delivery-backup.dump"
docker tag "$image" podzemelye-jury:tested
echo "Поставка: smoke, bootstrap/SIGINT, данные/формы после перезапуска, backup/restore — OK."
