import { describe, expect, it } from 'vitest'
import { characters } from '../test/status'
import {
  hypotheticalPath,
  parseProfitPath,
  professionSlug,
  profitPath,
  realmSlug,
  resolveHypothetical,
  resolveRun,
  runPath,
  type ProfitView,
} from './profitRoute'

describe('the Profit page paths', () => {
  it('reads each view from its path', () => {
    expect(parseProfitPath('/profit')).toEqual({ kind: 'start' })
    expect(parseProfitPath('/profit/')).toEqual({ kind: 'start' })
    expect(parseProfitPath('/profit/gold')).toEqual({ kind: 'gold' })
    expect(parseProfitPath('/profit/skill')).toEqual({ kind: 'skill' })
    expect(parseProfitPath('/profit/vendorcheck')).toEqual({ kind: 'vendorcheck' })
    expect(parseProfitPath('/profit/skill/dreamscythe-horde/Frell/first-aid')).toEqual({
      kind: 'run',
      realm: 'dreamscythe-horde',
      character: 'Frell',
      profession: 'first-aid',
    })
    // a character nobody uploaded: the profession, then the skill (all digits, which a profession's slug never is)
    expect(parseProfitPath('/profit/skill/dreamscythe-horde/first-aid/45')).toEqual({
      kind: 'hypothetical',
      realm: 'dreamscythe-horde',
      profession: 'first-aid',
      skill: 45,
    })
  })

  it('means nothing by any other path under it', () => {
    for (const path of [
      '/profit/nope',
      '/profit/gold/x',
      '/profit/vendorcheck/x',
      '/profit/skill/r/c',
      '/profit/skill/r//p',
      '/profit/skill/r/%E0/p',
      '/profit/skill/r/tailoring/0',
    ]) {
      expect(parseProfitPath(path)).toBeNull()
    }
  })

  it('writes each view as the path it reads back from', () => {
    const views: ProfitView[] = [
      { kind: 'start' },
      { kind: 'gold' },
      { kind: 'skill' },
      { kind: 'vendorcheck' },
      { kind: 'run', realm: 'classic-beta-pve-horde', character: 'Ëlf Guy', profession: 'tailoring' },
      { kind: 'hypothetical', realm: 'classic-beta-pve-horde', profession: 'first-aid', skill: 120 },
    ]
    for (const view of views) expect(parseProfitPath(profitPath(view))).toEqual(view)
  })

  it('names realms and professions as lower-case words joined by dashes', () => {
    expect(realmSlug({ realm: 'Dreamscythe', faction: 'Horde' })).toBe('dreamscythe-horde')
    expect(realmSlug({ realm: "Mograine's Rest", faction: '' })).toBe('mograine-s-rest')
    expect(professionSlug('First Aid')).toBe('first-aid')
    expect(runPath({ realm: 'Classic Beta PvE', faction: 'Horde' }, 'Tailor Guy', 'Tailoring')).toBe(
      '/profit/skill/classic-beta-pve-horde/Tailor%20Guy/tailoring',
    )
    expect(hypotheticalPath({ realm: 'Classic Beta PvE', faction: 'Horde' }, 'First Aid', 45)).toBe(
      '/profit/skill/classic-beta-pve-horde/first-aid/45',
    )
  })
})

describe('resolveHypothetical', () => {
  const houses = [
    { realm: 'Classic Beta PvE', faction: 'Horde' },
    { realm: 'Dreamscythe', faction: 'Alliance' },
  ]
  const view = (realm: string, profession: string, skill = 45) => ({ kind: 'hypothetical', realm, profession, skill }) as const

  it('finds the priced house and the profession a path names, ignoring case', () => {
    const found = resolveHypothetical(view('Classic-Beta-PvE-Horde', 'first-aid'), houses, ['First Aid', 'Tailoring'])
    expect(found).toEqual({ realm: houses[0], profession: 'First Aid', skill: 45 })
  })

  it('finds nothing for a realm without prices or a profession nobody skills up', () => {
    expect(resolveHypothetical(view('nowhere-horde', 'tailoring'), houses, ['Tailoring'])).toBeNull()
    expect(resolveHypothetical(view('dreamscythe-alliance', 'alchemy'), houses, ['Tailoring'])).toBeNull()
    expect(resolveHypothetical(view('dreamscythe-alliance', 'mining'), houses, ['Mining', 'Tailoring'])).toBeNull()
    expect(resolveHypothetical(view('dreamscythe-alliance', 'herbalism'), houses, ['Herbalism', 'Tailoring'])).toBeNull()
  })
})

describe('resolveRun', () => {
  const run = (realm: string, character: string, profession: string) =>
    ({ kind: 'run', realm, character, profession }) as const

  it('finds the group, profession and character a path names, ignoring case', () => {
    const found = resolveRun(run('classic-beta-pve-horde', 'tailor guy', 'Tailoring'), characters.groups)
    expect(found?.group.realm).toBe('Classic Beta PvE')
    expect(found?.choice.name).toBe('Tailoring')
    expect(found?.holder.name).toBe('Tailor Guy')
    expect(found?.professions.map((p) => p.name)).toEqual(['Cooking', 'Tailoring'])
  })

  it('finds nothing for another realm, character or profession', () => {
    expect(resolveRun(run('dreamscythe-horde', 'Tailor Guy', 'tailoring'), characters.groups)).toBeNull()
    expect(resolveRun(run('classic-beta-pve-horde', 'Frell', 'tailoring'), characters.groups)).toBeNull()
    expect(resolveRun(run('classic-beta-pve-horde', 'Tailor Guy', 'alchemy'), characters.groups)).toBeNull()
    // a profession without recipes in this version isn't one to skill up
    expect(resolveRun(run('classic-beta-pve-horde', 'Tailor Guy', 'cooking'), characters.groups, ['Tailoring'])).toBeNull()
  })
})
