# CHANGELOG

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

### Добавлено

- Визард определяет Docker-движок (colima, OrbStack, Docker Desktop) и работает поверх любого. Новая стадия «Репозиторий внутри движка» проверяет, что WORKSPACE виден в VM colima. Если не виден, визард печатает точную команду `colima start --mount $WORKSPACE:w --mount $HOME:w` и запускает её только после подтверждения. Перед перезапуском предупреждает, что `colima stop` остановит все контейнеры в VM. `$HOME` в команде остаётся потому, что `--mount` заменяет весь список, а конфиги для контейнера лежат в домашней папке.
- Git push из контейнера по SSH. Визард получил шаг «Git-доступ по SSH»: показывает приватные ключи из `~/.ssh`, останавливает на ключе с passphrase и советует deploy-ключ без неё, берёт хост из remote репозитория, собирает known_hosts через `ssh-keyscan` и просит сверить fingerprint. Ключ и known_hosts монтируются только на чтение, git ходит ими через `GIT_SSH_COMMAND`, так что `.gitconfig` хоста и его `include` не мешают. known_hosts лежит в `.git-ssh/`, она в `.gitignore`.
- Смоук `tests/smoke-git-push.sh`: поднимает харнесс в отдельном compose-проекте рядом с одноразовым sshd и проверяет push из контейнера.

