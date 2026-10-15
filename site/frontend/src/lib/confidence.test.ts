import { describe, expect, it } from 'vitest'
import type { PriceConfidence } from '../api/client'
import { confidenceTitle, confidenceWhy } from './confidence'

const base: PriceConfidence = {
  level: 'medium',
  reason: 'unwatched',
  sold: 0,
  units: 1,
  listed: 12,
  scan_days: 5,
  watched_hours: 0,
  unlisted_since: null,
  flags: [],
  sold_pairs: 0,
}

describe('confidence', () => {
  it('words each reason', () => {
    expect(confidenceWhy({ ...base, reason: 'sold', sold: 7 })).toBe('7 units seen selling in the last 7 days')
    expect(confidenceWhy({ ...base, reason: 'few_sold', sold: 5, units: 8 })).toBe(
      'Only 5 units seen selling in the last 7 days; this plan sells 8',
    )
    expect(confidenceWhy({ ...base, reason: 'few_days', scan_days: 1 })).toBe('Priced from scans on only 1 day')
    expect(confidenceWhy({ ...base, reason: 'unsold', watched_hours: 4.5 })).toBe(
      'None seen selling in 4.5 hours of back-to-back scans',
    )
    expect(confidenceWhy({ ...base, reason: 'unsold', sold: 2, watched_hours: 3 })).toBe(
      'Only 2 units seen selling in 3 hours of back-to-back scans',
    )
    expect(confidenceWhy({ ...base, reason: 'thin', listed: 3 })).toBe('Rests on 3 units listed')
    expect(confidenceWhy({ ...base, reason: 'hand_set' })).toBe('Price set by hand')
    expect(confidenceWhy({ ...base, reason: 'one_pair', sold: 6, sold_pairs: 1 })).toBe(
      '6 units seen selling, all between one pair of scans: maybe a single buyer',
    )
    expect(confidenceWhy({ ...base, reason: 'few_sold', sold: 9, units: 4, watched_hours: 0.5 })).toBe(
      '9 units seen selling in the last 7 days, but the auction house was watched for only 0.5 hours',
    )
  })

  it('names the day an item went unlisted', () => {
    const why = confidenceWhy({ ...base, reason: 'unlisted', unlisted_since: '2026-10-02T12:00:00Z' })
    expect(why).toMatch(/^None listed since .+, and none seen selling/)
  })

  it('leads with the level', () => {
    expect(confidenceTitle(base)).toBe(
      'Medium confidence in the sell price: Sales unknown: they are seen only between snapshots of the auction house taken close together',
    )
  })
})
