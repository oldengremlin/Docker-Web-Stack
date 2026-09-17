#!/bin/bash
#
# Оновлення інсталяції з клону репозиторію: dcpmgmt, templates/, tools/.
#
# Запускати ЗАВЖДИ з клону — він знає, що копіювати. В інсталяції може
# лежати як завгодно стара версія, яка про цю команду й не чула.
#
#   cd ~/src/Docker-Web-Stack && tools/deploy.sh ../docker-compose-project
#   cd ~/src/docker-compose-project && ../Docker-Web-Stack/tools/deploy.sh .
#
# Не чіпає нічого, що належить інсталяції: domains/, secrets/, dcp.conf,
# nginx/, docker-compose*.yml. Тільки інструмент і шаблони.
#
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ARG="${1:-}"

[ -n "$DEST_ARG" ] || {
    echo "вжиток: $0 <каталог інсталяції>" >&2
    echo "приклад: $0 ../docker-compose-project" >&2
    exit 1
}
[ -d "$DEST_ARG" ] || { echo "немає такого каталогу: $DEST_ARG" >&2; exit 1; }
DEST="$(cd "$DEST_ARG" && pwd)"

[ "$SRC" != "$DEST" ] || {
    echo "джерело і призначення — той самий каталог ($SRC)." >&2
    echo "Запускайте з клону, вказуючи каталог інсталяції." >&2
    exit 1
}

# Порожній каталог — це перший розгортання, так і задумано. А от
# непорожній чужий каталог засипати файлами не будемо: надто легко
# помилитися шляхом і не помітити.
if [ -e "$DEST/dcp.conf" ] || [ -d "$DEST/domains" ] || [ -f "$DEST/dcpmgmt" ]; then
    :
elif [ -z "$(ls -A "$DEST")" ]; then
    echo "  info  $DEST порожній — розгортаємо інсталяцію з нуля"
else
    echo "$DEST не схожий на інсталяцію dcpmgmt: немає ні dcp.conf, ні domains/," >&2
    echo "ні dcpmgmt, але каталог і не порожній. Перевірте шлях." >&2
    exit 1
fi

was='—'
[ -x "$DEST/dcpmgmt" ] && was="$("$DEST/dcpmgmt" version 2>/dev/null || echo '?')"

mkdir -p "$DEST/templates" "$DEST/tools"

install -m 755 "$SRC/dcpmgmt" "$DEST/dcpmgmt"
echo "  ok   dcpmgmt"

for f in "$SRC"/templates/*.tmpl; do
    install -m 644 "$f" "$DEST/templates/$(basename "$f")"
    echo "  ok   templates/$(basename "$f")"
done

for f in "$SRC"/tools/*; do
    [ -f "$f" ] || continue
    install -m 755 "$f" "$DEST/tools/$(basename "$f")"
    echo "  ok   tools/$(basename "$f")"
done

# Шаблон, якого в репозиторії вже немає, лишається в інсталяції назавжди
# і мовчки бере участь у генерації. Копіювання його не прибирає, тож
# принаймні скажемо.
for f in "$DEST"/templates/*.tmpl; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -f "$SRC/templates/$b" ] || echo " увага templates/$b є в інсталяції, але не в репозиторії"
done

echo
echo "було:  $was"
printf 'стало: '
cd "$DEST" && ./dcpmgmt version
