## Установка харнесса

Пользователь просит поставить, поднять или настроить харнесс, спрашивает, какие зависимости нужны, или упёрся в ошибку визарда. Источник правды — `README.md` (зависимости и запуск) и `docs/setup/*.md` по темам; отвечай по ним.

1. Проверь зависимости из раздела «Что нужно» в `README.md` на хосте: `docker compose version`, `docker info`, наличие `~/.config/opencode` и `~/.gitconfig`. Назови, чего не хватает, и дай команду установки из README.
2. Спроси, какую папку пользователь сделает рабочей, и сравни её с настоящим путём харнесса (`pwd -P` в корне клона). Пути не должны пересекаться ни в какую сторону, иначе визард откажет: объясни причину по `docs/setup/workspace.md`, раздел «Харнесс не может лежать в рабочей папке», и предложи перенести клон, например в `~/opencode-compose`.
3. Визард `make` интерактивный и читает ответы с терминала: попроси пользователя запустить его в своём терминале из корня харнесса. Вопросы визарда объясняй по теме:
   - Docker-движок, colima, рабочая папка вне `$HOME`: `docs/setup/engine.md`
   - рабочая папка, несколько рабочих папок, домашка контейнера, сброс: `docs/setup/workspace.md`
   - git push, deploy-ключ, known_hosts: `docs/setup/git-ssh.md`
   - питон-профиль, `.venv`, apt-пакеты, обновление uv: `docs/setup/toolchain.md`
   - закрытый интернет, apt-зеркало, PyPI-индекс, прокси: `docs/setup/corporate-network.md`
   - провайдеры, обновления, симлинки, порты хоста, Linux: `docs/setup/operations.md`
   - запуск без визарда: `docs/setup/manual-setup.md`
   - модель угроз, что проверять после недоверенных сессий: `docs/setup/security.md`

Готово, когда `docker compose ps` в корне харнесса показывает контейнер `healthy`, а пользователь вошёл в веб-интерфейс по адресу из последнего экрана визарда.

## Agent skills

### Issue tracker

Issues и спеки живут локальными markdown-файлами в `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Дефолтный словарь: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: один `GLOSSARY.md` и `docs/adr/` в корне. See `docs/agents/domain.md`.
