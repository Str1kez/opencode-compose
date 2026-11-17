# Запуск без визарда

Визард делает всё описанное здесь сам и ещё проверяет то, что руками легко пропустить: харнесс вне рабочей папки, видимость папки в colima, ssh-ключ вне рабочей папки. Без него следи за этим сам, правила в [рабочей папке](workspace.md).

## `.env`

```sh
cp .env.example .env
```

В `.env` заполни минимум две переменные:

```sh
WORKSPACE=/Users/me/work
OPENCODE_SERVER_PASSWORD=<вывод openssl rand -base64 32>
```

Остальные переменные с пояснениями лежат в `.env.example`. Что стоит задать руками:

- `HOME_VOLUME`: своё имя volume домашки на рабочую папку. По умолчанию он общий `opencode_opencode-home`, и тогда агент из одной рабочей папки может подложить код в другую ([почему](workspace.md#домашняя-папка-контейнера)).
- `COMPOSE_PROJECT_NAME` и `OPENCODE_PORT`, если поднимаешь вторую рабочую папку рядом. Без них проект называется `opencode`, порт 4096.
- `HOST_OPENCODE_CONFIG` и `HOST_GITCONFIG`, если конфиги лежат не в `~/.config/opencode` и `~/.gitconfig`. Если файла нет, compose упадёт с понятной ошибкой, а не создаст пустую папку.
- `OPENCODE_UID` и `OPENCODE_GID` на Linux-хосте: вывод `id -u` и `id -g`.

## Запуск

```sh
docker compose up -d --build
docker compose logs -f
```

`--env-file` не нужен: compose сам читает `.env` из папки проекта и подставляет оттуда `WORKSPACE`, `INSTALL_UV` и остальное, включая аргументы сборки. Переменная, экспортированная в шелле, перебивает значение из `.env`. Посмотреть, что в итоге получилось, можно командой `docker compose config`.

Открой `http://localhost:4096`, логин `opencode`, пароль из `OPENCODE_SERVER_PASSWORD`.

## Дополнительные mount

Скиллы из `~/.agents`, глобальный gitignore, цели абсолютных симлинков в конфиге: скопируй `docker-compose.override.yml.example` в `docker-compose.override.yml` (он в `.gitignore`) и оставь нужные строки.

## Питон-проекты

Без визарда контейнерный `.venv` не отделён от хостового, и `uv sync` в контейнере перепишет хостовый venv Linux-сборкой. Для каждого питон-проекта:

1. Сделай `mkdir .venv` в проекте на хосте. Иначе на Linux Docker создаст папку от root.
2. Опиши volume поверх `.venv` в `docker-compose.override.yml` по образцу из `docker-compose.override.yml.example`.
3. Перечисли точки монтирования в аргументе сборки `VENV_MOUNT_POINTS`, по одной на строку: образ создаст их с владельцем opencode, иначе свежий volume принадлежит root и uv не сможет в него писать.

Питон-профиль включается строкой `INSTALL_UV=1` в `.env`, подробности в [тулчейне](toolchain.md).

## git push по ssh

Нужны mount ключа и known_hosts в `/run/git-ssh/` только на чтение и `GIT_SSH_COMMAND` в `.env`, пример строки лежит в `.env.example`. Проще и безопаснее сделать это визардом: он собирает known_hosts и проверяет ключ, смотри [git-доступ](git-ssh.md).
