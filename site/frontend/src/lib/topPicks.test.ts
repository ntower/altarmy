import { describe, expect, it } from 'vitest'
import type { RankResult } from '../api/client'
import { robeResult } from '../test/results'
import { topPicks } from './topPicks'

const row = (id: number, over: Partial<RankResult> = {}): RankResult => ({
  ...robeResult,
  recipe_id: id,
  output_item_id: 1000 + id,
  group: 'paying',
  per_day: 100,
  ...over,
})
const ids = (rows: RankResult[]) => rows.map((r) => r.recipe_id)

describe('topPicks', () => {
  it('takes the five that make most a day, whatever order the list is in', () => {
    // favorites first, or ranked by Each: the picks still go by a day
    const rows = [10, 70, 30, 60, 20, 50, 40].map((perDay, i) => row(i + 1, { per_day: perDay }))
    expect(ids(topPicks(rows))).toEqual([2, 4, 6, 7, 3])
  })

  it('leaves out what is not worth doing now, and what we are unsure of', () => {
    const rows = [
      row(1, { group: 'full' }),
      row(2, { group: 'pennies' }),
      row(3, { confidence: { level: 'low' } as RankResult['confidence'] }),
      row(4, { launch_prices: true }),
      row(5, { copied: 2 }),
      row(6, { slow: true }),
      row(7, { per_day: 0 }), // the disenchant budget left it nothing today
      row(8, { kind: 'flip', group: 'buy_to_disenchant' }),
      row(9),
    ]
    expect(ids(topPicks(rows))).toEqual([8, 9])
  })

  it('picks one row per item made, the better one', () => {
    const rows = [row(1, { per_day: 50 }), row(2, { output_item_id: 1001, per_day: 80 }), row(3, { per_day: 10 })]
    expect(ids(topPicks(rows))).toEqual([2, 3])
  })
})
