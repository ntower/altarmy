# Data Version Changelog

This file documents the data format versions used by AltArmy TBC's DataStore.
Each module has its own version number that is incremented when the storage format changes.

Canonical table: `DATA_VERSIONS` in [`DataStore.lua`](DataStore/DataStore.lua).

## Module Versions

### character (v3)
- **v1**: Initial version. Stores name, realm, level, class, classFile, race, faction, money, xp, xpMax, restXP, played, lastLogout, lastUpdate.
- **v2**: Also stores `guid` (`UnitGUID("player")`). Each scan folds older entries of the same character on the realm into the current key and deletes them: the same `guid`, or, for entries without one, a key that is the other's first name with the same classFile, raceFile and faction (WoW Forever's `UnitName("player")` went from "Frell Ofelements" to "Frell"). Entries keyed `Unknown` that were never scanned (made while `UnitName` read `UNKNOWNOBJECT` during loading) are dropped at `ADDON_LOADED`, and that name is never used as a key.
- **v3**: v2 misread the Forever change. `UnitName("player")` there returns the first name and the surname as two values ("Frell", "Ofelements"), so characters sharing a first name ("Frell Blast", "Frell Ofelements") were saved under the same "Frell" entry and overwrote each other. v2's first-name matching also folded one of them into the other.
  - Characters are keyed by GUID: `Characters[realm][guid]`. Only a client without `UnitGUID` keys by name.
  - `name` is the full name, joined with `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR` (a space when the client has none).
  - At `ADDON_LOADED`, every entry that carries a `guid` moves under that GUID. When two entries share a GUID, the one with the later `lastUpdate` wins and the other fills its missing fields.
  - Each scan folds in only the same GUID, or a GUID-less entry saved under exactly the character's full name. The first-name heuristic is gone.
  - When the stored name changes (paid rename, or the surname now reported), per-character settings keyed `realm\name` move to the new name (`AltArmy.RekeyCharSettings`).
  - An entry that v2 already mixed from two characters keeps the GUID it last carried. Its live fields are rescanned on login, but sub-tables written by the other character cannot be split apart.

### guildMembership (v1)
- **v1**: Guild name / membership fields on the character for guild-tab and sharing eligibility (written with character scans).

### containers (v3)
- **v1**: Initial version. Stores bag/bank contents in `char.Containers[bagID]` with `links` and `items` tables. Also stores `bagInfo` and `bankInfo` summaries.
- **v2**: Also stores equipped bag identity on inventory bags 1–4 and bank bags 5–11 as `bagLink` / `bagItemID` (backpack, keyring, and main bank container are not items).
- **v3**: Also stores `numSlots` per container (the slot count at scan time; 0 for an empty equippable bag slot), so the Inventory tab can draw empty slots. v2 data has none: readers (`InventoryLayout.ResolveNumSlots`) fall back to the highest used slot, raised to the client's backpack / main bank size, until the character's next bag or bank scan.

### equipment (v1)
- **v1**: Initial version. Stores equipped gear in `char.Inventory[slot]` (slots 1-19). Stores full link if enchanted, otherwise itemID.

### gearScores (v1)
- **v1**: Cached gear-score values from optional providers (TacoTip / GearScoreTBCClassic) for score-sort and missing-data checks.

### professions (v1)
- **v1**: Initial version. Stores profession skills in `char.Professions[name]` with rank, maxRank, isPrimary/isSecondary, and Recipes table. Primary profession names in `char.Prof1` and `char.Prof2`. Cooldown / specialization state lives alongside profession data.

### reputations (v2)
- **v1**: Initial version. Stored `char.Reputations[factionID]` using a broken `FACTION_STANDING_THRESHOLDS[standingID]` mix; cross-standing sort/order was wrong.
- **v2**: Stores `{ s = standingID, e = earnedValue, b = bottomValue, t = topValue }` per faction from `GetFactionInfo` so labels, colors, bars, and sort match the game.

