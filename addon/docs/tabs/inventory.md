# Inventory tab

One character's bags, bank and mail, drawn like the stock windows: slot grids with icons, stack counts, quality borders and item tooltips.

## Purpose

See what a character is carrying, has banked or has waiting in the mailbox, slot by slot, without logging in on it. Search still finds an item across every character; this tab shows one character's containers the way the game does.

## Access

- The **Inventory** side tab (after Gear). Both clients.
- The toolbar row holds the **character picker** (a dropdown of the characters under the Summary tab's realm filter, class-coloured, with the realm when more than one is shown, grouped by realm and faction as the Summary's sections are each group under a divider row naming it ("Realm — Faction"); on the Mail view the characters with mail and those without are each grouped) and, left of it, the **layout dropdown** for the active view. Each time the window opens the picker starts on the character playing and the tab on Bags; both last while the window stays open (switching tabs keeps them). Each view's layout and the mail sort are remembered (`AltArmyTBC_Options.inventory`).
- The character's gold is at the bottom right of every view.
- Sub-view tabs above the panel: **Bags**, **Bank**, **Mail**.

## Bags and Bank

Two layouts each:

- **Per bag** (default): the backpack, then each equipped bag as its own block headed by the bag's icon, name and used / total slots, then the keyring (only when it holds a key); the bank as its main grid, then each bank bag. Every block is drawn alike, the main bank and keyring included: as many blocks a row and as many columns each (five or six) as show the most slot columns a row (`InventoryLayout.BlockArrangement`). A wider window first spreads the blocks apart, then switches from three five-wide blocks to three six-wide ones, then to four five-wide ones. Hovering a header shows the bag item's tooltip.
- **Combined bags**: a bag bar of the bags' icons, then every slot in one grid as wide as the window fits. Hovering a bag on the bar lights its slots with retail's blue bag glow.

Empty slots are drawn as empty slot art. A slot's tooltip is the item's, plus which bag and slot it is in. Shift-click links the item to chat, Ctrl-click previews it in the Dressing Room (as on Gear and Search). The Bags footer shows used / total slots per group with an icon each: bags (backpack and bags), the reagent bag (WoW Forever's bag 5) and the keyring (only when it holds a key), each only when the character has it; the Bank footer shows one used / total for the whole bank.

The bank shows "Bank not recorded yet" until the character has opened its bank once. Characters scanned before slot counts were recorded (containers v2) get their bag sizes estimated from the items seen (a `~` before the count, explained in the header tooltip) until their next bag or bank scan.

On WoW Forever the bank is its tabs (each a bag slot), there is no separate main bank grid, the keyring is container -1 and bag 5 is the carried reagent bag; DataStore's bag roles (`DS:GetBagRoles()`) sort that out for the tab and for Search's locations. The first bank tab's slot holds a hidden placeholder item ("Character Bank Tab Bag (DNT)", Blizzard's do-not-translate marker); DataStore never records it as a bag (and a placeholder an older addon recorded is ignored, in this tab and in Search), so that tab is headed "Bank Bag" with the bank icon and no item tooltip (later tabs without a real bag are "Bank Tab N").

## Mail

Two layouts:

- **Inbox view** (default): one row per message with its attachment icons (wrapping when there are many), subject, sender, money and time left (yellow under 7 days, red under 3). The Subject, From, Money and Expires headers sort the rows (click again to flip; the choice is kept), latest expiry first by default like the stock inbox. Items, Subject and From stretch with the window (Items by whole icons, so more attachments fit a line); Money and Expires are fixed. Mail predicted from a send is marked "(sent)" and mail the game returned "(returned)" (a return predicted from the hook too), until that character opens its mailbox and the inbox is read for real. Hovering a row repeats the message's details; hovering an icon shows the item.
- **Combined items**: every attachment as an item slot, the message's sender and expiry in the tooltip; under the grid, a coin slot with the total gold waiting in the mail.

"No mail recorded yet" until the character has opened its mailbox once. The footer counts messages and items and says when the mailbox was last checked.

## Refresh

The open view redraws after any bag, bank, equipment or mailbox scan (`DS:OnContainerDataChanged`), when a cached send is written, and when an item's icon arrives from the server (`GET_ITEM_INFO_RECEIVED`, through `UI/PendingItemIcons.lua`). Bursts (looting fires one bag update per bag) are coalesced into one redraw on the next frame, and nothing redraws while the window is closed.

## Data source

`Data/Inventory/InventoryLayout.lua` (pure, unit-tested) builds the blocks, combined grid and inbox messages from the DataStore character record: `Containers` (containers v3 `numSlots`), `Mails` and `MailCache` (mail v2 `mailIndex`). `Data/Inventory/InventoryOptions.lua` owns the saved state. `UI/ItemSlotButton.lua` is the slot widget. See `AltArmy_TBC/Data/DATA_VERSIONS.md`.
