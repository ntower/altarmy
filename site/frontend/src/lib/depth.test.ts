import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { depthSteps, priceRange, profitAt, spread } from './depth'

const level = (price: number, quantity: number, counted = true, more = false) => ({
  price,
  quantity,
  counted,
  more,
  listings: 2,
  age: 1,
})

describe('depthSteps', () => {
  const levels = [level(90, 2, false), level(100, 4), level(120, 5), level(150, 9, true, true)]

  it('lays the levels end to end, the plan’s units put in after those at its price or under', () => {
    const { steps, total } = depthSteps(levels, { insert: { price: 100, units: 3 } })
    expect(steps.map((s) => [s.kind, s.price, s.x0, s.x1])).toEqual([
      ['uncounted', 90, 0, 2],
      ['level', 100, 2, 6],
      ['you', 100, 6, 9],
      ['level', 120, 9, 14],
      ['tail', 150, 14, 23],
    ])
    expect(total).toBe(23)
  })

  it('puts the plan’s units last when every level is cheaper, and marks what is bought', () => {
    expect(depthSteps(levels, { insert: { price: 200, units: 1 } }).steps.at(-1)).toMatchObject({ kind: 'you', x0: 20 })
    expect(depthSteps(levels, { taken: [0, 4, 1, 0] }).steps.map((s) => s.taken)).toEqual([0, 4, 1, 0])
  })

  it('carries each level’s listings and age, none for the plan’s own units', () => {
    const { steps } = depthSteps([{ ...level(100, 4), age: 3 }], { insert: { price: 200, units: 1 } })
    expect(steps.map((s) => [s.listings, s.age])).toEqual([
      [2, 3],
      [0, 0],
    ])
  })
})

describe('ranges', () => {
  it('leaves room around the prices, never under 0', () => {
    const { lo, hi } = priceRange([100, 200])
    expect(lo).toBeLessThan(100)
    expect(lo).toBeGreaterThanOrEqual(0)
    expect(hi).toBeGreaterThan(200)
    expect(priceRange([1]).lo).toBe(0)
  })

})

describe('spread', () => {
  it('moves labels down until none is closer than the gap, keeping each where it wants when it can', () => {
    expect(spread([50, 10, 55])).toEqual([50, 10, 63])
    expect(spread([20, 20, 20], 10)).toEqual([20, 30, 40])
    expect(spread([])).toEqual([])
  })
})

describe('profitAt', () => {
  it('moves the plan’s own AH profit by what each unit brings after the cut', () => {
    // the robe's AH sale makes 175 at 475; one robe at 575 brings 95 more
    expect(profitAt(robeResult, 475, 0.05, 475)).toBe(175)
    expect(profitAt(robeResult, 475, 0.05, 575)).toBe(270)
    expect(profitAt({ ...robeResult, sell_options: [] }, 475, 0.05, 500)).toBeNull()
  })
})
