import type { FlowNode, ItemInfo, ItemMap, RankResult } from '../api/client'
import { depthNote, unitsMade } from './selling'

/*
 * The Market section: every item of a plan with its auction house market, and what the plan does with it. The items
 * come from the plan's tree (what is bought, what is made, what is sold) and the disenchant exit's materials; each
 * is shown with the one thing most worth knowing about its market (`cue`), and the section's header sums the whole
 * plan up in a line (`headerSummary`). Words that compare with the past wait for `USUAL_FROM_DAYS` days of scans.
 */

/** Days of scans before "usually" means anything. */
export const USUAL_FROM_DAYS = 3
/** A price this far from the usual one (as a fraction) is worth a cue; nearer is "about usual". */
export const NOTABLE_MOVE = 0.05
/** A bought item at least this share of the cost is named in the header when it has a cue. */
const HEADER_SHARE = 0.4
/** Disenchanting floods a material's market when it adds at least this share of what is listed. */
const FLOOD_SHARE = 0.5

/** Where an item stands in the plan: bought (from the AH, a vendor, or gathered), made along the way, sold, or one of
 * the materials disenchanting gives. */
export type MarketGroup = 'buy' | 'make' | 'sell' | 'disenchant'
export const GROUP_ORDER: readonly MarketGroup[] = ['buy', 'make', 'sell', 'disenchant']

export interface MarketItem {
  itemId: number
  name: string
  group: MarketGroup
  /** Units the plan buys, makes or sells; a disenchant material's expected units. */
  quantity: number
  /** Copper spent on it (bought or made, postage included); null for what is sold. */
  cost: number | null
  /** How a bought item is got: ah, vendor or gather; "" otherwise. */
  source: string
  /** Units bought beyond what the auction house lists (priced at its dearest level). */
  short: number
  /** Its share of the plan's cost; null for what is sold. */
  share: number | null
  /** Bought by more than one branch of the plan (one walk up its ladder for them all). */
  shared: boolean
  /** The tree node it was first found at (its options, discounts); null for disenchant materials. */
  node: FlowNode | null
}

/** Every item of the plan worth a look at its market, grouped bought, made, sold, then disenchanted, the costliest
 * first within a group. Items bought by several branches are one entry with their quantities and costs summed. */
export function marketItems(r: RankResult): MarketItem[] {
  const found = new Map<string, MarketItem>()
  const add = (group: MarketGroup, node: FlowNode, source: string) => {
    const key = `${group}:${node.item_id}`
    const had = found.get(key)
    if (had) {
      had.quantity += node.quantity
      had.cost = (had.cost ?? 0) + node.cost
      had.short += node.short
      had.shared = true
      return
    }
    found.set(key, {
      itemId: node.item_id,
      name: node.name,
      group,
      quantity: node.quantity,
      cost: node.cost,
      source,
      short: node.short,
      share: null,
      shared: false,
      node,
    })
  }
  const walk = (node: FlowNode) => {
    if (!node.inputs.length) add('buy', node, node.source)
    else {
      add('make', node, '')
      node.inputs.forEach(walk)
    }
  }
  const root = r.tree
  root.inputs.forEach(walk)
  // what is sold: the root's output, unless nothing is made (an enchant) or the bought item itself goes (a flip)
  if (!root.enchant && !root.flip && r.best_exit !== 'skill' && root.item_id) {
    found.set(`sell:${root.item_id}`, {
      itemId: root.item_id,
      name: r.output_name,
      group: 'sell',
      quantity: Math.round(unitsMade(r)),
      cost: null,
      source: '',
      short: 0,
      share: null,
      shared: false,
      node: root,
    })
  }
  const de = r.exits.find((e) => e.kind === 'disenchant')
  if (de) {
    const units = unitsMade(r)
    for (const m of de.materials) {
      if (found.has(`disenchant:${m.item_id}`)) continue
      found.set(`disenchant:${m.item_id}`, {
        itemId: m.item_id,
        name: m.name,
        group: 'disenchant',
        quantity: units * m.chance * ((m.min_count + m.max_count) / 2),
        cost: null,
        source: '',
        short: 0,
        share: null,
        shared: false,
        node: null,
      })
    }
  }
  const all = [...found.values()]
  for (const m of all) if (m.cost !== null && r.cost > 0) m.share = m.cost / r.cost
  return all.sort(
    (a, b) => GROUP_ORDER.indexOf(a.group) - GROUP_ORDER.indexOf(b.group) || (b.cost ?? 0) - (a.cost ?? 0),
  )
}

