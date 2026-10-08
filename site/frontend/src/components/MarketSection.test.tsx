import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { ItemMap, RankResult } from '../api/client'
import { linen, robe, thread } from '../test/items'
import { robeResult } from '../test/results'
import { mockApi, renderWithProviders } from '../test/utils'
import { useMarket } from '../lib/marketFocus'
import { MarketSection } from './MarketSection'

const level = (price: number, quantity: number, counted = true) => ({
  price,
  quantity,
  counted,
  more: false,
  listings: 1,
  age: 2,
})

// Ten robes posted on the AH from linen bought up its ladder (only 8 listed) and a vendor's thread.
const posted: RankResult = {
  ...robeResult,
  best_exit: 'ah',
  likely_exit: 'ah',
  crafts: 10,
  cost: 3000,
  sell_options: [
    { kind: 'ah', profit: 6000 },
    { kind: 'vendor', profit: 2000 },
  ],
  tree: {
    ...robeResult.tree,
    inputs: [{ ...robeResult.tree.inputs[0]!, quantity: 10, cost: 2900, short: 2 }, robeResult.tree.inputs[1]!],
  },
}
const items: ItemMap = {
  '1': { ...linen, ah_price: 280, ah_quantity: 8, ah_levels: [level(280, 5), level(300, 3)], median_7d: 250, scans_7d: 4 },
  '2': thread,
  '3': { ...robe, ah_price: 950, ah_sell_price: 950, ah_quantity: 12, ah_levels: [level(940, 4), level(990, 8)] },
}

function Harness({ result }: { result: RankResult }) {
  const market = useMarket(result, 'gold', () => {})
  return (
    <MarketSection
      result={result}
      items={items}
      list={market.list}
      selected={market.selected}
      onSelect={market.select}
      watchedHours={0}
    />
  )
}

const tile = (name: RegExp) => screen.getByRole('button', { name })

describe('MarketSection', () => {
  it('opens on what is sold and switches to any item of the plan', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    const strip = screen.getByRole('group', { name: 'Items in this plan' })
    expect(within(strip).getAllByRole('button').map((b) => b.getAttribute('aria-pressed'))).toEqual([
      'false',
      'false',
      'true',
    ])
    expect(screen.getByText(/^We count on/)).toHaveTextContent(/for all 10/)
    // the linen's cue: two more bought than are listed
    expect(within(tile(/^Linen Cloth/)).getByText('2 short')).toBeInTheDocument()
    await userEvent.click(tile(/^Linen Cloth/))
    expect(tile(/^Linen Cloth/)).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByText(/^Buying 10 for/)).toHaveTextContent(/2 more than are listed, priced at the dearest 3 0/)
    expect(screen.getByText(/dearer than the usual/)).toHaveTextContent(/about 16% dearer than the usual 2 50/)
    await userEvent.click(tile(/^Coarse Thread/))
    expect(screen.getByText(/^Bought from a vendor/)).toBeInTheDocument()
  })

  it('shows the order book a click away: what a reagent buys of each level', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(tile(/^Linen Cloth/))
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show the order book' }))
    const rows = within(screen.getByRole('table')).getAllByRole('row')
    expect(rows[0]).toHaveTextContent('PriceUnitsListingsListed forYou buy')
    expect(rows.slice(1).map((r) => r.lastChild?.textContent)).toEqual(['5', '3'])
    expect(screen.getByRole('img', { name: /Price levels listed for Linen Cloth/ })).toBeInTheDocument()
    expect(screen.queryByRole('radio', { name: 'If I undercut' })).not.toBeInTheDocument()
  })

  it('tells what a level of the order book holds on hover', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(tile(/^Linen Cloth/))
    await userEvent.click(screen.getByRole('button', { name: 'Show the order book' }))
    // jsdom measures nothing: the chart is 640 px wide, its plot from 66 to 464 px holding the 8 units listed
    const target = screen.getByTestId('chart-hover')
    target.getBoundingClientRect = () => ({ left: 0, width: 640, top: 0, height: 190, right: 640, bottom: 190, x: 0, y: 0, toJSON: () => ({}) })
    fireEvent.pointerMove(target, { clientX: 100, clientY: 50 }) // the first level: 5 at 2 80
    expect(screen.getByText(/listed for 3 scans/)).toHaveTextContent('1 listing · listed for 3 scans')
    expect(screen.getByText('You buy 5')).toBeInTheDocument()
    fireEvent.pointerLeave(target)
    expect(screen.queryByText('You buy 5')).not.toBeInTheDocument()
  })

  it('moves the labels at a narrow chart’s edge into a legend under it', async () => {
    // a container 400 px wide, as on a phone
    vi.stubGlobal(
      'ResizeObserver',
      class {
        report: (entries: { contentRect: DOMRectReadOnly }[]) => void
        constructor(report: (entries: { contentRect: DOMRectReadOnly }[]) => void) {
          this.report = report
        }
        observe() {
          this.report([{ contentRect: { width: 400, height: 206, top: 0, left: 0 } as DOMRectReadOnly }])
        }
        unobserve() {}
        disconnect() {}
      },
    )
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(screen.getByRole('button', { name: 'Show the order book' }))
    // measured a frame later: the labels leave the chart's edge for the legend
    await waitFor(() => expect(screen.getByText(/^we count on/).tagName).toBe('LI'))
    expect(screen.getByText(/^break-even/).tagName).toBe('LI')
  })

  it('offers the profit at each price for what is sold on the auction house', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(screen.getByRole('button', { name: 'Show the order book' }))
    await userEvent.click(screen.getByRole('radio', { name: 'If I undercut' }))
    expect(screen.getByRole('img', { name: 'Session profit at each listing price' })).toBeInTheDocument()
    // hovered at its cheapest price, the profit is under what a vendor pays
    const target = screen.getByTestId('chart-hover')
    target.getBoundingClientRect = () => ({ left: 0, width: 640, top: 0, height: 206, right: 640, bottom: 206, x: 0, y: 0, toJSON: () => ({}) })
    fireEvent.pointerMove(target, { clientX: 66, clientY: 100 })
    expect(screen.getByText(/^Listed at/)).toBeInTheDocument()
    expect(screen.getByText(/^Vendor pays more/)).toHaveTextContent(/^Vendor pays more: 20 0$/)
  })

  it('tells more about the item: every way to sell, sales seen, how it is counted', async () => {
    mockApi({})
    renderWithProviders(<Harness result={posted} />)
    await userEvent.click(screen.getByRole('button', { name: 'More about Green Robe' }))
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['Ways to sell', 'Sales seen', 'How we count'])
    await userEvent.click(screen.getByRole('tab', { name: 'Sales seen' }))
    expect(screen.getByText(/^Sales here aren't watched yet/)).toBeInTheDocument()
  })
})
