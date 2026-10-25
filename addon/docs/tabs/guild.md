# Guild tab

Opt-in guild data sharing: browse guildmate characters and recipes grouped by main.

## Visibility

- Tab button appears only when guild sharing is enabled (feature / settings) **and** at least one character on the current realm is in a guild.
- If sharing is off for the player, the tab shows a message with a button that opens Options → General and flashes the guild sharing toggle.

## Purpose

See who is playing which alts in the guild, open their shared professions/recipes, and annotate chat so unfamiliar alts show their main name.

## Layout

- Header: guild name / tabard. The character/profession search sits in the main toolbar row, in the spot Summary uses for item search.
- The Guild side tab and the window portrait show your guild crest (`UI/GuildCrest.lua`). If you have no guild, they show the tabard icon.
- Scroll list: one row per main (preferred name, character count, last online); expand for characters (class-colored name, level, primary professions). A wider window widens the name column (up to 100 px more); the count and professions take the rest.
- Recipe detail: back + character title (Whisper on the same line, right side), recipe search in the main toolbar row's search slot, profession tabs, sortable recipe list with a skill column (required skill colored by difficulty at the guildmate's skill), sorted by required skill by default. On WoW Forever the profession tabs are spellbook-style icon tabs in the toolbar row (same spot as the Gear / Cooldowns sub-view tabs), showing the profession spell icon the native profession window uses with the name in the tooltip and no skill level; other clients show text buttons with the skill level below the title line.
- Footer / settings for sharing preferences, notes wizard, pin-style UI prefs.

## Sharing

- Opt-in (`AltArmyTBC_SharingSettings`); defaults off.
- Broadcasts shareable character cards and recipes over guild addon messages (AceComm).
- Received data in `AltArmyTBC_GuildData`.
- Characters are identified by their character ID, so guildmates whose names share a first name (common on WoW Forever) stay separate, and a renamed character keeps its shared data. Every message also carries the sending character's ID, so our own echoed broadcasts are recognized even when another guildmate has the same short name.
- Works with guildmates on older AltArmy versions. IDs travel as extra fields next to the names, and older versions ignore them. Their messages carry no IDs, so their characters are stored and requested by name as before. When such a guildmate upgrades, their old name-only entries are replaced on their next broadcast.
- Onboarding dialog when appropriate (queued with other onboarding prompts).
- Changing the main (onboarding dialog or Options) also sets the preferred name ("What should people call you?") to the new main's first name — but only when the current preferred name is empty or matches (case-insensitive) a realm character's full or first name. Custom names are kept.
- Chat main-name insertion (channels configurable): prefixes messages / online-offline lines with the poster’s group display label when it differs from the sender.
- On WoW Forever, the professions of online guildmates who share nothing through Alt Army (no addon, or sharing turned off) are read straight from the server through profession links (`GuildLinkRead`), whatever the player's own sharing setting, which covers only what the player sends. They appear like any other guildmate's; nothing says how they were read. Opening such a character's recipes reads theirs next. Guildmates who share get theirs through the guild share messages.

## Search integration

Guildmate recipes can appear in Search (with guild tagging and online/whisper helpers), whether or not the player shares their own. See [search.md](search.md).

## Data source

`GuildShareSettings`, `GuildShareComm`, `GuildShareData`, `GuildLinkRead`, `GuildTabData`, `GuildChatMainName`, `GuildManualGroups`, `GuildNoteAltParser`.
