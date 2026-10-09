# Dev dumps — general-purpose live-client debug capture

`AltArmy.Debug.Dump(label, payload)` (in [`AltArmy_TBC/Data/Debug.lua`](../AltArmy_TBC/Data/Debug.lua)) is a **standing tool**, not a one-off. Use it whenever a bug can only be understood from live client state (WoW APIs, SavedVariables shape on a real character, a private-server client that behaves differently than expected) and chat-log printing would be too slow or tedious for the person testing it.

Prefer this over ad hoc `print`/`DEFAULT_CHAT_FRAME:AddMessage` debug logging whenever the data needed doesn't fit in a couple of short lines, or the person testing can't easily copy text out of the chat window.

## Why this exists instead of chat logging

Chat lines are hard to copy out of the WoW client and get truncated/interleaved when there's a lot of data. `Dump` instead writes a Lua table straight to SavedVariables, which an agent can read directly from disk after a `/reload` — no manual copy-paste, and full structured data (nested tables, full lists) instead of one-line summaries.

## How it works

- **Permanent, always safe to call.** `Dump` is a no-op unless master debug is on (`/altarmy debug on`), so leaving `AltArmy.Debug.Dump(...)` calls in committed code between debugging sessions costs nothing.
- **Keyed by label.** Each call's `payload` overwrites `AltArmyTBC_Options.debug.devDumps[label]` — pick a distinct label per call site so unrelated dumps don't clobber each other (e.g. two different searches happening in the same flow).
- **Center-screen alert.** Every successful dump shows a center-screen alert (`UIErrorsFrame`) reading `Alt Army dev dump: <label>`, so it's obvious to whoever is testing that a dump just fired — no need for them to check chat or guess whether their action was captured.

## Using it for a task

1. **Insert a call** at the point in the code where the interesting state exists, e.g.:
   ```lua
   AltArmy.Debug.Dump("recipeSearch", {
       query = query,
       scanned = scanned,
       results = someResultsSnapshot,
   })
   ```
   Build the payload out of plain tables/strings/numbers — it gets serialized into SavedVariables as-is. Snapshot only what's relevant to the current task (don't dump entire live objects with frames/functions in them).
2. **Ask the person testing** to:
   - Run `/altarmy debug on` (if not already on).
   - Reproduce the behavior (the alert confirms the dump fired).
   - Run `/reload`.
3. **Sync and read it yourself**:
   ```bash
   npm run dump:sync
   ```
   This copies the live SavedVariables file to `debug/compare-dump-source/AltArmy_TBC.lua` (see `.cursor/local.json` / `.cursor/local.json.example` for the source path). Then read `AltArmyTBC_Options.debug.devDumps.<label>` from that file directly (`rg -n "devDumps" debug/compare-dump-source/AltArmy_TBC.lua`, or open the file and search).
4. **Remove the call(s)** once the bug is understood — the payload/label are task-specific instrumentation, not something that should accumulate across many unrelated features. The `Dump`/`ShowCenterAlert` machinery itself stays in `Debug.lua` permanently for the next task.

## Multiple dump points in one investigation

If you need to capture state from more than one place at once (e.g. comparing what was scanned vs. what a search actually matched), just use different labels — they're stored independently in `devDumps` and none of them get evicted, so read them all after one repro + reload.

## Relationship to other dump tools

This is the **general-purpose** one. If you're specifically debugging the Gear tab's compare panel, use the purpose-built [`comparePanelDumps`](COMPARE_PANEL_DEBUG_DUMP.md) instead (has its own **Dump** button in the UI and a richer fixed schema). Reach for `AltArmy.Debug.Dump` for everything else.

`/altarmy taint` (`AltArmy.Debug.DumpTaint`, no debug mode needed) is the one for `ADDON_ACTION_BLOCKED` errors: it lists what is tainted on the player cast bar's path and by which addon, every global and foreign table field AltArmy tainted, and anything in AltArmy's SavedVariables the client cannot write (a function or secret value stops the whole file from being saved). The report opens in a copyable box (the export dialog) and is also stored as dump `taint`.
