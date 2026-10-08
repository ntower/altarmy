import type { FlowNode, ProfessionRank, RankResult } from '../api/client'
import { formatCoords } from './time'

/*
 * Skilling up: what a skill point costs, and how far a run of a recipe goes (the server's `runs`: the first run of
 * the cheapest climb up the profession that starts with the recipe, until the climb goes on with another).
 */

/** What an expected skill point costs in copper (negative when the run earns gold); null when it gives none. */
export const perPoint = (r: Pick<RankResult, 'profit' | 'skill_ups'>): number | null =>
  r.skill_ups ? -r.profit / r.skill_ups : null

/** The profession ranks to train during a run from `from` to `to` skill (the climb assumes the climber trains each
 * as it comes): those above the cap they have (`maxRank`) that a trainer teaches by `to`, and not before `from`,
 * where the run before already said so; the `first` run, from the climber's own skill, says every one they can train
 * already. Each with the cap the skill stops at without it. */
export function ranksToTrain(
  ranks: readonly ProfessionRank[],
  maxRank: number,
  from: number,
  to: number,
  first: boolean,
): { rank: ProfessionRank; stopsAt: number }[] {
  return ranks.flatMap((rank, i) =>
    rank.cap > maxRank && rank.train_at <= to && (first || rank.train_at > from)
      ? [{ rank, stopsAt: ranks[i - 1]?.cap ?? maxRank }]
      : [],
  )
}

/** The cap of the profession rank `skill` is within (the first whose cap is at or above it), `fallback` past the last
 * or before the ranks load: what a character nobody uploaded is taken to have trained to. */
export const rankCap = (ranks: readonly ProfessionRank[], skill: number, fallback: number): number =>
  ranks.find((r) => r.cap >= skill)?.cap ?? fallback

type Count = Pick<RankResult, 'crafts' | 'stop_skill' | 'reach_chances'>

/** Whether the run's crafts surely reach its skill: the chance after them exactly 1 (every craft a sure point), not
 * one that merely rounds to 100%. */
const certain = (r: Pick<RankResult, 'crafts' | 'reach_chances'>): boolean => r.reach_chances?.[r.crafts - 1] === 1

/** The results table's Craft until: the skill a run takes the crafter to and its crafts, "110 (~17 crafts)",
 * "110 (17 crafts)" when certain, "110 (1 craft)"; just the crafts without a run. */
export function craftUntil(r: Count): string {
  const crafts = r.crafts === 1 ? '1 craft' : `${certain(r) ? '' : '~'}${r.crafts} crafts`
  return r.stop_skill ? `${r.stop_skill} (${crafts})` : crafts
}

/** The default chance, in percent, that the crafts a run's checklist buys for reach its skill. */
export const DEFAULT_REACH_TARGET = 80
/** The most the user may ask for (the server's odds go at least this far). */
export const MAX_REACH_TARGET = 95
export const MIN_REACH_TARGET = 50

/** The crafts to buy for so that a run reaches its `stop_skill` with at least `target` percent chance: never fewer
 * than its expected crafts; when the odds the server sent never get there, as many as they go to (without them, the
 * crafts four times in five). */
export function craftsToReach(r: Pick<RankResult, 'crafts' | 'crafts_p80' | 'reach_chances'>, target: number): number {
  const odds = r.reach_chances ?? []
  const at = odds.findIndex((chance) => chance >= target / 100 - 1e-9)
  return Math.max(r.crafts, at === -1 ? Math.max(odds.length, r.crafts_p80) : at + 1)
}

type Run = Count & Pick<RankResult, 'stop_reason' | 'overtaken_by'>

/** How far to craft: "Craft until 85 skill (~17 times)", "(17 times)" when certain, "(once)"; "Craft ~17 times"
 * without the skill. */
export function runLead(r: Count): string {
  const times = r.crafts === 1 ? 'once' : `${certain(r) ? '' : '~'}${r.crafts} times`
  return r.stop_skill ? `Craft until ${r.stop_skill} skill (${times})` : `Craft ${times}`
}

/** Why the run stops there, after the lead's ", at which point ": "this recipe is about to turn grey", "you reach your
 * skill cap"; for a rival, the words around its name; null when the most crafts a run asks for cut it short. */
export function runReason(r: Pick<Run, 'stop_reason'>): string | null {
  switch (r.stop_reason) {
    case 'trivial':
      return 'this recipe turns grey'
    case 'cap':
      return 'you reach your skill cap'
    default:
      return null
  }
}

/** The article before `word`: "an" before a vowel ("an Alchemy trainer"), else "a". */
export const an = (word: string): string => (/^[aeiou]/i.test(word) ? 'an' : 'a')

export const AT_WHICH_POINT = ', at which point '
export const CHEAPER = ' becomes a cheaper option'

/** The whole run as plain text: "Craft until 85 skill (~17 times), at which point Heavy Copper Maul becomes a
 * cheaper option", "…, at which point this recipe is about to turn grey"; just the lead when the ceiling cut it short. */