/** The item the section opens on. Making gold: what decides the row, the output (the likeliest disenchant material
 * when disenchanting is how it likely sells). Skilling up: the costliest thing bought. */
export function defaultItem(list: readonly MarketItem[], r: RankResult, mode: 'gold' | 'skill'): number | null {
  if (!list.length) return null
  if (mode === 'skill') return (list.find((m) => m.group === 'buy') ?? list[0]!).itemId
  if ((r.likely_exit || r.best_exit) === 'disenchant') {
    const materials = r.exits.find((e) => e.kind === 'disenchant')?.materials ?? []
    const worth = (m: (typeof materials)[number]) => (m.value ?? 0) * m.expected
    const top = [...materials].sort((a, b) => worth(b) - worth(a))[0]
    if (top && list.some((m) => m.itemId === top.item_id)) return top.item_id
  }
  return (list.find((m) => m.group === 'sell') ?? list[0]!).itemId
}

/** What `qty` units cost bought up the counted price levels, cheapest first, after the first `skip` units (bought by
 * another branch): units taken per level (by index into `levels`, 0 for levels plans don't count on), the dearest
 * price reached, the average, and the units short of what is listed (priced at the dearest counted level). */
export function walkLadder(
  levels: ItemInfo['ah_levels'],
  qty: number,
  skip = 0,
): { taken: number[]; cost: number; last: number | null; average: number | null; short: number; dearest: number | null } {
  const taken = levels.map(() => 0)
  let toSkip = skip
  let left = qty
  let cost = 0
  let last: number | null = null
  let dearest: number | null = null
  levels.forEach((level, i) => {
    if (!level.counted) return
    dearest = level.price
    let here = level.quantity
    const skipped = Math.min(toSkip, here)
    toSkip -= skipped
    here -= skipped
    const take = Math.min(left, here)
    if (take <= 0) return
    taken[i] = take
    cost += take * level.price
    left -= take
    last = level.price
  })
  const short = left
  if (short > 0 && dearest !== null) {
    cost += short * dearest
    last = dearest
  }
  return { taken, cost, last, average: qty > 0 && last !== null ? Math.round(cost / qty) : null, short, dearest }
}

/** What the item usually goes for (the median over its latest days of scans), once there are enough of them. */
export function usualPrice(item: ItemInfo | undefined): number | null {
  if (!item || item.median_7d == null || (item.scans_7d ?? 0) < USUAL_FROM_DAYS) return null
  return item.median_7d
}

/** What the item's price is now, as the plan sees it: what a bought one averages up the ladder, else what selling
 * it counts on. */
export function priceNow(m: MarketItem, item: ItemInfo | undefined): number | null {
  if (!item) return null
  if (m.group === 'buy') return m.source === 'ah' ? walkLadder(item.ah_levels, m.quantity).average : null
  return item.ah_sell_price ?? item.market_price ?? null
}

/** How far `now` is from the usual price, as a fraction (0.09: 9% above); null without a usual price. */
export function moveFromUsual(now: number | null, item: ItemInfo | undefined): number | null {
  const usual = usualPrice(item)
  return now === null || usual === null || usual <= 0 ? null : (now - usual) / usual
}

export interface Cue {
  /** A word or two on the tile ("8 short", "▲9%"). */
  text: string
  /** The sentence behind it, for the tooltip and screen readers. */
  label: string
  /** bad: it costs the plan; good: it helps; note: worth knowing either way. */
  tone: 'bad' | 'good' | 'note'
}

const percent = (fraction: number) => `${Math.round(Math.abs(fraction) * 100)}%`

/** The one thing most worth knowing about an item's market, if anything: short of units, not listed, flooded by the
 * plan's disenchants, a thin market for what is sold, then a notable move from the usual price (coloured by whether it
 * hurts the plan: pricier to buy, cheaper to sell). */
