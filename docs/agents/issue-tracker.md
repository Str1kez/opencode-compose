# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## Модель для реализации

При нарезке на тикеты каждый тикет получает строку `**Модель реализации:** <sonnet|opus>, <low|medium|high> — <причина в несколько слов>`, сразу после `**Исполнение:**`. Агент `coder` по умолчанию работает на sonnet; ведущий агент тикета передаёт модель и effort из этой строки параметрами `model` и `effort` при запуске субагента.

- `sonnet` по умолчанию: обычная бизнес-логика, команды, хендлеры, рендеринг, CRUD по готовым швам.
- `opus`, если есть хотя бы одно из: новый шов или контракт между слоями, транзакции и конкурентность, миграции с данными, неочевидный алгоритм, решение, которое трудно откатить.
- `effort`: `low` для механики без ветвлений (маршрутизация, конфигурация, документация); `medium` для обычной логики; `high` для тикетов с `opus` и для всего, где ошибка проявляется только под конкуренцией или на границе слоёв.
- Ревью диффа идёт на модели `code-reviewer` (opus) и строкой не задаётся.
- Тикет реализует субагент `coder`: модель и effort из строки передаются параметрами запуска. `general-purpose` исполнителем тикета не берётся.
- Git-операции (удалить ветку, влить ветку, `git status`) оркестратор делает сам: субагент на такую команду стоит дороже самой команды.
- Строка относится к субагенту-исполнителю. Субагент для тестов берёт ту же модель, что и исполнитель.

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
