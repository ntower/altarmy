import type { CharacterGroup, Selection } from '../api/client'
import { type Holder, type ProfessionChoice, professionsOf, professionsToImagine } from './setup'

/*
 * The Profit page's paths: /profit (the start, then what the user is after), /profit/gold (making gold),
 * /profit/skill (which profession), /profit/skill/<realm>/<character>/<profession> (one character skilling up one
 * profession: a link to it opens exactly that, switching the realm) and /profit/skill/<realm>/<profession>/<skill>
 * (a character nobody uploaded skilling up one profession from that skill; the last part is all digits, which a
 * profession's never is). /profit/vendorcheck (what the selected realm's auction house lists beside the vendor
 * price) is reached only by its path: nothing links it. With the strategy picker (`STRATEGY_PICKER`),
 * /profit/gold/<strategy> is one way to make gold (`lib/strategies.ts`); /profit/gold/disenchant, from before
 * disenchanting became a filter, goes to /profit/gold/craft?exit=disenchant.
 */

export type ProfitView =
  | { kind: 'start' }
  /** without a `strategy`, the picker (or, without `STRATEGY_PICKER`, the one gold list) */
  | { kind: 'gold'; strategy?: GoldStrategy }
  | { kind: 'skill' }
  /** `realm` and `profession` as slugs (`realmSlug`, `professionSlug`), `character` as named */
  | { kind: 'run'; realm: string; character: string; profession: string }
  /** a character nobody uploaded, with `profession` (a slug) at `skill` on `realm` (a slug) */
  | { kind: 'hypothetical'; realm: string; profession: string; skill: number }
  | { kind: 'vendorcheck' }
  /** a path kept for old links: the page now at `to` */
  | { kind: 'moved'; to: string }

/** The ways to make gold that have a page (`lib/strategies.ts`). */
export const GOLD_STRATEGY_KEYS = ['craft', 'process', 'vendor', 'held'] as const
export type GoldStrategy = (typeof GOLD_STRATEGY_KEYS)[number]
const isStrategy = (key: string): key is GoldStrategy => (GOLD_STRATEGY_KEYS as readonly string[]).includes(key)

/** Lower-case words joined by dashes: "Classic Beta PvE" is "classic-beta-pve", "First Aid" "first-aid". */
const slug = (text: string) =>
  text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')

/** A realm and faction in a path: "dreamscythe-horde"; the realm alone for a house both factions share. */
export const realmSlug = ({ realm, faction }: Selection): string => slug(faction ? `${realm} ${faction}` : realm)

export const professionSlug = (name: string): string => slug(name)

/** What the Profit page shows at `pathname`; null for a path under it that means nothing. */
export function parseProfitPath(pathname: string): ProfitView | null {
  const parts = pathname.replace(/\/+$/, '').split('/').slice(2)
  const [first, ...rest] = parts
  if (first === undefined) return { kind: 'start' }
  if (first === 'gold' && rest.length === 0) return { kind: 'gold' }
  if (first === 'gold' && rest.length === 1 && rest[0] === 'disenchant')
    return { kind: 'moved', to: '/profit/gold/craft?exit=disenchant' }
  if (first === 'gold' && rest.length === 1 && isStrategy(rest[0] ?? '')) return { kind: 'gold', strategy: rest[0] as GoldStrategy }
  if (first === 'vendorcheck' && rest.length === 0) return { kind: 'vendorcheck' }
  if (first !== 'skill') return null
  if (rest.length === 0) return { kind: 'skill' }
  if (rest.length !== 3 || rest.some((p) => !p)) return null
  try {
    const [realm, second, third] = rest.map(decodeURIComponent) as [string, string, string]
    if (/^\d+$/.test(third)) {
      const skill = Number(third)
      return skill > 0 ? { kind: 'hypothetical', realm, profession: second, skill } : null
    }
    return { kind: 'run', realm, character: second, profession: third }
  } catch {
    return null // a malformed escape
  }
}

/** The path of a view of the Profit page. */
export function profitPath(view: ProfitView): string {
  switch (view.kind) {
    case 'start':
      return '/profit'
    case 'gold':
      return view.strategy ? `/profit/gold/${view.strategy}` : '/profit/gold'
    case 'moved':
      return view.to
    case 'skill':
      return '/profit/skill'
    case 'vendorcheck':
      return '/profit/vendorcheck'
    case 'run':
      return `/profit/skill/${[view.realm, view.character, view.profession].map(encodeURIComponent).join('/')}`
    case 'hypothetical':
      return `/profit/skill/${[view.realm, view.profession, String(view.skill)].map(encodeURIComponent).join('/')}`
  }
}

/** The path of `character` on `group`'s realm skilling up `profession`. */
export const runPath = (group: Selection, character: string, profession: string): string =>
  profitPath({ kind: 'run', realm: realmSlug(group), character, profession: professionSlug(profession) })

/** The path of a character nobody uploaded skilling up `profession` from `skill` on `realm`. */
export const hypotheticalPath = (realm: Selection, profession: string, skill: number): string =>
  profitPath({ kind: 'hypothetical', realm: realmSlug(realm), profession: professionSlug(profession), skill })

export type ResolvedHypothetical = { realm: Selection; profession: string; skill: number }

/**
 * The auction house (among `houses`, the realms with prices) and profession (among `professionNames`, the version's
 * with recipes, as `professionsToImagine` offers them) a hypothetical climb's path names; null when there is no such
 * house or profession.
 */
export function resolveHypothetical(
  view: Extract<ProfitView, { kind: 'hypothetical' }>,
  houses: readonly Selection[],
  professionNames: readonly string[],
): ResolvedHypothetical | null {
  const slug = view.realm.toLowerCase()
  const house = houses.find((h) => realmSlug(h) === slug)
  const choice = professionsToImagine(professionNames).find(
    (p) => professionSlug(p.name) === view.profession.toLowerCase(),
  )
  return house && choice ? { realm: { realm: house.realm, faction: house.faction }, profession: choice.name, skill: view.skill } : null
}

export type ResolvedRun = { group: CharacterGroup; professions: ProfessionChoice[]; choice: ProfessionChoice; holder: Holder }

/**
 * The character group, profession and character a run's path names, among the user's characters (`professionNames`
 * as `professionsOf` takes them); null when they have no such character, or it hasn't that profession.
 */
export function resolveRun(
  view: Extract<ProfitView, { kind: 'run' }>,
  groups: readonly CharacterGroup[],
  professionNames?: readonly string[],
): ResolvedRun | null {
  const realm = view.realm.toLowerCase()
  const group = groups.find((g) => realmSlug(g) === realm)
  if (!group) return null
  const professions = professionsOf(group, professionNames)
  const choice = professions.find((p) => professionSlug(p.name) === view.profession.toLowerCase())
  const holder = choice?.holders.find((h) => h.name.toLowerCase() === view.character.toLowerCase())
  return choice && holder ? { group, professions, choice, holder } : null
}
