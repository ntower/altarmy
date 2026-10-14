import { act, fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { focusManager } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import type { RankResult, StrategyOut } from '../api/client'
import { WHOLE_CHAIN, type RankParams } from '../api/queries'
import { linen, robe as robeItem, thread } from '../test/items'
import { professionRanks, robeResult } from '../test/results'
import { status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import type { Holder } from '../lib/setup'
import { MAX_TIME_VALUE, scaleRun } from '../lib/skill'
import { MASTER_CHEF, WORKING_OVERTIME } from '../lib/talents'
import { SkillWorkspace } from './SkillWorkspace'

const capItem = { ...robeItem, id: 4, name: 'Linen Cap', quality: 2 }
const items = { '1': linen, '2': thread, '3': robeItem, '4': capItem }
const steps = robeResult.steps.map((s) => ({ ...s, who: 'Tailor Guy' }))
// A run of 12 robes from Tailoring 20 to about 45, where a Linen Cap gives a cheaper point; 14 crafts four times
// in five.
const robeRun: RankResult = {
  ...robeResult,
  crafter: 'Tailor Guy',
  crafts: 12,
  crafts_p80: 14,
  cost: 3600,
  revenue: 0,
  profit: -3600,
  skill_ups: 12,
  stop_skill: 45,
  stop_reason: 'rival',
  overtaken_by: 'Linen Cap',
  overtaken_by_item: 4,
  // the odds of reaching 45 after 1, 2, ... crafts: 82% after 14, 95% after 20
  reach_chances: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.3, 0.5, 0.7, 0.8249, 0.86, 0.88, 0.9, 0.92, 0.94, 0.95],
  steps,
}
const capRun: RankResult = {
  ...robeRun,
  recipe_id: 101,
  recipe: 'Linen Cap',
  output_item_id: 9001, // no item info: shown by name
  output_name: 'Linen Cap',
  profit: -4800,
  cost: 4800,
}
const beltRun: RankResult = { ...robeRun, recipe_id: 102, recipe: 'Linen Belt', output_name: 'Linen Belt', profit: -100 }
const bootsRun: RankResult = { ...beltRun, recipe_id: 103, recipe: 'Linen Boots', output_item_id: 9004, output_name: 'Linen Boots' }
/** A strategy's card as the server sends it. */
const strategy = (key: StrategyOut['key'], run: RankResult, chain: RankResult[]): StrategyOut => ({ key, run, chain })
// After the robe's run: the belt's, then the boots'. The cheapest climb starts with the cap, the one without patterns
// with the belt.
const ranked = {
  results: [robeRun],
  total: 1,
  items,
  classes: {},
  learn: {},
  chain: [beltRun, bootsRun],
  strategies: [
    strategy('recommended', robeRun, [beltRun, bootsRun]),
    strategy('cheapest', capRun, [bootsRun]),
    strategy('no_patterns', beltRun, [bootsRun]),
  ],
}

const FILTERS: Omit<RankParams, 'top'> = {
  unlearned: 'train',
  lookAhead: 0,
  sources: ['trainer', 'recipe'],
  includeTrivial: false,
  skillCrafters: ['Tailor Guy'],
  exits: ['vendor', 'keep'],
  arcaneSalvager: false,
  minCost: null,
  maxCost: null,
  minProfit: null,
  maxProfit: null,
  minRoi: null,
  maxRoi: null,
  minConfidence: null,
  professions: ['Tailoring'],
  sort: 'skill',
  runs: true,
}
const CLIMBER = { name: 'Tailor Guy', classFile: 'MAGE', level: 30, rank: 20, maxRank: 75 }
const overtime = (rank: number) => ({ spellId: WORKING_OVERTIME, name: 'Working Overtime', rank, maxRank: 5 })

function urls(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([r]) => new URL(r.url)).filter((u) => u.pathname === pathname)
}
async function bodies(fetch: ReturnType<typeof mockApi>, pathname: string) {
  const requests = fetch.mock.calls.map(([r]) => r).filter((r) => new URL(r.url).pathname === pathname)
  return Promise.all(requests.map((r) => r.clone().json() as Promise<Record<string, unknown>>))
}

function api(over: Record<string, unknown> = {}) {
  return mockApi({
    '/api/status': status({ price_version: 1 }),
    '/api/rank': ranked,
    '/api/evaluate': () => ({ result: { ...scaleRun(robeRun, 14), cost: 4200 }, items }),
    '/api/events': {},
    ...over,
  })
}

const show = (climber: Holder = CLIMBER) =>
  renderWithProviders(<SkillWorkspace filters={FILTERS} climber={climber} profession="Tailoring" />)

/** The ladder's table: the strategy's whole climb. */
const ladder = async () => within(await screen.findByRole('region', { name: 'Your options' })).findByRole('table', { name: 'The climb' })

/** Open the run named `name`, the first of `strategy`'s climb, from the table, picking that strategy among the
 * others first unless it is the one shown; the run's details. */
async function choose(name: string, strategy = 'Recommended') {
  const options = await screen.findByRole('region', { name: 'Your options' })
  // side by side, a click picks it, folding the others away
  const card = within(options).queryByRole('button', { name: `Choose ${strategy}: ${name}` })
  if (card) await userEvent.click(card)
  else if (rowNames(await ladder())[0] !== `Open ${name}`) {
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: `Choose ${strategy}: ${name}` }))
  }
  const table = await ladder()
  await waitFor(() => expect(within(table).getAllByRole('button', { name: /^Open / })[0]).toHaveAttribute('aria-label', `Open ${name}`))
  await userEvent.click(within(table).getAllByRole('button', { name: `Open ${name}` })[0]!)
  return screen.getByRole('region', { name: 'Run details' })
}

/** The strategies' cards side by side that can be picked, as their buttons name them. */
const cardNames = (options: HTMLElement) =>
  within(options)
    .getAllByRole('button', { name: /^Choose / })
    .map((c) => c.getAttribute('aria-label'))

/** The ladder table's rows, as their buttons name them. */
const rowNames = (table: HTMLElement) =>
  within(table)
    .getAllByRole('button', { name: /^Open / })
    .map((r) => r.getAttribute('aria-label'))

