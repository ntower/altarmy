import { z } from 'zod'
import type { CharacterGroup, Selection } from '../api/client'
import type { Exit, Unlearned } from '../api/queries'
import { realmLabel } from './realms'
import { isStored, writeStored } from './storage'
import { craftingTalents, type CraftingTalent } from './talents'

/*
 * The Profit page's setup: a few questions asked before the search, each setting one thing about it. What the user is
 * after (gold, or skill in one profession), and for skill which profession and who. Making gold asks nothing more: its
 * list shows what playing it safe and what the auction house make side by side, and the user sorts by either. The
 * answers are the page's path (`profitRoute.ts`); the last ones are also stored, to mark them when asked again.
 */

export const aimSchema = z.enum(['gold', 'skill'])
const sellingSchema = z.enum(['reliable', 'any'])
export type Aim = z.infer<typeof aimSchema>

/** The answers given last, marked when the questions are asked again; the ones a changed aim no longer asks are kept
 * for when it comes back. Keys it no longer knows (a budget, from before that question was dropped) are stripped when
 * read. */
export const setupSchema = z.object({
  aim: aimSchema,
  profession: z.string().optional(),
  /** Which of the profession's holders is being skilled up (one; several from before one climbed at a time); unset:
   * the one who has it. */
  characters: z.array(z.string()).optional(),
  /** Skilling up a character nobody uploaded: the skill they start from (`CLIMBER_NAME` is then who). */
  climberSkill: z.number().optional(),
  /** How to sell, from when making gold asked; no longer asked or read (both ways show side by side). */
  selling: sellingSchema.optional(),
})
export type Setup = z.infer<typeof setupSchema>
export type Step = 'aim' | 'profession'

/** Every way to sell, in the order the filters list them. */
export const ALL_EXITS: readonly Exit[] = ['vendor', 'disenchant', 'ah']
/** Skilling up sells what is made to a vendor or disenchants it (when someone can), else keeps it. */
export const SKILL_EXITS: readonly Exit[] = ['vendor', 'disenchant', 'keep']

export type Card<K extends string> = {
  key: K
  title: string
  blurb: string
  details?: string
  /** Said after `details`, highlighted, and followed by `points` as a list. */
  caution?: string
  points?: readonly string[]
}

export const STEP_QUESTION: Readonly<Record<Step, string>> = {
  aim: "What's your goal?",
  profession: 'Which profession?',
}

export const AIMS: readonly Card<Aim>[] = [
  {
    key: 'skill',
    title: 'Skill up',
    blurb: 'Find the ideal sequence for leveling up your professions.',
  },
  {
    key: 'gold',
    title: 'Make gold',
    blurb: 'Find the best ways to turn your professions into profits.',
  },
]

/** One character having a profession, at what skill, and the Legacy talents that matter to it (`craftingTalents`). */
export type Holder = {
  name: string
  classFile: string
  level: number
  rank: number
  maxRank: number
  talents?: CraftingTalent[]
}

/** A profession someone on the realm has, and who. */
export type ProfessionChoice = { name: string; holders: Holder[] }

/** The secondary professions (any character may have all of them, on top of two primary ones), by lower-case name. */
const SECONDARY = new Set(['cooking', 'first aid', 'fishing'])

/** Whether a profession is a secondary one (Cooking, First Aid, Fishing). */
export const isSecondary = (profession: string): boolean => SECONDARY.has(profession.toLowerCase())

/** Gathering professions and Fishing, never offered for skilling up, though a few recipes name them (Mining's smelting, Skinning's). */
const NOT_SKILLED = new Set(['fishing', 'herbalism', 'mining', 'skinning'])

/**
 * What a character nobody uploaded is called: the server plans for whatever one name `skill_crafters` gives with
 * `climber_skill`, and the plan's steps and notes say it ("Your character's steps"). Never a comma (names are joined
 * on them) and never all digits (a path's skill is).
 */
export const CLIMBER_NAME = 'Your character'

/**
 * The professions someone could skill up without having uploaded a character: every one of the version's with
 * recipes (`withRecipes`), Fishing, Herbalism, Mining and Skinning left out, nobody holding them, alphabetically.
 */
