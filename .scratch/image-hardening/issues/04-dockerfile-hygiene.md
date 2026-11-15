# 04: Гигиена Dockerfile

**What to build:** Образ собирается предсказуемо на любом `BASE_IMAGE` и не вводит читателя в заблуждение.

- Корпоративные CA подхватываются явным `update-ca-certificates`. Сейчас их регистрирует только postinst пакета `ca-certificates`, и если базовый образ уже содержит пакет, сертификаты лежат мёртвым грузом и TLS к зеркалу падает.
- `SHELL` с pipefail вводится одной правкой вместе с заменой проверки `find | grep -q` на glob. По отдельности pipefail ломает подмену корпоративных источников: `grep -q` выходит рано, `find` получает SIGPIPE.
- Из списка пакетов уходит то, что уже есть в slim (`bash`, `tar`, `tzdata`). `make` остаётся: через него в большинстве проектов запускаются задачи.
- Либо cache mount для apt, либо `rm -rf /var/lib/apt/lists/*`: вместе они несовместимы, выбираем одно и пишем почему.
- OCI-лейблы образа.
- Занятый UID в базовом образе даёт внятную ошибку, как уже даёт занятый GID.

Не делаем: дигест базового образа по умолчанию (без CI он молча замораживает CVE-фиксы), `# syntax=` (тянет frontend с Docker Hub, ломает закрытые сети), супервизор в образе.

**Blocked by:** None (can start immediately).

**Status:** resolved

**Модель реализации:** sonnet, medium — механика сборки, но pipefail и порядок apt-шагов легко сломать молча

- [x] сборка с тестовым `*.crt` на базовом образе, где `ca-certificates` уже стоит: сертификат в доверенных
- [x] сборка с тестовым `*.sources` под pipefail: источники подменены
- [x] `*.conf` по-прежнему не попадают в слои образа
- [x] `bash`, `tar`, `tzdata` убраны из списка, `make` на месте
- [x] выбор между cache mount и чисткой списков записан комментарием
- [x] занятый UID даёт понятную ошибку сборки
- [x] оба смоука зелёные
- [x] запись в CHANGELOG

## Comments

- Не отмечено (нужен docker build, демона нет по решению пользователя): сборка с `*.crt` на базе с `ca-certificates`, сборка с `*.sources` под pipefail, `*.conf` вне слоёв, ошибка занятого UID, оба смоука. Логика glob/pipefail проверена локально в bash на временных каталогах (пустой `docker/apt` и с `*.sources`, `*.list`, `*.conf`, `*.crt`).
- 2026-11-15, OrbStack 29.8.2, ветка `task-image-hardening` после мёрджа всех тикетов: `tests/smoke-git-push.sh` и `tests/smoke-python-venv.sh` зелёные.
- Сборка из временной копии `docker/` на `buildpack-deps:trixie-curl` с `smoke-ca.crt`, `smoke.sources`, `smoke-secret.conf`: CA в `/etc/ssl/certs/ca-certificates.crt`, в `sources.list.d` только `smoke.sources`, `zz-build-*` в образе нет, `smoke-secret` нет в `docker history`. `OPENCODE_UID=0` валит сборку с `UID 0 is already taken by 'root'`. hadolint: остался только DL3066 (info), DL3046 починен через `useradd -l`.
