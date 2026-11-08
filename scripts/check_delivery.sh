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
    docker run --rm -i --network "container:$database" \
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
INSERT INTO groups (name) VALUES ('ДЕМО-01');
INSERT INTO users (max_user_id,group_id,institution_code) SELECT 900000001,id,'akvt' FROM groups;
INSERT INTO homework (group_id,owner_id,subject,body) SELECT id,900000001,'ДЕМО','delivery-test' FROM groups;
INSERT INTO homework_files SELECT id,1,'test.txt',decode('68656c6c6f','hex') FROM homework;
INSERT INTO useful_materials (category,title,body,link) VALUES ('study','ДЕМО','delivery-test','');
INSERT INTO useful_files SELECT id,1,'test.txt',decode('68656c6c6f','hex') FROM useful_materials;
INSERT INTO form_drafts SELECT 900000001,'homework',
 jsonb_build_object('group',id,'shared',false,'body','delivery-test','files',
 jsonb_build_array(jsonb_build_array('test.txt',jsonb_build_object('$bytes','aGVsbG8=')))),
 clock_timestamp()+interval '1 hour' FROM groups;
SQL
compose down
compose up -d migrate
database=$(compose ps -q postgres)
test "$(compose exec -T postgres psql -U podzemelye -d podzemelye_test -Atc "SELECT encode(data,'hex') FROM delivery_probe")" = 68656c6c6f
test "$(compose exec -T postgres psql -U podzemelye -d podzemelye_test -Atc "SELECT count(*) FROM form_drafts")" = 1
run_test python - <<'PYCODE'
import os
from app.db import Database
from app.handlers.homework import HomeworkHandler
from app.services.form_drafts import load
handler=HomeworkHandler()
with Database(os.environ['TEST_DATABASE_URL']).connect() as conn:
    for table in ('homework_files','useful_files'):
        assert conn.execute('SELECT data FROM '+table).fetchone()==(b'hello',)
    load(conn,900000001,[handler])
    assert handler.drafts[900000001].body=='delivery-test'
    assert handler.drafts[900000001].files==[['test.txt',b'hello']]
print('Вложения и корректный черновик прочитаны после пересоздания контейнеров.')
PYCODE
compose exec -T postgres pg_dump -U podzemelye -d podzemelye_test -Fc > "$root/.delivery-backup.dump"
compose exec -T postgres createdb -U podzemelye restore_test
compose exec -T postgres pg_restore -U podzemelye -d restore_test --exit-on-error < "$root/.delivery-backup.dump"
test "$(compose exec -T postgres psql -U podzemelye -d restore_test -Atc "SELECT encode(data,'hex') FROM delivery_probe")" = 68656c6c6f
test "$(compose exec -T postgres psql -U podzemelye -d restore_test -Atc "SELECT count(*) FROM form_drafts")" = 1
test "$(compose exec -T postgres psql -U podzemelye -d restore_test -Atc "SELECT encode(data,'hex') FROM homework_files")" = 68656c6c6f
test "$(compose exec -T postgres psql -U podzemelye -d restore_test -Atc "SELECT encode(data,'hex') FROM useful_files")" = 68656c6c6f
rm "$root/.delivery-backup.dump"
docker tag "$image" podzemelye-jury:tested
echo "Поставка: smoke, bootstrap/SIGINT, данные/формы после перезапуска, backup/restore — OK."
