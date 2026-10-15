import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { parseProfitPath, profitPath } from './profitRoute'
import { byGroup, liveStrategies, parseSellVia, sellViaExits, sellViaKinds } from './strategies'

describe('strategies', () => {
  it('offers Craft and sell, and Process trade goods only once it is switched on', () => {
    expect(liveStrategies().map((s) => s.key)).toEqual(['craft'])
  })

  it('reads Sell via from the URL, anything unknown as All', () => {
    expect(parseSellVia('disenchant')).toBe('disenchant')
    expect(parseSellVia('ah')).toBe('ah')
    expect(parseSellVia(null)).toBe('all')
    expect(parseSellVia('everything')).toBe('all')
  })

  it('ranks with the exits and kinds Sell via allows', () => {
    expect(sellViaExits('all')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(sellViaExits('vendor')).toEqual(['vendor'])
    expect(sellViaKinds('vendor')).toEqual(['craft'])
    // disenchanting also buys gear to disenchant
    expect(sellViaKinds('disenchant')).toEqual(['craft', 'flip'])
  })

  it('orders crafts by their group, each group as the server ranked it', () => {
    const r = (id: number, group: (typeof robeResult)['group']) => ({ ...robeResult, recipe_id: id, group })
    const ordered = byGroup([r(1, 'losing'), r(2, 'paying'), r(3, 'full'), r(4, 'paying'), r(5, 'pennies')])
    expect(ordered.map((x) => x.recipe_id)).toEqual([2, 4, 5, 3, 1])
  })
})

describe('the gold paths', () => {
  it('has a page per way to make gold, and sends the old disenchant page to its filter', () => {
    expect(parseProfitPath('/profit/gold/craft')).toEqual({ kind: 'gold', strategy: 'craft' })
    expect(parseProfitPath('/profit/gold/process')).toEqual({ kind: 'gold', strategy: 'process' })
    expect(parseProfitPath('/profit/gold/disenchant')).toEqual({ kind: 'moved', to: '/profit/gold/craft?exit=disenchant' })
    expect(parseProfitPath('/profit/gold/x')).toBeNull()
    expect(profitPath({ kind: 'gold', strategy: 'craft' })).toBe('/profit/gold/craft')
    expect(profitPath({ kind: 'gold' })).toBe('/profit/gold')
  })
})
