# HOW-TO: додати новий домен (WordPress) у docker-compose-project

Ця інструкція — результат "бойового" проходження всіх граблів при додаванні
`vvv.soft-dental.kiev.ua` (12.09.2026). Кожен пункт із граблями позначений 🪤.

---

## 0. Передумови

- DNS для нового домену вже вказує на цей сервер (A/AAAA-записи).
- Якщо домен буде проксіюватись через Cloudflare — **на старті лиши хмаринку
  сірою (DNS only)**. Увімкнеш проксі тільки після п.8, і одразу постав
  SSL/TLS-режим **Full** або **Full (strict)** — інакше отримаєш нескінченний
  редірект-цикл 🪤 (Cloudflare Flexible + `return 302 https://...` на origin
  = вічний ping-pong).

---

## 1. Створити `docker-compose.domains/<домен>.yml`

Скопіювати найближчий за структурою існуючий файл (наприклад
`www.ukr-com.net.yml`) і замінити всі входження старого домену на новий:
service-імена (`wordpress-...`, `db-...`, `certbot-...`), `container_name`,
`MYSQL_*`/`WORDPRESS_*` env, паролі (згенерувати нові), назви volume'ів,
`device:` шляхи в `/var/sites/<домен>/{web,db}`.

🪤 **Перевір руками, а не тільки очима:**
```bash
grep -n "старий-домен\|old-service-name" docker-compose.domains/<новий-домен>.yml
```
Порожній результат — гаразд. У нас якраз тут проскочив старий `wordpress-wwwukr-comnet`
у `certbot:` секції нового файлу не було, а от в **nginx-конфізі** (п.2) — був.

---

## 2. Створити `nginx/nginx-<домен>.conf`

Теж копія найближчого робочого конфіга. Замінити `server_name`, `root`,
шляхи до сертифіката, і **головне**:

```nginx
fastcgi_pass wordpress-<новий-домен>:9000;
```

🪤 Це рядок, який найлегше забути замінити при copy-paste — nginx не
скаржиться на старті (хост `wordpress-wwwukr-comnet` реально існує і
резолвиться), просто тихо направляє PHP-запити чужому сайту.

🪤 **`reuseport` тільки в ОДНОМУ файлі на весь стек.** У блоці
`listen 443 quic reuseport;` прапорець `reuseport` для спільного порту 443
має бути прописаний лише в одному "головному" vhost-конфізі (зараз це
`nginx-www.ukr-com.net.conf`). У новому файлі постав:
```nginx
listen 443 quic;      # без reuseport!
listen 443 ssl;
listen [::]:443 ssl;
```
Якщо скопіюєш `reuseport` — nginx впаде з `duplicate listen options`,
причому помилка вкаже на **чужий** файл (той, що завантажується пізніше
за алфавітом), а не на твій новий.

🪤 **Тимчасово закоментуй увесь `server { listen 443 ... }` блок**, лишивши
тільки `:80`-блок з `location /.well-known/acme-challenge`. Сертифіката
для нового домену ще нема, а `ssl_certificate` на неіснуючий файл валить
**весь** nginx (він один процес на всі домени) — тобто кладе одразу всі
сайти, не лише новий. Розкоментуєш після п.8.

---

## 3. Прописати в `docker-compose.main.yml`

Файл сам нагадує про це коментарем зверху. Додати:

```yaml
depends_on:
  - wordpress-<новий-домен>     # або redirect-<новий-домен>, якщо не WP

volumes:
  - wordpress-<новий-домен>:/var/www/html/<домен>
  - ./nginx/nginx-<домен>.conf:/etc/nginx/conf.d/<домен>.conf:ro
```

🪤 Якщо новий "сайт" — не WordPress, а щось на кшталт `redirect-*` /
кастомний бекенд (як `onlinemanager-rest` для `radre.ukr-com.net`) —
**обов'язково** додай його сервіс у `depends_on`. Пропуск цього пункту
не виявиться одразу (при повному `docker compose up -d` все одно піднімається
все), але вилізе пізніше при таргетованому `--force-recreate webserver`,
коли непов'язаний сервіс не встигне піднятись і nginx впаде з
`host not found in upstream`.

---

## 4. Додати рядок у `docker-compose.yml`