export function runText(r: Run): string {
  const lead = runLead(r)
  if (r.stop_reason === 'rival') return `${lead}${AT_WHICH_POINT}${r.overtaken_by || 'another recipe'}${CHEAPER}`
  const reason = runReason(r)
  return reason ? `${lead}${AT_WHICH_POINT}${reason}` : lead
}

const up = (n: number, f: number) => Math.ceil(n * f - 1e-9)

/** A flow chart node, and the nodes it is made from, scaled by `f`: units and crafts rounded up, copper rounded. */
function scaleNode(n: FlowNode, f: number): FlowNode {
  return {
    ...n,
    quantity: up(n.quantity, f),
    crafts: up(n.crafts, f),
    made: up(n.made, f),
    cost: Math.round(n.cost * f),
    postage: Math.round(n.postage * f),
    options: n.options.map((o) => ({ ...o, cost: Math.round(o.cost * f) })),
    inputs: n.inputs.map((i) => scaleNode(i, f)),
  }
}

/** A plan's steps and flow chart for `crafts` crafts instead of its own, each quantity (rounded up) and amount in
 * proportion: what the run shows at once while the server plans that many. */
export function scaleRun<T extends Pick<RankResult, 'crafts' | 'steps' | 'tree'>>(r: T, crafts: number): T {
  if (crafts === r.crafts || r.crafts <= 0 || crafts <= 0) return r
  const f = crafts / r.crafts
  return {
    ...r,
    crafts,
    steps: r.steps.map((s) => ({ ...s, quantity: up(s.quantity, f), value: Math.round(s.value * f) })),
    tree: scaleNode(r.tree, f),
  }
}

type PlainStep = Pick<RankResult['steps'][number], 'action' | 'name' | 'quantity' | 'via' | 'who' | 'enchant'>

/** One step as plain text, for the checklist copied into the game session; `vendor` names the vendor stood at. */
function stepText({ action, name, quantity, via, who, enchant }: PlainStep, vendor?: string): string {
  const what = `${quantity}x ${name}`
  const line = (() => {
    switch (action) {
      case 'buy':
        return `Buy ${what} ${via === 'ah' ? 'on the AH' : `from ${vendor ?? 'a vendor'}`}`
      case 'gather':
        return `Gather ${what}`
      case 'craft':
        return enchant ? `Cast ${name} ${quantity === 1 ? 'once' : `${quantity} times`}` : `Craft ${what}`
      case 'mail':
        return `Mail ${what} to ${via}`
      case 'sell':
        if (via === 'keep') return `Keep the ${what}`
        if (via === 'disenchant') return `Disenchant ${what} and auction the materials`
        return `Sell ${what} ${via === 'ah' ? 'on the AH' : `to ${vendor ?? 'a vendor'}`}`
      default:
        return `${action} ${what}`
    }
  })()
  return who ? `${who}: ${line}` : line
}

type PlainDetail = Pick<RankResult['details'][number], 'kind' | 'who' | 'location' | 'retrieve' | 'step'>

/** Where a detail line goes, as plain text: "Run to Mailbox at 50.0, 70.4. Retrieve 200x Linen Cloth." */
function placeText(verb: string, d: PlainDetail, itemName: (id: number) => string): string {
  const { name, map_x: x, map_y: y } = d.location!
  const at = x != null && y != null ? ` at ${formatCoords(x, y)}` : ''
  const retrieve = d.retrieve.map((r) => `${r.count}x ${itemName(r.item_id)}`).join(', ')
  const line = verb === 'Run to' ? `${verb} ${name}${at}.${retrieve ? ` Retrieve ${retrieve}.` : ''}` : `${verb} ${name}${at}`
  return d.who ? `${d.who}: ${line}` : line
}

/** A plan's steps as a numbered plain-text checklist, under a heading; with `details` (the detailed view), with
 * where to go in between, items retrieved named by `itemName`. */
export function stepsText(
  heading: string,
  steps: readonly PlainStep[],
  details: readonly PlainDetail[] = [],
  itemName: (id: number) => string = (id) => `item ${id}`,
): string {
  const lines: string[] = []
  if (details.length === 0) lines.push(...steps.map((s) => stepText(s)))
  let vendor: string | undefined
  for (const d of details) {
    if (d.kind === 'switch') {
      vendor = undefined
      lines.push(`Switch to ${d.who}`)
    } else if (d.kind === 'start' || d.kind === 'go') {
      vendor = d.location?.kind === 'vendor' ? d.location.name : undefined
      if (d.location) lines.push(placeText(d.kind === 'go' ? 'Run to' : 'Start at', d, itemName))
    } else {
      const step = d.step == null ? undefined : steps[d.step]
      if (step) lines.push(stepText(step, vendor))
    }
  }
  return [heading, ...lines.map((l, i) => `${i + 1}. ${l}`)].join('\n')
}
