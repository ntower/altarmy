/** What a character's Legacy talents and reputation did to a step: the API reports the effects, these name them. */

/** Working Overtime (WoW: Forever's Legacy talent): a better chance of a skill point from every craft. */
export const WORKING_OVERTIME = 1225451
export const WORKING_OVERTIME_PERCENT = 4
export const WORKING_OVERTIME_RANKS = 5

/** Master Chef (WoW: Forever's Legacy talent): a chance of an extra result from Cooking, per rank. */
export const MASTER_CHEF = 1225457
export const MASTER_CHEF_PERCENT = 10
export const MASTER_CHEF_RANKS = 5

/** A Legacy talent a character has that matters to their crafting, as the skill workspace names it. */
export type CraftingTalent = { spellId: number; name: string; rank: number; maxRank: number }

/**
 * The Legacy talents (ranked above 0) that matter when crafting `profession`: Working Overtime and Bartering always,
 * Master Chef only for Cooking.
 */
export function craftingTalents(
  talents: readonly { spell_id: number; name: string; rank: number; max_rank: number }[],
  profession: string,
): CraftingTalent[] {
  const wanted = [WORKING_OVERTIME, BARTERING, ...(profession.toLowerCase() === 'cooking' ? [MASTER_CHEF] : [])]
  return wanted.flatMap((id) => {
    const t = talents.find((t) => t.spell_id === id && t.rank > 0)
    return t ? [{ spellId: id, name: t.name, rank: t.rank, maxRank: t.max_rank }] : []
  })
}

/** What a talent's ranks do, the last line of its tooltip; "" for a talent not named here. */
export function talentNote({ spellId, rank }: CraftingTalent): string {
  switch (spellId) {
    case WORKING_OVERTIME:
      return `Increases your chance to gain a skill increase by ${rank * WORKING_OVERTIME_PERCENT}%`
    case BARTERING:
      return `Reduces the gold price of items from all vendors by ${rank * BARTERING_PERCENT}%`
    case MASTER_CHEF:
      return `Your cooking recipes have a ${rank * MASTER_CHEF_PERCENT}% chance to create an extra result`
    default:
      return ''
  }
}

/**
 * What came off a vendor buy: the buyer's Bartering talent and their standing with the vendor's faction, e.g.
 * "Bartering −10%, Orgrimmar reputation −10%"; "" without either.
 */
export function discountNote(discount: number, repDiscount = 0, repFaction = ''): string {
  const parts = []
  if (discount > 0) parts.push(`Bartering −${discount}%`)
  if (repDiscount > 0) parts.push(`${repFaction ? `${repFaction} reputation` : 'Reputation'} −${repDiscount}%`)
  return parts.join(', ')
}

/** Bartering (WoW: Forever's Legacy talent): vendor buys cheaper, `BARTERING_PERCENT` per rank. */
export const BARTERING = 1225459
export const BARTERING_RANKS = 2
export const BARTERING_PERCENT = 5

/**
 * A vendor buy's discounts as the step list says them, "after discount", without saying which (its tooltip names
 * them and their numbers); "" without either.
 */
export function discountLabel(discount: number, repDiscount = 0): string {
  return discount > 0 || repDiscount > 0 ? 'after discount' : ''
}

/** A sale's expected extra units from Master Chef, e.g. "+0.3 expected from Master Chef"; "" without any. */
export function bonusNote(bonus: number): string {
  return bonus > 0 ? `+${Number(bonus.toFixed(2))} expected from Master Chef` : ''
}
