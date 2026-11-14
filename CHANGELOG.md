# CHANGELOG

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

## [Unreleased]

### Добавлено

- Питон-профиль в визарде: `build-essential` и uv (0.13.8, образ закреплён по digest) прямо в образ, плюс поле для dev-библиотек проекта. Системный питон не ставится, его приносит `uv sync`.
- У контейнера свой `.venv`: отдельный volume поверх `WORKSPACE/.venv`. Хостовый macOS-venv контейнер не видит и не перезаписывает (ADR 0003).

### Изменено

- Дефолт `EXTRA_APT_PACKAGES` больше не содержит `python3-dev`.

