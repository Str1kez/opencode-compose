# 02: Движок-agnostic визард и colima mount

**What to build:** Визард работает с любым Docker-движком, а не только с Docker Desktop и OrbStack. Он определяет, что доступно (colima, OrbStack, Docker Desktop), и поднимает харнесс поверх любого из них. На colima визард проверяет, что WORKSPACE виден внутри VM, и, если нет, печатает точную команду `colima start --mount $WORKSPACE:w` вместо того, чтобы молча стартовать или перезапускать VM. compose по движку не ветвится — он работает поверх любого docker-совместимого сокета. Решения зафиксированы в ADR 0001.

**Blocked by:** None (can start immediately).

**Status:** ready-for-human

**Модель реализации:** sonnet, medium — детекция движка и проверка mount в визарде, обычная логика

- [ ] визард детектит доступный движок и не падает ни на colima, ни на OrbStack, ни на Docker Desktop
- [x] на colima без WORKSPACE в mount визард печатает точную `colima start --mount $WORKSPACE:w`
- [x] визард не стартует и не перезапускает colima без явного подтверждения пользователя
- [x] при добавлении mount визард предупреждает, что `colima stop && start` оборвёт остальные контейнеры пользователя
- [x] compose не содержит движок-специфичных веток
- [ ] смоук: харнесс поднимается на colima, сервер отвечает на healthcheck
- [x] `shellcheck` на `scripts/setup.sh` чист

## Comments

- 2026-11-14: Код в `task-engine-git` (8e4f372, фиксы ревью 17a98de). На машине разработки есть только OrbStack: colima проверена на заглушках `docker`/`colima` и в `tests/wizard-functions.sh`, Docker Desktop не проверялся. Осталось вживую: смоук на colima (в том числе WORKSPACE вне `$HOME`, путь с пробелами, профиль colima не default) и прогон визарда на Docker Desktop.
