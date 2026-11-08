import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import type { Characters, Learn, PriceConfidence, RankResult } from '../api/client'
import { BARTERING } from '../lib/talents'
import { linen, robe as robeItem, thread } from '../test/items'
import { bought, robeResult as robe, timedRobe } from '../test/results'
import { characters, status } from '../test/status'
import { mockApi, renderWithProviders, shown } from '../test/utils'
import { ResultsTable } from './ResultsTable'

const items = { '1': linen, '2': thread, '3': robeItem }

const disenchanted: RankResult = {
  ...robe,
  recipe_id: 101,
  best_exit: 'disenchant',
  revenue: 75988,
  postage: 30,
  mail_to: 'Enchy',
  exits: [
    { kind: 'vendor', value: 500, materials: [], postage: 0, mail_to: '' },
    {
      kind: 'disenchant',
      value: 75988,
      postage: 30,
      mail_to: 'Enchy',
      materials: [
        { item_id: 1, name: 'Linen Cloth', chance: 0.75, min_count: 1, max_count: 2, value: 75988, expected: 1.125 },
        { item_id: 2, name: 'Coarse Thread', chance: 0.25, min_count: 1, max_count: 1, value: null, expected: 0.25 },
      ],
    },
  ],
  steps: [
    { action: 'buy', item_id: 4, name: 'Medium Hide', quantity: 2, value: -12648, via: 'ah', who: '', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r.0.0'] },
    { action: 'craft', item_id: 5, name: 'Cured Medium Hide', quantity: 2, value: 0, via: 'Cure', who: '', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r.0'] },
    { action: 'craft', item_id: 3, name: 'Green Robe', quantity: 1, value: 0, via: 'Green Robe', who: '', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r'] },
    { action: 'mail', item_id: 3, name: 'Green Robe', quantity: 1, value: -30, via: 'Enchy', who: '', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r'] },
    { action: 'sell', item_id: 3, name: 'Green Robe', quantity: 1, value: 75988, via: 'disenchant', who: '', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['sell'] },
  ],
}

/** Hovers the flag labelled `label` and returns the text of the tooltip it opens. */
async function flagText(label: string): Promise<string | null> {
  await userEvent.hover(screen.getByLabelText(label))
  return (await screen.findByRole('tooltip')).textContent
}

type Place = Learn['items'][number]['places'][number]
const place: Place = { kind: 'drop', name: '', zone: '', side: '', chance: 0, count: 0, levels: '', limited: false, area: 0, map_x: 0, map_y: 0 }
const vendor: Place = { ...place, kind: 'vendor', area: 1637, map_x: 40, map_y: 60.5 }

const trusted: PriceConfidence = {
  level: 'high',
  reason: 'sold',
  sold: 9,
  units: 1,
  listed: 4,
  scan_days: 4,
  watched_hours: 2,
  unlisted_since: null,
  flags: [],
  sold_pairs: 2,
}

describe('ResultsTable slow sales and short books', () => {
  it('says how long a slow sale may take', async () => {
    const slow = { ...robe, recipe_id: 102, best_exit: 'ah', slow: true, days_to_sell: 3.2 }
    renderWithProviders(<ResultsTable results={[slow]} items={items} />)
    expect(await flagText('Slow to sell')).toBe('May take about 3 days to sell at the rate it sold lately')
  })

  it('flags a sell price trusted little, saying why, and flags nothing else', async () => {
    const confidence = { ...trusted, level: 'low' as const, reason: 'unlisted' as const, listed: 0 }
    const unsure = { ...robe, recipe_id: 102, best_exit: 'ah', confidence }
    renderWithProviders(<ResultsTable results={[unsure, robe]} items={items} />)
    expect(screen.getAllByLabelText('Low price confidence')).toHaveLength(1)
    expect(screen.queryByLabelText('Slow to sell')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Not enough listed')).not.toBeInTheDocument()
    expect(await flagText('Low price confidence')).toBe(
      'Low confidence in the sell price: None listed, and none seen selling: priced from what it was listed for before',
    )
  })

  it('flags nothing for a sell price trusted well', () => {
    renderWithProviders(<ResultsTable results={[{ ...robe, confidence: trusted }]} items={items} />)
    expect(screen.queryByLabelText(/price confidence/)).not.toBeInTheDocument()
  })

  it('flags a plan that buys more than the auction house lists', async () => {
    renderWithProviders(<ResultsTable results={[{ ...robe, short: 2 }]} items={items} />)
    expect(await flagText('Not enough listed')).toBe(
      'Needs 2 more units than the auction house lists; they are counted at the dearest price listed',
    )
  })

  it('opens a flag without expanding its row', async () => {
    renderWithProviders(<ResultsTable results={[{ ...robe, short: 2 }]} items={items} />)
    await userEvent.click(screen.getByLabelText('Not enough listed'))
    expect(screen.getByLabelText(`Details for ${robe.recipe}`)).toHaveAttribute('aria-expanded', 'false')
  })
})

/** Checks the open disenchant tooltip lists both materials and the expected total, three columns a row. */
async function expectDisenchantTooltip() {
  const title = await screen.findByText((_, el) => shown(el) === 'Disenchanting 1x Green Robe')
  const rows = Array.from(title.nextElementSibling?.children ?? [], (row) => Array.from(row.children, shown))
  expect(rows).toEqual([
    ['Linen Cloth', '×1-2 (75%)', '7 59 88'],
    ['Coarse Thread', '×1 (25%)', 'no price'],
    ['Expected total after AH cut', '', '7 59 88'],
  ])
}

/** A list item or table cell whose whole text is `text` (item names inside are separate elements). */
const line = (text: string) =>
  screen.getByText((_, el) => (el?.tagName === 'LI' || el?.tagName === 'TD') && shown(el) === text)

/** The text of each step listed under `who`, in order. */
const linesOf = (who: string) =>
  within(screen.getByRole('group', { name: `${who}'s steps` }))
    .getAllByRole('listitem')
    .map((li) => shown(li))

/** A flow chart node line whose whole text is `text` (amounts inside are coin elements). */
const detail = (text: string) => (_: string, el: Element | null) => el?.tagName === 'DIV' && shown(el) === text

/** The colours (teal, red) of the silver amounts in `el`, e.g. a sale's gross and net. */
const silverColors = (el: HTMLElement) =>
  Array.from(el.querySelectorAll('[data-unit="silver"]'), (coin) =>
    coin.closest<HTMLElement>('[style]')!.style.color.match(/--mantine-color-(\w+)-text/)?.[1],
  )

/** The colours of the gross and net amounts on the flow chart's sale line with text `text`. */
const saleColors = (text: string) => silverColors(screen.getByText(detail(text)))

/** Open the Flowchart view (rows open on Steps). */
const showFlow = async (nth = 0) => {
  await userEvent.click(screen.getAllByText('Flowchart')[nth]!)
}

/** Open the Steps view, and wait for its session plan. */
const showSteps = async (nth = 0) => {
  await userEvent.click(screen.getAllByText('Steps')[nth]!)
  await screen.findAllByText(/^\d+ crafts?:/)
}

/** /api/evaluate as the server answers it, for tests: each recipe planned as its row (once the user has made a
 * choice, as `chosen`), with the session's crafts. */
const planned =
  (rows: RankResult[], chosen?: RankResult) =>
  async (_: URL, request: Request) => {
    const body = (await request.clone().json()) as { recipe_id: number; choices: object; copies?: number }
    const row = rows.find((r) => r.recipe_id === body.recipe_id) ?? rows[0]!
    const result = chosen && Object.keys(body.choices).length ? chosen : row
    return { result: body.copies ? { ...result, crafts: body.copies } : result, items }
  }

/** The choices of the first /api/evaluate request that made any. */
async function choicesSent(fetch: ReturnType<typeof mockApi>) {
  for (const [request] of fetch.mock.calls) {
    if (new URL(request.url).pathname !== '/api/evaluate') continue
    const { choices } = (await request.clone().json()) as { choices: Record<string, string> }
    if (Object.keys(choices).length) return choices
  }
  return undefined
}

/** Render the rows with the server planning their sessions. */
function renderRows(rows: RankResult[]) {
  mockApi({ '/api/evaluate': planned(rows) })
  return renderWithProviders(<ResultsTable results={rows} items={items} />)
}

describe('ResultsTable', () => {
  it('formats money, ROI and the recipe as its output item, without the quantity', () => {
    renderRows([robe])
    expect(line('2 _0')).toBeInTheDocument()
    expect(screen.getByText('67%')).toBeInTheDocument()
    expect(line('Green Robe')).toBeInTheDocument()
    expect(screen.queryByRole('columnheader', { name: /^Output/ })).not.toBeInTheDocument()
    expect(line('3 _0')).toBeInTheDocument()
    expect(screen.queryByText(/Purchase/)).not.toBeInTheDocument()
  })

  it('shows the profit, investment, ROI, recipe and sell via columns for making gold, and nothing per hour', () => {
    renderWithProviders(<ResultsTable results={[timedRobe]} items={items} rankBy="profit" onSetFavorite={() => {}} />)
    const headers = screen.getAllByRole('columnheader').map((h) => h.textContent?.replace(/[▲▼]/g, ''))
    expect(headers).toEqual(['', 'Net profit', 'Investment', 'ROI', 'Recipe', 'Crafter', 'Sell via', ''])
  })

  it('shows what a skill point costs and how far each run goes when skilling up', () => {
    renderWithProviders(<ResultsTable results={[robe]} items={items} rankBy="skill" />)
    const headers = screen.getAllByRole('columnheader').map((h) => h.textContent?.replace(/[▲▼]/g, ''))
    expect(headers).toEqual(['Recipe', 'Cost per point', 'Craft until', 'Investment', 'Learn'])
  })

  it('opens a row elsewhere instead of unfolding it, given onOpen', async () => {
    const onOpen = vi.fn()
    renderWithProviders(<ResultsTable results={[robe]} items={items} rankBy="skill" onOpen={onOpen} />)
    await userEvent.click(screen.getByRole('button', { name: 'Open Green Robe' }))
    expect(onOpen).toHaveBeenCalledWith(robe)
    expect(screen.queryByRole('radiogroup', { name: 'Show the plan as' })).not.toBeInTheDocument() // nothing unfolds
    screen.getByRole('button', { name: 'Open Green Robe' }).focus()
    await userEvent.keyboard('{Enter}')
    expect(onOpen).toHaveBeenCalledTimes(2)
  })

  it('shows where each run stops and how it is learned', () => {
    const run: RankResult = { ...robe, stop_skill: 45, stop_reason: 'rival', crafts: 12, skill_ups: 5 }
    const learning: RankResult = { ...run, recipe_id: 101, crafter: 'Novice', crafters: ['Tailor Guy'] }
    const learn: Record<string, Learn> = { '101': { source: 'recipe', skill: 50, profession: 'Tailoring', items: [], train_cost: 0 } }
    renderWithProviders(<ResultsTable results={[run, learning]} items={items} rankBy="skill" learn={learn} />)
    expect(screen.getAllByText('45 (~12 crafts)')).toHaveLength(2) // the skill the run stops at, and its crafts
    expect(screen.queryByRole('img', { name: /Orange|Green|Yellow/ })).not.toBeInTheDocument() // no colour letters
    expect(screen.getByText('known')).toBeInTheDocument()
    expect(screen.getByText('pattern · Tailor Guy knows it')).toBeInTheDocument()
  })

  it('names the characters who know the recipe', () => {
    const unlearned = { ...robe, recipe_id: 101, crafters: [] }
    const browsed = { ...robe, recipe_id: 102, crafters: [], crafter: '' } // no characters at all
    renderRows([robe, unlearned, browsed])
    expect(screen.getByText('Tailor Guy')).toBeInTheDocument()
    expect(screen.getByText('not learned')).toBeInTheDocument()
    expect(screen.getByText('anyone')).toBeInTheDocument()
  })

  it('says where to learn a recipe nobody has', async () => {
    const unlearned = { ...robe, recipe_id: 101, crafters: [] }
    const trained = { ...robe, recipe_id: 102, crafters: [] }
    const learn: Record<string, Learn> = {
      '101': {
        source: 'recipe',
        skill: 50,
        profession: 'Tailoring',
        items: [
          {
            item_id: 4,
            name: 'Pattern: Green Robe',
            limited: true,
            places: [
              { ...vendor, name: 'Borya', zone: 'Orgrimmar', side: 'horde', limited: true },
              { ...place, kind: 'drop', name: 'Defias Pillager', zone: 'Westfall', chance: 0.0123 },
              { ...place, kind: 'more', count: 4 },
            ],
          },
        ],
        train_cost: 0,
      },
      '102': { source: 'trainer', skill: 30, profession: 'Tailoring', items: [], train_cost: 600 },
    }
    renderWithProviders(<ResultsTable results={[unlearned, trained]} items={items} learn={learn} />)
    const [first, second] = screen.getAllByText('not learned')
    await userEvent.hover(first)
    const tip = await screen.findByRole('tooltip')
    expect(within(tip).getByText('Pattern: Green Robe (Tailoring 50)')).toBeInTheDocument()
    expect(within(tip).getByText('Sold by Borya, Orgrimmar (limited stock)')).toBeInTheDocument()
    expect(within(tip).getByText('Drops from Defias Pillager, Westfall (0.012%)')).toBeInTheDocument()
    expect(within(tip).getByText('and 4 more')).toBeInTheDocument()
    expect(within(tip).getByText(/vanilla's world data/)).toBeInTheDocument()
    // its only vendor, on the zone map
    expect(within(tip).getByAltText('Map: Borya')).toHaveAttribute('src', '/maps/1637.jpg')
    expect(within(tip).getByTestId('map-dot')).toHaveStyle({ left: '40%', top: '60.5%' })
    await userEvent.unhover(first)
    await userEvent.hover(second)
    expect(await screen.findByText(/Taught by Tailoring trainers \(skill 30\)/)).toHaveTextContent(
      /^Taught by Tailoring trainers \(skill 30\) for 6 0$/,
    )
    // hovering or tapping it does not open the row
    await userEvent.click(second)
    expect(screen.getAllByLabelText(`Details for ${robe.recipe}`)[1]).toHaveAttribute('aria-expanded', 'false')
  })

  it('shows no map when more than one vendor sells the recipe', async () => {
    const unlearned = { ...robe, recipe_id: 101, crafters: [] }
    const places: Place[] = [
      { ...vendor, name: 'Borya', zone: 'Orgrimmar' },
      { ...vendor, name: 'Kendor', zone: 'Stormwind City', area: 1519 },
    ]
    const learn: Record<string, Learn> = {
      '101': { source: 'recipe', skill: 50, profession: 'Tailoring', items: [{ item_id: 4, name: 'Pattern: Green Robe', limited: false, places }], train_cost: 0 },
    }
    renderWithProviders(<ResultsTable results={[unlearned]} items={items} learn={learn} />)
    await userEvent.hover(screen.getByText('not learned'))
    const tip = await screen.findByRole('tooltip')
    expect(within(tip).getByText('Sold by Kendor, Stormwind City')).toBeInTheDocument()
    expect(within(tip).queryByRole('img')).not.toBeInTheDocument()
  })

  it('says what a recipe item without known places is', async () => {
    const unlearned = { ...robe, recipe_id: 101, crafters: [] }
    const item = { item_id: 4, name: 'Pattern: Green Robe', limited: false, places: [] }
    const learn: Record<string, Learn> = { '101': { source: 'bop', skill: 50, profession: 'Tailoring', items: [item], train_cost: 0 } }
    renderWithProviders(<ResultsTable results={[unlearned]} items={items} learn={learn} />)
    await userEvent.hover(screen.getByText('not learned'))
    const tip = await screen.findByRole('tooltip')
    expect(within(tip).getByText('Bind on pickup: looted or earned in the world')).toBeInTheDocument()
    expect(within(tip).queryByText(/vanilla's world data/)).not.toBeInTheDocument()
  })

  it('lets anyone convert essences and says so in the steps', async () => {
    const converted: RankResult = {
      ...robe,
      recipe_id: 1_000_000_960,
      kind: 'convert',
      profession: '',
      crafters: [],
      steps: robe.steps.map((s) => (s.action === 'craft' ? { ...s, convert: true } : s)),
    }
    const browsed = { ...converted, recipe_id: 1_000_000_961, crafter: '' } // no characters at all
    renderRows([converted, browsed])
    expect(screen.getByText('Tailor Guy')).toBeInTheDocument() // whoever the plan picks: no recipe to learn
    expect(screen.getByText('anyone')).toBeInTheDocument()
    expect(screen.queryByText('not learned')).not.toBeInTheDocument()
    await userEvent.click(screen.getAllByRole('button', { name: 'Details for Green Robe' })[0])
    await showSteps()
    expect(line('Convert into 1x Green Robe')).toBeInTheDocument()
  })

  it('names the enchanter who buys and disenchants a flip', () => {
    const flipped: RankResult = {
      ...disenchanted,
      recipe_id: 2_000_000_003,
      kind: 'flip',
      profession: '',
      crafters: [],
      crafter: 'Enchy',
    }
    renderRows([flipped])
    expect(screen.getByText('Enchy')).toBeInTheDocument()
    expect(screen.queryByText('not learned')).not.toBeInTheDocument()
  })

  it('names a flip as disenchanting the item it buys', () => {
    renderRows([{ ...disenchanted, recipe_id: 2_000_000_003, kind: 'flip', profession: '' }])
    expect(line('Disenchant Green Robe')).toBeInTheDocument()
  })

  it('does not say Disenchant before a crafted recipe', () => {
    renderRows([disenchanted])
    expect(line('Green Robe')).toBeInTheDocument()
  })

  it('shows only the chosen crafter, in class colours, then how many others know the recipe', () => {
    renderWithProviders(
      <ResultsTable
        results={[
          { ...robe, crafters: ['Alice', 'Tailor Guy'] },
          { ...robe, recipe_id: 101, crafters: ['Alice', 'Bob', 'Tailor Guy'] },
        ]}
        items={items}
        classes={{ 'Tailor Guy': 'MAGE', Alice: 'ROGUE' }}
      />,
    )
    expect(line('Tailor Guy (and 1 other)')).toHaveAttribute('title', 'Tailor Guy, Alice')
    expect(line('Tailor Guy (and 2 others)')).toHaveAttribute('title', 'Tailor Guy, Alice, Bob')
    expect(screen.getAllByText('Tailor Guy')[0]).toHaveAttribute('data-class', 'MAGE')
  })

  it('expands a row into a flow chart of the reagents, crafts and sale', async () => {
    renderRows([robe])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    expect(screen.getByText(detail('Buy on the AH · 2 0'))).toBeInTheDocument()
    expect(screen.getByText(detail('Buy from a vendor · 1 0'))).toBeInTheDocument()
    expect(screen.getByText('Craft 1x Green Robe')).toBeInTheDocument()
    expect(screen.getByText('Sell to a vendor')).toBeInTheDocument()
    // flow chart item names truncate rather than push the quantity out of the box
    expect(screen.getByText('Linen Cloth').closest('[data-truncate]')).not.toBeNull()
    expect(saleColors('Gross 5 0 · Net 2 0')).toEqual(['teal', 'teal'])
    expect(screen.queryByText(/Purchase/)).not.toBeInTheDocument()
  })

  it('shows a loss on the sale as a red, negative net', async () => {
    renderRows([{ ...robe, profit: -150 }])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    expect(saleColors('Gross 5 0 · Net -1 50')).toEqual(['teal', 'red'])
  })

  it('shows step-by-step instructions on the Steps tab', async () => {
    renderRows([robe, disenchanted])
    const [first, second] = screen.getAllByRole('button', { name: 'Details for Green Robe' })

    await userEvent.click(first)
    expect(first).toHaveAttribute('aria-expanded', 'true')
    await showSteps()
    expect(line('Purchase 10x Linen Cloth on the AH (2 0)')).toBeInTheDocument()
    expect(line('Purchase 1x Coarse Thread from a vendor (1 0)')).toBeInTheDocument()
    expect(line('Craft 1x Green Robe')).toBeInTheDocument()
    expect(line('Sell 1x Green Robe to a vendor (Gross 5 0 · Net 2 0)')).toBeInTheDocument()

    await userEvent.click(second)
    await showSteps(1)
    expect(line('Purchase 2x Medium Hide on the AH (1 26 48)')).toBeInTheDocument()
    expect(line('Craft 2x Cured Medium Hide')).toBeInTheDocument()
    expect(line('Mail 1x Green Robe to Enchy (30)')).toBeInTheDocument()
    expect(line('Disenchant Green Robe (view expected materials)')).toBeInTheDocument()
    expect(line('Auction materials (Gross 7 59 88 · Net 2 0)')).toBeInTheDocument()
  })

  it('names what Legacy talents did: a Bartering discount and Master Chef extras', async () => {
    const [linenStep, threadStep, craft, sale] = robe.steps
    const talented: RankResult = {
      ...robe,
      bonus_output: 0.3,
      steps: [linenStep, { ...threadStep, value: -90, discount: 10 }, craft, { ...sale, bonus: 0.3 }],
      tree: {
        ...robe.tree,
        inputs: [robe.tree.inputs[0], { ...robe.tree.inputs[1], cost: 90, discount: 10 }],
      },
    }
    renderRows([talented])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    // the flow chart's boxes are narrow: the discount is in the tooltip alone
    expect(screen.getByText(detail('Buy from a vendor · 90'))).toHaveAttribute('title', 'Bartering −10%')
    expect(screen.getByText(detail('+0.3 expected from Master Chef'))).toBeInTheDocument()
    await showSteps()
    expect(line('Purchase 1x Coarse Thread from a vendor (90, after discount)')).toBeInTheDocument()
    // the extra results are made by the craft: said there, not on the sale
    expect(line('Craft 1x Green Robe (+0.3 expected from Master Chef)')).toBeInTheDocument()
    expect(line('Sell 1x Green Robe to a vendor (Gross 5 0 · Net 2 0)')).toBeInTheDocument()
  })

  it('names the reputation that made a vendor cheaper', async () => {
    const [linenStep, threadStep, craft, sale] = robe.steps
    const honored = { rep_discount: 10, rep_faction: 'Orgrimmar' }
    const reputed: RankResult = {
      ...robe,
      steps: [linenStep, { ...threadStep, value: -90, ...honored }, craft, sale],
      tree: { ...robe.tree, inputs: [robe.tree.inputs[0], { ...robe.tree.inputs[1], cost: 90, ...honored }] },
    }
    renderRows([reputed])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    // the flow chart's boxes are narrow: the discount and whose reputation it is are in the tooltip alone
    const node = screen.getByText(detail('Buy from a vendor · 90'))
    expect(node).toHaveAttribute('title', 'Orgrimmar reputation −10%')
    await showSteps()
    expect(line('Purchase 1x Coarse Thread from a vendor (90, after discount)')).toBeInTheDocument()
  })

  it("lists the buyer's reputation discounts and Bartering ranks on hovering a discount", async () => {
    const [linenStep, threadStep, craft, sale] = robe.steps
    const both = { who: 'Tailor Guy', discount: 5, rep_discount: 10, rep_faction: 'Orgrimmar' }
    const discounted: RankResult = { ...robe, steps: [linenStep, { ...threadStep, value: -85, ...both }, craft, sale] }
    const [tailor] = characters.groups[0].characters
    const reputed: Characters = {
      ...characters,
      groups: [
        {
          ...characters.groups[0],
          characters: [
            {
              ...tailor,
              talents: [{ spell_id: BARTERING, name: 'Bartering', rank: 1, max_rank: 2 }],
              vendor_discounts: [
                { faction: 'Orgrimmar', percent: 10 },
                { faction: 'Darkspear Trolls', percent: 10 },
              ],
            },
          ],
        },
      ],
    }
    mockApi({ '/api/evaluate': planned([discounted]), '/api/status': status(), '/api/characters': reputed })
    renderWithProviders(<ResultsTable results={[discounted]} items={items} />)
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    await userEvent.hover(screen.getByText('after discount'))
    const title = await screen.findByText((_, el) => el?.tagName === 'DIV' && shown(el) === "Tailor Guy's vendor discounts")
    // the buyer's name in their class colour
    expect(within(title).getByText('Tailor Guy')).toHaveAttribute('data-class', 'MAGE')
    expect(await screen.findByText('Darkspear Trolls vendors')).toBeInTheDocument()
    expect(screen.getByText('Orgrimmar vendors')).toBeInTheDocument()
    expect(screen.getByText('Bartering 1/2')).toBeInTheDocument()
    expect(screen.getByText('−5%')).toBeInTheDocument()
  })

  it("leaves out reputation when the buyer has none, and says the step's discount until characters load", async () => {
    const [linenStep, threadStep, craft, sale] = robe.steps
    const bartered: RankResult = {
      ...robe,
      steps: [linenStep, { ...threadStep, value: -90, who: 'Stranger', discount: 10 }, craft, sale],
    }
    renderRows([bartered])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    await userEvent.hover(screen.getByText('after discount'))
    expect(await screen.findByText('Bartering 2/2')).toBeInTheDocument()
    expect(screen.getByText('−10%')).toBeInTheDocument()
    expect(screen.queryByText('Reputation')).not.toBeInTheDocument()
  })

  it('colours the Steps sale by its sign, without + or -', async () => {
    renderRows([{ ...robe, profit: -150 }])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    expect(silverColors(line('Sell 1x Green Robe to a vendor (Gross 5 0 · Net 1 50)'))).toEqual(['teal', 'red'])
  })

  it('shows the expected disenchant materials on the Steps sell line', async () => {
    renderRows([disenchanted])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    await userEvent.hover(screen.getByText('Auction materials'))
    await expectDisenchantTooltip()
  })

  it('auctions each material on its own line in the detailed view, each with the menu', async () => {
    renderRows([disenchanted])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    await userEvent.click(screen.getByRole('checkbox', { name: 'Detailed view' }))
    expect(line('Disenchant Green Robe')).toBeInTheDocument()
    // 1.125 Linen Cloth a disenchant: all the gross and net, since the thread has no price
    expect(line('Auction ~1.1x Linen Cloth (Gross 7 59 88 · Net 2 0)')).toBeInTheDocument()
    expect(line('Auction ~0.3x Coarse Thread (no price)')).toBeInTheDocument()
    expect(screen.queryByText('Auction materials')).not.toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Change how it is sold' })).toHaveLength(2)
  })

  it('shows the expected disenchant materials on the Steps row\'s "view expected materials"', async () => {
    renderRows([disenchanted])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    await userEvent.hover(within(line('Disenchant Green Robe (view expected materials)')).getByText('view expected materials'))
    await expectDisenchantTooltip()
  })

  it('shows the expected disenchant materials on the flow chart sell node', async () => {
    renderRows([disenchanted])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    await userEvent.hover(screen.getByText('Disenchant and auction'))
    await expectDisenchantTooltip()
  })

  it('names who does each step and mails intermediates between them', async () => {
    const split: RankResult = {
      ...robe,
      recipe_id: 102,
      crafter: 'Smithy',
      steps: [
        { action: 'buy', item_id: 1, name: 'Linen Cloth', quantity: 6, value: -120, via: 'ah', who: 'Leathery', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r.0.0'] },
        { action: 'craft', item_id: 2, name: 'Coarse Thread', quantity: 2, value: 0, via: 'Thread', who: 'Leathery', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r.0'] },
        { action: 'mail', item_id: 2, name: 'Coarse Thread', quantity: 2, value: -30, via: 'Smithy', who: 'Leathery', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r.0'] },
        { action: 'craft', item_id: 3, name: 'Green Robe', quantity: 1, value: 0, via: 'Green Robe', who: 'Smithy', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r'] },
        { action: 'sell', item_id: 3, name: 'Green Robe', quantity: 1, value: 500, via: 'vendor', who: 'Smithy', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['sell'] },
      ],
    }
    renderRows([split])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showSteps()
    // each character's steps under their name, in the order they do them
    expect(screen.getAllByRole('group').map((g) => g.getAttribute('aria-label'))).toEqual([
      "Leathery's steps",
      "Smithy's steps",
    ])
    expect(linesOf('Leathery')).toEqual([
      'Purchase 6x Linen Cloth on the AH (1 20)',
      'Craft 2x Coarse Thread',
      'Mail 2x Coarse Thread to Smithy (30)',
    ])
    expect(linesOf('Smithy')).toEqual(['Craft 1x Green Robe', 'Sell 1x Green Robe to a vendor (Gross 5 0 · Net 2 0)'])
  })

  it('puts the character on its own line in flow chart nodes', async () => {
    const named: RankResult = { ...robe, tree: { ...robe.tree, crafter: 'Smithy' } }
    renderRows([named])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    expect(screen.getByText('Craft 1x Green Robe')).toBeInTheDocument()
    expect(screen.getByText('Smithy')).toBeInTheDocument()
  })

  it('leaves mailing out of the flow chart, naming the enchanter under the sale', async () => {
    renderRows([disenchanted])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await showFlow()
    expect(screen.queryByText(/^Mail /)).not.toBeInTheDocument()
    expect(screen.queryByText(/Postage/)).not.toBeInTheDocument()
    expect(screen.getAllByText('Enchy')).toHaveLength(1) // the disenchanter under the sale
  })

  it('shows the recipe tooltip, not the item tooltip, on the recipe', async () => {
    renderRows([robe])
    const recipe = screen.getByText('Green Robe')
    expect(recipe.closest('[data-quality]')?.querySelector('img')).not.toBeNull()
    await userEvent.hover(recipe)
    expect(await screen.findByText('Reagents: Linen Cloth (10), Coarse Thread')).toBeInTheDocument()
  })

  it.each([false, true])('links flow and step items to their tooltips (steps: %s)', async (steps) => {
    renderRows([robe])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    if (steps) await showSteps()
    await userEvent.hover(screen.getByText('Linen Cloth'))
    expect(await screen.findByText((_, el) => shown(el) === 'Auction: 20')).toBeInTheDocument()
  })

  describe('sorting', () => {
    const rows: RankResult[] = [
      { ...robe, recipe_id: 1, recipe: 'Bolt', output_name: 'Bolt', cost: 50, profit: 300, best_exit: 'ah' },
      { ...robe, recipe_id: 2, recipe: 'Axe', output_name: 'Axe', cost: 900, profit: 100, best_exit: 'vendor' },
      { ...robe, recipe_id: 3, recipe: 'Cape', output_name: 'Cape', cost: 400, profit: 200, best_exit: 'disenchant' },
    ]
    const order = () =>
      screen.getAllByRole('button', { name: /^Details for / }).map((b) => b.getAttribute('aria-label')?.slice(12))
    const header = (name: string) => screen.getByRole('columnheader', { name: new RegExp(`^${name}`) })
    const sortBy = async (name: string) => await userEvent.click(screen.getByRole('button', { name: `Sort by ${name}` }))

    it('keeps the given order until a column is picked', () => {
      renderWithProviders(<ResultsTable results={rows} items={items} />)
      expect(order()).toEqual(['Bolt', 'Axe', 'Cape'])
      expect(header('Net profit')).toHaveAttribute('aria-sort', 'none')
    })

    it('sorts numbers largest first, then reverses on a second click', async () => {
      renderWithProviders(<ResultsTable results={rows} items={items} />)
      await sortBy('Investment')
      expect(order()).toEqual(['Axe', 'Cape', 'Bolt'])
      expect(header('Investment')).toHaveAttribute('aria-sort', 'descending')
      await sortBy('Investment')
      expect(order()).toEqual(['Bolt', 'Cape', 'Axe'])
      expect(header('Investment')).toHaveAttribute('aria-sort', 'ascending')
    })

    it('sorts text alphabetically first', async () => {
      renderWithProviders(<ResultsTable results={rows} items={items} />)
      await sortBy('Recipe')
      expect(order()).toEqual(['Axe', 'Bolt', 'Cape'])
      await sortBy('Sell via')
      expect(order()).toEqual(['Bolt', 'Cape', 'Axe'])
      expect(screen.getByText('Auction')).toBeInTheDocument()
      expect(header('Recipe')).toHaveAttribute('aria-sort', 'none')
    })

    it('keeps favorites first and marks them, whatever the sort', async () => {
      renderWithProviders(<ResultsTable results={rows} items={items} favorites={new Set([3])} />)
      expect(order()).toEqual(['Cape', 'Bolt', 'Axe'])
      await sortBy('Investment')
      expect(order()).toEqual(['Cape', 'Axe', 'Bolt'])
      await sortBy('Investment')
      expect(order()).toEqual(['Cape', 'Bolt', 'Axe'])
      expect(screen.getAllByLabelText('Favorite')).toHaveLength(1)
      expect(screen.getByRole('button', { name: 'Details for Cape' }).closest('tr')?.className).toMatch(/favorite/)
      expect(screen.getByRole('button', { name: 'Details for Axe' }).closest('tr')?.className).not.toMatch(/favorite/)
    })

    it('sorts profit ascending to surface the losers', async () => {
      renderWithProviders(<ResultsTable results={rows} items={items} />)
      await sortBy('Net profit')
      expect(order()).toEqual(['Bolt', 'Cape', 'Axe'])
      await sortBy('Net profit')
      expect(order()).toEqual(['Axe', 'Cape', 'Bolt'])
    })
  })

  describe('changing the plan', () => {
    const [linenNode, threadNode] = robe.tree.inputs
    /** The robe with its thread bought on the AH instead, as the server re-costs it. */
    const fromAh: RankResult = {
      ...robe,
      cost: 350,
      profit: 150,
      roi: 150 / 350,
      steps: robe.steps.map((s) => (s.item_id === 2 ? { ...s, value: -150, via: 'ah' } : s)),
      tree: {
        ...robe.tree,
        cost: 350,
        inputs: [linenNode!, { ...bought(2, 'Coarse Thread', 1, 150, 'ah', threadNode!.options) }],
      },
      sell_options: [
        { kind: 'vendor', profit: 150 },
        { kind: 'ah', profit: 125 },
      ],
    }
    async function open() {
      const fetch = mockApi({ '/api/evaluate': planned([robe], fromAh) })
      renderWithProviders(<ResultsTable results={[robe]} items={items} />)
      await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
      await showFlow() // the menus are the flow chart's
      return fetch
    }

    it('offers a menu only where there is a choice, best first', async () => {
      await open()
      expect(screen.queryByRole('button', { name: 'Change source of Linen Cloth' })).not.toBeInTheDocument()
      await userEvent.click(screen.getByRole('button', { name: 'Change source of Coarse Thread' }))
      expect(screen.getAllByRole('menuitem').map(shown)).toEqual([
        '✓Buy from a vendor1 0',
        'Buy on the AH1 50',
      ])
    })

    it('offers the other ways to sell on the sale', async () => {
      await open()
      await userEvent.click(screen.getByRole('button', { name: 'Change how it is sold' }))
      expect(screen.getAllByRole('menuitem').map(shown)).toEqual([
        '✓Sell to a vendorprofit 2 0',
        'Sell on the AHprofit 1 75',
      ])
      const amount = screen.getAllByRole('menuitem')[1]!.querySelector('[title="silver"]')!.closest('[style]')
      expect(amount).toHaveStyle({ color: 'var(--mantine-color-teal-text)' })
    })

    it('re-costs the recipe with the choice, and Reset brings back the best plan', async () => {
      const fetch = await open()
      expect(screen.queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
      await userEvent.click(screen.getByRole('button', { name: 'Change source of Coarse Thread' }))
      await userEvent.click(screen.getByRole('menuitem', { name: /Buy on the AH/ }))

      expect(await screen.findByText(detail('Buy on the AH · 1 50'))).toBeInTheDocument()
      const bodies = await Promise.all(
        fetch.mock.calls
          .map(([r]) => r)
          .filter((r) => r.method === 'POST' && new URL(r.url).pathname === '/api/evaluate')
          .map((r) => r.clone().json() as Promise<Record<string, unknown>>),
      )
      // the row is re-costed as the ranking has it (no copies or city: the time settings' batch)
      expect(bodies).toContainEqual({
        recipe_id: 100,
        unlearned: 'none',
        look_ahead: 0,
        sources: ['trainer', 'recipe'],
        include_trivial: true,
        skill_crafters: [],
        exits: ['vendor', 'ah', 'disenchant'],
        arcane_salvager: false,
        runs: false,
        gathered: [],
        choices: { 'r.1': 'ah' },
        strategy: 'recommended',
      })
      expect(line('1 50')).toBeInTheDocument() // the row's profit follows the changed plan
      expect(screen.getByLabelText('Changed plan')).toBeInTheDocument()

      await userEvent.click(screen.getByRole('button', { name: 'Reset' }))
      expect(await screen.findByText(detail('Buy from a vendor · 1 0'))).toBeInTheDocument()
      expect(line('2 _0')).toBeInTheDocument()
      expect(screen.queryByLabelText('Changed plan')).not.toBeInTheDocument()
      expect(screen.queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
    })

    it('offers the same menus on the Steps tab', async () => {
      await open()
      await showSteps()
      expect(screen.queryByRole('button', { name: 'Change source of Linen Cloth' })).not.toBeInTheDocument()
      expect(screen.queryByRole('button', { name: 'Change source of Green Robe' })).not.toBeInTheDocument()
      await userEvent.click(screen.getByRole('button', { name: 'Change source of Coarse Thread' }))
      expect(screen.getAllByRole('menuitem').map(shown)).toEqual(['✓Buy from a vendor1 0', 'Buy on the AH1 50'])
      await userEvent.keyboard('{Escape}')
      await userEvent.click(screen.getByRole('button', { name: 'Change how it is sold' }))
      expect(screen.getAllByRole('menuitem').map(shown)).toEqual([
        '✓Sell to a vendorprofit 2 0',
        'Sell on the AHprofit 1 75',
      ])
    })

    it('re-costs the recipe with a choice made on the Steps tab', async () => {
      const fetch = await open()
      await showSteps()
      await userEvent.click(screen.getByRole('button', { name: 'Change source of Coarse Thread' }))
      await userEvent.click(screen.getByRole('menuitem', { name: /Buy on the AH/ }))

      expect(await screen.findByText((_, el) => el?.tagName === 'LI' && shown(el) === 'Purchase 1x Coarse Thread on the AH (1 50)')).toBeInTheDocument()
      expect(await choicesSent(fetch)).toEqual({ 'r.1': 'ah' })
      await userEvent.click(screen.getByRole('button', { name: 'Reset' }))
      expect(await screen.findByText((_, el) => el?.tagName === 'LI' && shown(el) === 'Purchase 1x Coarse Thread from a vendor (1 0)')).toBeInTheDocument()
    })

    it('changes every use of a merged step at once, offering what they all offer, costs summed', async () => {
      const both = (vendor: number, ah: number) => [
        { key: 'vendor', cost: vendor, source: 'vendor', via: '', crafter: '', seconds: 0, convert: false },
        { key: 'ah', cost: ah, source: 'ah', via: '', crafter: '', seconds: 0, convert: false },
      ]
      // Thread for a sub-crafted bolt (r.0.0) and for the robe itself (r.1), bought in one step.
      const merged: RankResult = {
        ...robe,
        steps: [
          { action: 'buy', item_id: 2, name: 'Coarse Thread', quantity: 3, value: -300, via: 'vendor', who: '', discount: 0, rep_discount: 0, rep_faction: '', bonus: 0, seconds: 0, station: '', lead_seconds: 0, convert: false, enchant: false, paths: ['r.0.0', 'r.1'] },
          ...robe.steps.slice(2),
        ],
        tree: {
          ...robe.tree,
          inputs: [
            { ...robe.tree, item_id: 1, name: 'Linen Cloth', inputs: [bought(2, 'Coarse Thread', 2, 200, 'vendor', both(200, 300))] },
            bought(2, 'Coarse Thread', 1, 100, 'vendor', [...both(100, 150), { key: 'craft:9', cost: 90, source: '', via: 'Spin', crafter: '', seconds: 0, convert: false }]),
          ],
        },
      }
      const fetch = mockApi({ '/api/evaluate': planned([merged], robe) })
      renderWithProviders(<ResultsTable results={[merged]} items={items} />)
      await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
      await showSteps()
      await userEvent.click(screen.getByRole('button', { name: 'Change source of Coarse Thread' }))
      expect(screen.getAllByRole('menuitem').map(shown)).toEqual(['✓Buy from a vendor3 0', 'Buy on the AH4 50'])
      await userEvent.click(screen.getByRole('menuitem', { name: /Buy on the AH/ }))
      await screen.findByRole('button', { name: 'Reset' })
      expect(await choicesSent(fetch)).toEqual({ 'r.0.0': 'ah', 'r.1': 'ah' })
    })
  })

  describe('row actions', () => {
    it('offers to stop selling the output on the AH without expanding the row', async () => {
      const onSetAhBlocked = vi.fn()
      renderWithProviders(
        <ResultsTable results={[robe]} items={items} ahBlocked={new Set()} onSetAhBlocked={onSetAhBlocked} />,
      )
      await userEvent.click(screen.getByRole('button', { name: 'Actions for Green Robe' }))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Never sell on auction house' }))
      expect(onSetAhBlocked).toHaveBeenCalledWith(3, true)
      expect(screen.getByRole('button', { name: 'Details for Green Robe' })).toHaveAttribute('aria-expanded', 'false')
    })

    it('offers to allow selling a blocked output on the AH again', async () => {
      const onSetAhBlocked = vi.fn()
      renderWithProviders(
        <ResultsTable results={[robe]} items={items} ahBlocked={new Set([3])} onSetAhBlocked={onSetAhBlocked} />,
      )
      await userEvent.click(screen.getByRole('button', { name: 'Actions for Green Robe' }))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Allow selling on auction house' }))
      expect(onSetAhBlocked).toHaveBeenCalledWith(3, false)
    })

    it.each(['flip', 'convert'] as const)('does not offer to stop selling a %s on the AH', async (kind) => {
      renderWithProviders(
        <ResultsTable
          results={[{ ...disenchanted, kind, profession: '' }]}
          items={items}
          ahBlocked={new Set()}
          onSetAhBlocked={vi.fn()}
          onSetFavorite={vi.fn()}
        />,
      )
      await userEvent.click(screen.getByRole('button', { name: /^Actions for / }))
      expect((await screen.findAllByRole('menuitem')).map(shown)).toEqual(['Add to favorites'])
    })

    it('offers to add a recipe to favorites', async () => {
      const onSetFavorite = vi.fn()
      renderWithProviders(<ResultsTable results={[robe]} items={items} onSetFavorite={onSetFavorite} />)
      await userEvent.click(screen.getByRole('button', { name: 'Actions for Green Robe' }))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Add to favorites' }))
      expect(onSetFavorite).toHaveBeenCalledWith(robe.recipe_id, true)
    })

    it('offers to remove a favorite', async () => {
      const onSetFavorite = vi.fn()
      renderWithProviders(
        <ResultsTable results={[robe]} items={items} favorites={new Set([robe.recipe_id])} onSetFavorite={onSetFavorite} />,
      )
      await userEvent.click(screen.getByRole('button', { name: 'Actions for Green Robe' }))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Remove from favorites' }))
      expect(onSetFavorite).toHaveBeenCalledWith(robe.recipe_id, false)
    })

    it('has no actions menu without a handler', () => {
      renderRows([robe])
      expect(screen.queryByRole('button', { name: 'Actions for Green Robe' })).not.toBeInTheDocument()
    })
  })
})

describe('ResultsTable rankings and timed results', () => {
  const header = (name: string) => screen.getByRole('columnheader', { name: new RegExp(`^${name}`) })

  it('shows no profit per hour for a timed result', () => {
    renderRows([timedRobe])
    expect(screen.queryByRole('columnheader', { name: /Per hour/ })).not.toBeInTheDocument()
    expect(screen.queryByTitle(/crafts in/)).not.toBeInTheDocument()
  })

  it("shows the server's ranking on its column, and sorts the page by any header", async () => {
    const cheap = { ...timedRobe, recipe_id: 7, recipe: 'Cap', output_name: 'Cap', profit: 10 }
    const recipes = () => screen.getAllByRole('button', { name: /^Details for / }).map((b) => b.getAttribute('aria-label'))
    renderWithProviders(<ResultsTable results={[timedRobe, cheap]} items={items} rankBy="profit" />)
    expect(header('Net profit')).toHaveAttribute('aria-sort', 'descending')
    expect(recipes()).toEqual(['Details for Green Robe', 'Details for Cap'])
    await userEvent.click(screen.getByRole('button', { name: 'Sort by Net profit' })) // flips the server's order
    expect(header('Net profit')).toHaveAttribute('aria-sort', 'ascending')
    expect(recipes()).toEqual(['Details for Cap', 'Details for Green Robe'])
    await userEvent.click(screen.getByRole('button', { name: 'Sort by Investment' }))
    expect(header('Investment')).toHaveAttribute('aria-sort', 'descending')
    expect(header('Net profit')).toHaveAttribute('aria-sort', 'none')
  })

  it('shows a ranking by skill on its own column, cheapest point first, with the chance on hover', async () => {
    const chancy: RankResult = { ...timedRobe, profit: -300, roi: -0.5, crafts: 10, skill_chance: 0.25, skill_ups: 2.5 }
    const grey: RankResult = { ...timedRobe, recipe_id: 7, recipe: 'Cap', output_name: 'Cap', skill_chance: 0, skill_ups: 0 }
    renderWithProviders(<ResultsTable results={[chancy, grey]} items={items} rankBy="skill" />)
    expect(header('Cost per point')).toHaveAttribute('aria-sort', 'ascending')
    const cell = line('-1 20')
    expect(cell).toHaveAttribute('title', '25% chance of a skill point on the first craft ·2.5 expected from 10 crafts')
    expect(line('–')).toBeInTheDocument() // the grey one gives none
    const color = (el: HTMLElement) => el.closest<HTMLElement>('[style]')?.style.color.match(/--mantine-color-(\w+)-text/)?.[1]
    expect(color(within(cell).getByTitle('silver'))).toBe('red') // a cost
    await userEvent.click(screen.getByRole('button', { name: 'Sort by Cost per point' }))
    expect(header('Cost per point')).toHaveAttribute('aria-sort', 'descending')
  })

  it('shows no skill column for other rankings', () => {
    renderWithProviders(<ResultsTable results={[timedRobe]} items={items} rankBy="profit" />)
    expect(screen.queryByRole('columnheader', { name: /Cost per point/ })).not.toBeInTheDocument()
  })

  it('names the new Forever stations a plan needs, counted as set down on the spot', async () => {
    const deployed: RankResult = { ...timedRobe, timing: { ...timedRobe.timing!, deployed: ['loom', 'spinning_wheel'] } }
    renderRows([deployed])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    expect(
      screen.getByText('Needs a loom and a spinning wheel'),
    ).toBeInTheDocument()
  })

  it('says when a city lacks a station the plan needs, and never recommends it', async () => {
    const noAnvil: RankResult = {
      ...timedRobe,
      timing: { ...timedRobe.timing!, missing: ['anvil', 'spinning_wheel'] },
      cities: [{ ...timedRobe.cities[0]!, missing: ['anvil'] }, timedRobe.cities[1]!],
    }
    renderRows([noAnvil])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    expect(screen.getByText(/Orgrimmar has no anvil or spinning wheel: this plan can't be crafted there/)).toBeInTheDocument()
  })

  it('sums the plan up in one line, shows no times, and notes what the lines cannot show', async () => {
    renderRows([timedRobe])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    const text = (t: string) => screen.findByText((_, el) => el?.tagName === 'P' && shown(el) === t)
    expect(await text('10 crafts: Investment 3 0 · Net profit 2 0')).toBeInTheDocument()
    expect(screen.queryByText(/Estimated time|\/hr/)).not.toBeInTheDocument()
    expect(screen.getByText(`Estimated skill points gained: ${timedRobe.skill_ups}`)).toBeInTheDocument()
    expect(screen.queryByText(/^A batch of|^By city/)).not.toBeInTheDocument()
    expect(screen.getByText('No vendor in Orgrimmar sells Coarse Thread.')).toBeInTheDocument()
    expect(screen.queryByText(/can't be crafted there/)).not.toBeInTheDocument()
    await showSteps()
    expect(line('Craft 1x Green Robe')).toBeInTheDocument() // a 3.5 s craft: the time is not shown
    expect(line('Purchase 10x Linen Cloth on the AH (2 0)')).toBeInTheDocument()
  })

  it('says how many of the estimated skill points Working Overtime adds', async () => {
    renderRows([{ ...timedRobe, skill_ups: 9.71, skill_ups_bonus: 0.38 }])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    expect(
      screen.getByText('Estimated skill points gained: 9.7 (including 0.4 from Working Overtime)'),
    ).toBeInTheDocument()
  })

  it('puts a minus sign before a losing session in the summary', async () => {
    const losing: RankResult = { ...timedRobe, profit: -200, timing: { ...timedRobe.timing!, per_hour: -12345 } }
    renderRows([losing])
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    const text = (t: string) => screen.findByText((_, el) => el?.tagName === 'P' && shown(el) === t)
    expect(await text('10 crafts: Investment 3 0 · Net profit -2 0')).toBeInTheDocument()
  })
})

describe('ResultsTable: a gold list', () => {
  // ten robes on the AH: the market took one lately, so nine are counted at the vendor
  const posted: RankResult = {
    ...robe,
    best_exit: 'ah',
    crafts: 10,
    profit: 6000,
    cost: 3000,
    likely_profit: 2500,
    likely_exit: 'ah',
    depth_units: 1,
    excess_units: 9,
    safe_profit: 2000,
    safe_exit: 'vendor',
    ah_profit: 2500,
    ah_depth_units: 1,
    ah_excess_units: 9,
    sell_options: [
      { kind: 'ah', profit: 6000 },
      { kind: 'vendor', profit: 2000 },
    ],
  }
  const market = {
    ...items,
    '3': { ...robeItem, ah_price: 1000, market_price: 1000, median_7d: 950, scans_7d: 4, ah_sell_price: 950, ah_quantity: 1 },
  }
  const cells = () => within(screen.getAllByRole('row')[1]!).getAllByRole('cell')

  it('shows the recipe, then what playing it safe and the auction house make, the better in bold', () => {
    renderWithProviders(<ResultsTable results={[posted]} items={market} rankBy="gold" />)
    const headers = screen.getAllByRole('columnheader').map((h) => h.textContent)
    expect(headers).toEqual(['', 'Recipe', 'Safe profit▼', 'Auction profit▼'])
    const [, recipe, safe, ah] = cells()
    expect(shown(safe!)).toBe('20 _0vendor') // 2000 copper: 20 silver
    expect(shown(ah!)).toBe('25 _0market takes ~1 of 10') // counts on what the market takes
    expect(within(ah!).getByText('25').closest('[class*="secondary"]')).toBeNull()
    expect(within(safe!).getByText('20').closest('[class*="secondary"]')).not.toBeNull()
    expect(within(recipe!).getByText(/Tailoring · .*10 crafts · spend/)).toBeInTheDocument()
    expect(within(recipe!).getByText('Tailor Guy')).toBeInTheDocument()
    expect(screen.queryByText('Unproven', { exact: false })).not.toBeInTheDocument() // no verdict chip
    expect(screen.queryByLabelText(/price confidence/)).not.toBeInTheDocument()
  })

  it('says how many the market takes, in orange under half, or how many are listed', () => {
    const note = (r: RankResult) => {
      const { unmount } = renderWithProviders(<ResultsTable results={[r]} items={market} rankBy="gold" />)
      const ah = cells()[3]!
      const text = within(ah).getByText(/listed|takes|buyers/)
      const got = { text: shown(text), orange: text.closest('[style*="orange"]') !== null }
      unmount()
      return got
    }
    expect(note(posted)).toEqual({ text: 'market takes ~1 of 10', orange: true })
    expect(note({ ...posted, ah_depth_units: 7, ah_excess_units: 3 })).toEqual({
      text: 'market takes ~7 of 10',
      orange: false,
    })
    expect(note({ ...posted, ah_depth_units: 0, ah_excess_units: 10 })).toEqual({
      text: 'no buyers shown yet',
      orange: true,
    })
    expect(note({ ...posted, ah_depth_units: 10, ah_excess_units: 0 })).toEqual({
      text: '1 listed · you add 10',
      orange: false,
    })
  })

  it('shows a dash where a way to sell is not open to the recipe', () => {
    const vendorOnly: RankResult = { ...posted, ah_profit: null, sell_options: [{ kind: 'vendor', profit: 2000 }] }
    renderWithProviders(<ResultsTable results={[vendorOnly]} items={market} rankBy="gold" />)
    expect(shown(cells()[3]!)).toBe('–')
  })

  it('names an essence conversion safe', () => {
    const essence: RankResult = { ...posted, kind: 'convert', profession: '', safe_exit: 'convert', ah_profit: null }
    renderWithProviders(<ResultsTable results={[essence]} items={market} rankBy="gold" />)
    const [, recipe, safe] = cells()
    expect(shown(safe!)).toBe('20 _0essences sell')
    expect(within(recipe!).getByText(/Essence conversion · /)).toBeInTheDocument()
  })

  it('warns when an auction house sale may take long', () => {
    renderWithProviders(
      <ResultsTable results={[{ ...posted, slow: true, days_to_sell: 9.6 }]} items={market} rankBy="gold" />,
    )
    expect(screen.getByText('slow: ~10 days')).toHaveAttribute('title', expect.stringMatching(/about 10 days/))
  })

  it('puts both profits on one line under the recipe for phones', () => {
    renderWithProviders(<ResultsTable results={[posted]} items={market} rankBy="gold" />)
    const phone = cells()[1]!.querySelector('[class*="onlyBelowXs"]')
    expect(shown(phone)).toBe('Safe 20 0 AH 25 0market takes ~1 of 10')
  })

  it('re-ranks the whole list on the server by a header, best first, and reverses it on another click', async () => {
    const onGoldSort = vi.fn()
    const table = (sort: string, order?: 'asc' | 'desc') =>
      renderWithProviders(
        <ResultsTable
          results={[posted]}
          items={market}
          rankBy="gold"
          goldSort={sort}
          goldOrder={order}
          onGoldSort={onGoldSort}
        />,
      )
    const header = () => screen.getByRole('columnheader', { name: /Auction profit/ })
    const click = (name: string) => userEvent.click(screen.getByRole('button', { name: `Sort by ${name}` }))
    let shown = table('likely')
    expect(header()).toHaveAttribute('aria-sort', 'none')
    await click('Auction profit')
    expect(onGoldSort).toHaveBeenLastCalledWith('ah', 'desc')
    shown.unmount()
    shown = table('ah', 'desc')
    expect(header()).toHaveAttribute('aria-sort', 'descending')
    await click('Auction profit')
    expect(onGoldSort).toHaveBeenLastCalledWith('ah', 'asc')
    await click('Safe profit') // another header: best first
    expect(onGoldSort).toHaveBeenLastCalledWith('safe', 'desc')
    shown.unmount()
    table('ah', 'asc')
    expect(header()).toHaveAttribute('aria-sort', 'ascending')
    expect(header()).toHaveTextContent('Auction profit▲')
    await click('Auction profit')
    expect(onGoldSort).toHaveBeenLastCalledWith('ah', 'desc')
  })

  it('opens with the totals by the copies, then Market (summed up) and Steps closed around the open Flowchart', async () => {
    mockApi({})
    renderWithProviders(<ResultsTable results={[{ ...posted, crafter: 'Tailor Guy' }]} items={market} rankBy="gold" />)
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    expect(screen.queryByRole('radiogroup', { name: 'Show the plan as' })).not.toBeInTheDocument()
    expect(screen.queryByText(/Estimated skill points gained/)).not.toBeInTheDocument()
    const totals = screen.getByText((_, el) => el?.tagName === 'P' && shown(el)?.startsWith('10 crafts: Investment') === true)
    expect(totals.parentElement).toContainElement(screen.getByLabelText('Copies').closest('.mantine-InputWrapper-root') as HTMLElement)
    const sections = [/^Market/, 'Flowchart', 'Steps'].map((name) => screen.getByRole('button', { name }))
    expect(sections.map((s) => s.getAttribute('aria-expanded'))).toEqual(['false', 'true', 'false'])
    expect(sections[0]!.compareDocumentPosition(sections[1]!) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(sections[1]!.compareDocumentPosition(sections[2]!) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    // the closed header says what selling counts on
    expect(shown(sections[0]!)).toMatch(/^Market Counting on 9 50 for 1 of 10 · break-even /)
    // React Flow hides its nodes until it has measured them, a tick after mounting
    const flow = screen.getByRole('region', { name: 'Flowchart' })
    await waitFor(() => expect(within(flow).getByRole('button', { name: 'Change source of Coarse Thread' })).toBeVisible())
    await userEvent.click(sections[2]!)
    expect(within(screen.getByRole('region', { name: 'Steps' })).getByRole('checkbox', { name: 'Detailed view' })).toBeVisible()
    await userEvent.click(sections[0]!)
    const section = screen.getByRole('region', { name: /^Market/ })
    expect(within(section).getByRole('button', { name: /^Green Robe/, pressed: true })).toBeInTheDocument()
    expect(within(section).getByText(/We count on/)).toHaveTextContent(/for 1 of your 10; the other 9 at Vendor/)
    expect(within(section).getByText(/usually/)).toBeInTheDocument()
    await userEvent.click(within(section).getByRole('button', { name: 'More about Green Robe' }))
    expect(within(section).getByText(/the other 9 are counted at Vendor/)).toBeInTheDocument()
  })

  it('opens Market on an item named in the steps', async () => {
    mockApi({})
    renderWithProviders(<ResultsTable results={[posted]} items={market} rankBy="gold" />)
    await userEvent.click(screen.getByRole('button', { name: 'Details for Green Robe' }))
    await userEvent.click(screen.getByRole('button', { name: 'Steps' }))
    const steps = screen.getByRole('region', { name: 'Steps' })
    await userEvent.click(within(steps).getByRole('button', { name: 'Linen Cloth' }))
    expect(screen.getByRole('button', { name: /^Market/ })).toHaveAttribute('aria-expanded', 'true')
    const section = screen.getByRole('region', { name: /^Market/ })
    expect(within(section).getByRole('button', { name: /^Linen Cloth/, pressed: true })).toBeInTheDocument()
    expect(within(section).getByText(/^Buying 10 for/)).toBeInTheDocument()
  })
})

describe('ResultsTable: an enchant cast for the skill point alone', () => {
  const NAME = 'Enchant Bracer - Minor Health'
  const enchant: RankResult = {
    ...robe,
    recipe_id: 110,
    recipe: NAME,
    kind: 'enchant',
    profession: 'Enchanting',
    crafters: ['Enchy'],
    crafter: 'Enchy',
    output_item_id: 0,
    output_name: NAME,
    cost: 20000,
    revenue: 0,
    profit: -20000,
    roi: -1,
    best_exit: 'skill',
    crafts: 5,
    skill_ups: 5,
    exits: [],
    sell_options: [{ kind: 'skill', profit: -20000 }],
    reagents: [{ item_id: 1, count: 2 }],
    steps: [
      { ...robe.steps[0]!, quantity: 10, value: -20000, who: 'Enchy' },
      { ...robe.steps[2]!, item_id: 0, name: NAME, via: NAME, quantity: 5, who: 'Enchy', enchant: true },
    ],
    tree: {
      ...robe.tree,
      item_id: 0,
      name: NAME,
      via: NAME,
      quantity: 5,
      crafts: 5,
      made: 5,
      cost: 20000,
      crafter: 'Enchy',
      enchant: true,
      inputs: [{ ...bought(1, 'Linen Cloth', 10, 20000), crafter: 'Enchy' }],
    },
  }

  it('names the enchant and what each point it gives costs', () => {
    renderWithProviders(<ResultsTable results={[enchant]} items={items} rankBy="skill" />)
    expect(line(NAME)).toBeInTheDocument()
    expect(line('known')).toBeInTheDocument()
    expect(line('-40 _0')).toBeInTheDocument() // per skill point
    expect(line('~5 crafts')).toBeInTheDocument() // the crafts (no run here: no skill it stops at)
  })

  it('says Skill only where a table sells, making gold', () => {
    renderWithProviders(<ResultsTable results={[enchant]} items={items} rankBy="profit" />)
    expect(line('Skill only')).toBeInTheDocument()
    expect(screen.getByText('-100%')).toBeInTheDocument()
    expect(line('-2 _0 _0')).toBeInTheDocument() // net profit: what it cost
  })

  it('ends the flow chart and the steps with the cast: nothing is sold', async () => {
    renderRows([enchant])
    await userEvent.click(screen.getByRole('button', { name: `Details for ${NAME}` }))
    await showFlow()
    expect(screen.getByText('Cast 5x · skill up only')).toBeInTheDocument()
    expect(screen.queryByText(/Gross/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByText('Steps'))
    expect(linesOf('Enchy')).toContain(`Cast ${NAME} 5 times`)
    expect(screen.queryByText(/^Sell \d/)).not.toBeInTheDocument()
  })
})