```yaml
include:
  - docker-compose.domains/<домен>.yml
```

---

## 5. Підняти весь стек (НЕ таргетовано!)

```bash
docker compose up -d
```

🪤 **Не використовуй `docker compose up -d --force-recreate <сервіс>`**
на цьому етапі. Таргетований запуск піднімає лише вказаний сервіс і те,
що в його `depends_on` — а незалежні `certbot-*`-контейнери (і будь-що
не в ланцюжку залежностей) можуть просто не стартувати, якщо вже не
працювали. Перевіряй потім:
```bash
docker ps --format '{{.Names}}' | grep certbot | wc -l   # має збігатись з кількістю доменів
```

---

## 6. Наповнити `/var/sites/<домен>/web` файлами WordPress

🪤 **Найбільша пастка всієї схеми.** Офіційний `wordpress:*-fpm` entrypoint
копіює ядро WP не в bind-mounted підкаталог `/var/www/html/<домен>`, а
завжди у свій `WORKDIR` — тобто `/var/www/html` **цілого контейнера**
(ефемерно, не бачить ні nginx, ні host). Для старих сайтів це непомітно,
бо їхні каталоги вже були непорожні до першого запуску. Для нового —
каталог порожній, і БД ініціюється, а `web/` лишається пустим.

Виправлення — форсувати entrypoint працювати у правильному каталозі:

```bash
# знайти РЕАЛЬНУ (з префіксом проєкту) назву volume — вона НЕ дорівнює
# імені у yml-файлі!
docker volume ls --format '{{.Name}}' | grep <новий-домен-без-крапок>

docker run -d --name wp-init-tmp \
  -w /var/www/html/<домен> \
  -v docker-compose-project_wordpress-<новий-домен>:/var/www/html/<домен> \
  -e WORDPRESS_DB_HOST=db-<новий-домен> \
  -e WORDPRESS_DB_USER=u<новий-домен> \
  -e WORDPRESS_DB_PASSWORD=<пароль> \
  -e WORDPRESS_DB_NAME=<новий-домен> \
  wordpress:<версія>-fpm

sleep 3
docker logs wp-init-tmp        # "Complete! ... copied to /var/www/html/<домен>"
docker rm -f wp-init-tmp
ls -l /var/sites/<домен>/web/  # має бути непорожньо
```

🪤 `-v <коротке-ім'я>:...` у `docker run` створить НОВИЙ окремий volume
замість підхоплення compose-івського — переконайся, що використовуєш
повну назву з префіксом проєкту (`docker-compose-project_...`), інакше
файли підуть в нікуди.

---

## 7. Отримати перший SSL-сертифікат

🪤 **Не роби `docker exec` у контейнер `certbot-<домен>`** — він уже сидить
у нескінченному циклі `certbot renew` і тримає lock; `exec ... certonly`
в той самий контейнер впаде з `Another instance of Certbot is already running`.

Замість цього — окремий одноразовий контейнер з тими самими volume'ами:

```bash
docker run --rm \
  -v docker-compose-project_certbot-etc:/etc/letsencrypt \
  -v docker-compose-project_certbot-var:/var/lib/letsencrypt \
  -v docker-compose-project_wordpress-<новий-домен>:/var/www/html/<домен> \
  certbot/certbot certonly \
  --webroot -w /var/www/html/<домен> \
  -d <домен> \
  --agree-tos --email oldengremlin@gmail.com --non-interactive
```

Це працює лише якщо `webserver` уже піднятий і слухає :80 з
`location /.well-known/acme-challenge` (див. п.2 — тому 443-блок був
закоментований, а не весь файл).

Фоновий `certbot-<домен>` (той, що в циклі) сам підхопить виданий
сертифікат на наступному плановому `renew` — нічого додатково робити не треба.

---

## 8. Увімкнути 443 і перезапустити webserver

Розкоментувати `server { listen 443 ... }` блок у `nginx/nginx-<домен>.conf`
(закоментований у п.2), потім:

```bash
docker compose up -d --force-recreate webserver
docker logs webserver --tail 30    # без [emerg] — все ок
```

---

## 9. Перевірка ДО того, як чіпати Cloudflare/DNS

```bash
curl -vk https://127.0.0.1/ -H "Host: <домен>"
```

