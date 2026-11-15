# 02: Домашний volume на каждый репозиторий

**What to build:** Домашка контейнера (`HOME_VOLUME`) больше не общая между репозиториями. Агент пишет в неё бинарь opencode, `~/.local/bin` и `~/.bashrc`; агент с промпт-инъекцией в репозитории A мог подложить `git` или подменить бинарь, и контейнер репозитория B запускал это с deploy-ключом B и его рабочей копией на запись. Закладка переживала рестарт и `up --build`. Визард выводит `HOME_VOLUME` из `WORKSPACE` (`opencode-home-<slug>`), общее имя `opencode_opencode-home` остаётся явным opt-in. Решение записано в ADR 0004.

**Blocked by:** None (can start immediately).

**Status:** resolved

**Исполнение:** агент

**Модель реализации:** opus, high — граница безопасности между репозиториями, миграция существующих настроек

- [x] регрессионный тест в `tests/wizard-functions.sh` написан первым и падал без правки
- [x] `home_volume_name()` и запись `HOME_VOLUME` в `save_workspace_identity()`; явное общее имя сохраняется, чужое выведенное заменяется
- [x] при переезде с незаданного `HOME_VOLUME` визард предупреждает про повторный логин и способ оставить общую домашку
- [x] комментарии в `docker-compose.yml` и `.env.example`, README, ADR 0004, запись в CHANGELOG
- [x] `shellcheck` (koalaman/shellcheck:stable) на `scripts/setup.sh` и `tests/wizard-functions.sh` чист, кроме info SC2015 в `tests/wizard-functions.sh:182`, которого эта ветка не касалась
- [ ] смоуки `tests/smoke-*.sh` не запускались

## Comments

- Проверено: `tests/wizard-functions.sh` до правки падал с `home_volume_name: command not found`, после правки проходит целиком; `bash -n` на `scripts/setup.sh` и тесте чист.
- Смоуки задают свой `HOME_VOLUME` в собственном `.env`, визард не вызывают, правка их не затрагивает.
- Остаточный риск: внутри одного репозитория закладка возможна, пока апдейтер и агент работают под одним пользователем (ADR 0004).
- Исправления после ревью: README больше не называет домашку общей (разделы про логин и тулчейн); ручной `HOME_VOLUME`, не равный общему имени, заменяется с предупреждением, которое называет прежнее значение; миграционная заметка и README советуют удалить старую общую домашку (`docker volume rm opencode_opencode-home`) после перехода всех репозиториев; в `tests/wizard-functions.sh` добавлены проверки миграции на том же workspace и замены `my-home` с заметкой; в README модели угроз добавлены вложенные `WORKSPACE` и общий deploy-ключ.
- Статус `resolved` допустим: он описан для закрытых тикетов в `docs/agents/issue-tracker.md`, а в `docs/agents/triage-labels.md` словаря закрытия нет.
