import type { ItemMap, RankResult } from '../api/client'

/*
 * What to watch for when posting a craft on the auction house: the price under which another exit pays more, the price
 * under which the session loses gold, what the plan counted on, and how much a disenchant adds to what is listed.
 */

/** Units the session makes (Master Chef's extra ones included). */
export const unitsMade = (r: Pick<RankResult, 'output_count' | 'crafts' | 'bonus_output'>): number =>
  r.output_count * r.crafts + r.bonus_output

/** The best way to sell other than the auction house, per unit after postage; null if there is none. */
export function fallback(r: Pick<RankResult, 'exits'>): { kind: string; value: number } | null {
  const others = r.exits.filter((e) => e.kind !== 'ah').map((e) => ({ kind: e.kind, value: e.value - e.postage }))
  return others.reduce<{ kind: string; value: number } | null>((best, e) => (!best || e.value > best.value ? e : best), null)
}

/** The lowest listing price at which the auction house still beats the best other exit (`cut` its share of a sale);
 * null when there is no other exit. */
export function floor(r: Pick<RankResult, 'exits'>, cut: number): number | null {
  const other = fallback(r)
  return other && other.value > 0 ? Math.ceil(other.value / (1 - cut)) : null
}

/** The listing price under which the session loses gold: what each unit cost, before the cut. */
export function breakEven(r: Pick<RankResult, 'cost' | 'output_count' | 'crafts' | 'bonus_output'>, cut: number): number {
  return Math.ceil(r.cost / Math.max(1, unitsMade(r)) / (1 - cut))
}

/** What the plan counted on for its AH sale: the price, and for how many of the units made. */
export function countedOn(
  r: Pick<RankResult, 'output_item_id' | 'output_count' | 'crafts' | 'bonus_output' | 'excess_units'>,
  items: ItemMap,
): { price: number | null; units: number; of: number } {
  const of = Math.round(unitsMade(r))
  return { price: items[r.output_item_id]?.ah_sell_price ?? null, units: Math.max(0, of - r.excess_units), of }
}

/** What disenchanting the session adds to each material's market: the expected units next to those listed. */
export function floodCheck(
  r: Pick<RankResult, 'exits' | 'output_count' | 'crafts' | 'bonus_output'>,
  items: ItemMap,
): { itemId: number; name: string; adds: number; listed: number | null }[] {
  const de = r.exits.find((e) => e.kind === 'disenchant')
  if (!de) return []
  const units = unitsMade(r)
  return de.materials.map((m) => ({
    itemId: m.item_id,
    name: m.name,
    adds: Math.round(units * m.chance * ((m.min_count + m.max_count) / 2)),
    listed: items[m.item_id]?.ah_quantity ?? null,
  }))
}

/** What playing it safe makes for the session, and how (`vendor`, `disenchant`, or `convert`: an essence conversion's
 * materials sell), from `RankResult.safe_profit`; null when neither a vendor nor disenchanting is open to it. */
export function safeProfit(r: Pick<RankResult, 'safe_profit' | 'safe_exit'>): { kind: string; profit: number } | null {
  return r.safe_profit == null ? null : { kind: r.safe_exit ?? '', profit: r.safe_profit }
}

/** What the auction house makes for the session, counting only the units its market has shown it takes (the rest
 * at the best other exit: `RankResult.ah_profit`); null when it can't be sold there. */
export const ahProfit = (r: Pick<RankResult, 'ah_profit'>): number | null => r.ah_profit ?? null

/** How the auction house's figure was counted: `counted` of the `made` units at `price` each, the rest the safe way
 * (`restKind`); `allSold` is what it would make if every unit sold there. Null when it can't be sold there. */
export function ahCount(
  r: Pick<
    RankResult,
    'ah_profit' | 'ah_excess_units' | 'sell_options' | 'exits' | 'output_item_id' | 'output_count' | 'crafts' | 'bonus_output'
  >,
  items: ItemMap,
): { counted: number; made: number; price: number | null; restKind: string | null; allSold: number | null } | null {
  if (r.ah_profit == null) return null
  const made = Math.round(unitsMade(r))
  return {
    counted: Math.max(0, made - r.ah_excess_units),
    made,
    price: items[r.output_item_id]?.ah_sell_price ?? null,
    restKind: r.ah_excess_units > 0 ? (fallback(r)?.kind ?? null) : null,
    allSold: r.sell_options.find((o) => o.kind === 'ah')?.profit ?? null,
  }
}

/** The line under the auction house's figure: how many the market takes of those the session makes when that is
 * fewer (`warn` when under half, or none), else how many are listed and how many the session adds. */
export function depthNote(
  r: Pick<RankResult, 'ah_profit' | 'ah_excess_units' | 'output_item_id' | 'output_count' | 'crafts' | 'bonus_output'>,
  items: ItemMap,
): { text: string; warn: boolean } | null {
  if (r.ah_profit == null) return null
  const made = Math.round(unitsMade(r))
  const takes = Math.max(0, made - r.ah_excess_units)
  if (r.ah_excess_units > 0)
    return takes === 0
      ? { text: 'no buyers shown yet', warn: true }
      : { text: `market takes ~${takes} of ${made}`, warn: takes < made / 2 }
  const listed = items[r.output_item_id]?.ah_quantity
  return listed == null ? null : { text: `${listed.toLocaleString()} listed · you add ${made}`, warn: false }
}

/** A disenchant's materials as the detailed step list auctions them: each with the units `disenchants` are expected
 * to give, and its share of the sale's `gross` and the session's `net` by what it is worth (the last priced one
 * takes what rounding leaves, so the shares add up); an unpriced one gets no share (`gross` null). Empty without a
 * priced material to share by. */
export function materialSales(
  r: Pick<RankResult, 'exits'>,
  disenchants: number,
  gross: number,
  net: number,
): { item_id: number; name: string; units: number; gross: number | null; net: number | null }[] {
  const materials = r.exits.find((e) => e.kind === 'disenchant')?.materials ?? []
  const worth = materials.reduce((sum, m) => sum + (m.value ?? 0), 0)
  if (worth <= 0) return []
  const last = materials.findLastIndex((m) => (m.value ?? 0) > 0)
  let grossLeft = gross
  let netLeft = net
  return materials.map((m, i) => {
    const units = m.expected * disenchants
    if (!m.value) return { item_id: m.item_id, name: m.name, units, gross: null, net: null }
    const g = i === last ? grossLeft : Math.round((gross * m.value) / worth)
    const n = i === last ? netLeft : Math.round((net * m.value) / worth)
    grossLeft -= g
    netLeft -= n
    return { item_id: m.item_id, name: m.name, units, gross: g, net: n }
  })
}

/** An expected count of units: whole from 10 up, else to one decimal without a trailing ".0" ("4", "0.3"). */
export const expectedUnits = (units: number): string =>
  units >= 10 ? String(Math.round(units)) : String(Number(units.toFixed(1)))
