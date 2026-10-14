import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { VendorCheck as VendorCheckOut } from '../api/client'
import { makeItem } from '../test/items'
import { status } from '../test/status'
import { mockApi, renderWithProviders, shown } from '../test/utils'
import { HIDDEN_QUALITIES_KEY, HIDDEN_TYPES_KEY, VendorCheck } from './VendorCheck'

const item = (over: Partial<VendorCheckOut['items'][number]>): VendorCheckOut['items'][number] => ({
  id: 1,
  name: 'Linen Cloth',
  quality: 1,
  class_id: 7,
  subclass_name: 'Cloth',
  icon: 'inv_fabric_linen_01',
  sell_price: 13,
  ah_price: 5,
  ah_quantity: 14,
  seen_at: '2026-10-14T10:00:00Z',
  ...over,
})

/** A page as the server sends it: the rows in its order, every item of the realm being the four below. */
const check = (over: Partial<VendorCheckOut> = {}): VendorCheckOut => ({
  realm: 'Classic Beta PvE',
  faction: 'Horde',
  items: [
    item({ id: 3, name: 'Green Robe', quality: 2, class_id: 4, sell_price: 500, ah_price: 120, ah_quantity: 1 }),
    item({ id: 1 }),
    item({ id: 2, name: 'Coarse Thread', sell_price: 10, ah_price: 100, ah_quantity: 50, icon: null }),
    item({ id: 4, name: 'Old Key', quality: 0, class_id: 13, subclass_name: null, sell_price: 0, ah_price: 7 }),
  ],
  total: 4,
  listed: 4,
  page: 1,
  page_size: 50,
  classes: [4, 7, 13],
  qualities: [0, 1, 2],
  ...over,
})

afterEach(() => {
  vi.unstubAllGlobals()
  localStorage.clear()
})

const rowNames = (table: HTMLElement) =>
  within(table)
    .getAllByRole('row')
    .slice(1)
    .map((r) => within(r).getAllByRole('cell')[0]?.textContent)

/** Each /api/vendorcheck request's query, as `name=value` pairs other than the game version. */
function asked(fetch: ReturnType<typeof mockApi>): string[] {
  return fetch.mock.calls
    .map(([r]) => new URL(r.url))
    .filter((u) => u.pathname === '/api/vendorcheck')
    .map((u) => {
      const pairs: string[] = []
      u.searchParams.forEach((v, k) => {
        if (k !== 'game_version') pairs.push(`${k}=${v}`)
      })
      return pairs.join('&')
    })
}

const types = () => screen.getByRole('group', { name: 'Item types' })
const qualities = () => screen.getByRole('group', { name: 'Quality' })

