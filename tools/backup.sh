#!/bin/bash
#
# Бекап стека: дампи БД усіх WordPress-доменів + файли web/ + конфігурація.
# Ротація на 10 рівнів: BAK/0 — свіжий, BAK/9 — найстаріший.
#
# Запускати з кореня проєкту або будь-звідки — шлях визначається сам.
# У crontab:  0 4 * * *  /шлях/до/проєкту/tools/backup.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SITES_ROOT=$(awk -F= '$1 ~ /^[[:space:]]*sites_root/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' dcp.conf)
: "${SITES_ROOT:=/var/sites}"
LEVELS=9
DEST="BAK/0"

mkdir -p BAK
rm -rf "BAK/$LEVELS" 2>/dev/null || true
for i in $(seq $((LEVELS-1)) -1 0); do
    [ -d "BAK/$i" ] && mv "BAK/$i" "BAK/$((i+1))"
done
mkdir -p "$DEST"

# ── бази даних ──
# Дамп робиться всередині контейнера: на хості mysqldump не потрібен, а
# пароль береться з оточення контейнера і не світиться в списку процесів.
for domain in $(./dcpmgmt list --names --type wordpress); do
    sid=${domain//./}
    container="db-$sid"
    docker ps --format '{{.Names}}' | grep -qx "$container" || {
        echo "пропущено $domain: контейнер $container не працює" >&2
        continue
    }
    echo "дамп БД: $domain"
    docker exec "$container" sh -c \
        'exec mariadb-dump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
            --add-drop-table --complete-insert --single-transaction \
            --order-by-primary --dump-date "$MYSQL_DATABASE"' \
        | xz -z9 > "$DEST/db.$domain.sql.xz"
done

# ── файли сайтів ──
for domain in $(./dcpmgmt list --names); do
    [ -d "$SITES_ROOT/$domain/web" ] || continue
    echo "архів web: $domain"
    tar cJf "$DEST/web.$domain.tar.xz" -C "$SITES_ROOT/$domain" web
done

# ── конфігурація стека (без secrets/ — вони бекапляться окремо й інакше) ──
tar cJf "$DEST/config.tar.xz" \
    dcp.conf domains templates dcpmgmt tools \
    docker-compose.yml docker-compose.main.yml docker-compose.domains nginx

echo
echo "готово: $DEST"
du -sh "$DEST"
echo
echo "УВАГА: secrets/ сюди НЕ потрапив — це паролі БД."
echo "У режимі password_mode = derived бекапити його й не треба: досить"
echo "копії майстер-ключа (dcpmgmt secrets key), з неї каталог відновлює"
echo "команда dcpmgmt secrets restore. У режимі random зберігайте secrets/"
echo "окремо — без нього дампи відновити можна, а контейнери підняти ні."
