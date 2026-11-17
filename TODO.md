# TODO

- [x] docker-compose с opencode v2 server: Alpine, репозиторий на запись, конфиги хоста только на чтение, доступ из браузера, ежедневное автообновление.
- [x] Скрипт-визард `scripts/setup.sh`: проверяет Docker, собирает `.env`, генерирует пароль, находит абсолютные симлинки в конфигах и пишет `docker-compose.override.yml`, поднимает контейнер и открывает браузер. Нужен, чтобы коллега поднял всё сам, без README и без меня.
- [x] Проброс локальных портов хоста (`HOST_LOOPBACK_PORTS`): провайдеры из конфига, которые ходят в прокси на `127.0.0.1`, падали с ECONNREFUSED.
- [x] Перевести образ с Alpine на Debian slim: glibc нужен тулчейну проектов (колёса Python, uv). Тулчейн задаётся через `EXTRA_APT_PACKAGES`.
- [x] Визард работает поверх любого Docker-движка (colima, OrbStack, Docker Desktop) и проверяет colima mount; git push из контейнера выбранным ssh-ключом; питон-профиль и свой `.venv` в контейнере. Спека `docs/specs/0001-engine-agnostic-git-push.md`.
- [x] Прогнать визард вживую на colima: happy path с WORKSPACE внутри `$HOME` прошёл. Не тестировались WORKSPACE вне `$HOME`, путь с пробелами, профиль colima не default и Docker Desktop.
- [x] Рабочая папка вместо репозитория: узкая папка, один контейнер, `.venv`-volume на питон-проект, один deploy-ключ. Спека `.scratch/workspace-folder/spec.md`, ADR 0005, тикеты 01-04.
- [ ] Живая проверка рабочей папки на рабочем маке (минимум два питон-проекта и один репозиторий без питона, переключение проектов в браузере): тикет `.scratch/workspace-folder/issues/05-live-check-on-work-mac.md`.
- [ ] Дать README и `docs/setup/` человеку, который харнесс не видел, и поднять по ним, в том числе через агента по `AGENTS.md`: тикет `.scratch/engine-git/issues/03`.
- [x] Разнести README по `docs/setup/`, расписать запрет харнесса в рабочей папке, вычистить устаревшее, дать агенту в `AGENTS.md` маршрут установки.
- [x] Доработки образа и compose по аудиту: апдейтер, compose-проект на репозиторий, ужесточение compose, гигиена Dockerfile, README про прокси. Тикеты `.scratch/image-hardening/issues/01-05`.
- [ ] Аудит изоляции агента: домашка на репозиторий сделана (`.scratch/agent-containment/issues/02`), побег на хост через `.git` ждёт решения (`.scratch/agent-containment/issues/01`).
- [x] uv в образ через pip из корпоративного PyPI-индекса вместо образа с ghcr.io: тикет `.scratch/uv-via-pip/issues/01`.
- [ ] Docker для системных тестов: отдельный dind рядом с opencode, opencode в его сетевом namespace.
- [ ] Проверить в браузере встроенный терминал. Basic auth и сессии уже работают.