describe('SkillWorkspace', () => {
  it('starts with the recommended climb as a table, the strategies side by side on asking', async () => {
    api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const table = await ladder()
    expect(rowNames(table)).toEqual(['Open Green Robe', 'Open Linen Belt', 'Open Linen Boots'])
    // no cards: the table is the climb
    expect(within(options).queryByRole('article')).not.toBeInTheDocument()
    expect(within(options).queryByRole('button', { name: /^Choose / })).not.toBeInTheDocument()
    expect(within(options).queryByRole('button', { name: /^(Show all|Show more|Back to cards)$/ })).not.toBeInTheDocument()
    // the strategies' summaries side by side, in the server's order, each a card picking it; no runs
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    expect(within(options).queryByRole('table', { name: 'The climb' })).not.toBeInTheDocument()
    expect(cardNames(options)).toEqual([
      'Choose Recommended: Green Robe',
      'Choose Cheapest: Linen Cap',
      'Choose Trainer only: Linen Belt',
    ])
    expect(within(options).queryByRole('article')).not.toBeInTheDocument()
    expect(within(options).queryByText(/per skill point|Craft until/)).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
  })

  it('names each strategy over its card, what it plans for a click away, and what its climb comes to by each rank', async () => {
    const milestones = (at75: number, at150: number) => [
      { skill: 75, cost: at75, unknown: 0, crafts: 40, reachable: true },
      { skill: 150, cost: at150, unknown: 0, crafts: 190, reachable: true },
    ]
    const robe = {
      ...robeRun,
      milestones: [
        ...milestones(1000, 4000),
        { skill: 225, cost: 5000, unknown: 1, crafts: 420, reachable: true },
        { skill: 300, cost: 0, unknown: 0, crafts: 0, reachable: false },
      ],
    }
    api({
      '/api/rank': {
        ...ranked,
        results: [robe],
        strategies: [
          strategy('recommended', robe, ranked.chain),
          strategy('cheapest', { ...capRun, milestones: milestones(2000, 2000).slice(0, 1) }, [bootsRun]),
          strategy('no_patterns', { ...beltRun, milestones: milestones(3000, 9000) }, [robeRun]),
        ],
      },
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    // the recommended run is the one to craft now, named, with what its climb comes to and the crafts it takes
    const costs = within(options).getByRole('group', { name: 'Cost to reach each rank with Green Robe first' })
    expect(within(costs).getByText('Recommended')).toBeInTheDocument()
    expect(within(costs).getAllByRole('columnheader').map((h) => h.textContent)).toEqual(['Skill', 'Cost', 'Crafts'])
    expect(costs).toHaveTextContent('75-10 0~40')
    expect(costs).toHaveTextContent('225-50 0~420+ 1 pattern of unknown price300 Unreachable')
    // the rank the climb never reaches: its skill, then the word across the cost and crafts
    const never = within(costs).getByRole('rowheader', { name: '300' }).closest('tr')!
    expect(within(never).getAllByRole('cell').map((c) => [c.textContent, c.getAttribute('colspan')])).toEqual([
      [' Unreachable', '2'],
    ])
    // what it plans for, on asking
    const about = within(costs).getByRole('button', { name: 'Recommended' })
    expect(about).toHaveAttribute('aria-expanded', 'false')
    expect(within(costs).queryByText(/Values your time/)).not.toBeInTheDocument()
    await userEvent.click(about)
    expect(about).toHaveAttribute('aria-expanded', 'true')
    expect(within(costs).getAllByRole('listitem').map((i) => i.textContent)).toEqual([
      'Uses recipes from the trainer and patterns you can buy',
      'Values your time at 5s 0c per minute',
      'Avoid crafts with <10% chance of a skill point',
    ])
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    expect(cardNames(options)).toEqual([
      'Choose Recommended: Green Robe',
      'Choose Cheapest: Linen Cap',
      'Choose Trainer only: Linen Belt',
    ])
    // each card is its strategy's summary
    const heads = ['Linen Cap', 'Linen Belt'].map((name) =>
      within(options).getByRole('group', { name: `Cost to reach each rank with ${name} first` }),
    )
    const cheapest = within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' })
    expect(cheapest).toContainElement(heads[0]!)
    // its name a plain title, nothing to open: what it plans for always shown, under its table
    expect(heads[0]).toHaveTextContent(/^Cheapest/)
    expect(heads[1]).toHaveTextContent(/^Trainer only/)
    expect(within(cheapest).queryByRole('button')).not.toBeInTheDocument()
    expect(heads[1]).toHaveTextContent('150-90 0~190')
    const plans = within(heads[0]!).getByText('No cutoff for recipes with a low chance of a skill point')
    const table = within(heads[0]!).getByRole('table')
    expect(table.compareDocumentPosition(plans) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
  })

  it('picks a strategy by its card, with a click or the keyboard', async () => {
    const capChain = { ...ranked, results: [capRun], chain: [bootsRun], strategies: [] }
    api({ '/api/rank': (url: URL) => (url.searchParams.get('strategy') === 'cheapest' ? capChain : ranked) })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(await within(options).findByRole('button', { name: 'Compare strategies' }))
    within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' }).focus()
    await userEvent.keyboard('{Enter}')
    await waitFor(async () => expect(rowNames(await ladder())).toEqual(['Open Linen Cap', 'Open Linen Boots']))
    expect(within(options).getByRole('group', { name: 'Cost to reach each rank with Linen Cap first' })).toHaveTextContent(
      'Cheapest',
    )
  })

  it('shows a climb coming back to a recipe in its table', async () => {
    const chain = [beltRun, bootsRun, beltRun]
    api({ '/api/rank': { ...ranked, chain } })
    show()
    expect(rowNames(await ladder())).toEqual(['Open Green Robe', 'Open Linen Belt', 'Open Linen Boots', 'Open Linen Belt'])
  })

  it('opens one row of the table at a time, under itself', async () => {
    api()
    show()
    const table = await ladder()
    await userEvent.click(within(table).getByRole('button', { name: 'Open Linen Boots' }))
    let run = within(table).getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Boots/)
    // the rows around it stay
    expect(rowNames(table)).toEqual(['Open Green Robe', 'Open Linen Belt', 'Open Linen Boots'])
    // opening another closes it
    await userEvent.click(within(table).getByRole('button', { name: 'Open Green Robe' }))
    expect(screen.getAllByRole('region', { name: 'Run details' })).toHaveLength(1)
    run = within(table).getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Green Robe/)
    expect(within(table).getByRole('button', { name: 'Open Green Robe' })).toHaveAttribute('aria-expanded', 'true')
    // and a click on its row closes it again
    await userEvent.click(within(table).getByRole('button', { name: 'Open Green Robe' }))
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
  })

  /** A climb of seven runs after the robe's, served as long as asked for. */
  function longClimb() {
    const run = (i: number): RankResult => ({
      ...beltRun,
      recipe_id: 200 + i,
      recipe: `Run ${i}`,
      output_item_id: 9000 + i, // no item info: shown by name
      output_name: `Run ${i}`,
      stop_skill: 45 + 5 * i,
    })
    const runs = Array.from({ length: 7 }, (_, i) => run(i + 1))
    return api({
      '/api/rank': (url: URL) => ({ ...ranked, chain: runs.slice(0, Number(url.searchParams.get('chain_length') ?? 2)) }),
    })
  }
  it('shows the whole climb, each run from where the one before stops', async () => {
    const fetch = longClimb()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const table = await ladder()
    expect(within(table).getAllByRole('columnheader').map((h) => h.textContent)).toEqual([
      'Skill',
      'Recipe',
      'Crafts',
      'Cost',
    ])
    expect(rowNames(table)).toEqual(['Open Green Robe', ...Array.from({ length: 7 }, (_, i) => `Open Run ${i + 1}`)])
    // asked for at once, under the recommended strategy
    const asked = urls(fetch, '/api/rank')[0]
    expect([asked?.searchParams.get('strategy'), asked?.searchParams.get('chain_length')]).toEqual([null, String(WHOLE_CHAIN)])
    const rows = within(table).getAllByRole('button', { name: /^Open / })
    expect(rows[0]).toHaveTextContent('20–45')
    expect(rows[0]).toHaveTextContent('~12')
    expect(rows[0]).toHaveTextContent('-36 0')
    expect(rows[1]).toHaveTextContent('45–50')
    expect(rows[2]).toHaveTextContent('50–55')
    // the strategy's summary and the way to the others above it
    expect(within(options).getByRole('group', { name: 'Cost to reach each rank with Green Robe first' })).toBeInTheDocument()
    expect(within(options).getByRole('button', { name: 'Compare strategies' })).toBeInTheDocument()
  })

  it('opens a row of the climb in place, planned as the chain has it', async () => {
    const fetch = longClimb()
    show()
    const table = await ladder()
    await userEvent.click(within(table).getByRole('button', { name: 'Open Run 3' }))
    const run = within(table).getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Run 3/)
    // the third run after the robe's: found in its climb
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ recipe_id: 203, chain_from: 100, chain_at: 3 }),
    )
    await userEvent.click(within(run).getByRole('button', { name: 'Close' }))
    expect(within(table).queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
    // the run crafted now is its own, with nothing to find in a chain (its plan fetched ahead)
    await userEvent.click(within(table).getByRole('button', { name: 'Open Green Robe' }))
    expect(within(within(table).getByRole('region', { name: 'Run details' })).getByRole('heading')).toHaveTextContent(/Green Robe/)
    const robes = (await bodies(fetch, '/api/evaluate')).filter((b) => b.recipe_id === 100)
    expect(robes.length).toBeGreaterThan(0)
    for (const body of robes) expect(body).not.toHaveProperty('chain_at')
  })

  it('returns to the table after a pick or a reset', async () => {
    const capChain = { ...ranked, results: [capRun], chain: [bootsRun], strategies: [] }
    api({ '/api/rank': (url: URL) => (url.searchParams.get('strategy') === 'cheapest' ? capChain : ranked) })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await ladder()
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    expect(within(options).queryByRole('table', { name: 'The climb' })).not.toBeInTheDocument()
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' }))
    await waitFor(async () => expect(rowNames(await ladder())).toEqual(['Open Linen Cap', 'Open Linen Boots']))
    expect(within(options).queryByRole('button', { name: /^Choose / })).not.toBeInTheDocument()
    await userEvent.click(within(options).getByRole('button', { name: 'Reset to recommended' }))
    await waitFor(async () =>
      expect(rowNames(await ladder())).toEqual(['Open Green Robe', 'Open Linen Belt', 'Open Linen Boots']),
    )
  })

  it("makes a picked strategy's climb the table, its first run as ranked under it", async () => {
    // ranked under the strategy, the cap's run goes on to 60, where the boots take over
    const longer: RankResult = { ...capRun, crafts: 30, stop_skill: 60, overtaken_by: 'Linen Boots', overtaken_by_item: 9004 }
    const capChain = { ...ranked, results: [longer], chain: [bootsRun], strategies: [] }
    const fetch = api({
      '/api/rank': (url: URL) => (url.searchParams.get('strategy') === 'cheapest' ? capChain : ranked),
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' }))
    const table = await ladder()
    await waitFor(() => expect(rowNames(table)).toEqual(['Open Linen Cap', 'Open Linen Boots']))
    const asked = urls(fetch, '/api/rank').find((u) => u.searchParams.get('strategy'))
    expect(asked?.searchParams.get('strategy')).toBe('cheapest')
    expect(asked?.searchParams.get('top')).toBe('1')
    expect(asked?.searchParams.get('chain_length')).toBe(String(WHOLE_CHAIN))
    // named over its table
    expect(
      within(options).getByRole('group', { name: 'Cost to reach each rank with Linen Cap first' }),
    ).toHaveTextContent('Cheapest')
    const cap = within(table).getByRole('button', { name: 'Open Linen Cap' })
    await waitFor(() => expect(cap).toHaveTextContent('20–60'))
    expect(cap).toHaveTextContent('~30')
    // opened, the run as ranked under the strategy
    await userEvent.click(cap)
    const run = screen.getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Cap/)
    expect(run).toHaveTextContent(/Craft until 60 skill/)
  })

  it("shows a picked strategy's own start while its climb is on its way, never the one shown before", async () => {
    let release: (value: unknown) => void = () => {}
    const capChain = { ...ranked, results: [capRun], chain: [bootsRun, beltRun], strategies: [] }
    api({
      '/api/rank': (url: URL) =>
        url.searchParams.get('strategy') === 'cheapest'
          ? new Promise((resolve) => (release = () => resolve(capChain)))
          : ranked,
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' }))
    // the cap's climb as it came with the list, the rest on its way
    const table = await ladder()
    expect(rowNames(table)).toEqual(['Open Linen Cap', 'Open Linen Boots'])
    expect(within(options).getByLabelText('Working out what comes after')).toBeInTheDocument()
    release(undefined)
    await waitFor(() => expect(rowNames(table)).toEqual(['Open Linen Cap', 'Open Linen Boots', 'Open Linen Belt']))
    expect(within(options).queryByLabelText('Working out what comes after')).not.toBeInTheDocument()
  })

  /** `/api/rank` with the custom strategy planning a climb of the boots and then the belt, the others as ranked. */
  function customApi() {
    const bootsFirst = { ...bootsRun, milestones: [{ skill: 75, cost: 900, unknown: 0, crafts: 30, reachable: true }] }
    const custom = { ...ranked, results: [bootsFirst], chain: [beltRun], strategies: [] }
    const cheap = { ...ranked, results: [capRun], chain: [bootsRun], strategies: [] }
    return api({
      '/api/rank': (url: URL) => {
        const strategy = url.searchParams.get('strategy')
        return strategy === 'custom' ? custom : strategy === 'cheapest' ? cheap : ranked
      },
    })
  }

  it('customizes a strategy beside it, then shows its climb, first among the strategies compared', async () => {
    const fetch = customApi()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    // under each card
    expect(within(options).getAllByRole('button', { name: /^Customize / }).map((b) => b.textContent)).toEqual([
      'Customize',
      'Customize',
      'Customize',
    ])
    await userEvent.click(within(options).getByRole('button', { name: 'Customize Cheapest' }))
    // the strategy it starts from beside the one being made, the settings under them
    expect(within(options).queryByRole('button', { name: /^Choose / })).not.toBeInTheDocument()
    expect(within(options).getByRole('region', { name: 'Cheapest' })).toBeInTheDocument()
    const form = within(options).getByRole('form', { name: 'Custom strategy' })
    // as the cheapest plans: gold alone, at any chance
    expect(within(form).getByRole('checkbox', { name: 'Trainers' })).toBeChecked()
    expect(within(form).getByRole('checkbox', { name: 'Patterns you can buy' })).toBeChecked()
    expect(within(form).getByRole('checkbox', { name: 'Bind on pickup patterns' })).not.toBeChecked()
    const worth = within(form).getByRole('textbox', { name: 'How much is your time worth to you?' })
    const chance = within(form).getByRole('textbox', { name: 'Lowest chance of a skill point' })
    expect([worth, chance].map((i) => (i as HTMLInputElement).value)).toEqual(['0 silver per minute', '0%'])
    await userEvent.clear(worth)
    await userEvent.type(worth, '2')
    await userEvent.clear(chance)
    await userEvent.type(chance, '25')
    // planned as it settles, its summary beside the one it started from
    const yours = () => within(options).getByRole('region', { name: 'Your strategy' })
    await waitFor(() => expect(within(yours()).getByRole('group')).toHaveTextContent('75-9 0~30'))
    expect(yours()).toHaveTextContent('Values your time at 2s 0c per minute')
    expect(yours()).toHaveTextContent('Avoid crafts with <25% chance of a skill point')
    const asked = urls(fetch, '/api/rank')
      .filter((u) => u.searchParams.get('strategy') === 'custom')
      .at(-1)
    expect([
      asked?.searchParams.get('time_value'),
      asked?.searchParams.get('min_chance'),
      asked?.searchParams.getAll('sources'),
    ]).toEqual(['200', '0.25', ['trainer', 'recipe']])
    await userEvent.click(within(form).getByRole('button', { name: 'Use this strategy' }))
    // its whole climb's table, named Custom
    await waitFor(async () => expect(rowNames(await ladder())).toEqual(['Open Linen Boots', 'Open Linen Belt']))
    const whole = urls(fetch, '/api/rank')
      .filter((u) => u.searchParams.get('strategy') === 'custom')
      .at(-1)
    expect(whole?.searchParams.get('chain_length')).toBe(String(WHOLE_CHAIN))
    expect(
      within(options).getByRole('group', { name: 'Cost to reach each rank with Linen Boots first' }),
    ).toHaveTextContent(/^Custom/)
    // a run of it is planned under it
    await userEvent.click(within(await ladder()).getByRole('button', { name: 'Open Linen Boots' }))
    const run = screen.getByRole('region', { name: 'Run details' })
    await userEvent.clear(within(run).getByRole('textbox', { name: 'Crafts to buy for' }))
    await userEvent.type(within(run).getByRole('textbox', { name: 'Crafts to buy for' }), '40')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({
        recipe_id: 103,
        strategy: 'custom',
        time_value: 200,
        min_chance: 0.25,
        copies: 40,
      }),
    )
    // compared, four cards: the custom one first
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    expect(cardNames(options)).toEqual([
      'Choose Custom: Linen Boots',
      'Choose Recommended: Green Robe',
      'Choose Cheapest: Linen Cap',
      'Choose Trainer only: Linen Belt',
    ])
    // the custom one edited, the built-in ones customized
    expect(within(options).getAllByRole('button', { name: /^(Edit|Customize) / }).map((b) => b.getAttribute('aria-label'))).toEqual([
      'Edit Custom',
      'Customize Recommended',
      'Customize Cheapest',
      'Customize Trainer only',
    ])
  })

  it('asks once per time value, however often the user steps back to one', async () => {
    const fetch = customApi()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Customize Recommended' }))
    const worth = within(options).getByRole('textbox', { name: 'How much is your time worth to you?' })
    const timeValues = () =>
      urls(fetch, '/api/rank')
        .filter((u) => u.searchParams.get('strategy') === 'custom')
        .map((u) => u.searchParams.get('time_value'))
    for (const silver of ['6', '5', '6', '5', '6']) {
      await userEvent.clear(worth)
      await userEvent.type(worth, silver)
      await waitFor(() => expect(timeValues().at(-1) ?? null).not.toBeNull())
      await new Promise((r) => setTimeout(r, 500)) // past the debounce
    }
    expect(timeValues().filter((v) => v === '600')).toHaveLength(1)
    expect(timeValues().filter((v) => v === '500')).toHaveLength(1)
  }, 15_000)

  it('never asks for more time value than the server takes, however much is typed', async () => {
    const fetch = customApi()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Customize Recommended' }))
    const worth = within(options).getByRole('textbox', { name: 'How much is your time worth to you?' })
    await userEvent.clear(worth)
    // the keys past the most it takes do nothing
    await userEvent.type(worth, '9999999')
    expect(worth).toHaveValue('9999 silver per minute')
    const custom = () => urls(fetch, '/api/rank').filter((u) => u.searchParams.get('strategy') === 'custom')
    await waitFor(() => expect(custom().at(-1)?.searchParams.get('time_value')).toBe('999900'), { timeout: 3000 })
    // a value set past it at once (a paste) is refused: the field keeps what it had
    fireEvent.change(worth, { target: { value: '50000' } })
    expect(worth).toHaveValue('9999 silver per minute')
    for (const u of custom()) expect(Number(u.searchParams.get('time_value'))).toBeLessThanOrEqual(MAX_TIME_VALUE)
  })

  it('plans the strategies compared, and the one customized from, again as the talent sliders move', async () => {
    // with Working Overtime, every strategy's climb takes fewer crafts
    const at = (url: URL) => Number(url.searchParams.get('working_overtime') ?? 0)
    const fewer = (r: RankResult, by: number): RankResult => ({
      ...r,
      milestones: [{ skill: 75, cost: 1000, unknown: 0, crafts: 40 - by, reachable: true }],
    })
    const fetch = api({
      '/api/rank': (url: URL) => {
        const by = at(url) * 5
        return {
          ...ranked,
          results: [fewer(robeRun, by)],
          strategies: [
            strategy('recommended', fewer(robeRun, by), [beltRun]),
            strategy('cheapest', fewer(capRun, by), [bootsRun]),
            strategy('no_patterns', fewer(beltRun, by), [bootsRun]),
          ],
        }
      },
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    const cheapest = () => within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' })
    expect(cheapest()).toHaveTextContent('~40')
    const [wo] = within(screen.getByRole('group', { name: 'Legacy talents' })).getAllByRole('slider')
    wo!.focus()
    await userEvent.keyboard('{ArrowRight}{ArrowRight}')
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('working_overtime')).toBe('2'))
    await waitFor(() => expect(cheapest()).toHaveTextContent('~30'))
    // and beside a strategy being customized
    await userEvent.click(within(options).getByRole('button', { name: 'Customize Cheapest' }))
    wo!.focus()
    await userEvent.keyboard('{ArrowRight}')
    await waitFor(() => expect(within(options).getByRole('region', { name: 'Cheapest' })).toHaveTextContent('~25'))
  })

  it('picks the built-in strategy a customized one comes back to, and cancels back to the cards', async () => {
    customApi()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Customize Recommended' }))
    // cancelled: the strategies side by side again
    await userEvent.click(within(options).getByRole('button', { name: 'Cancel' }))
    expect(cardNames(options)).toHaveLength(3)
    // the cheapest's settings, made from the recommended one's
    await userEvent.click(within(options).getByRole('button', { name: 'Customize Recommended' }))
    const form = within(options).getByRole('form', { name: 'Custom strategy' })
    const worth = within(form).getByRole('textbox', { name: 'How much is your time worth to you?' })
    const chance = within(form).getByRole('textbox', { name: 'Lowest chance of a skill point' })
    expect([worth, chance].map((i) => (i as HTMLInputElement).value)).toEqual(['5 silver per minute', '10%'])
    await userEvent.clear(worth)
    await userEvent.type(worth, '0')
    await userEvent.clear(chance)
    await userEvent.type(chance, '0')
    // with no source ticked, nothing to use
    await userEvent.click(within(form).getByRole('checkbox', { name: 'Trainers' }))
    await userEvent.click(within(form).getByRole('checkbox', { name: 'Patterns you can buy' }))
    expect(within(form).getByRole('button', { name: 'Use this strategy' })).toBeDisabled()
    await userEvent.click(within(form).getByRole('checkbox', { name: 'Trainers' }))
    await userEvent.click(within(form).getByRole('checkbox', { name: 'Patterns you can buy' }))
    await userEvent.click(within(form).getByRole('button', { name: 'Use this strategy' }))
    await waitFor(async () => expect(rowNames(await ladder())).toEqual(['Open Linen Cap', 'Open Linen Boots']))
    expect(
      within(options).getByRole('group', { name: 'Cost to reach each rank with Linen Cap first' }),
    ).toHaveTextContent(/^Cheapest/)
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    expect(cardNames(options)).toHaveLength(3)
  })

  it('resets another strategy picked back to the recommended one', async () => {
    const capChain = { ...ranked, results: [capRun], chain: [bootsRun], strategies: [] }
    api({ '/api/rank': (url: URL) => (url.searchParams.get('strategy') === 'cheapest' ? capChain : ranked) })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await ladder()
    // the recommended one: nothing to reset
    expect(within(options).queryByRole('button', { name: 'Reset to recommended' })).not.toBeInTheDocument()
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Cheapest: Linen Cap' }))
    await waitFor(async () => expect(rowNames(await ladder())).toEqual(['Open Linen Cap', 'Open Linen Boots']))
    await userEvent.click(within(options).getByRole('button', { name: 'Reset to recommended' }))
    await waitFor(async () =>
      expect(rowNames(await ladder())).toEqual(['Open Green Robe', 'Open Linen Belt', 'Open Linen Boots']),
    )
    expect(within(options).queryByRole('button', { name: 'Reset to recommended' })).not.toBeInTheDocument()
  })

  it("plans with the climber's Working Overtime and Bartering, or the ranks the sliders set", async () => {
    const fetch = api()
    show({ ...CLIMBER, talents: [overtime(2)] })
    const sliders = await screen.findByRole('group', { name: 'Legacy talents' })
    const [wo, barter] = within(sliders).getAllByRole('slider')
    // the climber's own ranks: 2 of Working Overtime, no Bartering
    expect(wo).toHaveAttribute('aria-valuenow', '2')
    expect(barter).toHaveAttribute('aria-valuenow', '0')
    expect(sliders).toHaveTextContent('Working Overtime2/5')
    expect(sliders).toHaveTextContent('Bartering0/2')
    expect(sliders).not.toHaveTextContent('Master Chef') // not Cooking
    // what a point of each does, whatever the rank
    await userEvent.hover(within(sliders).getByText('Working Overtime'))
    expect(
      await screen.findByText('Increases your chance to gain a skill increase by 4% per talent point'),
    ).toBeInTheDocument()
    await userEvent.hover(within(sliders).getByText('Bartering'))
    expect(
      await screen.findByText('Reduces the gold price of items from all vendors by 5% per talent point'),
    ).toBeInTheDocument()
    const first = urls(fetch, '/api/rank')[0]
    expect([first?.searchParams.get('working_overtime'), first?.searchParams.get('bartering')]).toEqual(['2', '0'])
    // moved, the plans follow
    wo!.focus()
    await userEvent.keyboard('{ArrowRight}{ArrowRight}{ArrowRight}')
    expect(sliders).toHaveTextContent('Working Overtime5/5')
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('working_overtime')).toBe('5'))
    await choose('Green Robe')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ working_overtime: 5, bartering: 0 }),
    )
  })

  it('offers Master Chef too when skilling up Cooking', async () => {
    const fetch = api()
    const chef = { spellId: MASTER_CHEF, name: 'Master Chef', rank: 3, maxRank: 5 }
    renderWithProviders(
      <SkillWorkspace
        filters={{ ...FILTERS, professions: ['Cooking'] }}
        climber={{ ...CLIMBER, talents: [chef] }}
        profession="Cooking"
      />,
    )
    const sliders = await screen.findByRole('group', { name: 'Legacy talents' })
    expect(within(sliders).getAllByRole('slider').map((t) => t.getAttribute('aria-valuenow'))).toEqual(['0', '0', '3'])
    expect(sliders).toHaveTextContent('Master Chef3/5')
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('master_chef')).toBe('3')
  })

  it('starts the sliders at nothing for a climber without talents', async () => {
    const fetch = api()
    show()
    const sliders = await screen.findByRole('group', { name: 'Legacy talents' })
    expect(within(sliders).getAllByRole('slider').map((t) => t.getAttribute('aria-valuenow'))).toEqual(['0', '0'])
    // not Cooking: no Master Chef sent
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('master_chef')).toBeNull()
  })

  it("says where a run's last points get slow, and how many crafts it usually takes", async () => {
    // eight orange points, then one at 1 in 4
    const slow = { ...robeRun, point_crafts: [1, 1, 1, 1, 1, 1, 1, 1, 4] }
    api({ '/api/rank': { ...ranked, results: [slow], strategies: [strategy('recommended', slow, ranked.chain)] } })
    show()
    // opened, the run says its usual spread (10% done after 11 crafts, 90% after 17) and where it gets slow
    const run = await choose('Green Robe')
    expect(run).toHaveTextContent('Usually 11–17 crafts. The last point takes ~4 of these ~12 crafts')
    // beside it, the recipe's skill-up chance by skill, the run's stretch shaded
    expect(within(run).getByRole('img', { name: /^Skill-up chance for Green Robe by skill/ })).toBeInTheDocument()
  })

  it('says what the best run is worth and how far it goes', async () => {
    const fetch = api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const run = await choose('Green Robe')
    expect(run).toHaveTextContent('Craft until 45 skill (~12 times)')
    // one amount: what the run comes to per skill point after selling, a loss in red with its minus sign
    const headline = within(run).getByText(/per skill point/)
    const silver = within(headline).getByTitle('silver')
    expect(silver.parentElement).toHaveTextContent(/^-3 0$/) // 3600 copper spent for 12 points: 3s 0c each
    expect(silver.closest<HTMLElement>('[style]')?.style.color).toContain('red')
    expect(within(run).queryByText(/You must/)).not.toBeInTheDocument() // known: nothing to say
    await userEvent.click(within(run).getByRole('button', { name: 'Close' }))
    expect(within(options).queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
    // each strategy's plan for the 14 crafts it opens with, under it, fetched ahead
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).map((b) => [b.recipe_id, b.copies, b.strategy])).toEqual([
        [100, 14, 'recommended'],
        [101, 14, 'cheapest'],
        [102, 14, 'no_patterns'],
      ]),
    )
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('runs')).toBe('true')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/events')).map((b) => b.name)).toEqual(['next_up_shown', 'row_opened']),
    )
  })

  it('opens a chosen option out into its run: what to make until when, why, what comes next, the checklist', async () => {
    const fetch = api()
    show()
    const run = await choose('Green Robe')
    expect(run).toHaveTextContent(/Craft until 45 skill \(~12 times\)/)
    expect(run).not.toHaveTextContent(/cheaper option/)
    // the crafts to buy for: enough to reach the target four times in five
    expect(within(run).getByRole('textbox', { name: 'Crafts to buy for' })).toHaveValue('14')
    expect(within(run).getByText('82% chance to reach your target of 45 skill')).toBeInTheDocument()
    expect(within(run).queryByText(/Why this one|Then, at/)).not.toBeInTheDocument()
    expect(screen.queryByText(/after this run/)).not.toBeInTheDocument() // the header stays as it was
    // the checklist buys for the 14 crafts an unlucky run takes, grouped by who does what
    await waitFor(async () => expect(await bodies(fetch, '/api/evaluate')).toHaveLength(3)) // fetched ahead, once each
    const [plan] = await bodies(fetch, '/api/evaluate')
    expect(plan).toMatchObject({ recipe_id: 100, copies: 14, runs: true, skill_crafters: ['Tailor Guy'] })
    // the plan opens as its steps, the flow chart a click away
    const views = within(run).getByRole('radiogroup', { name: 'Show the plan as' })
    const [first, second] = within(views).getAllByRole('radio')
    expect([first, second]).toEqual([within(views).getByLabelText('Steps'), within(views).getByLabelText('Flowchart')])
    expect(within(views).getByLabelText('Steps')).toBeChecked()
    expect(within(run).getByRole('group', { name: "Tailor Guy's steps" })).toBeInTheDocument()
    expect(within(run).getByText(/Sell 2x/)).toBeInTheDocument() // for the 14 crafts
    // more crafts: better odds, and the checklist buys for them; past the odds sent, the last of them
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    expect(within(run).getByText('95% chance to reach your target of 45 skill')).toBeInTheDocument()
    await waitFor(async () => expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ copies: 20 }))
    await userEvent.type(input, '0')
    expect(within(run).getByText('95% chance to reach your target of 45 skill')).toBeInTheDocument()
    await waitFor(async () => expect((await bodies(fetch, '/api/events')).map((b) => b.name)).toContain('row_opened'))
    // and back to the options
    await userEvent.click(within(run).getByRole('button', { name: 'Close' }))
    expect(await screen.findByRole('region', { name: 'Your options' })).toBeInTheDocument()
  })

  it("shows the run's market under the plan, on the costliest reagent, and on any item named in the steps", async () => {
    api()
    show()
    const run = await choose('Green Robe')
    const header = within(run).getByRole('button', { name: /^Market/ })
    expect(header).toHaveAttribute('aria-expanded', 'false')
    expect(header).toHaveTextContent(/Buying 2 reagents for/)
    await userEvent.click(header)
    const section = within(run).getByRole('region', { name: /^Market/ })
    expect(within(section).getByRole('button', { name: /^Linen Cloth/, pressed: true })).toBeInTheDocument()
    await userEvent.click(header) // closed again: a name in the steps opens it on that item
    const stepsGroup = within(run).getByRole('group', { name: "Tailor Guy's steps" })
    await userEvent.click(within(stepsGroup).getByRole('button', { name: 'Coarse Thread' }))
    expect(header).toHaveAttribute('aria-expanded', 'true')
    const opened = within(run).getByRole('region', { name: /^Market/ })
    expect(within(opened).getByRole('button', { name: /^Coarse Thread/, pressed: true })).toBeInTheDocument()
  })

  it('buys for the chance to reach the target the Options ask for', async () => {
    const fetch = api()
    renderWithProviders(
      <SkillWorkspace filters={FILTERS} climber={CLIMBER} profession="Tailoring" reachTarget={90} />,
    )
    const run = await choose('Green Robe')
    expect(within(run).getByRole('textbox', { name: 'Crafts to buy for' })).toHaveValue('17')
    expect(within(run).getByText('90% chance to reach your target of 45 skill')).toBeInTheDocument()
    await waitFor(async () => expect((await bodies(fetch, '/api/evaluate'))[0]).toMatchObject({ copies: 17 }))
  })

  it('buys for the target again once a talent slider moves, forgetting a typed count', async () => {
    const fetch = api()
    show()
    const run = await choose('Green Robe')
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    expect(input).toHaveValue('20')
    const [wo] = within(screen.getByRole('group', { name: 'Legacy talents' })).getAllByRole('slider')
    wo!.focus()
    await userEvent.keyboard('{ArrowRight}')
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('working_overtime')).toBe('1'))
    // the run's chances changed: the count is the one reaching the target again
    await waitFor(() => expect(within(run).getByRole('textbox', { name: 'Crafts to buy for' })).toHaveValue('14'))
  })

  it("plans a picked strategy's run under it", async () => {
    const fetch = api()
    show()
    await choose('Linen Cap', 'Cheapest')
    expect(urls(fetch, '/api/rank').some((u) => u.searchParams.get('strategy') === 'cheapest')).toBe(true)
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).filter((b) => b.recipe_id === 101)).not.toHaveLength(0),
    )
    for (const body of (await bodies(fetch, '/api/evaluate')).filter((b) => b.recipe_id === 101)) {
      expect(body).toMatchObject({ strategy: 'cheapest' })
    }
  })

  it('says how many of the skill points counted on come from Working Overtime, after the odds', async () => {
    // the ranked run's 12 crafts expect 0.5 points from the talent; the plan for the 14 bought for, 0.6
    api({
      '/api/rank': {
        ...ranked,
        results: [{ ...robeRun, skill_ups_bonus: 0.48 }],
        strategies: [strategy('recommended', { ...robeRun, skill_ups_bonus: 0.48 }, ranked.chain)],
      },
      '/api/evaluate': () => ({ result: { ...scaleRun(robeRun, 14), skill_ups_bonus: 0.56 }, items }),
    })
    show({ ...CLIMBER, talents: [overtime(1)] })
    const run = await choose('Green Robe')
    expect(
      await within(run).findByText(
        '82% chance to reach your target of 45 skill (includes ~0.6 skill points from Working Overtime)',
      ),
    ).toBeInTheDocument()
    expect(within(run).queryByText(/· .* points from Working Overtime/)).not.toBeInTheDocument()
  })

  it('says what to do to learn a recipe the climber lacks', async () => {
    const pattern: RankResult = { ...capRun, crafters: ['Someone Else'], learn_cost: 1200 }
    const unknown: RankResult = { ...beltRun, crafters: [], learn_cost: null }
    const vendor = {
      kind: 'vendor',
      name: 'Rann Flamespinner',
      zone: 'Orgrimmar',
      area: 1637,
      map_x: 63.2,
      map_y: 51.5,
      side: '',
      limited: false,
      chance: 0,
      count: 0,
      levels: '',
    }
    const learn = {
      '101': {
        source: 'recipe',
        skill: 50,
        profession: 'Tailoring',
        items: [{ item_id: 9001, name: 'Pattern: Linen Cap', price: 1200, limited: false, places: [vendor] }],
        train_cost: 0,
      },
    }
    const strategies = [
      strategy('recommended', robeRun, ranked.chain),
      strategy('cheapest', pattern, []),
      strategy('no_patterns', unknown, []),
    ]
    api({ '/api/rank': { ...ranked, strategies, learn } })
    show()
    const run = await choose('Linen Cap', 'Cheapest')
    // the run names what the pattern costs
    expect(within(run).getByText(/You must buy the pattern/)).toHaveTextContent(/^You must buy the pattern \(12 0\)/)
    // and the checklist starts with buying it from its vendor, the zone map on hover
    const steps = within(run).getByRole('group', { name: "Tailor Guy's steps" })
    const first = within(steps).getAllByRole('listitem')[0]!
    expect(first).toHaveTextContent(
      /^Buy Pattern: Linen Cap from Rann Flamespinner, Orgrimmar at 63\.2, 51\.5 \(12 0\)$/,
    )
    await userEvent.hover(within(first).getByText(/Rann Flamespinner/))
    expect(await screen.findByRole('img', { name: /Rann Flamespinner/ })).toBeInTheDocument()
  })

  it('says what a trainer asks to teach a recipe the climber lacks', async () => {
    const trained: RankResult = { ...capRun, crafters: [], learn_cost: 600 }
    const learn = { '101': { source: 'trainer', skill: 0, profession: 'Tailoring', items: [], train_cost: 600 } }
    api({ '/api/rank': { ...ranked, strategies: [ranked.strategies[0]!, strategy('cheapest', trained, [])], learn } })
    show()
    const run = await choose('Linen Cap', 'Cheapest')
    expect(within(run).getByText(/You must learn it from a trainer/)).toHaveTextContent(
      /^You must learn it from a trainer \(6 0\)/,
    )
    const steps = within(run).getByRole('group', { name: "Tailor Guy's steps" })
    expect(within(steps).getAllByRole('listitem')[0]!).toHaveTextContent(
      /^Learn Linen Cap from a Tailoring trainer \(6 0\)$/,
    )
    // an expense, in red like the others
    const fee = within(steps).getAllByRole('listitem')[0]!.querySelector('[data-cost]')
    expect(fee).toHaveTextContent('6 0')
  })

  it('opens a strategy other than the recommended one', async () => {
    api()
    show()
    const run = await choose('Linen Cap', 'Cheapest')
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Cap/)
  })

  it('scrolls the opened option fully into view as it grows', async () => {
    // jsdom has no layout: every box 100 px down and 1000 tall, in a 600 px window
    const scrollTo = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
    const top = vi.spyOn(HTMLElement.prototype, 'offsetTop', 'get').mockReturnValue(100)
    const height = vi.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockReturnValue(1000)
    vi.stubGlobal('innerHeight', 600)
    try {
      api()
      show()
      await choose('Green Robe')
      // taller than the window: its top, less the margin
      await waitFor(() => expect(scrollTo).toHaveBeenLastCalledWith(0, 84))
    } finally {
      scrollTo.mockRestore()
      top.mockRestore()
      height.mockRestore()
      vi.unstubAllGlobals()
    }
  })

  it('asks only for the first run of each climb, with no full list', async () => {
    const fetch = api({ '/api/rank': { ...ranked, results: [robeRun, capRun, beltRun], total: 9 } })
    show()
    await userEvent.click(await screen.findByRole('button', { name: 'Compare strategies' }))
    expect(screen.queryByRole('button', { name: /See all/ })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank').every((u) => u.searchParams.get('top') === '1')).toBe(true)
  })

  it('shows no spinner while the plan fetched ahead is on its way, only for a count the user types', async () => {
    api({ '/api/evaluate': () => new Promise(() => {}) }) // never answers
    show()
    const run = await choose('Green Robe')
    expect(within(run).getByText(/Sell 2x/)).toBeInTheDocument() // the ranked run, in proportion
    await new Promise((r) => setTimeout(r, 500)) // past the count's debounce
    expect(within(run).queryByLabelText('Planning')).not.toBeInTheDocument()
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    expect(await within(run).findByLabelText('Planning')).toBeInTheDocument()
  })

  it('copies the checklist as plain text', async () => {
    const writeText = vi.fn(async () => {})
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    api()
    show()
    const run = await choose('Green Robe')
    await userEvent.click(within(run).getByRole('button', { name: 'Copy steps' }))
    expect(writeText).toHaveBeenCalledTimes(1)
    const [text] = writeText.mock.calls[0] as unknown as [string]
    expect(text.split('\n')[0]).toBe(
      'Tailoring: Green Robe. Craft until 45 skill (~12 times)',
    )
    expect(text).toContain('1. Tailor Guy: Buy 12x Linen Cloth on the AH') // for the 14 crafts to buy for
    expect(await screen.findByRole('button', { name: 'Copied' })).toBeInTheDocument()
  })

  it('spells out where to go in the detailed view, copied as detailed, and only beside the steps', async () => {
    const writeText = vi.fn(async () => {})
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    const auctioneer = { id: 'ah', kind: 'ah', name: 'Auctioneer Stockton', map_x: 71.4, map_y: 46.7, map_area: 1637 }
    const details: RankResult['details'] = [
      { kind: 'start', who: 'Tailor Guy', step: null, location: auctioneer, retrieve: [], seconds: 0 },
      { kind: 'step', who: 'Tailor Guy', step: 0, location: null, retrieve: [], seconds: 0 },
    ]
    api({ '/api/evaluate': () => ({ result: { ...scaleRun(robeRun, 14), details }, items }) })
    show()
    const run = await choose('Green Robe')
    expect(within(run).queryByText(/Start at/)).not.toBeInTheDocument()
    await userEvent.click(within(run).getByRole('checkbox', { name: 'Detailed view' }))
    expect(await within(run).findByText(/Start at/)).toHaveTextContent('Start at Auctioneer Stockton at 71.4, 46.7')
    await userEvent.click(within(run).getByRole('button', { name: 'Copy steps' }))
    const [text] = writeText.mock.calls[0] as unknown as [string]
    expect(text.split('\n')[1]).toBe('1. Tailor Guy: Start at Auctioneer Stockton at 71.4, 46.7')
    await userEvent.click(within(run).getByRole('radio', { name: 'Flowchart' }))
    expect(within(run).queryByRole('checkbox', { name: 'Detailed view' })).not.toBeInTheDocument()
  })

  it('holds still when prices change, until refreshed', async () => {
    let version = 1
    const fetch = api({ '/api/status': () => status({ price_version: version }) })
    show()
    await screen.findByRole('region', { name: 'Your options' })
    const asked = urls(fetch, '/api/rank').length
    version = 2
    act(() => {
      focusManager.setFocused(false)
      focusManager.setFocused(true)
    })
    expect(await screen.findByText('Prices updated since this list was made')).toBeInTheDocument()
    // asked again on focus, perhaps, but still at the prices the list was made with
    expect(urls(fetch, '/api/rank').map((u) => u.searchParams.get('price_version'))).toEqual(
      Array(urls(fetch, '/api/rank').length).fill('1'),
    )
    expect(asked).toBeGreaterThan(0)
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('price_version')).toBe('2'))
    expect(screen.queryByText('Prices updated since this list was made')).not.toBeInTheDocument()
  })

  it("changes a reagent's source in the run, re-costed, until Reset", async () => {
    const onAh = {
      ...scaleRun(robeRun, 14),
      cost: 5000,
      profit: -5000,
      steps: robeRun.steps.map((s) => (s.item_id === 2 && s.action === 'buy' ? { ...s, via: 'ah', value: -150 } : s)),
    }
    const fetch = api({
      '/api/evaluate': async (_: URL, request: Request) => {
        const body = (await request.clone().json()) as { choices: Record<string, string> }
        return { result: Object.keys(body.choices).length ? onAh : { ...scaleRun(robeRun, 14), cost: 4200 }, items }
      },
    })
    show()
    const run = await choose('Green Robe')
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    expect(screen.getAllByRole('menuitem').map((m) => m.textContent)).toEqual([
      expect.stringMatching(/^✓Buy from a vendor/),
      expect.stringMatching(/^Buy on the AH/),
    ])
    await userEvent.click(await screen.findByRole('menuitem', { name: /Buy on the AH/ }))

    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ recipe_id: 100, copies: 14, runs: true, choices: { 'r.1': 'ah' } }),
    )
    expect(await within(run).findByText((_, el) => el?.tagName === 'LI' && /Coarse Thread on the AH/.test(el.textContent ?? ''))).toBeInTheDocument()
    expect(within(run).getByText('Changed plan')).toBeInTheDocument()

    await userEvent.click(within(run).getByRole('button', { name: 'Reset' }))
    expect(await within(run).findByText((_, el) => el?.tagName === 'LI' && /Coarse Thread from a vendor/.test(el.textContent ?? ''))).toBeInTheDocument()
    expect(within(run).queryByText('Changed plan')).not.toBeInTheDocument()
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })

  it('plans a picked strategy again under it, whatever the count', async () => {
    // bought for as many crafts as the run asks, so its plan isn't fetched for a count: a change of source plans the
    // run again, under the strategy
    const capOption: RankResult = {
      ...capRun,
      crafts_p80: 12,
      reach_chances: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0.5, 0.7, 0.8, 0.9, 0.95],
    }
    const fetch = api({ '/api/rank': { ...ranked, strategies: [ranked.strategies[0]!, strategy('cheapest', capOption, [])] } })
    show()
    const run = await choose('Linen Cap', 'Cheapest')
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: /Buy on the AH/ }))
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({
        recipe_id: 101,
        runs: true,
        strategy: 'cheapest',
        choices: { 'r.1': 'ah' },
      }),
    )
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ recipe_id: 101, copies: 20, strategy: 'cheapest' }),
    )
  })

  it('offers the menus in the flow chart too, and forgets the changes on another option', async () => {
    api()
    show()
    let run = await choose('Green Robe')
    await userEvent.click(within(run).getByRole('radio', { name: 'Flowchart' }))
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: /Buy on the AH/ }))
    expect(await within(run).findByRole('button', { name: 'Reset' })).toBeInTheDocument()
    await userEvent.click(within(run).getByRole('button', { name: 'Close' }))
    run = await choose('Linen Cap', 'Cheapest')
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })

  it("changes a source in a run of the chain, planned again as the chain has it", async () => {
    const fetch = api()
    show()
    const table = await ladder()
    await userEvent.click(within(table).getByRole('button', { name: 'Open Linen Boots' }))
    const run = within(table).getByRole('region', { name: 'Run details' })
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: /Buy on the AH/ }))
    // the boots are the second run after the robe's, the one crafted now: found in its climb
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({
        recipe_id: 103,
        runs: true,
        chain_from: 100,
        chain_at: 2,
        strategy: 'recommended',
        choices: { 'r.1': 'ah' },
      }),
    )
    expect(await within(run).findByRole('button', { name: 'Reset' })).toBeInTheDocument()
  })

  it('reminds the climber to train the next rank beside the run that reaches its skill', async () => {
    // capped at 75: Journeyman is taught from 50, which the belt's run (45 to 60) reaches
    const versions = [{ key: 'forever', label: 'WoW: Forever', build: null, recipes: 3, ah_cut: 0.05, profession_ranks: professionRanks }]
    const chain = [{ ...beltRun, stop_skill: 60 }, { ...bootsRun, stop_skill: 80 }]
    api({ '/api/rank': { ...ranked, chain }, '/api/versions': versions })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    // a word in the belt's row, and only there
    const table = await ladder()
    const belt = within(table).getByRole('button', { name: 'Open Linen Belt' })
    await waitFor(() => expect(belt).toHaveTextContent('45–60Train Journeyman'))
    expect(within(table).getByRole('button', { name: 'Open Green Robe' })).not.toHaveTextContent('Train')
    expect(within(table).getByRole('button', { name: 'Open Linen Boots' })).not.toHaveTextContent('Train')
    // the reminder itself once the row is open
    expect(screen.queryByRole('alert', { name: /^Train / })).not.toBeInTheDocument()
    await userEvent.click(belt)
    const note = await within(table).findByRole('alert', { name: 'Train Journeyman Tailoring' })
    expect(note).toHaveTextContent('Available at 50 skill and level 10')
    expect(screen.getAllByRole('alert', { name: /^Train / })).toHaveLength(1)
    // none among the strategies side by side
    await userEvent.click(within(options).getByRole('button', { name: 'Compare strategies' }))
    expect(screen.queryByRole('alert', { name: /^Train / })).not.toBeInTheDocument()
  })

  it('says to visit a trainer at the cap', async () => {
    api({ '/api/rank': { ...ranked, results: [], total: 0, chain: [], strategies: [] } })
    show({ ...CLIMBER, rank: 75 })
    expect(await screen.findByText("You're at your Tailoring cap (75)")).toBeInTheDocument()
    expect(screen.getByText(/Visit a Tailoring trainer to learn the next rank, then \/reload/)).toBeInTheDocument()
  })

  it('plans for a character nobody uploaded from the skill given, never stuck at a cap', async () => {
    const fetch = api()
    const you = { name: 'Your character', classFile: '', level: 0, rank: 75, maxRank: 75 }
    renderWithProviders(
      <SkillWorkspace
        filters={{ ...FILTERS, skillCrafters: [you.name], climberSkill: 75 }}
        climber={you}
        profession="Tailoring"
        hypothetical
      />,
    )
    await screen.findByRole('region', { name: 'Your options' })
    expect(screen.queryByText(/You're at your Tailoring cap/)).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('climber_skill')).toBe('75')
    await choose('Green Robe')
    await waitFor(() => expect(bodies(fetch, '/api/evaluate')).resolves.not.toHaveLength(0))
    for (const body of await bodies(fetch, '/api/evaluate')) {
      expect(body).toMatchObject({ skill_crafters: ['Your character'], climber_skill: 75 })
    }
  })
})
