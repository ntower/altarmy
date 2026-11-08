import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { linen } from '../test/items'
import { robeResult } from '../test/results'
import { characters, status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { SearchTab } from './SearchTab'

vi.mock('../lib/features', () => ({ MAKE_GOLD: true }))

const at = (path: string) => window.history.replaceState(null, '', path)
const ranked = (...results: (typeof robeResult)[]) => ({ results, total: results.length, items: { '1': linen }, classes: {} })

/** The rank requests made, oldest first. */
const rankCalls = (fetch: ReturnType<typeof mockApi>) =>
  fetch.mock.calls.map(([request]) => new URL(request.url)).filter((u) => u.pathname === '/api/rank')

const smelt = {
  ...robeResult,
  recipe_id: 7,
  recipe: 'Smelt Copper',
  output_name: 'Copper Bar',
  profession: 'Mining',
  process: { group: 'smelt' as const, inputs_value: 500, gain: 300, buy_up_to: 70, main_input: 1, uses: 12 },
}

const vendorCheck = {
  realm: 'Classic Beta PvE',
  faction: 'Horde',
  items: [],
  total: 0,
  listed: 0,
  page: 1,
  page_size: 50,
  classes: [],
  qualities: [],
}

describe("making gold's two tabs", () => {
  it('lists every way to make gold in one ranking, by the better of safe and auction profit', async () => {
    at('/profit/gold')
    const flip = { ...robeResult, recipe_id: 9, recipe: 'Disenchant Green Robe', kind: 'flip' as const, profession: '', crafts: 3 }
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked(robeResult, flip) })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('tab', { name: 'Make gold' })).toHaveAttribute('aria-selected', 'true')
    expect(await screen.findByRole('button', { name: 'Sort by Safe profit' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Sort by Auction profit' })).toBeInTheDocument()
    // no strategy pages: no picker, no Sell via, no groups
    expect(screen.queryByRole('heading', { name: 'How do you want to make gold?' })).not.toBeInTheDocument()
    expect(screen.queryByRole('radiogroup', { name: 'Sell via' })).not.toBeInTheDocument()
    const list = rankCalls(fetch).at(-1)?.searchParams
    expect(list?.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(list?.getAll('kinds')).toEqual([]) // crafts, conversions and gear bought to disenchant alike
    expect(list?.get('sort')).toBe('likely')
    // gear bought to disenchant says so in place of a profession
    expect(screen.getByText(/Buy and disenchant/)).toBeInTheDocument()
    expect(screen.getByText(/3 bought/)).toBeInTheDocument()
  })

  it("shows the processing numbers the server puts on a processing recipe's row, in one request", async () => {
    at('/profit/gold')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked(robeResult, smelt) })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/processing adds/)).toBeInTheDocument()
    expect(screen.getByText('Smelting')).toBeInTheDocument()
    expect(screen.getByText(/buy Linen Cloth up to/)).toBeInTheDocument()
    expect(rankCalls(fetch).some((u) => u.searchParams.has('process'))).toBe(false)
    const rows = screen.getAllByRole('button', { name: /^Details for / }).map((b) => b.getAttribute('aria-label'))
    expect(rows).toEqual(['Details for Green Robe', 'Details for Smelt Copper']) // the list's order
    // opened, its market says what the inputs bring as they are
    await userEvent.click(screen.getByRole('button', { name: 'Details for Smelt Copper' }))
    await userEvent.click(await screen.findByRole('button', { name: /^Market/ }))
    expect(await screen.findByText(/Sell inputs instead/)).toBeInTheDocument()
  })

  it('says a processing recipe that loses to selling its inputs does', async () => {
    at('/profit/gold')
    const losing = { ...smelt, process: { ...smelt.process, gain: -40 } }
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': ranked(losing) })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/processing loses/)).toBeInTheDocument()
  })

  it('switches to the vendor check by its tab, a path of its own, ', async () => {
    at('/profit/gold')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': ranked(),
      '/api/vendorcheck': vendorCheck,
    })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('tab', { name: 'Vendor check' }))
    expect(window.location.pathname).toBe('/profit/gold/vendorcheck')
    expect(await screen.findByText('No scan of this realm yet.')).toBeInTheDocument()
    const asked = fetch.mock.calls.map(([r]) => new URL(r.url)).find((u) => u.pathname === '/api/vendorcheck')
    expect([asked?.searchParams.get('sort'), asked?.searchParams.get('order')]).toEqual(['percent', 'asc'])
    await userEvent.click(screen.getByRole('tab', { name: 'Make gold' }))
    expect(window.location.pathname).toBe('/profit/gold')
  })

  it('opens the vendor check at its path, ranking nothing', async () => {
    at('/profit/gold/vendorcheck')
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/vendorcheck': vendorCheck })
    renderWithProviders(<SearchTab />)
    const tabs = await screen.findByRole('tablist')
    expect(within(tabs).getByRole('tab', { name: 'Vendor check' })).toHaveAttribute('aria-selected', 'true')
    expect(screen.queryByRole('heading', { name: 'Vendor check' })).not.toBeInTheDocument() // the tab names it
    await waitFor(() =>
      expect(fetch.mock.calls.some(([r]) => new URL(r.url).pathname === '/api/vendorcheck')).toBe(true),
    )
    expect(fetch.mock.calls.some(([r]) => new URL(r.url).pathname === '/api/rank')).toBe(false)
  })
})
