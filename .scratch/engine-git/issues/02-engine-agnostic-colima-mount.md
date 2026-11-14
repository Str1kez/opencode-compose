# 02: Движок-agnostic визард и colima mount

**What to build:** Визард работает с любым Docker-движком, а не только с Docker Desktop и OrbStack. Он определяет, что доступно (colima, OrbStack, Docker Desktop), и поднимает харнесс поверх любого из них. На colima визард проверяет, что WORKSPACE виден внутри VM, и, если нет, печатает точную команду `colima start --mount $WORKSPACE:w` вместо того, чтобы молча стартовать или перезапускать VM. compose по движку не ветвится — он работает поверх любого docker-совместимого сокета. Решения зафиксированы в ADR 0001.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] визард детектит доступный движок и не падает ни на colima, ни на OrbStack, ни на Docker Desktop
- [ ] на colima без WORKSPACE в mount визард печатает точную `colima start --mount $WORKSPACE:w`
- [ ] визард не стартует и не перезапускает colima без явного подтверждения пользователя
- [ ] при добавлении mount визард предупреждает, что `colima stop && start` оборвёт остальные контейнеры пользователя
- [ ] compose не содержит движок-специфичных веток
- [ ] смоук: харнесс поднимается на colima, сервер отвечает на healthcheck
- [ ] `shellcheck` на `scripts/setup.sh` чист
