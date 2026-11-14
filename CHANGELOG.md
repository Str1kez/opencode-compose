# CHANGELOG

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

### Добавлено

- Git push из контейнера по SSH. Визард получил шаг «Git-доступ по SSH»: показывает приватные ключи из `~/.ssh`, останавливает на ключе с passphrase и советует deploy-ключ без неё, берёт хост из remote репозитория, собирает known_hosts через `ssh-keyscan` и просит сверить fingerprint. Ключ и known_hosts монтируются только на чтение, git ходит ими через `GIT_SSH_COMMAND`, так что `.gitconfig` хоста и его `include` не мешают. known_hosts лежит в `.git-ssh/`, она в `.gitignore`.
- Смоук `tests/smoke-git-push.sh`: поднимает харнесс в отдельном compose-проекте рядом с одноразовым sshd и проверяет push из контейнера.

