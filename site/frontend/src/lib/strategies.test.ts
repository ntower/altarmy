import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { parseProfitPath, profitPath } from './profitRoute'
import { byGroup, kindChipParams, parseKindChip, parseSellVia, sellViaExits } from './strategies'

describe('the gold list', () => {
  it('reads Sell via from the URL, anything unknown as All', () => {
    expect(parseSellVia('disenchant')).toBe('disenchant')
    expect(parseSellVia('ah')).toBe('ah')
    expect(parseSellVia(null)).toBe('all')
    expect(parseSellVia('everything')).toBe('all')
  })

  it('ranks with the exits Sell via allows', () => {
    expect(sellViaExits('all')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(sellViaExits('vendor')).toEqual(['vendor'])
  })

  it('narrows the list to one kind by its chip: processing by the server, the rest by kind', () => {
    expect(parseKindChip('flip')).toBe('flip')
    expect(parseKindChip('nope')).toBe('all')
    expect(kindChipParams('all')).toEqual({})
    expect(kindChipParams('process')).toEqual({ process: true })
    expect(kindChipParams('flip')).toEqual({ kinds: ['flip'] })
    expect(kindChipParams('convert')).toEqual({ kinds: ['convert'] })
  })

  it('orders results by their group, each group as the server ranked it', () => {
    const r = (id: number, group: (typeof robeResult)['group']) => ({ ...robeResult, recipe_id: id, group })
    const ordered = byGroup([r(1, 'losing'), r(2, 'paying'), r(3, 'full'), r(4, 'paying'), r(5, 'pennies')])
    expect(ordered.map((x) => x.recipe_id)).toEqual([2, 4, 5, 3, 1])
  })
})

describe('the gold paths', () => {
  it('has two tabs, and sends the strategy pages from before them to the list', () => {
    expect(parseProfitPath('/profit/gold')).toEqual({ kind: 'gold' })
    expect(parseProfitPath('/profit/gold/vendorcheck')).toEqual({ kind: 'gold', tab: 'vendorcheck' })
    for (const old of ['craft', 'process', 'vendor', 'held'])
      expect(parseProfitPath(`/profit/gold/${old}`)).toEqual({ kind: 'moved', to: '/profit/gold' })
    expect(parseProfitPath('/profit/gold/disenchant')).toEqual({ kind: 'moved', to: '/profit/gold?exit=disenchant' })
    expect(parseProfitPath('/profit/gold/x')).toBeNull()
    expect(profitPath({ kind: 'gold', tab: 'vendorcheck' })).toBe('/profit/gold/vendorcheck')
    expect(profitPath({ kind: 'gold' })).toBe('/profit/gold')
  })
})
