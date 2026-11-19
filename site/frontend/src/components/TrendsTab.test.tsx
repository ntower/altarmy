import { fireEvent, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Coverage, FoundItem, MarketHistory } from '../api/client'
import { ADMIN, LINKED, mockApi, renderWithProviders } from '../test/utils'
import { status } from '../test/status'
import { TrendsPage } from './Pages'

const house = (over: Partial<Coverage>): Coverage => ({
  auction_house_id: 1,
  realm: 'Americas Normal',
  faction: 'Horde',
  prices: 10,
  last_scan: '2026-11-18 12:00:00',
  last_scan_items: 10,
  scans_7d: 3,
  uploaders_7d: 1,
  watched_hours: 4,
  realm_key: 'americas-normal',
  open: true,
  feed: false,
  launch: false,
  ...over,
})

const coverage = [house({}), house({ auction_house_id: 2, faction: 'Alliance', last_scan: '2026-11-19 08:00:00' })]
const linen: FoundItem = { id: 2589, name: 'Linen Cloth', quality: 1, icon: 'inv_fabric_linen_01', priced: true }

const history: MarketHistory = {
  days: [
    { day: '2026-11-17', low: 10, median: 20, high: 40, open: null, close: null },
    { day: '2026-11-18', low: 12, median: 25, high: 9000, open: null, close: null },
  ],
  hours: [],
  flows: [{ day: '2026-11-18', sold: 7, cancelled: 0, expired: 0, posted: 0 }],
}

const paths = (fetch: ReturnType<typeof mockApi>) => fetch.mock.calls.map(([r]) => new URL(r.url))

describe('TrendsPage', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    window.history.pushState(null, '', '/')
  })

  it('is for admins only, and asks nothing of the admin routes for anyone else', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/coverage': coverage })
    window.history.pushState(null, '', '/trends?item=2589')
    renderWithProviders(<TrendsPage />, LINKED)
    expect(await screen.findByText(/This page is for site admins/)).toBeInTheDocument()
    expect(paths(fetch).some((u) => u.pathname.startsWith('/api/admin/'))).toBe(false)
  })

  it('searches an item and draws its history at the newest scanned house, over the range picked', async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/coverage': coverage,
      '/api/admin/items': (url: URL) => (url.searchParams.get('q')?.toLowerCase().includes('lin') ? [linen] : []),
      '/api/admin/items/2589/history': history,
    })
    window.history.pushState(null, '', '/trends')
    renderWithProviders(<TrendsPage />, ADMIN)
    expect(screen.getByText(/Search for an item/)).toBeInTheDocument()

    await userEvent.type(screen.getByPlaceholderText('Search by name or id'), 'lin')
    await userEvent.click(await screen.findByRole('option', { name: /Linen Cloth/ }))
    expect(new URLSearchParams(window.location.search).get('item')).toBe('2589')

    expect(await screen.findByRole('img', { name: 'Price history of Linen Cloth' })).toBeInTheDocument()
    expect(screen.getByText(/\+25\.0% over the range/)).toBeInTheDocument()
    expect(screen.getByText(/7 bought/)).toBeInTheDocument()
    const asked = paths(fetch).filter((u) => u.pathname === '/api/admin/items/2589/history')
    expect(asked.at(-1)?.searchParams.get('auction_house_id')).toBe('2') // scanned most recently
    expect(asked.at(-1)?.searchParams.get('days')).toBe('30')

    // hovering reads a day
    const target = screen.getByTestId('chart-hover')
    target.getBoundingClientRect = () => ({ left: 0, width: 720, top: 0, height: 240, right: 720, bottom: 240, x: 0, y: 0, toJSON: () => ({}) })
    fireEvent.pointerMove(target, { clientX: 700, clientY: 50 })
    expect(screen.getByText(/7 bought$/)).toBeInTheDocument()

    await userEvent.click(screen.getByText('90d'))
    await waitFor(() =>
      expect(
        paths(fetch)
          .filter((u) => u.pathname === '/api/admin/items/2589/history')
          .some((u) => u.searchParams.get('days') === '90'),
      ).toBe(true),
    )
  })

  it('opens the item and house the URL names', async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/coverage': coverage,
      '/api/admin/items': (url: URL) => (url.searchParams.get('q') === '2589' ? [linen] : []),
      '/api/admin/items/2589/history': { days: [], hours: [], flows: [] },
    })
    window.history.pushState(null, '', '/trends?item=2589&house=1&days=14')
    renderWithProviders(<TrendsPage />, ADMIN)
    expect(await screen.findByText(/Not enough of Linen Cloth's prices recorded at Americas Normal \(Horde\) over the last 14 days/)).toBeInTheDocument()
    const asked = paths(fetch).find((u) => u.pathname === '/api/admin/items/2589/history')
    expect(asked?.searchParams.get('auction_house_id')).toBe('1')
  })
})
