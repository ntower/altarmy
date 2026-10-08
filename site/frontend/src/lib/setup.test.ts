import { describe, expect, it } from 'vitest'
import type { CharacterGroup } from '../api/client'
import { filterRealmSkills, filterSkills, presetsFor, professionsOf, searchKey, skillsByCharacter, skillsByRealm, storePresets } from './setup'

describe('professionsOf', () => {
  it('leaves out Fishing, Herbalism, Mining and Skinning', () => {
    const profession = (name: string) => ({ name, rank: 1, max_rank: 75, recipes: 1 })
    const group = {
      realm: 'R',
      faction: 'Horde',
      characters: [
        {
          name: 'Amy',
          class_file: 'MAGE',
          level: 22,
          professions: [
            profession('Fishing'),
            profession('Herbalism'),
            profession('Mining'),
            profession('Skinning'),
            profession('Tailoring'),
          ],
          talents: [],
          vendor_discounts: [],
        },
      ],
    }
    expect(professionsOf(group as CharacterGroup).map((p) => p.name)).toEqual(['Tailoring'])
  })
})

describe('skillsByCharacter', () => {
  it('groups the professions by character, both alphabetically', () => {
    const holder = (name: string, rank: number) => ({ name, classFile: 'MAGE', level: 22, rank, maxRank: 75 })
    const characters = skillsByCharacter([
      { name: 'Tailoring', holders: [holder('Zed', 10), holder('Amy', 20)] },
      { name: 'Cooking', holders: [holder('Zed', 30)] },
    ])
    expect(characters.map((c) => c.name)).toEqual(['Amy', 'Zed'])
    expect(characters[1]?.professions).toEqual([
      { name: 'Cooking', rank: 30, maxRank: 75 },
      { name: 'Tailoring', rank: 10, maxRank: 75 },
    ])
  })
})

describe('skillsByRealm', () => {
  const profession = (name: string, rank = 1) => ({ name, rank, max_rank: 75, recipes: 1 })
  const someone = (name: string, professions: ReturnType<typeof profession>[]) => ({
    name,
    class_file: 'MAGE',
    level: 22,
    professions,
    talents: [],
    vendor_discounts: [],
  })
  const groups = [
    { realm: 'Zandalar', faction: 'Horde', characters: [someone('Zed', [profession('Tailoring')])] },
    { realm: 'Atiesh', faction: 'Alliance', characters: [someone('Gatherer', [profession('Mining')])] },
    {
      realm: 'Atiesh',
      faction: 'Horde',
      characters: [someone('Bo', [profession('Tailoring'), profession('Cooking')]), someone('Al', [profession('Alchemy')])],
    },
  ] as CharacterGroup[]

  it('groups by realm and faction, then character, then profession, dropping empty realms', () => {
    const realms = skillsByRealm(groups)
    expect(realms.map((r) => r.label)).toEqual(['Atiesh (Horde)', 'Zandalar (Horde)']) // nobody to skill up on Atiesh (Alliance)
    expect(realms[0]?.realm).toEqual({ realm: 'Atiesh', faction: 'Horde' })
    expect(realms[0]?.characters.map((c) => `${c.name}: ${c.professions.map((p) => p.name).join(', ')}`)).toEqual([
      'Al: Alchemy',
      'Bo: Cooking, Tailoring',
    ])
  })

  it('puts the realm with the most characters first', () => {
    const more = [
      ...groups,
      {
        realm: 'Yojamba',
        faction: 'Alliance',
        characters: ['Cy', 'Di', 'Ed'].map((n) => someone(n, [profession('Cooking')])),
      },
    ] as CharacterGroup[]
    expect(skillsByRealm(more).map((r) => r.label)).toEqual(['Yojamba (Alliance)', 'Atiesh (Horde)', 'Zandalar (Horde)'])
  })

  it('narrows by realm, character or profession', () => {
    const shown = (query: string) =>
      filterRealmSkills(skillsByRealm(groups), query).map((r) => `${r.label}: ${r.characters.map((c) => c.name).join(', ')}`)
    expect(shown('zanda')).toEqual(['Zandalar (Horde): Zed'])
    expect(shown('tailor')).toEqual(['Atiesh (Horde): Bo', 'Zandalar (Horde): Zed'])
    expect(shown('alch')).toEqual(['Atiesh (Horde): Al'])
    expect(shown('nothing')).toEqual([])
  })
})

describe('filterSkills', () => {
  const characters = [
    { name: 'Amy', classFile: 'MAGE', level: 22, professions: [{ name: 'Cooking', rank: 1, maxRank: 75 }] },
    {
      name: 'Frell',
      classFile: 'ROGUE',
      level: 60,
      professions: [
        { name: 'Cooking', rank: 1, maxRank: 75 },
        { name: 'Tailoring', rank: 1, maxRank: 75 },
      ],
    },
  ]
  const shown = (query: string) =>
    filterSkills(characters, query).map((c) => `${c.name}: ${c.professions.map((p) => p.name).join(', ')}`)

  it('keeps every profession of a character whose name matches', () => {
    expect(shown('frel')).toEqual(['Frell: Cooking, Tailoring'])
  })

  it('keeps only the matching professions, and drops characters with none', () => {
    expect(shown('TAIL')).toEqual(['Frell: Tailoring'])
    expect(shown(' cook ')).toEqual(['Amy: Cooking', 'Frell: Cooking'])
    expect(shown('zzz')).toEqual([])
  })

  it('keeps everything without a query', () => {
    expect(shown('')).toEqual(['Amy: Cooking', 'Frell: Cooking, Tailoring'])
  })
})

describe('storePresets', () => {
  it("writes an aim's presets under its keys only", () => {
    storePresets('skill', presetsFor('skill'))
    expect(localStorage.getItem(searchKey('skill', 'exits'))).toBe('["vendor","disenchant","keep"]')
    expect(localStorage.getItem(searchKey('skill', 'minProfit'))).toBe('null')
    expect(localStorage.getItem(searchKey('gold', 'exits'))).toBeNull()
    storePresets('gold')
    expect(localStorage.getItem(searchKey('gold', 'exits'))).toBe('["vendor","disenchant","ah"]')
    expect(localStorage.getItem(searchKey('gold', 'minProfit'))).toBe('0.0001') // making gold sells every way
    expect(localStorage.getItem(searchKey('skill', 'exits'))).toBe('["vendor","disenchant","keep"]')
  })

  it('keeps what the user changed when the aim is picked again', () => {
    localStorage.setItem(searchKey('gold', 'minProfit'), '5')
    storePresets('gold')
    expect(localStorage.getItem(searchKey('gold', 'minProfit'))).toBe('5')
    expect(localStorage.getItem(searchKey('gold', 'minRoi'))).toBe('0')
  })
})
