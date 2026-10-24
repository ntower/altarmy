import { describe, expect, it, vi } from 'vitest'
import { featuresFor } from './useFeatures'

vi.mock('./features', () => ({
  MAKE_GOLD: false,
  STRATEGY_PICKER: false,
  PROCESSING: true,
  VENDOR_RUNS: false,
  WHAT_I_HOLD: true,
}))

describe('featuresFor', () => {
  it('follows the flags for anyone but an admin', () => {
    expect(featuresFor(false)).toEqual({
      makeGold: false,
      strategyPicker: false,
      processing: true,
      vendorRuns: false,
      whatIHold: true,
    })
  })

  it('switches every flag on for an admin', () => {
    expect(Object.values(featuresFor(true)).every(Boolean)).toBe(true)
  })
})
