import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { focusManager } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import type { RankResult } from '../api/client'
import type { RankParams } from '../api/queries'
import { linen, robe as robeItem, thread } from '../test/items'
import { professionRanks, robeResult } from '../test/results'
import { status } from '../test/status'
import { mockApi, renderWithProviders } from '../test/utils'
import type { Holder } from '../lib/setup'
import { scaleRun } from '../lib/skill'
import { WORKING_OVERTIME } from '../lib/talents'
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
// After the robe's run: the belt's, then the boots'.
const ranked = { results: [robeRun, capRun], total: 2, items, classes: {}, learn: {}, chain: [beltRun, bootsRun] }

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

/** Open the option named `name` from the overview, picking it among the others first unless it is the one to craft
 * now; the run's details. */
async function choose(name: string) {
  const options = await screen.findByRole('region', { name: 'Your options' })
  if (!within(options).queryByRole('button', { name: `Choose ${name}` })) {
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
  }
  // side by side, a click picks it; the one to craft now opens
  if (within(options).getAllByRole('button', { name: /^Choose / }).length > 1) {
    await userEvent.click(within(options).getByRole('button', { name: `Choose ${name}` }))
  }
  await userEvent.click(within(options).getByRole('button', { name: `Choose ${name}` }))
  // already side by side, that click only picked it
  if (!screen.queryByRole('region', { name: 'Run details' })) {
    await userEvent.click(within(options).getByRole('button', { name: `Choose ${name}` }))
  }
  return screen.getByRole('region', { name: 'Run details' })
}

/** The chain's recipes, in order. */
const chainNames = (chain: HTMLElement) =>
  within(chain)
    .getAllByRole('article')
    .map((e) => e.getAttribute('aria-label'))