export const professionsToImagine = (withRecipes: readonly string[]): ProfessionChoice[] =>
  withRecipes
    .filter((name) => !NOT_SKILLED.has(name.toLowerCase()))
    .map((name) => ({ name, holders: [] }))
    .sort((a, b) => a.name.localeCompare(b.name))

/**
 * The one profession a character nobody uploaded skills up, held by `CLIMBER_NAME` at `skill` of `maxRank` (the cap
 * of the rank that skill is in, so the training reminders still come), so the search and workspace take them as any
 * holder.
 */
export const hypotheticalProfessions = (profession: string, skill: number, maxRank: number): ProfessionChoice[] => [
  { name: profession, holders: [{ name: CLIMBER_NAME, classFile: '', level: 0, rank: skill, maxRank }] },
]

/**
 * The professions the group's characters have, by name, each once, with who has it at what skill, Fishing, Herbalism, Mining
 * and Skinning left out. With `withRecipes` (the version's professions that have recipes), only those: gathering skills have nothing
 * to rank.
 */
export function professionsOf(
  group: CharacterGroup | undefined,
  withRecipes?: readonly string[],
): ProfessionChoice[] {
  const ranked = withRecipes && new Set(withRecipes.map((n) => n.toLowerCase()))
  const byName = new Map<string, ProfessionChoice>()
  for (const c of group?.characters ?? []) {
    for (const p of c.professions) {
      const key = p.name.toLowerCase()
      if ((ranked && !ranked.has(key)) || NOT_SKILLED.has(key)) continue
      const entry = byName.get(key) ?? { name: p.name, holders: [] }
      const talents = craftingTalents(c.talents, p.name)
      entry.holders.push({
        name: c.name,
        classFile: c.class_file,
        level: c.level,
        rank: p.rank,
        maxRank: p.max_rank,
        ...(talents.length ? { talents } : {}),
      })
      byName.set(key, entry)
    }
  }
  return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
}

/** One character and the professions they could skill up, at what skill. */
export type CharacterSkills = {
  name: string
  classFile: string
  level: number
  professions: { name: string; rank: number; maxRank: number }[]
}