Якщо тут усе ок (валідний хендшейк, притомна відповідь — навіть `302` на
`wp-admin/install.php` для свіжого WP це нормально) — проблема, якщо вона
є ззовні, шукається вже на боці Cloudflare/DNS/файрвола, не тут.

Якщо домен буде за Cloudflare — вмикай проксі (оранжеву хмаринку) і
одразу став **SSL/TLS → Full** (або **Full strict**), інакше — нескінченний
редірект.

---

## 10. HTTP/2 і HTTP/3 — чи можна безпечно вмикати

Так, обидва per-vhost, конфлікту між доменами не буде — за умови:

- `http2 on;` — безпечно завжди, без нюансів (nginx обирає vhost за SNI
  ще до цього).
- `http3 on;` + `listen 443 quic;` — теж безпечно, **АЛЕ**:
  - 🪤 `reuseport` у `listen 443 quic reuseport;` прописується **лише в
    одному** vhost-конфізі на весь стек (зараз — `nginx-www.ukr-com.net.conf`).
    Усі інші домени — просто `listen 443 quic;` без `reuseport`. Дублікат
    валить весь `webserver` з `duplicate listen options`, причому помилка
    вказує на файл, що вантажиться пізніше за алфавітом — не на винуватця.
  - 🪤 QUIC ходить по UDP. У `docker-compose.main.yml` порт `443` мав
    прокинутий лише TCP. Без явного:
    ```yaml
    ports:
      - 443:443
      - 443:443/udp
    ```
    nginx усередині контейнера чесно слухає `443 quic`, віддає
    `Alt-Svc: h3=...`, але пакети ззовні не долітають — браузер мовчки
    фолбечиться на h2, і ефект непомітний, доки не заміряєш протокол напряму.

Повний робочий блок для 443 (додається до нового vhost-конфіга):
```nginx
server {
    listen 443 quic;              # reuseport — ТІЛЬКИ в www.ukr-com.net.conf
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    http3 on;
    quic_gso on;
    quic_retry on;

    add_header Alt-Svc 'h3=":443"; h3-29=":443"; ma=86400';
    ...
}
```

🪤 Плагіни на кшталт "Cookies and Content Security Policy" (великі CSP/cookie
заголовки) можуть впертись у дефолтні fastcgi-буфери:
```
upstream sent too big header while reading response header from upstream
```
Лікується в `location ~ \.php$ { ... }`:
```nginx
fastcgi_buffer_size 32k;
fastcgi_buffers 8 16k;
```

---

## 11. Міграція чернетки (`vvv.*`) у продакшн (`www.*`) з повним демонтажем

Сценарій: розробка велась на тимчасовому домені (типу `vvv.soft-dental.kiev.ua`),
готовий сайт переїжджає на постійний (`www.soft-dental.kiev.ua`), після
успішного переїзду чернетку гасимо й видаляємо повністю.

### 11.1. Готуємо продакшн-оточення поруч, DNS ще не чіпаємо

Виконати п.1–5 цього ж HOWTO для нового домену (`www.soft-dental.kiev.ua`),
з 443-блоком закоментованим (сертифіката для нього ще нема).

### 11.2. Переносимо дані (ще до перемикання DNS)

Дамп + завантаження БД:
```bash
docker exec db-<vvv-домен> sh -c \
  'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" <vvv-база>' > dump.sql

docker exec -i db-<www-домен> sh -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" <www-база>' < dump.sql
```

Файли (медіа/теми/плагіни):
```bash
rsync -a /var/sites/<vvv-домен>/web/ /var/sites/<www-домен>/web/
```

🪤 **Не роби заміну URL руками через SQL/`sed` по дампу.** Gutenberg й
Elementor зберігають частину даних як serialized PHP
(`s:34:"https://vvv...";`), де довжина рядка захардкожена в самому блобі.
Проста текстова заміна її не перераховує — при різній довжині
старого/нового домену отримуєш биту серіалізацію (білі екрани, поламаний
Elementor). Навіть якщо зараз пощастило через однакову довжину доменів —
звичка не рятує наступного разу.

Правильний інструмент — `wp-cli search-replace` (десеріалізує → міняє →
серіалізує назад коректно). В образах `wordpress:*-fpm` його нема,
запускаємо окремим одноразовим контейнером `wordpress:cli` проти
volume/БД нового домену:

