# dcpmgmt — README і застереження

Перша робоча версія. Синтаксично валідна (`bash -n` пройшов), але **жодного разу не виконувалась на реальній інфраструктурі**. Перед першим реальним запуском — обов'язково прочитайте цей файл.

## Встановлення

```bash
cp dcpmgmt ~/src/docker-compose-project/
chmod +x ~/src/docker-compose-project/dcpmgmt
```

Запускати завжди з кореня проєкту (`~/src/docker-compose-project`).

## Перед першим запуском — перевірте й підправте

У самому скрипті, розділ "Налаштування":
```bash
CERTBOT_EMAIL="oldengremlin@gmail.com"
DEFAULT_WP_IMAGE="wordpress:6.8.3-php8.4-fpm"
```

І один важливий момент: `issue_cert_bootstrap()` монтує `docker-compose-project_certbot-etc` / `docker-compose-project_certbot-var` за **іменем volume, яке залежить від назви проєкту** (`name:` у `docker-compose.yml`, зараз `docker-compose-project`). Якщо колись перейменуєте проєкт — виправте ці два рядки в функції.

## Що варто зробити перед першим реальним запуском команди, що змінює прод

1. `git init` / `git commit` поточного стану проєкту (якщо ще не в git) — щоб мати миттєвий `git diff`/`git checkout` для відкату `docker-compose.yml`/`docker-compose.main.yml`.
2. Ручний бекап: `cp docker-compose.yml docker-compose.yml.bak; cp docker-compose.main.yml docker-compose.main.yml.bak`.
3. **Перший реальний прогін зробіть на некритичному тестовому домені** (наприклад, ще один `*.soft-dental.kiev.ua` піддомен), не на `www.ukr-com.net` і не одразу на щось важливе.

## Відомі крихкі місця (чесно, без прикрас)

- **`webserver_deps_volumes_add/remove`** редагують `docker-compose.main.yml` текстовими `sed`-вставками "перед першим рядком `    volumes:`" і "перед першим рядком `    environment:`" усередині секції `webserver`. Це працює для **поточної** структури файлу, але крихко до ручних правок цієї структури в майбутньому (наприклад, якщо додасте ще один `environment:`-блок вище по файлу випадково, вставка може піти не туди). Після кожної операції **скрипт сам виконує `nginx -t`**, що зловить більшість синтаксичних наслідків, але не логічні (наприклад, вставку не в той сервіс).
- **`del-site`/`del-proxy-site`** для `webserver_deps_volumes_remove` з порожнім `$service` (проксі-кейс) видаляє рядки depends_on за шаблоном з порожнім значенням — **перевірте вручну** `docker-compose.main.yml` після `del-proxy-site`, ця гілка найменш обкатана.
- **Немає перевірки, що `nginx -t` пройде ДО** `add-*`-операцій (тобто якщо конфіг вже був у зламаному стані до запуску скрипта — скрипт про це не попередить заздалегідь, тільки після своєї зміни).
- **Немає dry-run режиму.** Кожна команда одразу виконує реальні дії (файли, `docker compose up`, `nginx reload`, отримання сертифіката в Let's Encrypt — а в Let's Encrypt є **rate limits** на кількість видач сертифікатів для одного домену на тиждень, тому не варто гарячково повторювати `add-site` кілька разів поспіль при помилках — краще розібратись, чому впало, а не ретраїти наосліп).
- **`add-proxy-site`** створює тільки заготовку `docker-compose.domains/<domain>.yml` із `certbot`-сервісом; сервіс застосунку (як `onlinemanager-rest` для `radre`) — свідомо залишено дописати вручну, як ви й просили.
- Скрипт **не перевіряє `MYSQL_RANDOM_ROOT_PASSWORD` конфлікти** чи довжину domain (MySQL DB name теж має ліміт 64 символи — для дуже довгих доменів варто додати таку саму обрізку, як для юзернейму; наразі цього немає).
- HTTP/3 у `write_nginx_wp_conf` **завжди** вмикається (`listen 443 quic;`, без `reuseport`) — за досвідом цієї сесії, з увімкненим `quic_bpf on;` у головному `nginx.conf` це має бути безпечно. Якщо `quic_bpf` не увімкнено — краще прибрати h3-рядки з шаблону до типового стану "спочатку h2-only", як робили з `vvv.soft-dental.kiev.ua`.

## Рекомендація

Це хороша база для подальшого доопрацювання, але я б не довіряв їй продакшн без:
1. Перенесення в git-репозиторій;
2. Кількох тестових прогонів на некритичних доменах;
3. Ідеально — доопрацювання разом із Claude Code, де можна ітеративно тестувати прямо на сервері, дивитись реальні `docker compose config`/`nginx -t` виводи і виправляти крихкі місця вище, а не гадати наперед.

## Приклади використання

```bash
# Повноцінний WordPress-сайт
./dcpmgmt add-site new-site.example.com
./dcpmgmt add-site new-site.example.com wordpress:7.1.0-php8.5-fpm

# Redirect-сайт
./dcpmgmt add-redirect-site alias.example.com www.ukr-com.net

# Proxy-сайт (без WordPress, без redirect)
./dcpmgmt add-proxy-site api.example.com my-api-container:8080

# Видалення
./dcpmgmt del-site new-site.example.com
./dcpmgmt del-redirect-site alias.example.com
./dcpmgmt del-proxy-site api.example.com
```
