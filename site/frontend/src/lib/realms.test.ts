import { describe, expect, it } from 'vitest'
import type { CharacterGroup, Coverage } from '../api/client'
import { fromKey, realmLabel, realmOptions, toKey } from './realms'

const house = (realm: string, faction: string, prices = 10): Coverage => ({
  auction_house_id: 1,
  realm,
  faction,
  prices,
  last_scan: null,
  last_scan_items: 0,
  scans_7d: 0,
  watched_hours: 0,
  uploaders_7d: 0,
  open: true,
  feed: false,
  launch: false,
})
const group = (realm: string, faction: string, n = 1): CharacterGroup => ({
  realm,
  faction,
  characters: Array.from({ length: n }, (_, i) => ({ name: `C${i}`, class_file: 'MAGE', level: 60, professions: [], talents: [], vendor_discounts: [] })),
})

describe('realms', () => {
  it('round-trips keys and labels shared auction houses', () => {
    expect(fromKey(toKey({ realm: 'Classic Beta PvE', faction: '' }))).toEqual({ realm: 'Classic Beta PvE', faction: '' })
    expect(realmLabel({ realm: 'Dreamscythe', faction: 'Horde' })).toBe('Dreamscythe (Horde)')
    expect(realmLabel({ realm: 'Classic Beta PvE', faction: '' })).toBe('Classic Beta PvE (both factions)')
  })

  it('offers groups first, then priced auction houses none of them uses', () => {
    const groups = [group('Classic Beta PvE', 'Horde', 2), group('Dreamscythe', 'Horde')]
    const coverage = [
      house('Classic Beta PvE', ''), // the Horde group's (shared) house
      house('Dreamscythe', 'Horde'), // the Dreamscythe group's own
      house('Dreamscythe', 'Alliance'),
      house('Empty', '', 0), // no prices: nothing to browse
    ]
    expect(realmOptions(groups, coverage)).toEqual([
      { value: 'Classic Beta PvE\tHorde', label: 'Classic Beta PvE (Horde) · 2 characters', section: 'Your characters' },
      { value: 'Dreamscythe\tHorde', label: 'Dreamscythe (Horde) · 1 character', section: 'Your characters' },
      { value: 'Dreamscythe\tAlliance', label: 'Dreamscythe (Alliance)', section: 'Browse a realm' },
    ])
  })
})
