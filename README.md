# Alt Army

Account-wide alt management for World of Warcraft (WoW: Forever, and TBC Anniversary), in two parts that share
this repository:

- **[`addon/`](addon/README.md)** – the Alt Army addon: character summary, gear and reputation grids, profession
  cooldowns and raid lockouts, item and recipe search, auction house scans, and the export the site takes.
  Released to [CurseForge](https://www.curseforge.com/wow/addons/alt-army) and
  [Wago](https://addons.wago.io/addons/aNDMjY6o) from `addon-v*` tags; the zip of the newest release is
  [AltArmy_TBC.zip](https://github.com/ntower/altarmy/releases/latest/download/AltArmy_TBC.zip).
- **[`site/`](site/README.md)** – the Alt Army site: the API and web app that find profitable crafting recipes
  and production chains from the characters and auction house scans the addon collects, and Alt Army Sync, the
  Windows uploader ([altarmy-sync.exe](https://github.com/ntower/altarmy/releases/download/sync-latest/altarmy-sync.exe),
  released from `sync-v*` tags).

Each part has its own README, tooling and tests; run their commands from inside their folder.
`CLAUDE.md` describes the layout, the contract between the two, and how releases work.
