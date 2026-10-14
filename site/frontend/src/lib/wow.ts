/** Game-data lookups for item tooltips. Codes follow the client's DB2 enums (ItemSparse, Item). */

import type { ItemInfo } from '../api/client'

/** In-game item quality colours, indexed by quality (0 poor .. 7 heirloom). */
export const QUALITY_COLORS = [
  '#9d9d9d',
  '#ffffff',
  '#1eff00',
  '#0070dd',
  '#a335ee',
  '#ff8000',
  '#e6cc80',
  '#00ccff',
] as const

/** Quality names, indexed as `QUALITY_COLORS` is. */
export const QUALITY_NAMES = ['Poor', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Artifact', 'Heirloom'] as const

/** A quality's name, or "Quality N" for one the game added since. */
export const qualityName = (quality: number): string => QUALITY_NAMES[quality] ?? `Quality ${quality}`

/** Equip slot names by InventoryType, as the tooltip's left-hand slot line shows them. */
export const INVENTORY_TYPES: Readonly<Record<number, string>> = {
  1: 'Head',
  2: 'Neck',
  3: 'Shoulder',
  4: 'Shirt',
  5: 'Chest',
  6: 'Waist',
  7: 'Legs',
  8: 'Feet',
  9: 'Wrist',
  10: 'Hands',
  11: 'Finger',
  12: 'Trinket',
  13: 'One-Hand',
  14: 'Off Hand',
  15: 'Ranged',
  16: 'Back',
  17: 'Two-Hand',
  19: 'Tabard',
  20: 'Chest',
  21: 'Main Hand',
  22: 'Off Hand',
  23: 'Held In Off-hand',
  24: 'Projectile',
  25: 'Thrown',
  26: 'Ranged',
  28: 'Relic',
}

const ITEM_CLASS = { container: 1, weapon: 2, armor: 4, quiver: 11 } as const

/** Item class names by ItemClass id (the DB2 enum), as the vendor check's type filter names them. */
export const ITEM_CLASS_NAMES: Readonly<Record<number, string>> = {
  0: 'Consumable',
  1: 'Container',
  2: 'Weapon',
  3: 'Gem',
  4: 'Armor',
  5: 'Reagent',
  6: 'Projectile',
  7: 'Trade Goods',
  8: 'Generic',
  9: 'Recipe',
  10: 'Money',
  11: 'Quiver',
  12: 'Quest',
  13: 'Key',
  14: 'Permanent',
  15: 'Miscellaneous',
  16: 'Glyph',
}

/** An item class's name, or "Class N" for one the game added since. */
export const itemClassName = (classId: number): string => ITEM_CLASS_NAMES[classId] ?? `Class ${classId}`

const BINDINGS: Readonly<Record<number, string>> = {
  1: 'Binds when picked up',
  2: 'Binds when equipped',
  3: 'Binds when used',
  4: 'Quest Item',
}

export const bindingText = (bonding: number): string | undefined => BINDINGS[bonding]

/** Icon image on Wowhead's CDN; `small` is 18px, `medium` 36px, `large` 56px. */
export function iconUrl(icon: string, size: 'small' | 'medium' | 'large'): string {
  return `https://wow.zamimg.com/images/wow/icons/${size}/${icon}.jpg`
}

/** A class in a word or two, as said in a sentence: "mage", "death knight" (from its class file, e.g. DEATHKNIGHT). */
export const classWord = (classFile: string): string =>
  classFile.toLowerCase().replace(/^(death|demon)(knight|hunter)$/, '$1 $2')

/** The icon the game shows for each profession (DB2 SkillLine's SpellIconFileID through ManifestInterfaceData, for
 * the skill lines Forever's recipes use), by lower-case name. */
const PROFESSION_ICONS: Readonly<Record<string, string>> = {
  alchemy: 'trade_alchemy',
  blacksmithing: 'trade_blacksmithing',
  comprehension: 'spell_holy_mindsooth',
  cooking: 'inv_misc_food_15',
  demonology: 'spell_shadow_metamorphosis',
  enchanting: 'trade_engraving',
  engineering: 'trade_engineering',
  'first aid': 'spell_holy_sealofsacrifice',
  fishing: 'trade_fishing',
  herbalism: 'trade_herbalism',
  leatherworking: 'trade_leatherworking',
  mining: 'trade_mining',
  poisons: 'trade_brewpoison',
  skinning: 'inv_misc_pelt_wolf_01',
  tailoring: 'trade_tailoring',
}

/** A profession's icon name (for `iconUrl`); undefined for one the game gives none we know. */
export const professionIcon = (profession: string): string | undefined => PROFESSION_ICONS[profession.toLowerCase()]

/** A zone's map (772x515), by AreaTable id, served with the front end (`public/maps`, fetched from Wowhead by
 * scripts/fetch_zone_maps.py); it frames the zone as the in-game world map does, so map coordinates are
 * percentages of it. */
export const zoneMapUrl = (area: number): string => `/maps/${area}.jpg`

/** Copper split into the coins to show, from the largest non-zero one down to copper, zeros included so amounts
 * line up (0 shows as 0 copper). Copper is left out from 100 gold, silver too from 10000 gold. */
export function splitMoney(copper: number): { unit: 'gold' | 'silver' | 'copper'; amount: number }[] {
  const gold = Math.floor(copper / 10000)
  const silver = Math.floor(copper / 100) % 100
  if (gold >= 10000) return [{ unit: 'gold', amount: gold }]
  if (gold >= 100)
    return [
      { unit: 'gold', amount: gold },
      { unit: 'silver', amount: silver },
    ]
  const parts = [
    { unit: 'gold' as const, amount: gold },
    { unit: 'silver' as const, amount: silver },
    { unit: 'copper' as const, amount: copper % 100 },
  ]
  const first = parts.findIndex((p) => p.amount > 0)
  return first < 0 ? [{ unit: 'copper', amount: 0 }] : parts.slice(first)
}

/** The slot line: left "Chest", right "Cloth". Undefined for items that are not equipment or bags. */
export function slotLine(item: ItemInfo): { left: string; right?: string } | undefined {
  if (item.class_id === ITEM_CLASS.container || item.class_id === ITEM_CLASS.quiver) {
    if (!item.container_slots) return undefined
    return {
      left: `${item.container_slots} Slot ${item.subclass_name ?? 'Bag'}`,
    }
  }
  const slot = INVENTORY_TYPES[item.inventory_type]
  if (!slot) return undefined
  const showSubclass =
    (item.class_id === ITEM_CLASS.weapon || item.class_id === ITEM_CLASS.armor) &&
    item.inventory_type !== 16 && // cloaks are all Cloth; the game shows just "Back"
    item.subclass_name !== 'Miscellaneous'
  return {
    left: slot,
    right: showSubclass ? (item.subclass_name ?? undefined) : undefined,
  }
}

/** Weapon speed as the tooltip shows it ("Speed 2.50"), or undefined. */
export const speedText = (item: ItemInfo): string | undefined =>
  item.class_id === ITEM_CLASS.weapon && item.item_delay > 0
    ? `Speed ${(item.item_delay / 1000).toFixed(2)}`
    : undefined

/** A weapon's damage line: left "153 - 256 Damage", right its speed. Undefined until the damage is ingested. */
export function damageLine(item: ItemInfo): { left: string; right?: string } | undefined {
  if (item.dmg_max <= 0) return undefined
  return {
    left: `${item.dmg_min} - ${item.dmg_max} Damage`,
    right: speedText(item),
  }
}

/** The line under a weapon's damage: "(53.8 damage per second)", or undefined. */
export const dpsText = (item: ItemInfo): string | undefined =>
  item.dmg_max > 0 ? `(${item.dps.toFixed(1)} damage per second)` : undefined

/** "565 Armor", or undefined for items without armor (or from before it was ingested). */
export const armorText = (item: ItemInfo): string | undefined =>
  item.armor > 0 ? `${item.armor} Armor` : undefined