describe('VendorCheck', () => {
  it('shows the page the server sends, in its order, what no vendor buys with dashes', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/vendorcheck': check() })
    renderWithProviders(<VendorCheck />)
    const table = await screen.findByRole('table', { name: 'Vendor check' })
    expect(asked(fetch)).toEqual(['sort=difference&order=desc&page=1'])
    expect(screen.getByText(/auction house on Classic Beta PvE \(Horde\)/)).toBeInTheDocument()
    expect(rowNames(table)).toEqual(['Green RobeCloth', 'Linen ClothCloth', 'Coarse ThreadCloth', 'Old Key'])
    expect(screen.getByText('4 of 4 items')).toBeInTheDocument()
    expect(within(table).getAllByRole('columnheader').map((h) => h.getAttribute('aria-sort'))).toEqual([
      'none',
      'none',
      'none',
      'none',
      'descending',
      'none',
    ])
    const cells = within(within(table).getAllByRole('row')[1]!).getAllByRole('cell')
    expect(cells[1]).toHaveTextContent('Armor')
    expect(shown(cells[2])).toBe('1 20') // 120 copper: 1s 20c
    expect(shown(cells[3])).toBe('5 _0')
    expect(shown(cells[4])).toBe('3 80')
    expect(cells[5]).toHaveTextContent('+317%')
    expect(within(within(table).getAllByRole('row')[3]!).getAllByRole('cell')[5]).toHaveTextContent('-90%')
    const key = within(table).getAllByRole('row')[4]!
    expect(within(key).getAllByRole('cell').map((c) => c.textContent)).toEqual(['Old Key', 'Key', '7', '—', '—', '—'])
    expect(screen.queryByRole('button', { name: '2' })).not.toBeInTheDocument() // one page: no pager
  })

  it('asks the server to sort by a clicked header, reversing on another click', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/vendorcheck': check() })
    renderWithProviders(<VendorCheck />)
    const table = await screen.findByRole('table', { name: 'Vendor check' })
    const click = (name: string) => userEvent.click(within(table).getByRole('button', { name: `Sort by ${name}` }))

    await click('AH price')
    await click('AH price')
    await click('Item') // text: A first
    await click('% Difference')
    await click('Type')
    await click('Vendor pays')
    await waitFor(() =>
      expect(asked(fetch)).toEqual([
        'sort=difference&order=desc&page=1',
        'sort=ah_price&order=desc&page=1',
        'sort=ah_price&order=asc&page=1',
        'sort=item&order=asc&page=1',
        'sort=percent&order=desc&page=1',
        'sort=type&order=asc&page=1',
        'sort=vendor&order=desc&page=1',
      ]),
    )
    expect(within(table).getByRole('button', { name: 'Sort by Vendor pays' }).closest('th')).toHaveAttribute(
      'aria-sort',
      'descending',
    )
  })

  it('asks the server to leave out unticked types and qualities, and remembers them', async () => {
    const fetch = mockApi({ '/api/status': status(), '/api/vendorcheck': check() })
    const first = renderWithProviders(<VendorCheck />)
    await screen.findByRole('table', { name: 'Vendor check' })
    expect(within(types()).getAllByRole('checkbox').map((c) => c.getAttribute('value'))).toEqual(['4', '7', '13'])
    expect(within(qualities()).getAllByRole('checkbox').map((c) => c.getAttribute('value'))).toEqual(['0', '1', '2'])
    expect(screen.getAllByRole('checkbox').every((c) => (c as HTMLInputElement).checked)).toBe(true)

    await userEvent.click(within(types()).getByRole('checkbox', { name: 'Key' }))
    await userEvent.click(within(types()).getByRole('checkbox', { name: 'Armor' }))
    await userEvent.click(within(qualities()).getByRole('checkbox', { name: 'Poor' }))
    await waitFor(() =>
      expect(asked(fetch).at(-1)).toBe(
        'hide_classes=4&hide_classes=13&hide_qualities=0&sort=difference&order=desc&page=1',
      ),
    )
    expect(JSON.parse(localStorage.getItem(HIDDEN_TYPES_KEY)!)).toEqual([4, 13]) // in the checkboxes' order
    expect(JSON.parse(localStorage.getItem(HIDDEN_QUALITIES_KEY)!)).toEqual([0])
    expect(within(types()).getByRole('checkbox', { name: 'Key' })).not.toBeChecked()

    // ticked again, it is sent no more
    await userEvent.click(within(types()).getByRole('checkbox', { name: 'Armor' }))
    await waitFor(() =>
      expect(asked(fetch).at(-1)).toBe('hide_classes=13&hide_qualities=0&sort=difference&order=desc&page=1'),
    )
    first.unmount()

    // remembered: the next visit asks for the same at once
    const again = mockApi({ '/api/status': status(), '/api/vendorcheck': check() })
    renderWithProviders(<VendorCheck />)
    await screen.findByRole('table', { name: 'Vendor check' })
    expect(asked(again)).toEqual(['hide_classes=13&hide_qualities=0&sort=difference&order=desc&page=1'])
    expect(within(types()).getByRole('checkbox', { name: 'Key' })).not.toBeChecked()
    expect(within(qualities()).getByRole('checkbox', { name: 'Poor' })).not.toBeChecked()
  })

  it('keeps a hidden type hidden while none of it is listed', async () => {
    localStorage.setItem(HIDDEN_TYPES_KEY, JSON.stringify([9]))
    const fetch = mockApi({ '/api/status': status(), '/api/vendorcheck': check() })
    renderWithProviders(<VendorCheck />)
    await screen.findByRole('table', { name: 'Vendor check' })
    await userEvent.click(within(types()).getByRole('checkbox', { name: 'Key' }))
    await waitFor(() =>
      expect(asked(fetch).at(-1)).toBe('hide_classes=9&hide_classes=13&sort=difference&order=desc&page=1'),
    )
  })

  it('pages through the server, back to the first page when the filter or sort changes', { timeout: 15_000 }, async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/vendorcheck': (url: URL) => {
        const page = Number(url.searchParams.get('page'))
        return check({
          total: 120,
          listed: 130,
          page,
          items: Array.from({ length: page === 3 ? 20 : 50 }, (_, i) => item({ id: 1000 + i, name: `Item ${i}` })),
        })
      },
    })
    renderWithProviders(<VendorCheck />)
    const table = await screen.findByRole('table', { name: 'Vendor check' })
    expect(rowNames(table)).toHaveLength(50)
    expect(screen.getByText('120 of 130 items, 1–50 shown')).toBeInTheDocument()
    // a pager above the table and one under it
    expect(screen.getAllByRole('button', { name: '3' })).toHaveLength(2)
    await userEvent.click(screen.getAllByRole('button', { name: '3' })[0]!)
    expect(await screen.findByText('120 of 130 items, 101–120 shown')).toBeInTheDocument()
    expect(rowNames(table)).toHaveLength(20)

    await userEvent.click(within(table).getByRole('button', { name: 'Sort by AH price' }))
    expect(await screen.findByText('120 of 130 items, 1–50 shown')).toBeInTheDocument()
    await userEvent.click(screen.getAllByRole('button', { name: '2' })[1]!)
    await screen.findByText('120 of 130 items, 51–100 shown')
    await userEvent.click(within(types()).getByRole('checkbox', { name: 'Armor' }))
    expect(await screen.findByText('120 of 130 items, 1–50 shown')).toBeInTheDocument()
    expect(asked(fetch)).toEqual([
      'sort=difference&order=desc&page=1',
      'sort=difference&order=desc&page=3',
      'sort=ah_price&order=desc&page=1',
      'sort=ah_price&order=desc&page=2',
      'hide_classes=4&sort=ah_price&order=desc&page=1',
    ])
  })

  it('opens a clicked row into its order book, with what a vendor pays drawn across it', async () => {
    const level = (price: number, quantity: number) => ({ price, quantity, counted: true, more: false, listings: 1, age: 0 })
    const fetch = mockApi({
      '/api/status': status(),
      '/api/vendorcheck': check(),
      '/api/vendorcheck/items/1': makeItem({
        id: 1,
        name: 'Linen Cloth',
        sell_price: 13,
        ah_levels: [level(5, 10), level(9, 3), level(30, 4)],
      }),
    })
    renderWithProviders(<VendorCheck />)
    const table = await screen.findByRole('table', { name: 'Vendor check' })
    const linen = within(table).getAllByRole('row')[2]!
    expect(within(linen).getByRole('button', { name: 'Linen Cloth' })).toHaveAttribute('aria-expanded', 'false')

    await userEvent.click(within(linen).getAllByRole('cell')[3]!) // anywhere on the row
    const details = await screen.findByRole('region', { name: "Linen Cloth's order book" })
    expect(within(details).getByText('13 units are listed under what a vendor pays.')).toBeInTheDocument()
    expect(within(details).getByText(/vendor pays 13c/)).toBeInTheDocument() // the line across the chart
    expect(within(linen).getByRole('button', { name: 'Linen Cloth' })).toHaveAttribute('aria-expanded', 'true')
    const itemCalls = fetch.mock.calls.filter(([r]) => new URL(r.url).pathname === '/api/vendorcheck/items/1')
    expect(itemCalls).toHaveLength(1)

    // the name is the keyboard's way: it closes the row, as a click on the row again would
    await userEvent.click(within(linen).getByRole('button', { name: 'Linen Cloth' }))
    expect(screen.queryByRole('region', { name: "Linen Cloth's order book" })).not.toBeInTheDocument()
    await userEvent.click(within(linen).getAllByRole('cell')[1]!)
    expect(await screen.findByRole('region', { name: "Linen Cloth's order book" })).toBeInTheDocument()

    // one at a time; another sort closes it
    await userEvent.click(within(table).getByRole('button', { name: 'Sort by Item' }))
    expect(screen.queryByRole('region', { name: "Linen Cloth's order book" })).not.toBeInTheDocument()
  })

  it('says so in an opened row when no vendor buys the item', async () => {
    mockApi({
      '/api/status': status(),
      '/api/vendorcheck': check(),
      '/api/vendorcheck/items/4': makeItem({
        id: 4,
        name: 'Old Key',
        sell_price: 0,
        ah_levels: [{ price: 7, quantity: 2, counted: true, more: false, listings: 1, age: 0 }],
      }),
    })
    renderWithProviders(<VendorCheck />)
    const table = await screen.findByRole('table', { name: 'Vendor check' })
    await userEvent.click(within(table).getByRole('button', { name: 'Old Key' }))
    const details = await screen.findByRole('region', { name: "Old Key's order book" })
    expect(within(details).getByText('No vendor buys this item.')).toBeInTheDocument()
    expect(within(details).queryByText(/vendor pays/)).not.toBeInTheDocument()
  })

  it('says when no realm is selected or nothing is scanned', async () => {
    mockApi({
      '/api/status': status(),
      '/api/vendorcheck': check({ realm: '', faction: '', items: [], total: 0, listed: 0, classes: [], qualities: [] }),
    })
    renderWithProviders(<VendorCheck />)
    expect(await screen.findByText('No scan of this realm yet.')).toBeInTheDocument()
    expect(screen.getByText('Select a realm on the Profit page first.')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('shows the error when the server fails', async () => {
    mockApi({ '/api/status': status() })
    renderWithProviders(<VendorCheck />)
    expect(await screen.findByText('no mock for /api/vendorcheck')).toBeInTheDocument()
  })
})