describe('SkillWorkspace', () => {
  it('starts with the best option and what comes after it, the others side by side on asking', async () => {
    api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    expect(within(options).getAllByRole('button', { name: /^Choose / }).map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Green Robe',
    ])
    // the runs that follow it, each opening out in place
    let chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chainNames(chain)).toEqual(['Linen Belt', 'Linen Boots'])
    // each arrow says the skill the next run starts at: where the one before stops
    expect(within(chain).getAllByText(/^At \d+ skill$/).map((e) => e.textContent)).toEqual(['At 45 skill', 'At 45 skill'])
    expect(within(chain).getAllByRole('button', { name: /^Open / })).toHaveLength(2)
    expect(chain).not.toHaveAttribute('aria-disabled')
    // the others side by side, the cheapest point first, the chain muted until one is picked
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
    expect(cards.map((c) => c.getAttribute('aria-label'))).toEqual(['Choose Green Robe', 'Choose Linen Cap'])
    expect(within(options).queryByText('Best')).not.toBeInTheDocument()
    chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chain).toHaveAttribute('aria-disabled', 'true')
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
  })

  it('lays the options out in the server\'s order, each with what its climb comes to by each rank', async () => {
    // the server puts the best climb first; the cap's climb costs less, but dead-ends at 75: it stays where it is,
    // and isn't badged
    const milestones = (at75: number, at150: number) => [
      { skill: 75, cost: at75, unknown: 0 },
      { skill: 150, cost: at150, unknown: 0 },
    ]
    api({
      '/api/rank': {
        ...ranked,
        options: [
          {
            ...robeRun,
            climb_cost: 9000,
            climb_end: 225,
            milestones: [...milestones(1000, 4000), { skill: 225, cost: 5000, unknown: 1 }],
          },
          { ...capRun, climb_cost: 2000, climb_end: 75, milestones: milestones(2000, 2000).slice(0, 1) },
          { ...beltRun, climb_cost: 9500, climb_end: 225, milestones: milestones(3000, 9000) },
        ],
        option_chains: [ranked.chain, [bootsRun], [robeRun]],
      },
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    // the best climb's run is the one to craft now, with what its climb comes to over it
    expect(within(options).getAllByRole('button', { name: /^Choose / }).map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Green Robe',
    ])
    const robe = within(options).getByRole('group', { name: 'Cost to reach each rank with Green Robe first' })
    expect(robe).toHaveTextContent('75 skill:-10 0')
    expect(robe).toHaveTextContent('225 skill:-50 0+ 1 pattern of unknown price')
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
    expect(cards.map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Green Robe',
      'Choose Linen Cap',
      'Choose Linen Belt',
    ])
    // the best is badged Recommended, the others not; on hover it says what it weighs
    expect(within(cards[0]!).getByText('Recommended')).toBeInTheDocument()
    expect(within(options).getAllByText('Recommended')).toHaveLength(1)
    await userEvent.hover(within(cards[0]!).getByText('Recommended'))
    expect(await screen.findByText(/Reaches the highest skill of these options for the least/)).toBeInTheDocument()
    // each column has its own milestones and chain
    expect(within(options).getByRole('group', { name: 'Cost to reach each rank with Linen Belt first' })).toHaveTextContent(
      '150 skill:-90 0',
    )
    expect(chainNames(within(options).getByRole('region', { name: 'What comes after Linen Cap' }))).toEqual(['Linen Boots'])
    expect(chainNames(within(options).getByRole('region', { name: 'What comes after Linen Belt' }))).toEqual(['Green Robe'])
  })

  it('badges the best option even when every climb needs a pattern of unknown price', async () => {
    api({
      '/api/rank': {
        ...ranked,
        options: [
          { ...robeRun, climb_cost: 9000, climb_unknown: 1, climb_end: 150 },
          { ...capRun, climb_cost: 8000, climb_unknown: 1, climb_end: 150 },
        ],
        option_chains: [ranked.chain, [bootsRun]],
      },
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    // a labelled button, saying how many others there are
    await userEvent.click(within(options).getByRole('button', { name: 'Other options (1)' }))
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
    expect(within(cards[0]!).getByText('Recommended')).toBeInTheDocument()
    expect(within(options).getAllByText('Recommended')).toHaveLength(1)
  })

  it('shows each option as picking it gives', async () => {
    // listed, the cap stops where the robe gets cheaper; as an option, as the first run of its own climb, at 60
    const asOption: RankResult = { ...capRun, crafts: 30, stop_skill: 60, overtaken_by: 'Linen Boots', overtaken_by_item: 9004 }
    api({ '/api/rank': { ...ranked, options: [robeRun, asOption] } })
    show()
    await userEvent.click(await screen.findByRole('button', { name: /^Other options/ }))
    expect(screen.getByRole('button', { name: 'Choose Linen Cap' })).toHaveTextContent(
      'Craft until 60 skill (~30 times), at which point Linen Boots becomes a cheaper option',
    )
  })

  it("hangs each option's own chain under it, side by side only its next run, and may come back to a recipe", async () => {
    const chain = [beltRun, bootsRun, beltRun]
    api({ '/api/rank': { ...ranked, options: [robeRun, capRun], chain, option_chains: [chain, [bootsRun]] } })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    expect(chainNames(within(options).getByRole('region', { name: 'What comes after' }))).toEqual([
      'Linen Belt',
      'Linen Boots',
      'Linen Belt',
    ])
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    const best = within(options).getByRole('region', { name: 'What comes after' })
    const cap = within(options).getByRole('region', { name: 'What comes after Linen Cap' })
    expect(chainNames(best)).toEqual(['Linen Belt'])
    expect(chainNames(cap)).toEqual(['Linen Boots'])
    expect(best).toHaveAttribute('aria-disabled', 'true')
    expect(cap).toHaveAttribute('aria-disabled', 'true')
    expect(screen.queryByText(/whole climb/)).not.toBeInTheDocument()
  })

  it("offers the top card's details in place, its chain still under it", async () => {
    api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const card = within(options).getByRole('button', { name: 'Choose Green Robe' })
    await userEvent.click(card)
    const run = within(options).getByRole('region', { name: 'Run details' })
    expect(chainNames(screen.getByRole('region', { name: 'What comes after' }))).toEqual([
      'Linen Belt',
      'Linen Boots',
    ])
    await userEvent.click(within(run).getByRole('button', { name: 'Close' }))
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
  })

  it('opens any card of the single column in place, one at a time, under What to craft next', async () => {
    api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    await userEvent.click(within(chain).getByRole('button', { name: 'Open Linen Boots' }))
    let run = within(chain).getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Boots/)
    expect(within(options).getByText('What to craft next')).toBeInTheDocument()
    // the cards around it stay
    expect(within(options).getByRole('button', { name: 'Choose Green Robe' })).toBeInTheDocument()
    expect(within(chain).getByRole('button', { name: 'Open Linen Belt' })).toBeInTheDocument()
    // opening another closes it
    await userEvent.click(within(chain).getByRole('button', { name: 'Open Linen Belt' }))
    expect(screen.getAllByRole('region', { name: 'Run details' })).toHaveLength(1)
    // in place of the belt's card (whose item, in these fixtures, is the robe's)
    expect(within(chain).queryByRole('button', { name: 'Open Linen Belt' })).not.toBeInTheDocument()
    expect(within(chain).getByRole('region', { name: 'Run details' })).toBeInTheDocument()
    expect(within(chain).getByRole('button', { name: 'Open Linen Boots' })).toBeInTheDocument()
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Green Robe' }))
    expect(screen.getAllByRole('region', { name: 'Run details' })).toHaveLength(1)
    expect(within(screen.getByRole('region', { name: 'Run details' })).getByRole('heading')).toHaveTextContent(/Green Robe/)
    expect(within(options).getByText('What to craft next')).toBeInTheDocument()
  })

  it('shows three more runs after the chain on asking', async () => {
    const run = (i: number): RankResult => ({ ...beltRun, recipe_id: 200 + i, recipe: `Run ${i}`, output_name: `Run ${i}` })
    const runs = Array.from({ length: 7 }, (_, i) => run(i + 1))
    const fetch = api({
      '/api/rank': (url: URL) => ({ ...ranked, chain: runs.slice(0, Number(url.searchParams.get('chain_length') ?? 2)) }),
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chainNames(chain)).toEqual(['Run 1', 'Run 2'])
    await userEvent.click(within(chain).getByRole('button', { name: 'Show more' }))
    await waitFor(() => expect(chainNames(chain)).toHaveLength(5))
    // the longer chain follows the best, the one crafted now
    const asked = urls(fetch, '/api/rank').find((u) => u.searchParams.get('chain_length'))
    expect([asked?.searchParams.get('chain_from'), asked?.searchParams.get('chain_length')]).toEqual(['100', '5'])
    await userEvent.click(within(chain).getByRole('button', { name: 'Show more' }))
    await waitFor(() => expect(chainNames(chain)).toHaveLength(7))
    // fewer than asked for: the chain ended
    expect(within(chain).queryByRole('button', { name: 'Show more' })).not.toBeInTheDocument()
  })

  it('makes a picked option the one to craft now, with what comes after it', async () => {
    // the cheapest climb starting with the cap: its run goes on to 60, where the boots take over
    const longer: RankResult = { ...capRun, crafts: 30, stop_skill: 60, overtaken_by: 'Linen Boots', overtaken_by_item: 9004 }
    const capChain = { ...ranked, results: [longer], chain: [bootsRun], chain_start: longer }
    const fetch = api({
      '/api/rank': (url: URL) => (url.searchParams.get('chain_from') === '101' ? capChain : ranked),
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Linen Cap' }))
    // folded back around it
    expect(within(options).getAllByRole('button', { name: /^Choose / }).map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Linen Cap',
    ])
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    await waitFor(() => expect(chainNames(chain)).toEqual(['Linen Boots']))
    expect(chain).not.toHaveAttribute('aria-disabled')
    const asked = urls(fetch, '/api/rank').find((u) => u.searchParams.get('chain_from'))
    expect(asked?.searchParams.get('chain_from')).toBe('101')
    expect(asked?.searchParams.get('top')).toBe('1')
    expect(asked?.searchParams.getAll('skip')).toEqual([]) // nothing passed over: its climb may come back to the robe
    const card = within(options).getByRole('button', { name: 'Choose Linen Cap' })
    expect(card).toHaveTextContent('Craft until 60 skill (~30 times), at which point Linen Boots becomes a cheaper option')
    // opened and closed, it is still the one to craft now
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Linen Cap' }))
    const run = screen.getByRole('region', { name: 'Run details' })
    expect(within(run).getByRole('heading')).toHaveTextContent(/Linen Cap/)
    expect(run).toHaveTextContent(/Craft until 60 skill/) // the run as it stands after the pick
    await userEvent.click(within(run).getByRole('button', { name: 'Close' }))
    const back = await screen.findByRole('region', { name: 'Your options' })
    expect(within(back).getByRole('button', { name: 'Choose Linen Cap' })).toBeInTheDocument()
  })

  it("hangs a picked option's own chain under it while its climb is on its way, never the one shown before", async () => {
    let release: (value: unknown) => void = () => {}
    const capChain = { ...ranked, results: [capRun], chain: [bootsRun, beltRun], chain_start: capRun }
    api({
      '/api/rank': (url: URL) =>
        url.searchParams.get('chain_from') === '101'
          ? new Promise((resolve) => (release = () => resolve(capChain)))
          : { ...ranked, options: [robeRun, capRun], option_chains: [ranked.chain, [bootsRun]] },
    })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Linen Cap' }))
    // the cap's chain as it came with the list, muted; the robe's (fading out) is out of the accessibility tree
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    expect(chainNames(chain)).toEqual(['Linen Boots'])
    expect(chain).toHaveAttribute('aria-disabled', 'true')
    release(undefined)
    await waitFor(() => expect(chainNames(chain)).toEqual(['Linen Boots', 'Linen Belt']))
    expect(chain).not.toHaveAttribute('aria-disabled')
  })

  it('resets another run picked to craft now back to the recommended one', async () => {
    const capChain = { ...ranked, results: [capRun], chain: [bootsRun], chain_start: capRun }
    api({ '/api/rank': (url: URL) => (url.searchParams.get('chain_from') === '101' ? capChain : ranked) })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    // the recommended one: nothing to reset
    expect(within(options).queryByRole('button', { name: 'Reset to recommended' })).not.toBeInTheDocument()
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    await userEvent.click(within(options).getByRole('button', { name: 'Choose Linen Cap' }))
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    await waitFor(() => expect(chainNames(chain)).toEqual(['Linen Boots']))
    await userEvent.click(within(options).getByRole('button', { name: 'Reset to recommended' }))
    expect(within(options).getAllByRole('button', { name: /^Choose / }).map((c) => c.getAttribute('aria-label'))).toEqual([
      'Choose Green Robe',
    ])
    await waitFor(() => expect(chainNames(within(options).getByRole('region', { name: 'What comes after' }))).toEqual(['Linen Belt', 'Linen Boots']))
    expect(within(options).queryByRole('button', { name: 'Reset to recommended' })).not.toBeInTheDocument()
  })

  it("says where a run's last points get slow, and how many crafts it usually takes", async () => {
    // eight orange points, then one at 1 in 4
    const slow = { ...robeRun, point_crafts: [1, 1, 1, 1, 1, 1, 1, 1, 4] }
    api({ '/api/rank': { ...ranked, results: [slow, capRun] } })
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const card = within(options).getByRole('button', { name: 'Choose Green Robe' })
    expect(card).toHaveTextContent('The last point takes ~4 of these ~12 crafts')
    expect(card).not.toHaveTextContent('Usually')
    // opened, the run also says its usual spread: 10% done after 11 crafts, 90% after 17
    const run = await choose('Green Robe')
    expect(run).toHaveTextContent('Usually 11–17 crafts. The last point takes ~4 of these ~12 crafts')
  })

  it('says what the best run is worth and how far it goes', async () => {
    const fetch = api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const cards = within(options).getAllByRole('button', { name: /^Choose / })
    expect(cards[0]).toHaveTextContent('Craft until 45 skill (~12 times), at which point Linen Cap becomes a cheaper option')
    // the cheaper recipe's item in its quality's colour, with its tooltip
    expect(within(cards[0]!).getByText('Linen Cap').closest('[data-quality]')).toHaveAttribute('data-quality', '2')
    // one amount: what the run comes to per skill point after selling, a loss in red with its minus sign
    expect(within(cards[0]!).getByText(/per skill point/)).toBeInTheDocument()
    const silver = within(cards[0]!).getByTitle('silver')
    expect(silver.parentElement).toHaveTextContent(/^-3 0$/) // 3600 copper spent for 12 points: 3s 0c each
    expect(silver.closest<HTMLElement>('[style]')?.style.color).toContain('red')
    expect(within(cards[0]!).queryByText(/after selling back/)).not.toBeInTheDocument()
    expect(within(cards[0]!).queryByText(/You know it|You must/)).not.toBeInTheDocument() // known: nothing to say
    expect(within(cards[0]!).queryByRole('img', { name: /Orange/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Run details' })).not.toBeInTheDocument()
    // each option's plan for the 14 crafts it opens with, fetched ahead
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).map((b) => [b.recipe_id, b.copies])).toEqual([
        [100, 14],
        [101, 14],
      ]),
    )
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('runs')).toBe('true')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/events')).map((b) => b.name)).toEqual(['next_up_shown']),
    )
  })

  it('opens a chosen option out into its run: what to make until when, why, what comes next, the checklist', async () => {
    const fetch = api()
    show()
    const run = await choose('Green Robe')
    expect(run).toHaveTextContent(/Craft until 45 skill \(~12 times\), at which point Linen Cap becomes a cheaper option/)
    // the crafts to buy for: enough to reach the target four times in five
    expect(within(run).getByRole('textbox', { name: 'Crafts to buy for' })).toHaveValue('14')
    expect(within(run).getByText('82% chance to reach your target of 45 skill')).toBeInTheDocument()
    expect(within(run).queryByText(/Why this one|Then, at/)).not.toBeInTheDocument()
    expect(screen.queryByText(/after this run/)).not.toBeInTheDocument() // the header stays as it was
    // the checklist buys for the 14 crafts an unlucky run takes, grouped by who does what
    await waitFor(async () => expect(await bodies(fetch, '/api/evaluate')).toHaveLength(2)) // fetched ahead, once
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

  it('says how many of the skill points counted on come from Working Overtime, after the odds', async () => {
    // the ranked run's 12 crafts expect 0.5 points from the talent; the plan for the 14 bought for, 0.6
    api({
      '/api/rank': { ...ranked, results: [{ ...robeRun, skill_ups_bonus: 0.48 }, capRun] },
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
    api({ '/api/rank': { ...ranked, results: [robeRun, pattern, unknown], total: 3, learn } })
    show()
    await userEvent.click(await screen.findByRole('button', { name: /^Other options/ }))
    // the cards warn of a pattern nobody can price, and say one whose cost is counted must be trained
    expect(screen.getByText('You must find the pattern (price unknown)')).toBeInTheDocument()
    const card = screen.getByRole('button', { name: 'Choose Linen Cap' })
    expect(within(card).getByText('You will need to buy the pattern (included in the cost)')).toBeInTheDocument()
    const run = await choose('Linen Cap')
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
    api({ '/api/rank': { ...ranked, results: [robeRun, trained], total: 2, learn } })
    show()
    const run = await choose('Linen Cap')
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

  it('opens an option other than the best', async () => {
    api()
    show()
    const run = await choose('Linen Cap')
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

  it('asks only for the options side by side, with no full list', async () => {
    const many = [robeRun, capRun, beltRun, { ...beltRun, recipe_id: 103, recipe: 'Linen Boots', output_name: 'Linen Boots' }]
    const fetch = api({ '/api/rank': { ...ranked, results: many, total: 9 } })
    show()
    await userEvent.click(await screen.findByRole('button', { name: /^Other options/ }))
    expect(screen.queryByRole('button', { name: /See all/ })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank').map((u) => u.searchParams.get('top'))).toContain('4')
    expect(urls(fetch, '/api/rank').every((u) => Number(u.searchParams.get('top')) <= 4)).toBe(true)
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
      'Tailoring: Green Robe. Craft until 45 skill (~12 times), at which point Linen Cap becomes a cheaper option',
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

  it("plans an option again as its card shows it, never coming back to those it leaves out", async () => {
    // the cap side by side leaves out the robe; bought for as many crafts as the run asks, so its plan isn't
    // fetched for a count: a change of source plans the run again, with what it leaves out
    const capOption: RankResult = {
      ...capRun,
      crafts_p80: 12,
      reach_chances: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0.5, 0.7, 0.8, 0.9, 0.95],
      climb_without: [100],
    }
    const fetch = api({ '/api/rank': { ...ranked, options: [robeRun, capOption] } })
    show()
    const run = await choose('Linen Cap')
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: /Buy on the AH/ }))
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({
        recipe_id: 101,
        runs: true,
        climb_without: [100],
        choices: { 'r.1': 'ah' },
      }),
    )
    // planned for a count the user types, it is those crafts whatever the climb leaves out
    const input = within(run).getByRole('textbox', { name: 'Crafts to buy for' })
    await userEvent.clear(input)
    await userEvent.type(input, '20')
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({ recipe_id: 101, copies: 20, climb_without: [] }),
    )
    const counted = (await bodies(fetch, '/api/evaluate')).filter((b) => b.copies !== undefined)
    expect(counted.length).toBeGreaterThan(0)
    expect(counted.every((b) => Array.isArray(b.climb_without) && b.climb_without.length === 0)).toBe(true)
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
    run = await choose('Linen Cap')
    expect(within(run).queryByRole('button', { name: 'Reset' })).not.toBeInTheDocument()
  })

  it("changes a source in a run of the chain, planned again as the chain has it", async () => {
    const fetch = api()
    show()
    const options = await screen.findByRole('region', { name: 'Your options' })
    const chain = within(options).getByRole('region', { name: 'What comes after' })
    await userEvent.click(within(chain).getByRole('button', { name: 'Open Linen Boots' }))
    const run = within(chain).getByRole('region', { name: 'Run details' })
    await userEvent.click(await within(run).findByRole('button', { name: 'Change source of Coarse Thread' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: /Buy on the AH/ }))
    // the boots are the second run after the robe's, the one crafted now: found in its climb
    await waitFor(async () =>
      expect((await bodies(fetch, '/api/evaluate')).at(-1)).toMatchObject({
        recipe_id: 103,
        runs: true,
        chain_from: 100,
        chain_at: 2,
        climb_without: [],
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
    const after = within(options).getByRole('region', { name: 'What comes after' })
    const note = await within(after).findByRole('alert', { name: 'Train Journeyman Tailoring' })
    expect(note).toHaveTextContent('Available at 50 skill and level 10')
    // beside the belt's card, and only there
    expect(note.parentElement?.parentElement).toContainElement(within(after).getByRole('article', { name: 'Linen Belt' }))
    expect(screen.getAllByRole('alert', { name: /^Train / })).toHaveLength(1)
    // the single column only: none among the options side by side
    await userEvent.click(within(options).getByRole('button', { name: /^Other options/ }))
    expect(screen.queryByRole('alert', { name: /^Train / })).not.toBeInTheDocument()
  })

  it('says to visit a trainer at the cap', async () => {
    api({ '/api/rank': { ...ranked, results: [], total: 0, chain: [] } })
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
