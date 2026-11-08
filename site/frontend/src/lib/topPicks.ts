import type { RankResult } from '../api/client'
import { WORTH_GROUPS } from './strategies'

/** What a pick is, for its badge: processing apart from other crafts. */
export type PickKind = 'craft' | 'process' | 'flip' | 'convert' | 'enchant'
export const pickKind = (r: Pick<RankResult, 'kind' | 'process'>): PickKind => (r.process ? 'process' : r.kind)

type Pickable = Pick<
  RankResult,
  'group' | 'confidence' | 'launch_prices' | 'copied' | 'slow' | 'output_item_id' | 'per_day'
>

/**
 * The best `n` things to do now from `results`, by what a day of each makes (`per_day`, whatever order the list is in:
 * favorites first, or by Each): only what pays or is worth buying to disenchant, nothing we are unsure of (a low price
 * confidence, launch prices, a post shared with others who copied it, a slow sale), and one per item made. Fewer when
 * not enough qualify.
 */
export function topPicks<T extends Pickable>(results: readonly T[], n = 5): T[] {
  const items = new Set<number>()
  return [...results]
    .filter((r) => WORTH_GROUPS.has(r.group) && r.per_day > 0)
    .filter((r) => !(r.confidence?.level === 'low' || r.launch_prices || r.copied > 0 || r.slow))
    .sort((a, b) => b.per_day - a.per_day)
    .filter((r) => {
      if (items.has(r.output_item_id)) return false
      items.add(r.output_item_id)
      return true
    })
    .slice(0, n)
}