```bash
docker run -it --rm \
  --network docker-compose-project_app-network \
  -v docker-compose-project_wordpress-<www-домен>:/var/www/html \
  -e WORDPRESS_DB_HOST=db-<www-домен> \
  -e WORDPRESS_DB_USER=u<www-домен> \
  -e WORDPRESS_DB_PASSWORD=<пароль-www> \
  -e WORDPRESS_DB_NAME=<www-домен> \
  wordpress:cli wp search-replace \
  'https://vvv.старий-домен' 'https://www.новий-домен' \
  --all-tables --precise --dry-run
```

Спочатку **обов'язково з `--dry-run`** — перевір кількість замін на
адекватність, потім прибери прапорець і виконай насправді.

🪤 Elementor кешує згенерований CSS у **фізичні файли**
`wp-content/uploads/elementor/css/*.css` зі старими URL, зашитими прямо
в текст — `search-replace` по БД їх не чіпає. Після міграції видали цю
директорію (Elementor перегенерує сам) або Elementor → Tools →
Regenerate CSS & Data.

Перевірка без DNS:
```bash
curl -vk http://127.0.0.1/ -H "Host: <www-домен>"
```

### 11.3. Cutover

1. Заздалегідь зменшити TTL DNS-запису `<www-домен>`.
2. Перемкнути A/AAAA на IP цього сервера, дочекатись пропагації:
   ```bash
   dig +short <www-домен>
   ```
3. Отримати перший сертифікат (п.7 цього HOWTO — одноразовим
   `certbot/certbot certonly --webroot`, НЕ `exec` у renew-контейнер).
4. Розкоментувати 443-блок, `docker compose up -d --force-recreate webserver`.
5. Перевірити ззовні; якщо домен за Cloudflare — проксі вмикати одразу з
   SSL/TLS **Full**/**Full strict** (інакше нескінченний редірект, п.9/10).

### 11.4. Демонтаж чернетки

Тільки після кількох днів стабільної роботи `www`:
```bash
docker compose stop wordpress-<vvv-домен> db-<vvv-домен> certbot-<vvv-домен>
docker compose rm -f wordpress-<vvv-домен> db-<vvv-домен> certbot-<vvv-домен>
docker volume rm docker-compose-project_wordpress-<vvv-домен> docker-compose-project_db-<vvv-домен>
```
Далі прибрати: `include:` рядок у `docker-compose.yml`, файли
`docker-compose.domains/<vvv-домен>.yml` і `nginx/nginx-<vvv-домен>.conf`,
відповідні `depends_on`/volume-рядки в `docker-compose.main.yml`. Опційно —
`certbot revoke` для сертифіката чернетки і прибирання `/var/sites/<vvv-домен>/`.

---

## Короткий чекліст (TL;DR)

1. [ ] `docker-compose.domains/<домен>.yml` — новий, всі імена/паролі унікальні
2. [ ] `nginx/nginx-<домен>.conf` — `fastcgi_pass` на СВІЙ wordpress-сервіс,
       без `reuseport`, 443-блок ЗАКОМЕНТОВАНИЙ
3. [ ] `docker-compose.main.yml` — `depends_on` + обидва volume-мапінги
4. [ ] `docker-compose.yml` — `include:`
5. [ ] `docker compose up -d` (повний, не таргетований!)
6. [ ] Наповнити `web/` через `docker run -w /var/www/html/<домен> -v <PROJECT>_wordpress-<домен>:...`
7. [ ] `docker run --rm certbot/certbot certonly --webroot ...` (НЕ exec у renew-контейнер)
8. [ ] Розкоментувати 443, `docker compose up -d --force-recreate webserver`
9. [ ] `curl -vk https://127.0.0.1/ -H "Host: <домен>"` — перевірка локально
10. [ ] Тільки тепер — Cloudflare proxy + SSL mode Full/Full strict
11. [ ] (опц.) HTTP/3: `listen 443 quic;` без `reuseport` + порт `443:443/udp`
        в `docker-compose.main.yml` (див. розділ 10)
12. [ ] (опц.) Міграція чернетки в прод: `wp-cli search-replace --dry-run`,
        НЕ ручний SQL/sed (див. розділ 11)