export function cue(m: MarketItem, r: RankResult, items: ItemMap): Cue | null {
  const item = items[m.itemId]
  if (m.short > 0)
    return {
      text: `${m.short} short`,
      label: `${m.short} more than are listed: priced at the dearest listing`,
      tone: 'bad',
    }
  const onAh = m.group !== 'make' && !(m.group === 'buy' && m.source !== 'ah')
  if (!onAh || !item) return null
  if (item.listed === false) return { text: 'not listed', label: 'None listed in the newest scan', tone: 'bad' }
  if (m.group === 'disenchant' && item.ah_quantity != null && m.quantity >= item.ah_quantity * FLOOD_SHARE) {
    const adds = Math.round(m.quantity)
    return {
      text: 'floods',
      label: `Disenchanting adds ~${adds} to the ${item.ah_quantity.toLocaleString()} listed`,
      tone: 'bad',
    }
  }
  if (m.group === 'sell') {
    const depth = depthNote(r, items)
    if (depth?.warn) {
      const label = depth.text.startsWith('market') ? `The ${depth.text}` : 'No buyers shown yet'
      return { text: 'thin', label, tone: 'bad' }
    }
  }
  const move = moveFromUsual(priceNow(m, item), item)
  if (move === null || Math.abs(move) < NOTABLE_MOVE) return null
  const above = move > 0
  const hurts = m.group === 'buy' ? above : !above
  return {
    text: `${above ? '▲' : '▼'}${percent(move)}`,
    label: `${percent(move)} ${above ? 'above' : 'below'} usual`,
    tone: hurts ? 'bad' : 'good',
  }
}

export type HeaderSummary = (
  | { kind: 'ah'; price: number; units: number; of: number }
  | { kind: 'exit'; exit: string }
  | { kind: 'skill'; reagents: number; cost: number }
) & {
  /** A bought item that is most of the cost and has something to say. */
  flag: { name: string; share: number; cue: Cue } | null
}

/** The section header's line: what selling counts on (making gold, when it sells on the auction house), else how it
 * is sold, or what a skill run buys; and the bought item that is most of the cost, when its market has a cue. */
export function headerSummary(
  r: RankResult,
  list: readonly MarketItem[],
  items: ItemMap,
  mode: 'gold' | 'skill',
): HeaderSummary {
  const big = list.find((m) => m.group === 'buy' && (m.share ?? 0) >= HEADER_SHARE)
  const bigCue = big && cue(big, r, items)
  const flag = big && bigCue ? { name: big.name, share: big.share ?? 0, cue: bigCue } : null
  if (mode === 'skill') {
    const bought = list.filter((m) => m.group === 'buy')
    return { kind: 'skill', reagents: bought.length, cost: r.cost, flag }
  }
  const exit = r.likely_exit || r.best_exit
  const price = items[r.output_item_id]?.ah_sell_price
  if (exit === 'ah' && price != null) {
    const of = Math.round(unitsMade(r))
    return { kind: 'ah', price, units: Math.max(0, of - r.excess_units), of, flag }
  }
  return { kind: 'exit', exit, flag }
}

/** What the market's sales tell, in words: how many were seen sold, over how long it was watched. */
export function seenSold(sold: number, watched: number, pairs: number | null): string {
  if (watched <= 0) return "Sales here aren't watched yet: nobody has scanned twice within 30 minutes lately"
  const hours = `${formatHours(watched)} watched`
  if (sold === 0) return `None seen sold in ${hours}`
  if ((pairs ?? 0) <= 1) return `${sold} seen sold in ${hours}, all between one pair of scans: maybe a single buyer`
  return `At least ${sold} seen sold in ${hours}, over ${pairs} scan pairs`
}

/** Hours to the nearest whole one, or to one decimal under 10 ("0.3 hours", "19 hours"). */
function formatHours(hours: number): string {
  const shown = hours >= 10 ? Math.round(hours) : Number(hours.toFixed(1))
  return `${shown} ${shown === 1 ? 'hour' : 'hours'}`
}
