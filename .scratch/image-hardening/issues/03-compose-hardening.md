# 03: Ужесточение compose

**What to build:** Контейнер получает ровно те права, которые ему нужны, и корректно переживает долгий первый старт и остановку. Ни одна capability серверу не нужна, поэтому все сбрасываются, повышение привилегий запрещено, число процессов ограничено (единственный размножающийся процесс — socat с `fork`). `start_period` у healthcheck растёт с запасом на первую установку opencode в медленной корпоративной сети: сейчас 60 секунд, и `up --wait` может сдаться раньше. `stop_grace_period` больше, чем окно остановки в entrypoint (10 секунд). Отсутствующий WORKSPACE даёт внятную ошибку во всех местах, где он подставляется, а не только в одном.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Модель реализации:** sonnet, medium — конфигурация, но `cap_drop` может сломать что-то неочевидное

- [ ] `cap_drop: ALL`, `no-new-privileges`, `pids_limit`; сервер, socat-проброс портов и апдейтер работают
- [ ] `start_period` и `stop_grace_period` подняты, `docker compose down` останавливает контейнер с кодом 143, а не по SIGKILL
- [x] пустой WORKSPACE даёт внятную ошибку compose во всех подстановках
- [ ] оба смоука зелёные
- [x] запись в CHANGELOG

## Comments

- Пункты 1, 2 (код 143) и 4 не отмечены: нет Docker daemon, рантайм и смоуки не запускались. Изменения в compose (`cap_drop`, `no-new-privileges`, `pids_limit`, `start_period: 300s`, `stop_grace_period: 30s`) проверены только через `docker compose config`; по коду ни одной capability рантайму не нужно (USER opencode с первой инструкции, порты > 1024, нет chown/setuid).
