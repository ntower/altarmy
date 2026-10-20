# CLAUDE.md

Conventions for AI agents working on the addon, `addon/` in the altarmy monorepo (the site is `site/`; see the
root `CLAUDE.md`). "The repo root" below means this folder: run every `npm` command from `addon/`. The
workflows (`.github/workflows/addon-*.yml`), the pre-commit hook (`.githooks/`) and the skills
(`.claude/skills/`) live at the monorepo root.

## Project

AltArmy TBC is an account-wide alt-management addon for **World of Warcraft: Forever** (the main focus) and **TBC Anniversary** (supported, but not what new work is aimed at). The name and the `AltArmy_TBC/` folder predate Forever. UI and data live under `AltArmy_TBC/` (Lua 5.1). Tests and tooling: `npm test`, `npm run check` (see `TESTING.md`, `LINTING.md`).

## Documentation

Product docs live in **`docs/`**. Start at [`docs/README.md`](docs/README.md).

Do **not** recreate deleted root specs (`ALTARMY_TBC_STRUCTURE.md`, `ALTARMY_TBC_SUMMARY.md`, `ALTARMY_TBC_CHARACTERS.md`, `ALTARMY_TBC_SEARCH.md`, `ALTARMY_TBC_OPTIONS_AND_MINIMAP.md`). Cross-character item lookup is Search; one character's containers are the Inventory tab (`Tabs/TabInventory*.lua`).

### Keep docs in the same task

When you change **user-visible** behavior, update the matching docs in the **same task** — not as a follow-up.

| Code change | Update |
|-------------|--------|
| Tab UI / workflow (`Tabs/Tab*.lua`) | Matching `docs/tabs/*.md`; `docs/FEATURES.md` if it is a significant new capability |
| New main-window tab | New `docs/tabs/` file, `docs/README.md`, `docs/FEATURES.md`, `docs/ARCHITECTURE.md` |
| Options, minimap, slash commands | `docs/tabs/options.md` |
| Alerts, bank alts, realm filter, optional addon deps | `docs/FEATURES.md` (cross-cutting) and the owning tab doc |
| DataStore scan/shape / SavedVariables | `AltArmy_TBC/Data/DESIGN.md` and `DATA_VERSIONS.md` if a version or domain changed |
| Shipping or dropping a roadmap item | `docs/FEATURE_IDEAS.md` status table; move shipped detail into FEATURES / tab docs |

### Altitude

Significant features only. Skip debug-only slash commands, placeholder files, and pixel-level UI.

### Finish check

If the diff is user-visible and no `docs/` (or Data DESIGN / DATA_VERSIONS) file changed, the work is incomplete unless the change is purely internal.

## Other project rules

Prefer red-green-refactor for new features: write a failing unit test first, then make it pass.

Domain-specific skills (e.g. debug compare dumps, Summary missing-data) live in the monorepo root's `.claude/skills/`.

### Debugging live-client behavior

When a bug needs live WoW API / SavedVariables state to diagnose (not just reading code), use the **dev-dump** tool instead of asking the person to paste chat output: `AltArmy.Debug.Dump(label, payload)` (see [`.claude/skills/dev-dump/SKILL.md`](../.claude/skills/dev-dump/SKILL.md) and [`docs/DEV_DUMPS.md`](docs/DEV_DUMPS.md)). It writes structured data to SavedVariables (read it yourself via `npm run dump:sync`) and fires a center-screen alert so the person knows it fired. Assume the person cannot easily copy text out of the WoW chat window.

### Lua tooling

Use `npm test` and `npm run check` / `npm run lint` from the repo root. Do **not** search for a system Lua install, invent `LUA_51_PATH`, shim `luajit` as `lua.exe`, or poke Homebrew/LuaRocks unless an `npm` script fails with a clear missing-tool message — if Lua 5.1 / busted / luacheck are missing, run `npm run setup:dev` once, then retry. Runners auto-resolve `<repo>/.lua51/bin` (and Windows Lua for Windows defaults); no per-session env exports are needed once that tree exists.

### Lua 5.1 local-variable limit

WoW (Forever and TBC alike) runs Lua 5.1, which allows at most **200 local variables per function** (a file's main chunk counts as one function). Exceeding it fails at load with `main function has more than 200 local variables` — **luacheck does not catch this**; only `npm run check`'s Lua 5.1 compile pass does. Run it after editing large `Tabs/Tab*.lua` files (especially `TabGuild.lua` / `TabGear.lua` / `TabSearch.lua`), before considering the work done.

When editing those large UI files: prefer packing related constants/session state into one table (`local UI = { ... }`, `local state = { ... }`) instead of many top-level `local`s; prefer small helper modules under `Data/` for pure logic rather than growing a tab file's main-chunk locals. Nested `do ... end` blocks do **not** reset the limit, only a new function gets a fresh 200; forward declarations (`local foo` then `foo = function...`) still count. If the warning appears, count top-level locals and reduce by grouping into tables or extracting helpers until comfortably under 200, leaving headroom for future edits.
