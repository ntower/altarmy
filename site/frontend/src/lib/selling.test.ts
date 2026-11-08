import { describe, expect, it } from 'vitest'
import type { RankResult } from '../api/client'
import { linen, makeItem } from '../test/items'
import { robeResult } from '../test/results'
import {
  ahCount,
  ahProfit,
  breakEven,
  countedOn,
  depthNote,
  expectedUnits,
  fallback,
  floodCheck,
  floor,
  materialSales,
  safeProfit,
} from './selling'

// the robe: costs 300 to make one, a vendor pays 500, the AH nets 475 of a 500 listing
const robe: RankResult = { ...robeResult, best_exit: 'ah' }

describe('selling', () => {
  it('says under what price another exit pays more', () => {
    expect(fallback(robe)).toEqual({ kind: 'vendor', value: 500 })
    expect(floor(robe, 0.05)).toBe(527) // 500 / 0.95, rounded up
    expect(floor({ exits: [{ kind: 'ah', value: 475, materials: [], postage: 0, mail_to: '' }] }, 0.05)).toBeNull()
  })

  it('says under what price the session loses gold', () => {
    expect(breakEven(robe, 0.05)).toBe(316) // 300 / 0.95
    expect(breakEven({ ...robe, cost: 3000, crafts: 10 }, 0.05)).toBe(316)
  })

  it('says what the plan counted on, and for how many', () => {
    const items = { 3: makeItem({ id: 3, name: 'Green Robe', ah_sell_price: 480 }) }
    expect(countedOn({ ...robe, crafts: 5, excess_units: 3 }, items)).toEqual({ price: 480, units: 2, of: 5 })
  })

  it('says what disenchanting adds to each material listed', () => {
    const de: RankResult = {
      ...robe,
      crafts: 5,
      exits: [
        {
          kind: 'disenchant',
          value: 900,
          postage: 0,
          mail_to: '',
          materials: [{ item_id: 1, name: 'Linen Cloth', chance: 0.8, min_count: 1, max_count: 3, value: 700, expected: 1.6 }],
        },
      ],
    }
    expect(floodCheck(de, { 1: { ...linen, ah_quantity: 90 } })).toEqual([
      { itemId: 1, name: 'Linen Cloth', adds: 8, listed: 90 },
    ])
    expect(floodCheck(robe, {})).toEqual([])
  })
})

describe('the two ways to sell', () => {
  // ten robes: the AH counts on 3 at 950 net, the other 7 at the vendor's 500
  const ten: RankResult = {
    ...robe,
    crafts: 10,
    safe_profit: 2000,
    safe_exit: 'vendor',
    ah_profit: 2000 + 3 * 450,
    ah_excess_units: 7,
    exits: [
      { kind: 'ah', value: 950, materials: [], postage: 0, mail_to: '' },
      { kind: 'vendor', value: 500, materials: [], postage: 0, mail_to: '' },
    ],
    sell_options: [
      { kind: 'ah', profit: 6500 },
      { kind: 'vendor', profit: 2000 },
    ],
  }
  const listed = { 3: makeItem({ id: 3, name: 'Green Robe', ah_quantity: 4, ah_sell_price: 1000 }) }

  it('plays it safe as the server says, if it can', () => {
    expect(safeProfit(ten)).toEqual({ kind: 'vendor', profit: 2000 })
    expect(safeProfit({ safe_profit: null, safe_exit: null })).toBeNull()
    expect(ahProfit({ ah_profit: null })).toBeNull()
  })

  it('says how many the market takes, or how many are listed', () => {
    expect(depthNote(ten, listed)).toEqual({ text: 'market takes ~3 of 10', warn: true })
    expect(depthNote({ ...ten, ah_excess_units: 4 }, listed)).toEqual({ text: 'market takes ~6 of 10', warn: false })
    expect(depthNote({ ...ten, ah_excess_units: 10 }, listed)).toEqual({ text: 'no buyers shown yet', warn: true })
    expect(depthNote({ ...ten, ah_excess_units: 0 }, listed)).toEqual({ text: '4 listed · you add 10', warn: false })
    expect(depthNote({ ...ten, ah_excess_units: 0 }, {})).toBeNull()
    expect(depthNote({ ...ten, ah_profit: null }, listed)).toBeNull()
  })

  it('says how the auction house figure was counted', () => {
    expect(ahCount(ten, listed)).toEqual({ counted: 3, made: 10, price: 1000, restKind: 'vendor', allSold: 6500 })
    expect(ahCount({ ...ten, ah_excess_units: 0 }, listed)?.restKind).toBeNull()
    expect(ahCount({ ...ten, ah_profit: null }, listed)).toBeNull()
  })

  it("shares a disenchant's sale among its materials by what each is worth, adding up", () => {
    const material = (item_id: number, value: number | null, expected: number) =>
      ({ item_id, name: `item ${item_id}`, chance: 1, min_count: 1, max_count: 1, value, expected })
    const exits = [
      {
        kind: 'disenchant',
        value: 300,
        postage: 0,
        mail_to: '',
        materials: [material(1, 100, 1.5), material(2, null, 0.1), material(3, 200, 0.25)],
      },
    ]
    // 3 disenchants: a third and two thirds of 1000 gross and 100 net, the last taking what rounding leaves
    expect(materialSales({ exits }, 3, 1000, 100)).toEqual([
      { item_id: 1, name: 'item 1', units: 4.5, gross: 333, net: 33 },
      { item_id: 2, name: 'item 2', units: expect.closeTo(0.3), gross: null, net: null },
      { item_id: 3, name: 'item 3', units: 0.75, gross: 667, net: 67 },
    ])
    expect(materialSales({ exits: [{ ...exits[0]!, materials: [material(2, null, 1)] }] }, 3, 1000, 100)).toEqual([])
    expect(materialSales({ exits: [] }, 3, 1000, 100)).toEqual([])
  })

  it('says expected units to one decimal under 10, whole above', () => {
    expect(expectedUnits(4)).toBe('4')
    expect(expectedUnits(0.25)).toBe('0.3')
    expect(expectedUnits(4.46)).toBe('4.5')
    expect(expectedUnits(12.6)).toBe('13')
  })
})
