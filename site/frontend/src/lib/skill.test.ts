import { describe, expect, it } from 'vitest'
import { professionRanks, robeResult } from '../test/results'
import { an, rangeText, tailText, craftsToReach, craftUntil, perPoint, ranksToTrain, runLead, runText, scaleRun, stepsText } from './skill'

describe('craftsToReach', () => {
  const run = { crafts: 3, crafts_p80: 5, reach_chances: [0, 0.2, 0.5, 0.79, 0.8, 0.9, 0.95] }
  it('buys for the first craft count whose odds reach the chance asked for, never fewer than expected', () => {
    expect(craftsToReach(run, 80)).toBe(5)
    expect(craftsToReach(run, 90)).toBe(6)
    expect(craftsToReach(run, 50)).toBe(3)
    expect(craftsToReach(run, 20)).toBe(3) // never under the expected crafts
  })
  it('goes as far as the odds go when they never get there, else the crafts four times in five', () => {
    expect(craftsToReach(run, 96)).toBe(7)
    expect(craftsToReach({ ...run, reach_chances: undefined }, 95)).toBe(5)
  })
})

describe('perPoint', () => {
  it('is what an expected skill point costs, negative when the run earns', () => {
    expect(perPoint({ ...robeResult, profit: -300, skill_ups: 3 })).toBe(100)
    expect(perPoint({ ...robeResult, profit: 300, skill_ups: 3 })).toBe(-100)
    expect(perPoint({ ...robeResult, skill_ups: 0 })).toBeNull()
  })
})

describe('ranksToTrain', () => {
  const names = (due: ReturnType<typeof ranksToTrain>) => due.map((d) => `${d.rank.name}<${d.stopsAt}`)

  it('names each rank above the cap on the run that reaches its training skill', () => {
    // a Journeyman (cap 150) at 100: Expert is taught from 125, Artisan from 200
    expect(names(ranksToTrain(professionRanks, 150, 100, 120, true))).toEqual([])
    expect(names(ranksToTrain(professionRanks, 150, 120, 130, false))).toEqual(['Expert<150'])
    expect(names(ranksToTrain(professionRanks, 150, 125, 160, false))).toEqual([]) // said on the run before
    expect(names(ranksToTrain(professionRanks, 150, 160, 210, false))).toEqual(['Artisan<225'])
    expect(names(ranksToTrain(professionRanks, 150, 110, 260, false))).toEqual(['Expert<150', 'Artisan<225'])
  })

  it('names on the first run every rank the climber can train already', () => {
    expect(names(ranksToTrain(professionRanks, 75, 60, 70, true))).toEqual(['Journeyman<75'])
    expect(names(ranksToTrain(professionRanks, 75, 60, 70, false))).toEqual([])
    expect(names(ranksToTrain(professionRanks, 300, 280, 300, true))).toEqual([]) // nothing above Artisan
  })
})

describe('runText', () => {
  it('says to which skill to craft, how many times, and why then', () => {
    const run = { crafts: 17, stop_skill: 85, stop_reason: 'rival', overtaken_by: 'Heavy Copper Maul' }
    expect(runText(run)).toBe(
      'Craft until 85 skill (~17 times), at which point Heavy Copper Maul becomes a cheaper option',
    )
    expect(runText({ ...run, stop_reason: 'trivial' })).toBe(
      'Craft until 85 skill (~17 times), at which point this recipe turns grey',
    )
    expect(runText({ ...run, stop_reason: 'cap' })).toBe(
      'Craft until 85 skill (~17 times), at which point you reach your skill cap',
    )
    expect(runText({ ...run, crafts: 100, stop_reason: 'ceiling' })).toBe('Craft until 85 skill (~100 times)')
    expect(runLead({ crafts: 1, stop_skill: 85 })).toBe('Craft until 85 skill (once)')
    expect(runLead({ crafts: 3, stop_skill: 0 })).toBe('Craft ~3 times')
  })

  it('drops the tilde only when the crafts surely reach the skill', () => {
    expect(runLead({ crafts: 3, stop_skill: 85, reach_chances: [0, 0, 1, 1] })).toBe('Craft until 85 skill (3 times)')
    expect(runLead({ crafts: 3, stop_skill: 85, reach_chances: [0, 0, 0.9999, 1] })).toBe(
      'Craft until 85 skill (~3 times)',
    )
    expect(craftUntil({ crafts: 3, stop_skill: 85, reach_chances: [0, 0, 1] })).toBe('85 (3 crafts)')
    expect(craftUntil({ crafts: 3, stop_skill: 85, reach_chances: [0, 0, 0.9999] })).toBe('85 (~3 crafts)')
  })

  it('says to which skill a run in the table goes, and in how many crafts', () => {
    expect(craftUntil({ crafts: 17, stop_skill: 110 })).toBe('110 (~17 crafts)')
    expect(craftUntil({ crafts: 1, stop_skill: 110 })).toBe('110 (1 craft)')
    expect(craftUntil({ crafts: 3, stop_skill: 0 })).toBe('~3 crafts')
  })
})

