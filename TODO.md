# TODO

- [x] docker-compose с opencode v2 server: Alpine, репозиторий на запись, конфиги хоста только на чтение, доступ из браузера, ежедневное автообновление.
- [x] Скрипт-визард `scripts/setup.sh`: проверяет Docker, собирает `.env`, генерирует пароль, находит абсолютные симлинки в конфигах и пишет `docker-compose.override.yml`, поднимает контейнер и открывает браузер. Нужен, чтобы коллега поднял всё сам, без README и без меня.
- [x] Проброс локальных портов хоста (`HOST_LOOPBACK_PORTS`): провайдеры из конфига, которые ходят в прокси на `127.0.0.1`, падали с ECONNREFUSED.
- [x] Перевести образ с Alpine на Debian slim: glibc нужен тулчейну проектов (колёса Python, uv). Тулчейн задаётся через `EXTRA_APT_PACKAGES`.
- [x] Визард работает поверх любого Docker-движка (colima, OrbStack, Docker Desktop) и проверяет colima mount; git push из контейнера выбранным ssh-ключом; питон-профиль и свой `.venv` в контейнере. Спека `docs/specs/0001-engine-agnostic-git-push.md`.
- [x] Прогнать визард вживую на colima: happy path с WORKSPACE внутри `$HOME` прошёл. Не тестировались WORKSPACE вне `$HOME`, путь с пробелами, профиль colima не default и Docker Desktop.
- [ ] Дать README человеку, который харнесс не видел, и поднять по нему: тикет `.scratch/engine-git/issues/03`.
- [ ] Docker для системных тестов: отдельный dind рядом с opencode, opencode в его сетевом namespace.
- [ ] Проверить в браузере встроенный терминал. Basic auth и сессии уже работают.
