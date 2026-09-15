# Перенесення WordPress на інший домен

Типовий сценарій: сайт робився на чернетці (`vvv.example.com`), готовий —
переїжджає на постійний домен (`www.example.com`), після кількох днів
стабільної роботи чернетка гаситься.

## 1. Підняти цільовий домен поруч

DNS ще не чіпаємо — сертифікат поки отримати нізвідки:

```bash
sudo ./dcpmgmt add wordpress www.example.com --no-cert
```

Домен підніметься із заглушкою на `:80`, БД і контейнери — на місці.

## 2. Перенести дані

Дамп і завантаження — обидва всередині контейнерів, пароль береться з
їхнього оточення:

```bash
docker exec db-vvvexamplecom sh -c \
  'exec mariadb-dump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' > dump.sql

docker exec -i db-wwwexamplecom sh -c \
  'exec mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' < dump.sql
```

Файли:

```bash
sudo rsync -a /var/sites/vvv.example.com/web/ /var/sites/www.example.com/web/
```

`wp-config.php` при цьому перезапишеться старим — але параметри БД у ньому
беруться зі змінних оточення контейнера, тож він лишається робочим.

## 3. Замінити URL — тільки через wp-cli

**Не робіть заміну URL через SQL або `sed` по дампу.** Gutenberg і
Elementor зберігають частину даних як serialized PHP
(`s:34:"https://vvv.example.com";`), де довжина рядка захардкожена в самому
блобі. Текстова заміна її не перераховує: при різній довжині старого й
нового домену отримаєте биту серіалізацію — білі екрани й поламаний
редактор. Якщо довжини випадково збіглися і обійшлось — наступного разу
не обійдеться.

`wp-cli` десеріалізує, замінює й серіалізує назад коректно. В образах
`wordpress:*-fpm` його немає, тож разовим контейнером:

```bash
docker run -it --rm \
  --network docker-compose-project_app-network \
  -v /var/sites/www.example.com/web:/var/www/html \
  -w /var/www/html \
  -e WORDPRESS_DB_HOST=db-wwwexamplecom \
  -e WORDPRESS_DB_USER=uwwwexamplecom \
  -e WORDPRESS_DB_NAME=wwwexamplecom \
  --env-file secrets/www.example.com.env \
  wordpress:cli wp search-replace \
    'https://vvv.example.com' 'https://www.example.com' \
    --all-tables --precise --dry-run
```

Спершу обов'язково з `--dry-run`: подивіться на кількість замін і чи
виглядає вона осмислено. Потім приберіть прапорець і виконайте насправді.

Ім'я мережі перевіряється так: `docker network ls | grep app-network`.

## 4. Elementor кешує CSS у файли

`search-replace` по БД не чіпає згенеровані CSS-файли зі старими URL
усередині:

```bash
sudo rm -rf /var/sites/www.example.com/web/wp-content/uploads/elementor/css
```

Elementor перегенерує сам (або Elementor → Tools → Regenerate CSS & Data).

## 5. Перевірити до перемикання DNS

```bash
curl -vk http://127.0.0.1/ -H "Host: www.example.com"
```

## 6. Перемкнути DNS і взяти сертифікат

1. Заздалегідь зменшити TTL запису.
2. Перемкнути A/AAAA, дочекатись пропагації: `dig +short www.example.com`.
3. Взяти сертифікат і ввімкнути 443:

```bash
sudo ./dcpmgmt cert issue www.example.com
```

`cert issue` сам перегенерує nginx-конфіг із 443-блоком і перезавантажить
nginx. Якщо домен за Cloudflare — проксі вмикати вже після цього, одразу з
режимом SSL/TLS **Full** або **Full (strict)**.

## 7. Прибрати чернетку

Тільки після кількох днів стабільної роботи:

```bash
sudo ./dcpmgmt remove vvv.example.com --purge
```

`--purge` знесе разом із файлами, базою й сертифікатом. Без нього — тільки
зі стека, дані лишаться на диску.
