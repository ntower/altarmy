import type { ItemInfo, RankResult } from '../api/client'
import { unitsMade } from './selling'

/*
 * The geometry of the Market section's charts, kept apart from drawing them: the order book as a staircase of price
 * levels (units along, price up), and the session's profit over the price it is listed at.
 */

type Level = ItemInfo['ah_levels'][number]

/** One stretch of the staircase: units `x0`..`x1` at `price`. `you`: the plan's own units, put in where they would be
 * listed; `uncounted`: a level plans don't count on (just listed, far under the usual price); `tail`: the level that
 * pools every higher-priced one. `taken`: the units of it the plan buys; `age`: the scans it has survived (0 for `you`). */
export interface DepthStep {
  x0: number
  x1: number
  price: number
  kind: 'level' | 'uncounted' | 'tail' | 'you'
  taken: number
  listings: number
  age: number
}

/** The price levels end to end, cheapest first, with `insert` (units the plan lists) put in after the levels at its
 * price or under; `taken` marks the units bought of each level (by index, as `walkLadder` gives them). */
export function depthSteps(
  levels: readonly Level[],
  { insert, taken }: { insert?: { price: number; units: number } | undefined; taken?: readonly number[] | undefined } = {},
): { steps: DepthStep[]; total: number } {
  const steps: DepthStep[] = []
  let x = 0
  let inserted = !insert || insert.units <= 0
  const put = (price: number, units: number, kind: DepthStep['kind'], took: number, listings: number, age: number) => {
    steps.push({ x0: x, x1: x + units, price, kind, taken: took, listings, age })
    x += units
  }
  levels.forEach((level, i) => {
    if (!inserted && insert && level.price > insert.price) {
      put(insert.price, insert.units, 'you', 0, 0, 0)
      inserted = true
    }
    const kind = !level.counted ? 'uncounted' : level.more ? 'tail' : 'level'
    put(level.price, level.quantity, kind, taken?.[i] ?? 0, level.listings, level.age)
  })
  if (!inserted && insert) put(insert.price, insert.units, 'you', 0, 0, 0)
  return { steps, total: x }
}

/** A range that holds every value given, with a little room above and below. */
export function valueRange(values: readonly number[]): { lo: number; hi: number } {
  const lo = Math.min(...values)
  const hi = Math.max(...values)
  const pad = Math.max(1, (hi - lo) * 0.08, Math.abs(hi) * 0.02)
  return { lo: lo - pad, hi: hi + pad }
}

/** As `valueRange`, for prices: never under 0. */
export function priceRange(prices: readonly number[]): { lo: number; hi: number } {
  const { lo, hi } = valueRange(prices)
  return { lo: Math.max(0, lo), hi }
}

/** Labels at a chart's right edge, by the y each wants, moved down where needed so none comes closer than `gap` px
 * to another (in the order they want, top first). */
export function spread(ys: readonly number[], gap = 13): number[] {
  const order = ys.map((y, i) => ({ y, i })).sort((a, b) => a.y - b.y)
  const out = [...ys]
  let last = -Infinity
  for (const { y, i } of order) {
    const placed = Math.max(y, last + gap)
    out[i] = placed
    last = placed
  }
  return out
}

/** The session's profit if every unit it makes sells on the auction house at `price` each: the plan's own AH profit
 * moved by what each unit then brings in more or less after the cut. Null when the plan has no AH sale to start
 * from. */
export function profitAt(
  r: Pick<RankResult, 'sell_options' | 'output_count' | 'crafts' | 'bonus_output'>,
  sellPrice: number | null,
  cut: number,
  price: number,
): number | null {
  const ah = r.sell_options.find((o) => o.kind === 'ah')
  if (!ah || sellPrice === null) return null
  return Math.round(ah.profit + unitsMade(r) * (1 - cut) * (price - sellPrice))
}