/** `professions` turned around: per character (alphabetically), their professions (alphabetically). */
export function skillsByCharacter(professions: readonly ProfessionChoice[]): CharacterSkills[] {
  const byName = new Map<string, CharacterSkills>()
  for (const p of professions) {
    for (const h of p.holders) {
      const entry = byName.get(h.name) ?? { name: h.name, classFile: h.classFile, level: h.level, professions: [] }
      entry.professions.push({ name: p.name, rank: h.rank, maxRank: h.maxRank })
      byName.set(h.name, entry)
    }
  }
  const characters = [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
  for (const c of characters) c.professions.sort((a, b) => a.name.localeCompare(b.name))
  return characters
}

/** The characters and professions matching `query` (case-insensitive, anywhere in the name): every profession of a
 * character whose name matches, else those whose own name does; characters left with none are dropped. */
export function filterSkills(characters: readonly CharacterSkills[], query: string): CharacterSkills[] {
  const q = query.trim().toLowerCase()
  if (!q) return [...characters]
  return characters.flatMap((c) => {
    if (c.name.toLowerCase().includes(q)) return [c]
    const professions = c.professions.filter((p) => p.name.toLowerCase().includes(q))
    return professions.length ? [{ ...c, professions }] : []
  })
}

/** A realm and faction's characters and the professions they could skill up, labelled "Realm (Faction)". */
export type RealmSkills = { realm: Selection; label: string; characters: CharacterSkills[] }

/**
 * Every character group's characters and professions (as `professionsOf` takes `withRecipes`), by realm and faction
 * (the one with the most characters first, ties alphabetically; groups with nobody to skill up left out), then by
 * character, then by profession.
 */
export function skillsByRealm(groups: readonly CharacterGroup[], withRecipes?: readonly string[]): RealmSkills[] {
  return groups
    .map((g) => ({
      realm: { realm: g.realm, faction: g.faction },
      label: realmLabel(g),
      size: g.characters.length,
      characters: skillsByCharacter(professionsOf(g, withRecipes)),
    }))
    .filter((r) => r.characters.length > 0)
    .sort((a, b) => b.size - a.size || a.label.localeCompare(b.label))
    .map(({ size: _size, ...r }) => r)
}

/** `filterSkills` within each realm (every character of a realm whose label matches); realms left with none are
 * dropped. */
export function filterRealmSkills(realms: readonly RealmSkills[], query: string): RealmSkills[] {
  const q = query.trim().toLowerCase()
  return realms.flatMap((r) => {
    if (q && r.label.toLowerCase().includes(q)) return [r]
    const characters = filterSkills(r.characters, query)
    return characters.length ? [{ ...r, characters }] : []
  })
}

/** Whether anyone in the group can disenchant. */
export const hasEnchanter = (group: CharacterGroup | undefined): boolean =>
  group?.characters.some((c) => c.professions.some((p) => p.name.toLowerCase() === 'enchanting')) ?? false

const professionIn = (professions: readonly ProfessionChoice[], name: string | undefined) =>
  professions.find((p) => p.name.toLowerCase() === name?.toLowerCase())

/**
 * The characters being skilled up: the picked profession's holders on the realm (those picked, if some were);
 * none when making gold. Only they do a recipe's final craft.
 */
export function skillCrafters(setup: Setup | null, professions: readonly ProfessionChoice[]): string[] {
  if (setup?.aim !== 'skill' || !setup.profession) return []
  const holders = professionIn(professions, setup.profession)?.holders ?? []
  const picked = setup.characters
  const names = holders.map((h) => h.name).filter((n) => !picked || picked.includes(n))
  return [...new Set(names)].sort()
}

/** The search filters a setup presets; the user may change them afterwards. Money in gold, as typed. */
export type Presets = {
  includeTrivial: boolean
  /** 0.0001 is one copper: only profitable recipes */
  minProfit: number | null
  /** percent; null lets losing recipes (negative ROI) through */
  minRoi: number | null
  exits: Exit[]
  /** which recipes nobody has learned count: skilling up looks at what can be trained too */
  unlearned: Unlearned
}

/** The filters an aim presets (the user may change them afterwards). */
export function presetsFor(aim: Aim): Presets {
  return aim === 'skill'
    ? // losing recipes may be the only way to skill up: no lower bound on profit or ROI; what is made along the way
      // is sold where it surely sells, not left on the auction house
      { includeTrivial: false, minProfit: null, minRoi: null, exits: [...SKILL_EXITS], unlearned: 'train' }
    : { includeTrivial: true, minProfit: 0.0001, minRoi: 0, exits: [...ALL_EXITS], unlearned: 'none' }
}

/**
 * Where an aim keeps one of its search filters: making gold and skilling up each remember their own, so answering one
 * never overwrites the other's. `legacySearchKey` is where every filter was kept before, read while an aim has none.
 */
export const searchKey = (aim: Aim, name: string) => `altarmy.search.${aim}.${name}`
export const legacySearchKey = (name: string) => `altarmy.search.${name}`

/**
 * Store the filters an aim presets under its keys, for its search to start from: only those it has none of yet, so
 * picking the aim again (every visit to the Profit page's start) keeps what the user changed.
 */
export function storePresets(aim: Aim, presets: Partial<Presets> = presetsFor(aim)) {
  for (const [name, value] of Object.entries(presets)) {
    const key = searchKey(aim, name)
    if (value !== undefined && !isStored(key)) writeStored(key, value)
  }
}

/** How the server ranks for this setup: the most profit, or the cheapest expected skill point. */
export const rankSort = (setup: Setup | null): 'profit' | 'skill' => (setup?.aim === 'skill' ? 'skill' : 'profit')

/** The professions the search is narrowed to: the one being skilled up. */
export const rankProfessions = (setup: Setup | null): string[] =>
  setup?.aim === 'skill' && setup.profession ? [setup.profession] : []
