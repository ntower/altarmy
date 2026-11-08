import { describe, expect, it, vi } from 'vitest'
import { featuresFor } from './useFeatures'

vi.mock('./features', () => ({ MAKE_GOLD: false }))

describe('featuresFor', () => {
  it('follows the flags for anyone but an admin', () => {
    expect(featuresFor(false)).toEqual({ makeGold: false })
  })

  it('switches every flag on for an admin', () => {
    expect(Object.values(featuresFor(true)).every(Boolean)).toBe(true)
  })
})