describe('stepsText', () => {
  it('writes the plan as a plain checklist', () => {
    const steps: Parameters<typeof stepsText>[1] = [
      { action: 'buy', name: 'Linen Cloth', quantity: 10, via: 'ah', who: 'Bob', enchant: false },
      { action: 'gather', name: 'Wool Cloth', quantity: 4, via: '', who: 'Bob', enchant: false },
      { action: 'craft', name: 'Green Robe', quantity: 1, via: 'Green Robe', who: 'Bob', enchant: false },
      { action: 'sell', name: 'Green Robe', quantity: 1, via: 'vendor', who: 'Bob', enchant: false },
    ]
    expect(stepsText('Tailoring: Green Robe', steps)).toBe(
      [
        'Tailoring: Green Robe',
        '1. Bob: Buy 10x Linen Cloth on the AH',
        '2. Bob: Gather 4x Wool Cloth',
        '3. Bob: Craft 1x Green Robe',
        '4. Bob: Sell 1x Green Robe to a vendor',
      ].join('\n'),
    )
  })
})

describe('stepsText with details', () => {
  it('spells out where to go and whom to switch to, naming the vendor stood at', () => {
    const steps: Parameters<typeof stepsText>[1] = [
      { action: 'buy', name: 'Coarse Thread', quantity: 2, via: 'vendor', who: 'Bob', enchant: false },
      { action: 'sell', name: 'Green Robe', quantity: 1, via: 'ah', who: 'Al', enchant: false },
    ]
    const place = (name: string, kind: string, x: number | null, y: number | null) =>
      ({ id: name, kind, name, map_x: x, map_y: y, map_area: null })
    const details: Parameters<typeof stepsText>[2] = [
      { kind: 'start', who: 'Bob', step: null, location: place('Thread Seller', 'vendor', 48.5, 71.2), retrieve: [] },
      { kind: 'step', who: 'Bob', step: 0, location: null, retrieve: [] },
      { kind: 'switch', who: 'Al', step: null, location: null, retrieve: [] },
      { kind: 'go', who: 'Al', step: null, location: place('Mailbox', 'mailbox', null, null), retrieve: [{ item_id: 3, count: 1 }] },
      { kind: 'step', who: 'Al', step: 1, location: null, retrieve: [] },
    ]
    expect(stepsText('Green Robe', steps, details, (id) => (id === 3 ? 'Green Robe' : '?'))).toBe(
      [
        'Green Robe',
        '1. Bob: Start at Thread Seller at 48.5, 71.2',
        '2. Bob: Buy 2x Coarse Thread from Thread Seller',
        '3. Switch to Al',
        '4. Al: Run to Mailbox. Retrieve 1x Green Robe.',
        '5. Al: Sell 1x Green Robe on the AH',
      ].join('\n'),
    )
  })
})

describe('scaleRun', () => {
  it('scales a plan to another number of crafts, quantities rounded up', () => {
    const plan = { ...robeResult, crafts: 4 }
    const more = scaleRun(plan, 6)
    expect(more.crafts).toBe(6)
    expect(more.steps.map((s) => [s.name, s.quantity, s.value])).toEqual([
      ['Linen Cloth', 15, -300],
      ['Coarse Thread', 2, -150],
      ['Green Robe', 2, 0],
      ['Green Robe', 2, 750],
    ])
    // and the flow chart: 6 robes, 15 linen for them
    expect([more.tree.quantity, more.tree.crafts, more.tree.inputs[0]?.quantity]).toEqual([2, 2, 15])
    expect(scaleRun(plan, 4)).toBe(plan)
  })
})

describe('tailText', () => {
  it('says how many crafts a run\'s slow last points take', () => {
    const run = { crafts: 30, point_crafts: [1, 1, 1, 1, 1, 2, 3, 5, 15] }
    expect(tailText(run)).toBe('The last 3 points take ~23 of these ~30 crafts')
    expect(tailText({ crafts: 22, point_crafts: [1, 1, 1, 1, 1, 2, 15] })).toBe('The last point takes ~15 of these ~22 crafts')
  })
  it('says nothing of a run without slow last points, or with only slow ones', () => {
    expect(tailText({ crafts: 10, point_crafts: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1] })).toBeNull()
    expect(tailText({ crafts: 50, point_crafts: [5, 10, 35] })).toBeNull()
    expect(tailText({ crafts: 40, point_crafts: [1, 1, 1, 30, 1, 1, 1, 3] })).toBeNull() // 3 of 40: not worth a word
    expect(tailText({ crafts: 1 })).toBeNull()
  })
})

describe('rangeText', () => {
  it('gives the crafts that get there one time in ten to nine in ten', () => {
    expect(rangeText({ reach_chances: [0, 0.05, 0.1, 0.5, 0.85, 0.9, 1] })).toBe('Usually 3–6 crafts')
  })
  it('says nothing of a run sure to take its crafts', () => {
    expect(rangeText({ reach_chances: [0, 0, 1, 1] })).toBeNull()
    expect(rangeText({})).toBeNull()
  })
})

describe('an', () => {
  it('takes "an" before a vowel', () => {
    expect(`${an('Alchemy')} Alchemy trainer`).toBe('an Alchemy trainer')
    expect(`${an('Engineering')} Engineering trainer`).toBe('an Engineering trainer')
    expect(`${an('Tailoring')} Tailoring trainer`).toBe('a Tailoring trainer')
  })
})
