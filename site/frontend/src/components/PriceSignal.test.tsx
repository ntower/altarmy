import { Notifications, notifications } from '@mantine/notifications'
import { type QueryClient, useQueryClient } from '@tanstack/react-query'
import { act, screen, waitFor } from '@testing-library/react'
import { useEffect } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import { PriceSignal } from './PriceSignal'

/** The signal listeners the component holds, by auction house id. */
const listeners = new Map<number, (version: number) => void>()

vi.mock('../lib/signals', () => ({
  watchPriceSignal: (ah: number, onVersion: (version: number) => void) => {
    listeners.set(ah, onVersion)
    return () => listeners.delete(ah)
  },
}))

function renderSignal() {
  return renderWithProviders(
    <>
      <Notifications />
      <PriceSignal />
    </>,
  )
}

const statusCalls = (fetch: ReturnType<typeof mockApi>) =>
  fetch.mock.calls.filter(([r]) => new URL(r.url).pathname === '/api/status').length

describe('PriceSignal', () => {
  beforeEach(() => {
    listeners.clear()
    notifications.clean() // the store outlives a test
  })
  afterEach(() => vi.unstubAllGlobals())

  it('refetches the status when the server has newer prices and says so', async () => {
    let version = 3
    const fetch = mockApi({ '/api/status': () => status({ price_version: version }) })
    renderSignal()
    await waitFor(() => expect(listeners.has(1)).toBe(true))
    expect(statusCalls(fetch)).toBe(1)

    act(() => listeners.get(1)?.(3)) // the version already shown: the listen's first snapshot
    expect(statusCalls(fetch)).toBe(1)

    version = 4
    act(() => listeners.get(1)?.(4))
    await waitFor(() => expect(statusCalls(fetch)).toBe(2))
    expect(await screen.findByText('Prices updated')).toBeInTheDocument()
    expect(screen.getByText(/New auction house prices for Classic Beta PvE \(Horde\)/)).toBeInTheDocument()
  })

  it('marks every cached ranking stale when new prices come, refetching none', async () => {
    let version = 3
    const fetch = mockApi({ '/api/status': () => status({ price_version: version }) })
    let client: QueryClient | undefined
    function Probe() {
      const found = useQueryClient()
      useEffect(() => {
        client = found
      }, [found])
      return null
    }
    renderWithProviders(
      <>
        <Notifications />
        <PriceSignal />
        <Probe />
      </>,
    )
    await waitFor(() => expect(listeners.has(1)).toBe(true))
    client?.setQueryData(['rank', 'forever', '1.3', { held: true }], { results: [] })
    const ranking = () => client?.getQueryCache().find({ queryKey: ['rank', 'forever', '1.3', { held: true }] })
    expect(ranking()?.state.isInvalidated).toBe(false)

    version = 4
    act(() => listeners.get(1)?.(4))
    await waitFor(() => expect(ranking()?.state.isInvalidated).toBe(true))
    expect(fetch.mock.calls.filter(([r]) => new URL(r.url).pathname === '/api/rank')).toHaveLength(0)
  })

  it('says nothing when another realm is selected', async () => {
    let over = {}
    const fetch = mockApi({ '/api/status': () => status(over) })
    renderSignal()
    await waitFor(() => expect(listeners.has(1)).toBe(true))
    over = { auction_house_id: 2, selection: { realm: 'Dreamscythe', faction: 'Horde' }, price_version: 9 }
    act(() => listeners.get(1)?.(1)) // refetches: the status now names another auction house
    await waitFor(() => expect(listeners.has(2)).toBe(true))
    expect(statusCalls(fetch)).toBe(2)
    expect(listeners.has(1)).toBe(false) // stopped listening to the old one
    expect(screen.queryByText('Prices updated')).not.toBeInTheDocument()
  })
})
