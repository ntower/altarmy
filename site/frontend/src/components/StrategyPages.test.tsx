import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { linen } from '../test/items'
import { robeResult } from '../test/results'
import { characters, status, withEnchanter } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { setSearchParam } from '../lib/router'
import { SearchTab } from './SearchTab'

// The strategy pages, switched on
vi.mock('../lib/features', () => ({ MAKE_GOLD: true, STRATEGY_PICKER: true, PROCESSING: true, VENDOR_RUNS: true, WHAT_I_HOLD: true }))

const at = (path: string) => window.history.replaceState(null, '', path)
const ranked = (r = robeResult) => ({ results: [r], total: 1, items: {}, classes: {} })

function rankParams(fetch: ReturnType<typeof mockApi>) {
  return fetch.mock.calls
    .map(([request]) => new URL(request.url))
    .filter((u) => u.pathname === '/api/rank')
    .at(-1)?.searchParams
}

describe('the strategy pages', () => {
  it('asks how to make gold, ranking nothing', async () => {
    at('/profit/gold')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('heading', { name: 'How do you want to make gold?' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Craft and sell' })).toBeInTheDocument()
    expect(rankParams(fetch)).toBeUndefined()
    await userEvent.click(screen.getByRole('button', { name: 'Craft and sell' }))
    expect(window.location.pathname).toBe('/profit/gold/craft')
  })

  it('ranks crafts by what a day makes, selling only as Sell via allows', async () => {
    at('/profit/gold/craft')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': ranked({ ...robeResult, group: 'paying', likely_each: 20, per_day: 200 }),
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText('What to do')
    expect(rankParams(fetch)?.get('sort')).toBe('per_day')
    expect(rankParams(fetch)?.getAll('kinds')).toEqual(['craft'])
    expect(rankParams(fetch)?.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(screen.getByRole('link', { name: '‹ Ways to make gold' })).toHaveAttribute('href', '/profit/gold')
    await userEvent.click(screen.getByRole('radio', { name: 'Disenchant' }))
    await waitFor(() => expect(rankParams(fetch)?.getAll('exits')).toEqual(['disenchant']))
    expect(rankParams(fetch)?.getAll('kinds')).toEqual(['craft', 'flip'])
    expect(window.location.search).toBe('?exit=disenchant')
    act(() => setSearchParam('exit', null)) // back: All again, from the ranking already fetched
    await waitFor(() => expect(screen.getByRole('radio', { name: 'All' })).toBeChecked())
  })

  it("keeps its own filters, starting from the gold list's", async () => {
    localStorage.setItem('altarmy.search.gold.minProfit', JSON.stringify(5))
    at('/profit/gold/craft')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked() })
    const { unmount } = renderWithProviders(<SearchTab />)
    await waitFor(() => expect(rankParams(fetch)?.get('min_profit')).toBe('50000'))
    unmount()
    localStorage.setItem('altarmy.search.craft.minProfit', JSON.stringify(1))
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(rankParams(fetch)?.get('min_profit')).toBe('10000'))
    expect(localStorage.getItem('altarmy.search.gold.minProfit')).toBe('5')
    localStorage.clear()
  })

  it('asks who disenchants when several characters can, and sends the pick', async () => {
    const two = {
      ...withEnchanter,
      groups: withEnchanter.groups.map((g, i) =>
        i === 0
          ? {
              ...g,
              characters: [
                ...g.characters,
                {
                  name: 'Weak',
                  class_file: 'MAGE',
                  level: 10,
                  professions: [{ name: 'Enchanting', rank: 5, max_rank: 75, recipes: 0 }],
                  talents: [],
                  vendor_discounts: [],
                },
              ],
            }
          : g,
      ),
    }
    at('/profit/gold/craft?exit=disenchant')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': two, '/api/rank': ranked() })
    renderWithProviders(<SearchTab />)
    const select = await screen.findByRole('combobox', { name: 'Disenchanted by' })
    expect(select).toHaveValue('Enchy (Enchanting 60)') // the best
    expect(rankParams(fetch)?.get('disenchanter')).toBeNull()
    await userEvent.click(select)
    await userEvent.click(await screen.findByRole('option', { name: 'Weak (Enchanting 5)' }))
    await waitFor(() => expect(rankParams(fetch)?.get('disenchanter')).toBe('Weak'))
    expect(localStorage.getItem('altarmy.search.craft.disenchanter')).toBe('"Weak"')
    localStorage.clear()
  })

  it('folds every group but what pays', async () => {
    at('/profit/gold/craft')
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': {
        results: [
          { ...robeResult, recipe_id: 1, recipe: 'Paying Robe', group: 'paying' },
          { ...robeResult, recipe_id: 2, recipe: 'Losing Robe', group: 'losing' },
        ],
        total: 2,
        items: {},
        classes: {},
      },
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('button', { name: /Pays \(1\)/ })).toHaveAttribute('aria-expanded', 'true')
    const losing = screen.getByRole('button', { name: /Loses money: craft to order only \(1\)/ })
    expect(losing).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByRole('button', { name: 'Details for Losing Robe' })).not.toBeInTheDocument()
    await userEvent.click(losing)
    expect(screen.getByRole('button', { name: 'Details for Losing Robe' })).toBeInTheDocument()
  })

  it('processes trade goods in their groups, against selling the inputs, under the essences', async () => {
    at('/profit/gold/process')
    const bar = {
      ...robeResult,
      recipe_id: 7,
      recipe: 'Smelt Copper',
      likely_each: 30,
      process: { group: 'smelt' as const, inputs_value: 500, gain: 300, buy_up_to: 70, main_input: 1, uses: 12 },
    }
    const bolt = {
      ...robeResult,
      recipe_id: 8,
      recipe: 'Bolt of Linen Cloth',
      process: { group: 'cloth' as const, inputs_value: 900, gain: -40, buy_up_to: 10, main_input: 1, uses: 3 },
    }
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': { results: [bolt, bar], total: 2, items: { '1': linen }, classes: {} },
      '/api/essences': {
        tiers: [
          { lesser: 10, greater: 11, per: 3, lesser_buy: 100, greater_buy: 400, lesser_sell: 120, greater_sell: 380, up: 61, down: -58 },
        ],
        items: {},
      },
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('button', { name: /Smelting \(1\)/ })).toHaveAttribute('aria-expanded', 'true')
    expect(rankParams(fetch)?.get('process')).toBe('true')
    expect(rankParams(fetch)?.get('sort')).toBe('per_day')
    const groups = screen.getAllByRole('button', { name: /\(1\)$/ }).map((b) => b.textContent)
    expect(groups).toEqual(['▾ Smelting (1)', '▾ Cloth (1)']) // in the groups' order, not the server's
    expect(screen.getByText(/processing loses/)).toBeInTheDocument()
    expect(await screen.findByText('Buy 3 lesser, combine, sell the greater')).toBeInTheDocument()
  })

  it('shares the materials out when disenchanting, over the days asked for', async () => {
    at('/profit/gold/craft?exit=disenchant')
    const flip = {
      ...robeResult,
      kind: 'flip' as const,
      group: 'buy_to_disenchant' as const,
      likely_exit: 'disenchant',
      crafts: 8,
      budget_casts: 3,
      pay_at_most: 9500,
      needs_skill: 50,
    }
    const fetch = mockApi({ '/api/status': status(), '/api/characters': withEnchanter, '/api/rank': ranked(flip) })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/Buy 3 and disenchant, paying at most/)).toBeInTheDocument()
    expect(screen.getByText('the materials sell for 3 of 8 · needs Enchanting 50')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Buy to disenchant \(1\)/ })).toHaveAttribute('aria-expanded', 'true')
    expect(rankParams(fetch)?.get('sell_days')).toBe('1')
    await userEvent.click(screen.getByRole('radio', { name: 'A week' }))
    await waitFor(() => expect(rankParams(fetch)?.get('sell_days')).toBe('7'))
    localStorage.clear()
  })

  it('lists vendor runs: what is listed under a vendor, and what to buy from vendors, by zone', async () => {
    at('/profit/gold/vendor')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/vendor-runs': {
        under_vendor: [{ item_id: 1, units: 3, cheapest: 50, vendor: 80, profit: 90, fresh: true }],
        runs: [
          {
            zone: 'The Barrens',
            profit: 5000,
            resells: [
              {
                item_id: 1,
                vendor: 'Trader',
                limited: true,
                restock_s: 3600,
                unit_cost: 2000,
                sell_price: 9000,
                margin: 5000,
                units: 1,
                profit: 5000,
                area: 17,
                map_x: 50,
                map_y: 50,
              },
            ],
          },
        ],
        items: { '1': linen },
      },
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('tab', { name: 'Under what a vendor pays (1)' })).toBeInTheDocument()
    expect(screen.getByText('new')).toBeInTheDocument()
    expect(fetch.mock.calls.some(([r]) => new URL(r.url).pathname === '/api/rank')).toBe(false)
    await userEvent.click(screen.getByRole('tab', { name: 'Vendor to auction house (1)' }))
    expect(screen.getByRole('heading', { name: 'The Barrens' })).toBeInTheDocument()
    expect(screen.getByText(/limited, back in 1h/)).toBeInTheDocument()
  })

  it('says what each character holds and what to do with it, and keeps what is ticked', async () => {
    at('/profit/gold/held')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/holdings': {
        characters: [
          {
            name: 'Tailor Guy',
            class_file: 'MAGE',
            bags_at: null,
            bank_at: null,
            held: [
              { item_id: 1, count: 20, place: 'bags', bound: false, verdict: 'auction', value: 380, why: '' },
              { item_id: 2, count: 1, place: 'bank', bound: false, verdict: 'keep', value: 0, why: 'reagent' },
            ],
          },
        ],
        kept: [],
        items: { '1': linen },
      },
      '/api/kept/1': [1],
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText('Post on the auction house (1)')).toBeInTheDocument()
    expect(screen.getByText('a reagent of a recipe your characters know')).toBeInTheDocument()
    expect(screen.getAllByText(/Bags scanned never/)).toHaveLength(1)
    await userEvent.click(screen.getByRole('checkbox', { name: 'Keep Linen Cloth' }))
    await waitFor(() =>
      expect(fetch.mock.calls.some(([r]) => r.method === 'PUT' && new URL(r.url).pathname === '/api/kept/1')).toBe(true),
    )
  })
})
