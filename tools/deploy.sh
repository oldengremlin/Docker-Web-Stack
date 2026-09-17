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
# Типово спершу робить git pull у клоні. Вимкнути — --no-pull; умовчання
# для себе можна задати змінною DCP_DEPLOY (--pull або --no-pull), а ключ
# у рядку команди її перекриває.
#
# Не чіпає нічого, що належить інсталяції: domains/, secrets/, dcp.conf,
# nginx/, docker-compose*.yml. Тільки інструмент і шаблони.
#
set -euo pipefail

main() {
    local SRC
    SRC="$(cd "$(dirname "$0")/.." && pwd)"

    local pull=1 dest='' a
    local -a argv=()
    # Словорозділення тут навмисне: у змінній лежить рядок ключів.
    [ -n "${DCP_DEPLOY:-}" ] && argv+=(${DCP_DEPLOY})
    [ $# -gt 0 ] && argv+=("$@")

    for a in ${argv+"${argv[@]}"}; do
        case "$a" in
            --pull)    pull=1 ;;
            --no-pull) pull=0 ;;
            -*)        echo "невідомий ключ: $a" >&2; exit 1 ;;
            *)         dest="$a" ;;
        esac
    done

    [ -n "$dest" ] || {
        echo "вжиток: $0 [--pull|--no-pull] <каталог інсталяції>" >&2
        echo "приклад: $0 ../docker-compose-project" >&2
        exit 1
    }
    [ -d "$dest" ] || { echo "немає такого каталогу: $dest" >&2; exit 1; }

    local DEST
    DEST="$(cd "$dest" && pwd)"
    [ "$SRC" != "$DEST" ] || {
        echo "джерело і призначення — той самий каталог ($SRC)." >&2
        echo "Запускайте з клону, вказуючи каталог інсталяції." >&2
        exit 1
    }

    # Порожній каталог — це перше розгортання, так і задумано. А от
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

    if [ "$pull" -eq 1 ]; then
        if ! git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
            echo " увага $SRC не є git-репозиторієм — pull пропущено"
        elif [ -n "$(git -C "$SRC" status --porcelain)" ]; then
            echo " увага у клоні є незакомічені зміни — pull пропущено, розгортаю як є"
        else
            echo "  info  git pull --ff-only у $SRC"
            # --ff-only: мовчазний merge-комміт у чужому клоні — не те, по
            # що сюди приходять.
            git -C "$SRC" pull --ff-only
        fi
    fi

    local was='—'
    [ -x "$DEST/dcpmgmt" ] && was="$("$DEST/dcpmgmt" version 2>/dev/null || echo '?')"

    mkdir -p "$DEST/templates" "$DEST/tools"

    install -m 755 "$SRC/dcpmgmt" "$DEST/dcpmgmt"
    echo "  ok   dcpmgmt"

    local f b
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
}

# Виклик — останнім рядком файла. На цей момент bash прочитав скрипт
# цілком, тож git pull усередині може безпечно оновити навіть сам
# deploy.sh: інтерпретатор уже не повернеться до файла по наступну порцію.
main "$@"
