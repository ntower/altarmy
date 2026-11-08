import type { Exit, RankKind, RankParams } from '../api/queries'
import type { RankResult } from '../api/client'
import { ALL_EXITS } from './setup'

/*
 * The list of ways to make gold (/profit/gold): crafts, processing, essence conversions and gear bought to
 * disenchant, ranked together by what a day makes, with chips to narrow it to one kind and Sell via to one way of
 * selling.
 */

/** The list's kind chips: every kind, or one of them. */
export const KIND_CHIPS = ['all', 'craft', 'process', 'flip', 'convert'] as const
export type KindChip = (typeof KIND_CHIPS)[number]
export const KIND_CHIP_LABELS: Readonly<Record<KindChip, string>> = {
  all: 'All',
  craft: 'Crafts',
  process: 'Processing',
  flip: 'Buy & disenchant',
  convert: 'Essences',
}

/** The chip in the URL's `kind`; anything else is All. */
export const parseKindChip = (param: string | null): KindChip =>
  (KIND_CHIPS as readonly string[]).includes(param ?? '') ? (param as KindChip) : 'all'

/** The rank parameters a chip narrows the list with: Processing is the server's processing recipes alone (each
 * weighed against selling its inputs); the others one kind of result (filtered after the server's cache, so cheap). */
export const kindChipParams = (chip: KindChip): Pick<RankParams, 'kinds' | 'process'> =>
  chip === 'all' ? {} : chip === 'process' ? { process: true } : { kinds: [chip] satisfies RankKind[] }

/** The list's Sell via filter: every way to sell, or only one of them (`?exit=`). */
export const SELL_VIA = ['all', 'vendor', 'ah', 'disenchant'] as const
export type SellVia = (typeof SELL_VIA)[number]
export const SELL_VIA_LABELS: Readonly<Record<SellVia, string>> = {
  all: 'All',
  vendor: 'Vendor',
  ah: 'Auction',
  disenchant: 'Disenchant',
}

/** The Sell via choice in the URL's `exit`; anything else is All. */
export const parseSellVia = (param: string | null): SellVia =>
  (SELL_VIA as readonly string[]).includes(param ?? '') ? (param as SellVia) : 'all'

/** The exits a Sell via choice ranks with. */
export const sellViaExits = (via: SellVia): Exit[] => (via === 'all' ? [...ALL_EXITS] : [via])

/** The server's groups of a result, in the order they are shown: the first two are worth doing, the rest fold away
 * under "Not worth it right now". */
export type CraftGroup = RankResult['group']
export const CRAFT_GROUPS: readonly CraftGroup[] = ['paying', 'buy_to_disenchant', 'pennies', 'waiting', 'full', 'losing']
export const CRAFT_GROUP_LABELS: Readonly<Record<CraftGroup, string>> = {
  paying: 'Pays',
  buy_to_disenchant: 'Buy to disenchant',
  pennies: "Pays only pennies: less than a craft's time is worth",
  waiting: "Waiting for sales: nothing else pays for sure, and the auction house isn't proven here yet",
  full: 'Full right now: more is listed under you than sells in a day',
  losing: 'Loses money: craft to order only',
}

/** The groups worth doing now: the list shows them open, and the top picks come from them. */
export const WORTH_GROUPS: ReadonlySet<CraftGroup> = new Set(['paying', 'buy_to_disenchant'])
/** The short name of each group not worth doing now, for the folded section's heading and a row's note. */
export const NOT_WORTH_SHORT: Readonly<Record<CraftGroup, string>> = {
  paying: 'Pays',
  buy_to_disenchant: 'Buy to disenchant',
  pennies: 'Pennies',
  waiting: 'Waiting',
  full: 'Full',
  losing: 'Losing',
}

/** The results in their groups' order, each group in the order the server ranked it (by what a day makes). */
export function byGroup<T extends Pick<RankResult, 'group'>>(results: readonly T[]): T[] {
  return CRAFT_GROUPS.flatMap((g) => results.filter((r) => r.group === g))
}

/** The processing groups (smelting, leather, cloth, essences): a tag on a processing row. */
export type ProcessGroup = NonNullable<RankResult['process']>['group']
export const PROCESS_GROUP_LABELS: Readonly<Record<ProcessGroup, string>> = {
  smelt: 'Smelting',
  leather: 'Leather',
  cloth: 'Cloth',
  essence: 'Essences',
}

/** The list's Disenchant: the days its materials should sell within, which the budget shares out. */
export const SELL_DAYS = [1, 3, 7] as const
export type SellDays = (typeof SELL_DAYS)[number]
export const SELL_DAYS_LABELS: Readonly<Record<SellDays, string>> = { 1: 'A day', 3: '3 days', 7: 'A week' }
