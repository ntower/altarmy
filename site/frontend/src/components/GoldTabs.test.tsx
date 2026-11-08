import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { RankResult } from '../api/client'
import { linen } from '../test/items'
import { robeResult } from '../test/results'
import { characters, status, withEnchanter } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { setSearchParam } from '../lib/router'
import { SearchTab } from './SearchTab'

vi.mock('../lib/features', () => ({ MAKE_GOLD: true }))

const at = (path: string) => window.history.replaceState(null, '', path)
const ranked = (...results: RankResult[]) => ({ results, total: results.length, items: {}, classes: {} })

/** The rank calls made, oldest first. */
const rankCalls = (fetch: ReturnType<typeof mockApi>) =>
  fetch.mock.calls.map(([request]) => new URL(request.url)).filter((u) => u.pathname === '/api/rank')
/** The list's last rank call. */
const listParams = (fetch: ReturnType<typeof mockApi>) => rankCalls(fetch).at(-1)?.searchParams

describe("making gold's two tabs", () => {
  it('ranks every way to make gold in one list, by what a day makes, with no strategy to pick', async () => {
    at('/profit/gold')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': ranked({ ...robeResult, group: 'paying', likely_each: 20, per_day: 200, launch_prices: true, copied: 2 }),
    })
    renderWithProviders(<SearchTab />)
    await screen.findByRole('columnheader', { name: /A day/ })
    expect(screen.getByRole('tab', { name: 'Ways to make gold' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByLabelText('Launch prices')).toBeInTheDocument()
    expect(screen.getByLabelText('Others copied this')).toBeInTheDocument()
    const list = listParams(fetch)
    expect(list?.get('sort')).toBe('per_day')
    expect(list?.getAll('kinds')).toEqual([]) // every kind: crafts, conversions and gear bought to disenchant
    expect(list?.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(screen.queryByRole('heading', { name: 'How do you want to make gold?' })).not.toBeInTheDocument()
  })

  it('narrows the list by kind and by Sell via, in the URL', async () => {
    at('/profit/gold')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked(robeResult) })
    renderWithProviders(<SearchTab />)
    await screen.findByRole('radio', { name: 'Buy & disenchant' })
    await userEvent.click(screen.getByRole('radio', { name: 'Buy & disenchant' }))
    await waitFor(() => expect(listParams(fetch)?.getAll('kinds')).toEqual(['flip']))
    expect(window.location.search).toBe('?kind=flip')
    await userEvent.click(screen.getByRole('radio', { name: 'Disenchant' }))
    await waitFor(() => expect(listParams(fetch)?.getAll('exits')).toEqual(['disenchant']))
    act(() => {
      setSearchParam('exit', null)
      setSearchParam('kind', null)
    })
    await waitFor(() =>
      expect(screen.getAllByRole('radio', { name: 'All' }).every((r) => (r as HTMLInputElement).checked)).toBe(true),
    )
  })

  it('shows processing on its own chip, from the server', async () => {
    at('/profit/gold?kind=process')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked(robeResult) })
    renderWithProviders(<SearchTab />)
    await screen.findByRole('columnheader', { name: /A day/ })
    await waitFor(() => expect(listParams(fetch)?.get('process')).toBe('true'))
  })

  it('notes what processing adds on the whole list, in one rank call', async () => {
    at('/profit/gold')
    const bar = { ...robeResult, recipe_id: 7, recipe: 'Smelt Copper', output_name: 'Copper Bar', output_item_id: 70 }
    const process = { group: 'smelt' as const, inputs_value: 500, gain: 300, buy_up_to: 70, main_input: 1, uses: 12 }
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': { ...ranked({ ...bar, process }), items: { '1': linen } },
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findAllByText(/smelting adds/)).not.toHaveLength(0)
    expect(screen.getAllByText('Smelting').length).toBeGreaterThan(0) // its tag beside the name
    expect(rankCalls(fetch).some((u) => u.searchParams.has('process'))).toBe(false) // the server notes it anyway
  })

  it("keeps the gold list's filters", async () => {
    localStorage.setItem('altarmy.search.gold.minProfit', JSON.stringify(5))
    at('/profit/gold')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked(robeResult) })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(listParams(fetch)?.get('min_profit')).toBe('50000'))
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
    at('/profit/gold?exit=disenchant')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': two, '/api/rank': ranked(robeResult) })
    renderWithProviders(<SearchTab />)
    const select = await screen.findByRole('combobox', { name: 'Disenchanted by' })
    expect(select).toHaveValue('Enchy (Enchanting 60)') // the best
    expect(listParams(fetch)?.get('disenchanter')).toBeNull()
    await userEvent.click(select)
    await userEvent.click(await screen.findByRole('option', { name: 'Weak (Enchanting 5)' }))
    await waitFor(() => expect(listParams(fetch)?.get('disenchanter')).toBe('Weak'))
    expect(localStorage.getItem('altarmy.search.gold.disenchanter')).toBe('"Weak"')
    localStorage.clear()
  })

  it('folds what is not worth doing now into one section, saying why', async () => {
    at('/profit/gold')
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': ranked(
        { ...robeResult, recipe_id: 1, recipe: 'Paying Robe', group: 'paying' },
        { ...robeResult, recipe_id: 2, recipe: 'Losing Robe', group: 'losing' },
        { ...robeResult, recipe_id: 3, recipe: 'Full Robe', group: 'full' },
      ),
    })
    renderWithProviders(<SearchTab />)
    const later = await screen.findByRole('button', { name: /Not worth it right now \(2\): Full 1 · Losing 1/ })
    expect(later).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('button', { name: 'Details for Paying Robe' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Details for Losing Robe' })).not.toBeInTheDocument()
    await userEvent.click(later)
    expect(screen.getByRole('button', { name: 'Details for Losing Robe' })).toBeInTheDocument()
    expect(screen.getByText('loses money: craft to order only')).toBeInTheDocument()
  })

  it('puts the best few on top, and opens a pick in the list when it is clicked', async () => {
    at('/profit/gold')
    const pays = (id: number, name: string, over: Partial<RankResult> = {}): RankResult => ({
      ...robeResult,
      recipe_id: id,
      recipe: name,
      output_name: name,
      output_item_id: 100 + id,
      group: 'paying',
      ...over,
    })
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': ranked(
        pays(1, 'Robe A', { per_day: 9000 }),
        pays(2, 'Robe B', { slow: true, days_to_sell: 4 }), // unsure: not a pick
        pays(3, 'Robe C', { per_day: 500 }),
        pays(4, 'Robe D', { group: 'losing' }), // not worth doing: not a pick
      ),
    })
    renderWithProviders(<SearchTab />)
    const strip = await screen.findByRole('region', { name: 'Best right now' })
    const picks = within(strip).getAllByRole('button')
    expect(picks.map((b) => b.getAttribute('aria-label'))).toEqual(['Pick 1: Robe A', 'Pick 2: Robe C'])
    expect(screen.getByRole('button', { name: 'Details for Robe C' })).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(picks[1]!)
    expect(screen.getByRole('button', { name: 'Details for Robe C' })).toHaveAttribute('aria-expanded', 'true')
  })

  it('shares the materials out when disenchanting, over the days asked for', async () => {
    at('/profit/gold?exit=disenchant')
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
    expect((await screen.findAllByText(/Buy 3 and disenchant, paying at most/)).length).toBeGreaterThan(0)
    expect(screen.getAllByText('the materials sell for 3 of 8 · needs Enchanting 50').length).toBeGreaterThan(0)
    expect(listParams(fetch)?.get('sell_days')).toBe('1')
    await userEvent.click(screen.getByRole('radio', { name: 'A week' }))
    await waitFor(() => expect(listParams(fetch)?.get('sell_days')).toBe('7'))
    localStorage.clear()
  })

  it('shows the vendor check on its own tab, ranking nothing', async () => {
    at('/profit/gold/vendorcheck')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/vendorcheck': {
        realm: 'Classic Beta PvE',
        faction: 'Horde',
        items: [],
        total: 0,
        listed: 0,
        page: 1,
        page_size: 50,
        classes: [],
        qualities: [],
      },
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText('No scan of this realm yet.')).toBeInTheDocument()
    expect(screen.getByRole('tab', { name: 'Vendor check' })).toHaveAttribute('aria-selected', 'true')
    const asked = fetch.mock.calls.map(([r]) => new URL(r.url)).find((u) => u.pathname === '/api/vendorcheck')
    expect([asked?.searchParams.get('sort'), asked?.searchParams.get('order')]).toEqual(['percent', 'asc'])
    expect(rankCalls(fetch)).toHaveLength(0)
    await userEvent.click(screen.getByRole('tab', { name: 'Ways to make gold' }))
    expect(window.location.pathname).toBe('/profit/gold')
  })
})