### mail (v2)
- **v1**: Initial version. Stores mailbox contents in `char.Mails[]` with icon, itemID, count, sender, link, money, subject, lastCheck, daysLeft, returned.
- **v2**: Each row also carries `mailIndex`, the message it belongs to: the inbox position at scan for `Mails`, and one index per send or return (counting down from -1, `DS:NextMailCacheIndex`) for the predicted `MailCache` rows, so the Inventory tab groups a message's attachments and gold on one row. v1 rows have none and render as one message each.
- Still v2 (optional fields, nothing older reads them): a `MailCache` row predicted from mail between linked accounts (`Data/Link/LinkMail.lua`) carries `lm`, the send's id (so each side writes it once and knows when the other's data has it), and, for items sent over a link that is not our own Battle.net account (none yet: own accounts' mail arrives at once), `arrivesAt` (the send plus an hour); `ScanMailbox` keeps a row whose `arrivesAt` is still ahead.

### auctions (v1)
- **v1**: Initial version. Stores auction listings in `char.Auctions[]` and bids in `char.Bids[]` with itemID, count, bidAmount, buyoutAmount, timeLeft.

### currencies (v1)
- **v1**: Initial version. Stores TBC currency item counts in `char.Currencies[itemID] = count`.

### currencyList (v1)
- **v1**: Initial version. The native currency list (`C_CurrencyInfo`, WoW Forever's Character window Currency tab): `char.CurrencyList[currencyID] = quantity`, zeros included. Account-wide details in `AltArmyTBC_Data.CurrencyMeta[currencyID] = { name, icon, max, header, headerOrder, order }` (native header and list order). Absent on clients without `C_CurrencyInfo.GetCurrencyListInfo`.

### talents (v2)
- **v1**: Talent tab point totals for primary-spec inference (gear upgrade / compare warnings and missing-data).
- **v2**: On clients without the legacy `GetNumTalentTabs`/`GetTalentTabInfo` (e.g. WoW Forever), falls back to `C_SpecializationInfo.GetSpecialization`/`GetSpecializationInfo`. `char.talents.tabs` becomes an empty table (not a per-tab point array) and `char.talents.primary` becomes the specialization index (not a tab index) on this path; `specKey` is resolved from Blizzard's canonical specialization ID rather than tab position. Same fields, same meaning to callers (`ResolveSpecKey`/`HasTalentData`), just a different source on clients where the fallback is active.

### legacyTalents (v2)
- **v1**: WoW Forever's account-wide Legacy Points system. Stores `char.legacyTalents.nodes[nodeID] = rank` for every spent node, `totalRanksSpent`, and `restRank` (rank of the "Well Rested" rest-XP talent, resolved by name — see `Data/DataStore/DataStoreLegacy.lua`). Absent entirely on clients where the (unconfirmed, speculative) `C_Traits` API chain this relies on doesn't resolve, e.g. TBC Classic.
- **v2**: v1 read `C_ClassTalents.GetActiveConfigID()`, which is the class-talent config, so its nodes were class talents. v2 resolves the Legacy config by its DB2 trait system (45) or trees (1187/1188/1189), walks only those trees, and adds `char.legacyTalents.spells[spellID] = rank` (each node's definition spell, e.g. Master Chef 1225457, Bartering 1225459). `spells` marks v2 data: readers ignore `legacyTalents` without it, and a scan that can't resolve the Legacy config drops v1 data.

### levelHistory (v1)
- **v1**: Level-up milestones in `char.levelHistory.milestones[level]` with `reachedAt`, `playedTotal`, `playedLevel`, `zone`, `money`, `restXP`, `gear`, `deaths` (bracket count). Death log in `char.levelHistory.deaths[]` with `at`, `level`, `zone`, `playedTotal`, `killerName`, `killerGuid`. Account import gate `levelHistoryImport.questieAt` and `levelHistoryImport.nitAt`; per-character `levelHistory.meta.importedRxpAt`.
- **OrphanImports**: Imports for characters AltArmy has never scanned live in `OrphanImports.levelHistory[realm][name]` (same `levelHistory` shape). Merged into `Characters` on first login via `ScanCharacter`. Not shown in Summary/Gear UI.

## Domains without `dataVersions` keys

These are persisted on the character (or in other SavedVariables) but are not tracked in `DATA_VERSIONS` today:

- **Auctionator price updates** — `AltArmyTBC_AuctionScans = { version = 1, scans = { { t, faction, realm, key }, ... } }` (oldest first) via `Data/Integrations/AuctionatorScans.lua`: one entry per Auctionator database update (full scan, search, incremental scan; updates within 5 minutes on the same key and faction coalesce into the last entry's `t`), `key` being Auctionator's realm key (`Auctionator.State.CurrentRealm`, else `GetRealmName()`). At most 50 entries, none older than 30 days. The website's uploader reads it to name which faction's auction house an Auctionator upload came from; it is its own SavedVariable so the uploader need not parse `AltArmyTBC_Data`.
- **Auction house order book** — `AltArmyTBC_AuctionBook = { version = 1, lastRequest, scans = { { t, realm, faction, complete, listings, bidOnly, source, items }, ... } }` (oldest first) via `Data/Auctions/AuctionScan.lua` and `AuctionBook.lua`: one entry per full scan read to its end, on the scanning character's realm and faction, stamped with `GetServerTime()`. `items` is text, `<itemID>:<unit price>*<units>*<listings>,...;...`: per item its price levels cheapest first, at most 12, the rest folded into one `~` tail level. Unit prices are a listing's buyout over its count, rounded up; listings without a buyout are counted in `bidOnly` and not priced. Items are keyed by item id alone. `source` is `own` (Alt Army asked) or `heard` (another addon did). `lastRequest` is when anyone last asked, for the client's 15-minute cooldown. At most 3 scans per realm and faction, none older than 7 days. Sellers are never stored. The website prices crafts from it; `spec/fixtures/auction_book_v1.lua` is the golden file its parser is tested against too.
- **Raid lockouts** — `char.RaidLockouts` / `lastLockoutScan` via `DataStoreLockouts` (list replaced each scan).
- **Guild share** — `AltArmyTBC_GuildData` and `AltArmyTBC_SharingSettings` (protocol versioning is separate from character `dataVersions`). Received characters live in `AltArmyTBC_GuildData.chars[realm][key]`: `key` is the character's GUID when its sender shares IDs, else its name (senders on older versions). Entries carry `guid`, `sourceGuid` (the sending character) and `mainGuid` when known. Wire payloads stay at presence v2 / recipes v1 and add optional `guid`, `mainGuid` and `from` fields, which older clients ignore. Name-keyed entries are re-keyed by the sender's next presence that carries IDs; there is no load-time migration. The player's own characters are never stored there (`GSD.IsOwnCharacter`, by GUID or full name); entries older clients stored for them (on WoW Forever the echo check compared the sender's full name with the player's first name) are purged at login (`GSD.PurgeOwnCharacters`) and left out of Search. On WoW Forever professions can also be read from a character's own window through a profession link (`Guild/GuildLinkRead.lua`), additive and tolerated when absent: a profession then carries `linkReadAt`, `linkRv`, `maxRank` and `skillLine`; an entry made that way for a character nobody shared carries `linkOnly = true` (its `source` is its own name), and `linkLevel` is the roster level at the last read. `AltArmyTBC_GuildData.linkProbes[realm][guid][skillLine] = { triedAt, misses }` remembers links that went unanswered (pruned with `PurgeStale`).
