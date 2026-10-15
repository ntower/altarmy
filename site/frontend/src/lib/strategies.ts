import type { Exit, RankKind } from '../api/queries'
import type { RankResult } from '../api/client'
import { PROCESSING } from './features'
import type { GoldStrategy } from './profitRoute'
import { ALL_EXITS } from './setup'

/*
 * The ways to make gold, each a page at /profit/gold/<key> (`STRATEGY_PICKER`): the picker's cards, the strategy
 * bar's tabs and the router all read this list, so they can't disagree.
 */

export type StrategySpec = {
  key: GoldStrategy
  title: string
  /** what it is, in a line */
  blurb: string
  /** what the player does */
  errand: string
  /** whether it is offered yet */
  live: boolean
}

export const GOLD_STRATEGIES: readonly StrategySpec[] = [
  {
    key: 'craft',
    title: 'Craft and sell',
    blurb: 'Make what your characters know; post it, vendor it or disenchant it, whichever pays.',
    errand: "You'll buy reagents, craft, then post or vendor",
    live: true,
  },
  {
    key: 'process',
    title: 'Process trade goods',
    blurb: 'Smelt, tan or weave, or sell the raw goods: whichever pays after the cut.',
    errand: "You'll buy or gather raw goods, process them, then post",
    live: PROCESSING,
  },
]

/** The strategies offered now. */
export const liveStrategies = (): StrategySpec[] => GOLD_STRATEGIES.filter((s) => s.live)

/** Craft and sell's one filter: every way to sell, or only one of them (`?exit=`). */
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

/** The kinds of result a Sell via choice shows: crafts, and with Disenchant also gear bought to disenchant. */
export const sellViaKinds = (via: SellVia): RankKind[] => (via === 'disenchant' ? ['craft', 'flip'] : ['craft'])

/** Craft and sell's groups, in the order they are shown; only the first is open at first. */
export type CraftGroup = RankResult['group']
export const CRAFT_GROUPS: readonly CraftGroup[] = ['paying', 'pennies', 'waiting', 'full', 'losing']
export const CRAFT_GROUP_LABELS: Readonly<Record<CraftGroup, string>> = {
  paying: 'Pays',
  pennies: "Pays only pennies: less than a craft's time is worth",
  waiting: "Waiting for sales: nothing else pays for sure, and the auction house isn't proven here yet",
  full: 'Full right now: more is listed under you than sells in a day',
  losing: 'Loses money: craft to order only',
}

/** The results in their groups' order, each group in the order the server ranked it (by what a day makes). */
export function byGroup<T extends Pick<RankResult, 'group'>>(results: readonly T[]): T[] {
  return CRAFT_GROUPS.flatMap((g) => results.filter((r) => r.group === g))
}
