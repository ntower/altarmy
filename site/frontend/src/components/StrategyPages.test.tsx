import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { robeResult } from '../test/results'
import { characters, status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { setSearchParam } from '../lib/router'
import { SearchTab } from './SearchTab'

// The strategy pages, switched on
vi.mock('../lib/features', () => ({ MAKE_GOLD: true, STRATEGY_PICKER: true, PROCESSING: false }))

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
})
