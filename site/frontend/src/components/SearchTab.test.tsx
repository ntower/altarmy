import { act, fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { robeResult } from '../test/results'
import { characters, status, withEnchanter } from '../test/status'
import { GUEST, mockApi, renderWithProviders } from '../test/utils'
import { navigate } from '../lib/router'
import { SearchTab, SHOW_ARCANE_SALVAGER } from './SearchTab'
import { SYNC_DOWNLOAD } from './SyncCard'

// Tests that only check paging swap the results table for one line per row: rendering 150 full rows
// in jsdom takes seconds on a loaded machine.
const table = vi.hoisted(() => ({ stub: false }))
vi.mock('./ResultsTable', async (importOriginal) => {
  const actual = await importOriginal<typeof import('./ResultsTable')>()
  return {
    ...actual,
    ResultsTable: (props: Parameters<typeof actual.ResultsTable>[0]) =>
      table.stub ? <div>{props.results.length} rows</div> : <actual.ResultsTable {...props} />,
  }
})
afterEach(() => {
  table.stub = false
})

const noResults = { results: [], total: 0, items: {}, classes: {} }

const house = (realm: string, faction: string, prices = 10) => ({
  auction_house_id: 1,
  realm,
  faction,
  prices,
  last_scan: '2026-09-24 10:00:00',
  last_scan_items: prices,
  scans_7d: 1,
  uploaders_7d: 1,
})

function urls(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([request]) => new URL(request.url)).filter((u) => u.pathname === pathname)
}

/** Open the search at `path` (most tests make gold). */
const at = (path: string) => window.history.replaceState(null, '', path)
const GOLD = '/profit/gold'
/** Tailor Guy skilling up Tailoring on Classic Beta PvE (Horde). */
const TAILOR = '/profit/skill/classic-beta-pve-horde/Tailor%20Guy/tailoring'

/** The buttons of the question named `name`, by label. */
/** Open skilling up's Options, closed at first. */
const openOptions = async () => userEvent.click(await screen.findByRole('button', { name: 'Options' }))

const answers = (name: string) =>
  within(screen.getByRole('group', { name }))
    .getAllByRole('button')
    .map((b) => b.getAttribute('aria-label'))

describe('SearchTab', () => {
  const realm = () => screen.getByRole('combobox', { name: 'Realm' })

  beforeEach(() => at(GOLD))

  it('says so when no game data is loaded', async () => {
    mockApi({
      '/api/status': status({ recipes: 0 }),
      '/api/characters': characters,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/No game data has been loaded yet/)).toBeInTheDocument()
  })

  it('browses every recipe of a realm without characters', async () => {
    const shared = { realm: 'Classic Beta PvE', faction: '' }
    const fetch = mockApi({
      '/api/status': status({ characters: 0, selection: shared }),
      '/api/characters': { groups: [], selection: shared },
      '/api/coverage': [house('Classic Beta PvE', ''), house('Dreamscythe', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText(/No characters uploaded for this realm/)).toBeInTheDocument()
    expect(screen.queryByRole('radiogroup', { name: 'Recipes' })).not.toBeInTheDocument()
    expect(await screen.findByText('No recipes match these filters with the current prices.')).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toHaveLength(1)
    await waitFor(() =>
      expect(screen.getByRole('combobox', { name: 'Realm' })).toHaveValue('Classic Beta PvE (both factions)'),
    )
  })

  it('shows how fresh the selected auction house prices are', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', ''), { ...house('Dreamscythe', 'Horde'), auction_house_id: 2 }],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />, GUEST)
    const freshness = await screen.findByRole('status', {
      name: 'Price freshness',
    })
    expect(freshness).toHaveTextContent(/Auction house prices are from a scan \d+ days ago\./)
  })

  it('uploads a scan right in the realm card', async () => {
    const appended = new Map<string, unknown>()
    vi.stubGlobal(
      'FormData',
      class extends FormData {
        override append(name: string, value: string | Blob, fileName?: string): void {
          appended.set(name, value)
          super.append(name, typeof value === 'string' ? value : `file ${fileName}`)
        }
      },
    )
    const imported = {
      kind: 'altarmy',
      detail: '',
      characters: 1,
      groups: [],
      realms: [],
    }
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
      '/api/uploads': imported,
    })
    renderWithProviders(<SearchTab />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    await userEvent.click(await within(card).findByRole('button', { name: 'Upload your scan' }))
    expect(within(card).getByRole('heading', { name: 'Upload your scan' })).toBeInTheDocument()
    expect(within(card).queryByRole('combobox', { name: 'Realm' })).not.toBeInTheDocument()
    expect(within(card).getByRole('button', { name: 'Auto-upload' })).toBeInTheDocument()
    const file = new File(['AltArmyTBC_Data = {}'], 'AltArmy_TBC.lua')
    await userEvent.upload(card.querySelector<HTMLInputElement>('input[type="file"]')!, file)
    await userEvent.click(within(card).getByRole('button', { name: 'Upload' }))
    expect(await within(card).findByText(/Uploaded 1 characters/)).toBeInTheDocument()
    const post = fetch.mock.calls.map(([r]) => r).find((r) => r.method === 'POST')
    expect(new URL(post!.url).pathname).toBe('/api/uploads')
    expect(appended.get('file')).toBe(file)
    // The Alt Army Sync mention opens the same steps as the Auto-upload card.
    await userEvent.click(within(card).getByRole('button', { name: 'Alt Army Sync' }))
    expect(await within(card).findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    expect(within(card).getByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    await userEvent.click(within(card).getByRole('button', { name: 'Continue' }))
    expect(await within(card).findByRole('combobox', { name: 'Realm' })).toBeInTheDocument()
    vi.unstubAllGlobals()
  })

  it('offers only Upload your scan on the realm card, Auto-upload being a card beside the upload', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    expect(await within(card).findByRole('button', { name: 'Upload your scan' })).toBeInTheDocument()
    expect(within(card).queryByRole('button', { name: 'Auto-upload' })).not.toBeInTheDocument()
    await userEvent.click(within(card).getByRole('button', { name: 'Upload your scan' }))
    await userEvent.click(within(card).getByRole('button', { name: 'Auto-upload' }))
    expect(await within(card).findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    expect(within(card).getByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    await userEvent.click(within(card).getByRole('button', { name: 'Back to the realm' }))
    expect(await within(card).findByRole('combobox', { name: 'Realm' })).toBeInTheDocument()
  })

  it("opens Alt Army Sync's steps from the upload's Auto-upload card", async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    await userEvent.click(await within(card).findByRole('button', { name: 'Upload your scan' }))
    await userEvent.click(within(card).getByRole('button', { name: 'Auto-upload' }))
    expect(await within(card).findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    // The manual upload is now the card beside it.
    await userEvent.click(within(card).getByRole('button', { name: 'Upload your scan' }))
    expect(await within(card).findByRole('heading', { name: 'Upload your scan' })).toBeInTheDocument()
  })

  it('points hosted users to the Upload page for prices, with nothing to rank until a realm has them', async () => {
    const fetch = mockApi({
      '/api/status': status({ characters: 0, selection: null, prices: 0 }),
      '/api/characters': { groups: [], selection: null },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />, GUEST)
    expect(await screen.findByText('No data collected for this auction house')).toBeInTheDocument()
    expect(screen.queryByText(/guest/i)).not.toBeInTheDocument()
    expect(realm()).toHaveValue('')
    expect(screen.queryByRole('button', { name: 'Advanced Filters' })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
  })

  it('makes gold at its path, ranking by profit, both ways to sell side by side', async () => {
    localStorage.setItem('altarmy.search.unlearned', '"soon"')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab characters={<div>the characters</div>} />)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    expect(screen.queryByRole('group', { name: 'How do you want to sell?' })).not.toBeInTheDocument()
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.get('sort')).toBe('likely') // the gold list's default: the better of the two first
    expect(rank?.searchParams.get('unlearned')).toBe('none') // only recipes they know
    expect(rank?.searchParams.has('look_ahead')).toBe(false) // nothing is trained: no look-ahead or sources
    expect(rank?.searchParams.has('sources')).toBe(false)
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah'])
    expect(rank?.searchParams.has('professions')).toBe(false)
    // no summary of the answers: the path says them
    expect(screen.queryByRole('group', { name: 'Your setup' })).not.toBeInTheDocument()
    expect(screen.queryByText('Rank by')).not.toBeInTheDocument()
    // the characters beside the realm card
    expect(screen.getByText('the characters').nextElementSibling).toBe(screen.getByRole('region', { name: 'Realm' }))
    expect(realm()).toBeInTheDocument()
  })

  it('opens the realm card across the whole width while uploading a scan', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab characters={<div>the characters</div>} />)
    const card = await screen.findByRole('region', { name: 'Realm' })
    expect(card).not.toHaveAttribute('data-wide')
    await userEvent.click(await within(card).findByRole('button', { name: 'Upload your scan' }))
    expect(card).toHaveAttribute('data-wide')
    await userEvent.click(within(card).getByRole('button', { name: 'Continue' }))
    await waitFor(() => expect(card).not.toHaveAttribute('data-wide'))
  })

  it('skills up one profession: each recipe as a run until it turns grey, losing ones included', async () => {
    at('/profit/skill')
    localStorage.setItem('altarmy.search.minProfit', JSON.stringify(0.5))
    localStorage.setItem('altarmy.search.minRoi', JSON.stringify(0))
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByRole('group', { name: 'Which profession?' })
    expect(screen.getByRole('heading', { name: 'Which profession?' })).toBeInTheDocument()
    expect(answers('Which profession?')).toEqual(['Tailoring', 'Cooking']) // one profession, never any
    // the primary professions first, then the secondary ones
    expect(answers('Primary professions')).toEqual(['Tailoring'])
    expect(answers('Secondary professions')).toEqual(['Cooking'])
    const tailoring = screen.getByRole('button', { name: 'Tailoring' })
    const tailor = within(tailoring).getByText('Tailor Guy')
    expect(tailor).toHaveAttribute('data-class', 'MAGE')
    // a table row: the name, then the skill out of the highest there is
    expect(tailor.closest('p')?.nextElementSibling).toHaveTextContent(/^50\/300$/)
    expect(
      within(tailoring).getByRole('progressbar', {
        name: "Tailor Guy's Tailoring skill",
      }),
    ).toBeInTheDocument()
    expect(urls(fetch, '/api/rank')).toEqual([])
    await userEvent.click(tailoring)
    // the only tailor, picked at once: the path names them
    expect(window.location.pathname).toBe(TAILOR)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.get('include_trivial')).toBe('false')
    expect(rank?.searchParams.has('min_profit')).toBe(false)
    expect(rank?.searchParams.has('min_roi')).toBe(false) // losses have a negative ROI
    expect(rank?.searchParams.get('sort')).toBe('skill')
    expect(rank?.searchParams.get('runs')).toBe('true') // each as a run until another gets cheaper
    expect(rank?.searchParams.get('unlearned')).toBe('train') // and those they can train now,
    expect(rank?.searchParams.get('look_ahead')).toBe('0')
    expect(rank?.searchParams.getAll('sources')).toEqual(['trainer', 'recipe']) // not from bind on pickup recipes
    // sold to a vendor or disenchanted, else kept
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant', 'keep'])
    expect(rank?.searchParams.getAll('professions')).toEqual(['Tailoring'])
    expect(rank?.searchParams.getAll('skill_crafters')).toEqual(['Tailor Guy'])
    expect(screen.queryByRole('radio')).not.toBeInTheDocument() // no colour to stop at
    expect(screen.queryByRole('checkbox', { name: /Disenchant/ })).not.toBeInTheDocument()
    expect(localStorage.getItem('altarmy.search.minProfit')).toBe('0.5') // where it used to be: left alone
    expect(screen.queryByRole('group', { name: 'Your setup' })).not.toBeInTheDocument()
    // none of making gold's options
    expect(screen.getByRole('button', { name: 'Options' })).toBeInTheDocument()
    for (const gone of ['Advanced Filters', 'Filters']) {
      expect(screen.queryByRole('button', { name: gone })).not.toBeInTheDocument()
    }
    expect(screen.queryByLabelText('Crafts per session')).not.toBeInTheDocument()
    expect(screen.queryByRole('radio', { name: 'Include recipes I can train' })).not.toBeInTheDocument()
  })

  it("lays out a run's page: the climber's card beside the auction house's and the Options button under it", async () => {
    at(TAILOR)
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', 'Horde')],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const climber = await screen.findByRole('region', { name: 'Skilling up' })
    const house_ = screen.getByRole('region', { name: 'Realm' })
    // one grid: the climber's cell, the auction house's, then the Options button (the grid sets the climber's as tall
    // as the other two)
    const grid = climber.parentElement!.parentElement!
    expect(house_.parentElement!.parentElement).toBe(grid)
    expect(within(climber).getByRole('button', { name: 'Switch character or profession' })).toBeInTheDocument()
    expect(within(climber).getByRole('button', { name: 'Upload again' })).toBeInTheDocument()
    // the realm is the climber's: no picker, only how old its prices are and the upload
    expect(screen.queryByRole('combobox', { name: 'Realm' })).not.toBeInTheDocument()
    expect(await within(house_).findByRole('status', { name: 'Price freshness' })).toBeInTheDocument()
    expect(within(house_).getByRole('button', { name: 'Upload your scan' })).toBeInTheDocument()
    // the Options button under the auction house's, closed; open, one column: what teaches the recipes, then the
    // chance to reach
    const options = screen.getByRole('button', { name: 'Options' })
    expect(options).toHaveAttribute('aria-expanded', 'false')
    expect(options.parentElement).toBe(grid)
    expect(options.previousElementSibling).toBe(house_.parentElement)
    expect(screen.queryByRole('group', { name: 'Recipes taught by' })).not.toBeInTheDocument()
    await userEvent.click(options)
    expect(options).toHaveAttribute('aria-expanded', 'true')
    expect(document.getElementById(options.getAttribute('aria-controls')!)?.parentElement).toBe(grid)
    const taught = screen.getByRole('group', { name: 'Recipes taught by' })
    const chance = screen.getByRole('textbox', { name: 'Chance to reach target skill' })
    expect(taught.compareDocumentPosition(chance)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  })

  it("shows the Profit page's characters in the climber's card's place while they upload again", async () => {
    at(TAILOR)
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    function Page() {
      const [open, setOpen] = useState(false)
      return <SearchTab characters={<div>the start cards</div>} charactersOpen={open} onUploadCharacters={() => setOpen(true)} />
    }
    renderWithProviders(<Page />)
    expect(screen.queryByText('the start cards')).not.toBeInTheDocument()
    await userEvent.click(await screen.findByRole('button', { name: 'Upload again' }))
    expect(screen.getByText('the start cards')).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Skilling up' })).not.toBeInTheDocument()
  })

  it('asks which one of several tailors is skilling up before searching, offering them first next time', async () => {
    at('/profit/skill')
    const [first, ...rest] = characters.groups
    const seamstress = {
      name: 'Seamstress',
      class_file: 'PRIEST',
      level: 20,
      professions: [{ name: 'Tailoring', rank: 30, max_rank: 75, recipes: 1 }],
      talents: [],
      vendor_discounts: [],
    }
    const tailors = {
      ...characters,
      groups: [{ ...first!, characters: [...first!.characters, seamstress] }, ...rest],
    }
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': tailors,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await userEvent.click(await screen.findByRole('button', { name: 'Tailoring' }))
    const who = screen.getByRole('radiogroup', {
      name: 'Who is skilling up Tailoring?',
    })
    const guy = within(who).getByRole('radio', { name: /Tailor Guy 50\/300/ })
    const sea = within(who).getByRole('radio', { name: /Seamstress 30\/300/ })
    expect(sea).toBeChecked() // the lowest-skilled first
    expect(guy).not.toBeChecked()
    expect(urls(fetch, '/api/rank')).toEqual([])
    await userEvent.click(screen.getByRole('button', { name: 'Done' }))
    expect(window.location.pathname).toBe('/profit/skill/classic-beta-pve-horde/Seamstress/tailoring')
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    expect(urls(fetch, '/api/rank')[0]?.searchParams.getAll('skill_crafters')).toEqual(['Seamstress'])
    // back to the question: the one picked last is offered first
    act(() => navigate('/profit/skill'))
    await userEvent.click(await screen.findByRole('button', { name: 'Tailoring' }))
    expect(screen.getByRole('radio', { name: /Seamstress/ })).toBeChecked()
    await userEvent.click(screen.getByRole('radio', { name: /Tailor Guy/ }))
    await userEvent.click(screen.getByRole('button', { name: 'Done' }))
    expect(window.location.pathname).toBe(TAILOR)
    await waitFor(() =>
      expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('skill_crafters')).toEqual(['Tailor Guy']),
    )
  })

  it.each([
    ['a character who is gone', '/profit/skill/classic-beta-pve-horde/Retired/tailoring'],
    ['a profession nobody has', '/profit/skill/classic-beta-pve-horde/Tailor%20Guy/alchemy'],
    ['a realm without the character', '/profit/skill/dreamscythe-horde/Tailor%20Guy/tailoring'],
  ])('asks for the profession again at a run of %s', async (_, path) => {
    at(path)
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('group', { name: 'Which profession?' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/profit/skill')
    expect(urls(fetch, '/api/rank')).toEqual([])
    expect(urls(fetch, '/api/selection')).toEqual([])
  })

  it('offers only professions that have recipes', async () => {
    at('/profit/skill')
    const fishers = {
      ...characters,
      groups: [
        {
          ...characters.groups[0]!,
          characters: [
            {
              ...characters.groups[0]!.characters[0]!,
              professions: [
                { name: 'Fishing', rank: 10, max_rank: 75, recipes: 0 },
                { name: 'Tailoring', rank: 50, max_rank: 75, recipes: 1 },
              ],
            },
          ],
        },
      ],
    }
    mockApi({
      '/api/status': status(),
      '/api/characters': fishers,
      '/api/professions': ['Cooking', 'Tailoring'],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(answers('Which profession?')).toEqual(['Tailoring']))
  })

  it("a run of a character nobody has goes back to asking which profession", async () => {
    at(TAILOR)
    mockApi({
      '/api/status': status({ characters: 0 }),
      '/api/characters': { groups: [], selection: null },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(window.location.pathname).toBe('/profit/skill'))
  })

  describe('skilling up without characters', () => {
    /** Nobody uploaded, Classic Beta PvE (Horde) selected: its house and Dreamscythe's have prices. */
    const nobody = {
      '/api/status': status({ characters: 0 }),
      '/api/characters': { groups: [], selection: { realm: 'Classic Beta PvE', faction: 'Horde' } },
      '/api/coverage': [house('Classic Beta PvE', 'Horde'), house('Dreamscythe', 'Horde')],
      '/api/professions': ['Cooking', 'Mining', 'Tailoring'],
      '/api/rank': noResults,
    }
    const TRY = '/profit/skill/classic-beta-pve-horde/tailoring/45'

    it('asks which profession, every one that can be skilled up, and plans from skill 1 without asking', async () => {
      at('/profit/skill')
      const fetch = mockApi(nobody)
      renderWithProviders(<SearchTab />)
      await screen.findByRole('group', { name: 'Which profession?' })
      // every profession with recipes but the gathering ones, nobody holding them
      await waitFor(() => expect(answers('Which profession?')).toEqual(['Tailoring', 'Cooking']))
      expect(screen.queryByRole('progressbar')).not.toBeInTheDocument()
      await userEvent.click(screen.getByRole('button', { name: 'Tailoring' }))
      // nothing asked: straight to the climb from 1, the skill to change on its page
      expect(screen.queryByRole('textbox', { name: /skill now/ })).not.toBeInTheDocument()
      expect(window.location.pathname).toBe('/profit/skill/classic-beta-pve-horde/tailoring/1')
      // ranked for a made-up character with Tailoring at 1
      await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
      const [rank] = urls(fetch, '/api/rank')
      expect(rank?.searchParams.getAll('skill_crafters')).toEqual(['Your character'])
      expect(rank?.searchParams.get('climber_skill')).toBe('1')
      expect(rank?.searchParams.getAll('professions')).toEqual(['Tailoring'])
      expect(rank?.searchParams.get('runs')).toBe('true')
      expect(rank?.searchParams.get('unlearned')).toBe('train')
      // the answers, remembered to mark them next time
      expect(JSON.parse(localStorage.getItem('altarmy.setup.g1') ?? '')).toEqual({
        aim: 'skill',
        profession: 'Tailoring',
        climberSkill: 1,
      })
      // the climber's card: the profession and skill to change, what is assumed, and the upload
      const card = screen.getByRole('region', { name: 'Skilling up' })
      expect(within(card).getByRole('combobox', { name: 'Profession' })).toHaveValue('Tailoring')
      expect(within(card).getByRole('textbox', { name: 'Current skill' })).toHaveValue('1')
      expect(within(card).getByText(/Doing our best with no character data/)).toBeInTheDocument()
      expect(within(card).getByRole('button', { name: 'Upload your characters' })).toBeInTheDocument()
      expect(screen.queryByText(/Browsing every recipe/)).not.toBeInTheDocument()
      expect(screen.queryByRole('alert', { name: 'You do not have a disenchanter' })).not.toBeInTheDocument()
    })

    it("changes the skill or profession in the climber's card, in place of the path", async () => {
      at(TRY)
      const fetch = mockApi(nobody)
      renderWithProviders(<SearchTab />)
      const card = await screen.findByRole('region', { name: 'Skilling up' })
      const skill = within(card).getByRole('textbox', { name: 'Current skill' })
      await userEvent.clear(skill)
      await userEvent.type(skill, '120')
      await waitFor(() => expect(window.location.pathname).toBe('/profit/skill/classic-beta-pve-horde/tailoring/120'))
      await waitFor(() =>
        expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('climber_skill')).toBe('120'),
      )
      await userEvent.click(within(card).getByRole('combobox', { name: 'Profession' }))
      await userEvent.click(await screen.findByRole('option', { name: 'Cooking' }))
      await waitFor(() => expect(window.location.pathname).toBe('/profit/skill/classic-beta-pve-horde/cooking/120'))
      await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('professions')).toEqual(['Cooking']))
    })

    it('goes back to asking which profession when the path names no priced realm or profession', async () => {
      at('/profit/skill/nowhere-horde/tailoring/45')
      mockApi(nobody)
      renderWithProviders(<SearchTab />)
      await waitFor(() => expect(window.location.pathname).toBe('/profit/skill'))
    })

    it("keeps today's flow on a realm with characters", async () => {
      at('/profit/skill')
      mockApi({ ...nobody, '/api/status': status(), '/api/characters': characters })
      renderWithProviders(<SearchTab />)
      await waitFor(() => expect(answers('Which profession?')).toEqual(['Tailoring', 'Cooking']))
      expect(screen.getByRole('progressbar', { name: "Tailor Guy's Tailoring skill" })).toBeInTheDocument()
    })
  })

  it("opens a run on another realm than the selected one, selecting the run's", async () => {
    at(TAILOR)
    let selection = { realm: 'Dreamscythe', faction: 'Horde' }
    const fetch = mockApi({
      '/api/status': () => status({ selection }),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/selection': async (_: URL, request: Request) => {
        selection = (await request.json()) as typeof selection
        return status({ selection })
      },
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    expect(urls(fetch, '/api/selection')).toHaveLength(1)
    expect(selection).toEqual({ realm: 'Classic Beta PvE', faction: 'Horde' })
    expect(urls(fetch, '/api/rank')[0]?.searchParams.getAll('skill_crafters')).toEqual(['Tailor Guy'])
  })

  it("switches to another of the realm's characters and professions in place of the current path", async () => {
    at(TAILOR)
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const entries = window.history.length
    await userEvent.click(await screen.findByRole('button', { name: 'Switch character or profession' }))
    await userEvent.click(within(await screen.findByRole('listbox')).getByRole('option', { name: /Cooking/ }))
    expect(window.location.pathname).toBe('/profit/skill/classic-beta-pve-horde/Tailor%20Guy/cooking')
    expect(window.history.length).toBe(entries) // the back button leaves the climb, not each switch
  })

  it("switches to a character on another realm through the climber's select, selecting that realm", async () => {
    at(TAILOR)
    const alchemist = {
      ...characters,
      groups: characters.groups.map((g) =>
        g.realm === 'Dreamscythe'
          ? {
              ...g,
              characters: g.characters.map((c) =>
                c.name === 'Frell' ? { ...c, professions: [{ name: 'Alchemy', rank: 100, max_rank: 150, recipes: 1 }] } : c,
              ),
            }
          : g,
      ),
    }
    let selection = { realm: 'Classic Beta PvE', faction: 'Horde' }
    const fetch = mockApi({
      '/api/status': () => status({ selection }),
      '/api/characters': alchemist,
      '/api/rank': noResults,
      '/api/selection': async (_: URL, request: Request) => {
        selection = (await request.json()) as typeof selection
        return status({ selection })
      },
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    await userEvent.click(screen.getByRole('button', { name: 'Switch character or profession' }))
    const list = await screen.findByRole('listbox')
    expect(within(list).getByText('Dreamscythe (Horde)')).toBeInTheDocument()
    await userEvent.click(within(list).getByRole('option', { name: /Alchemy/ }))
    expect(window.location.pathname).toBe('/profit/skill/dreamscythe-horde/Frell/alchemy')
    await waitFor(() => expect(selection).toEqual({ realm: 'Dreamscythe', faction: 'Horde' }))
    await waitFor(() =>
      expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('skill_crafters')).toEqual(['Frell']),
    )
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('professions')).toEqual(['Alchemy'])
  })

  it('changes realm with the picker beside the profession question', async () => {
    at('/profit/skill')
    let selection = { realm: 'Classic Beta PvE', faction: 'Horde' }
    mockApi({
      '/api/status': () => status({ selection }),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/selection': async (_: URL, request: Request) => {
        selection = (await request.json()) as typeof selection
        return status({ selection })
      },
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('button', { name: 'Tailoring' })).toBeInTheDocument()
    await userEvent.click(realm())
    await userEvent.click(await screen.findByRole('option', { name: 'Dreamscythe (Horde) · 2 characters' }))
    expect(await screen.findByText(/None of your characters on this realm has a profession yet/)).toBeInTheDocument()
    expect(window.location.pathname).toBe('/profit/skill')
  })

  it('suggests Enchanting when nobody on the realm can disenchant', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    const { unmount } = renderWithProviders(<SearchTab />)
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('You do not have a disenchanter')
    expect(alert).toHaveTextContent(
      'Making a character with Enchanting can significantly increase your profits and can be done at level 1',
    )
    unmount()
  })

  it('suggests making an enchanter when skilling up too, since what is made is disenchanted when it can be', async () => {
    at(TAILOR)
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText('You do not have a disenchanter')).toBeInTheDocument()
  })

  it('says nothing about Enchanting with an enchanter, or when browsing', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': withEnchanter,
      '/api/rank': noResults,
    })
    const { unmount } = renderWithProviders(<SearchTab />)
    await screen.findByText(/No recipes match these filters/)
    expect(screen.queryByText('You do not have a disenchanter')).not.toBeInTheDocument()
    unmount()

    const shared = { realm: 'Classic Beta PvE', faction: '' }
    mockApi({
      '/api/status': status({ characters: 0, selection: shared }),
      '/api/characters': { groups: [], selection: shared },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText(/No characters uploaded for this realm/)
    expect(screen.queryByText('You do not have a disenchanter')).not.toBeInTheDocument()
  })

  it('ranks with the stored parameters', async () => {
    localStorage.setItem('altarmy.search.unlearned', '"train"')
    localStorage.setItem('altarmy.search.lookAhead', '15')
    localStorage.setItem('altarmy.search.sources', JSON.stringify(['bop', 'trainer']))
    localStorage.setItem('altarmy.search.includeTrivial', 'false')
    localStorage.setItem('altarmy.search.open', JSON.stringify(['advanced', 'characters']))
    localStorage.setItem('altarmy.search.exits', JSON.stringify(['ah', 'vendor']))
    localStorage.setItem('altarmy.search.minCost', JSON.stringify(0.5))
    localStorage.setItem('altarmy.search.maxCost', JSON.stringify(20))
    localStorage.setItem('altarmy.search.minRoi', 'null')
    localStorage.setItem('altarmy.search.maxRoi', JSON.stringify(250))
    localStorage.setItem('altarmy.search.minConfidence', '"medium"')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByLabelText('Min cost (gold)')).toHaveValue('0.5')
    // neither price confidence nor the sale verdict filters any more: the two ways to sell show side by side
    expect(screen.queryByLabelText('Minimum sale verdict', { selector: 'input' })).not.toBeInTheDocument()
    expect(screen.getByLabelText('Max cost (gold)')).toHaveValue('20')
    expect(screen.getByLabelText('Min profit (gold)')).toHaveValue('0.0001')
    expect(screen.getByLabelText('Min ROI (%)')).toHaveValue('')
    // no Sell via: making gold sells every way, and the stored exits are passed over
    expect(screen.queryByRole('checkbox', { name: 'Auction house' })).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox', { name: 'Vendor' })).not.toBeInTheDocument()
    // making gold ranks every recipe the characters know: none of the skill-up options
    expect(screen.queryByRole('radio', { name: 'Include recipes I can train' })).not.toBeInTheDocument()
    expect(
      screen.queryByRole('checkbox', {
        name: 'Show only recipes that can give a skill up',
      }),
    ).not.toBeInTheDocument()
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    expect(screen.queryByRole('button', { name: /^Characters/ })).not.toBeInTheDocument()
    await screen.findByText(/No recipes match these filters/)
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.toString()).toBe(
      'game_version=forever&unlearned=none&include_trivial=true&exits=vendor&exits=disenchant&exits=ah&arcane_salvager=false&min_cost=5000&max_cost=200000&min_profit=1&max_roi=2.5&sort=likely&top=50&price_version=0',
    )
  })

  it('skills up with the stored skill options', async () => {
    at(TAILOR)
    localStorage.setItem('altarmy.search.sources', JSON.stringify(['bop', 'trainer'])) // from before
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': withEnchanter,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await openOptions()
    expect(await screen.findByRole('checkbox', { name: 'Taught by trainers' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Taught by normal recipes' })).not.toBeChecked()
    expect(
      screen.getByRole('checkbox', {
        name: 'Taught by bind on pickup recipes',
      }),
    ).toBeChecked()
    await screen.findByText('No path was found for Tailor Guy to gain skill in Tailoring')
    const [rank] = urls(fetch, '/api/rank')
    expect(rank?.searchParams.getAll('sources')).toEqual(['trainer', 'bop'])
    expect(rank?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant', 'keep'])
  })

  it('keeps the filters of making gold and of skilling up apart', { timeout: 15_000 }, async () => {
    at(TAILOR)
    // from before the two were kept apart: making gold starts there
    localStorage.setItem('altarmy.search.exits', JSON.stringify(['ah', 'vendor']))
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': withEnchanter,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const exitsSent = () => urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('exits')
    const sourcesSent = () => urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('sources')
    await waitFor(() => expect(exitsSent()).toEqual(['vendor', 'disenchant', 'keep']))
    await openOptions()
    await userEvent.click(await screen.findByRole('checkbox', { name: 'Taught by trainers' }))
    await waitFor(() => expect(sourcesSent()).toEqual(['recipe']))

    act(() => navigate('/profit/gold'))
    await waitFor(() => expect(exitsSent()).toEqual(['vendor', 'disenchant', 'ah'])) // every way, whatever was stored
    expect(localStorage.getItem('altarmy.search.skill.sources')).toBe('["recipe"]') // untouched by gold

    // back to skilling up: what may teach its recipes, as the user left it
    act(() => window.history.back())
    await waitFor(() => expect(exitsSent()).toEqual(['vendor', 'disenchant', 'keep']))
    expect(sourcesSent()).toEqual(['recipe'])
  })

  it('hides the Arcane Salvager checkbox and never counts on one while it is hidden', async () => {
    if (SHOW_ARCANE_SALVAGER) return
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': { ...characters, arcane_salvager: true },
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText(/No recipes match these filters/)
    expect(
      screen.queryByRole('checkbox', {
        name: 'Use Arcane Salvager for disenchanting',
      }),
    ).toBeNull()
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('arcane_salvager')).toBe('false')
  })

  it.skipIf(!SHOW_ARCANE_SALVAGER)(
    'disenchants at an Arcane Salvager when a character can make one, until the user says otherwise',
    async () => {
      const salvager = () => urls(fetch, '/api/rank').at(-1)?.searchParams.get('arcane_salvager')
      let fetch = mockApi({
        '/api/status': status(),
        '/api/characters': characters,
        '/api/rank': noResults,
      })
      const { unmount } = renderWithProviders(<SearchTab />)
      const box = () =>
        screen.getByRole('checkbox', {
          name: 'Use Arcane Salvager for disenchanting',
        })
      await screen.findByText(/No recipes match these filters/)
      expect(box()).not.toBeChecked()
      expect(salvager()).toBe('false')
      unmount()

      fetch = mockApi({
        '/api/status': status(),
        '/api/characters': { ...characters, arcane_salvager: true },
        '/api/rank': noResults,
      })
      renderWithProviders(<SearchTab />)
      await screen.findByText(/No recipes match these filters/)
      expect(box()).toBeChecked()
      expect(box()).toHaveAccessibleDescription(
        '10% chance of extra disenchanting materials. Usable only at campfires.',
      )
      expect(salvager()).toBe('true')
      expect(urls(fetch, '/api/rank')).toHaveLength(1)
      await userEvent.click(box())
      await waitFor(() => expect(salvager()).toBe('false'))
      expect(localStorage.getItem('altarmy.search.arcaneSalvager')).toBe('false')
    },
  )

  it('saves the crafts per session on the server, then ranks again, and shows no time settings', async () => {
    const config = {
      ah_search: 8,
      ah_buy: 4,
      ah_post: 6,
      vendor_buy: 2,
      vendor_sell: 1.5,
      mail_send: 8,
      mail_attach: 2,
      mail_open: 3,
      mail_attachments: 12,
      switch_character: 45,
      disenchant: 3.5,
      craft_overhead: 0.5,
      batch: 10,
      time_value: 0,
      run_speed: 7,
      detour: 1.3,
    }
    const city = (name: string, faction: string) => ({
      name,
      faction,
      hub: 'Auctioneer',
      locations: 9,
      vendors: 3,
    })
    const settings = {
      cities: [city('Orgrimmar', 'Horde'), city('Thunder Bluff', 'Horde')],
      city: null,
      active: null,
      config,
      defaults: config,
    }
    // The server answers with what it stored.
    const saved: object[] = []
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/time': async (_: URL, request: Request) => {
        if (request.method !== 'PUT') return settings
        const body = (await request.json()) as {
          city: string | null
          config: object
        }
        saved.push(body)
        return {
          ...settings,
          city: body.city,
          config: { ...config, ...body.config },
        }
      },
    })
    renderWithProviders(<SearchTab />)
    // Crafts per session is one of the search's options; the other time settings are not shown.
    const batch = await screen.findByLabelText('Crafts per session')
    expect(screen.queryByRole('button', { name: 'Time assumptions' })).not.toBeInTheDocument()
    for (const gone of ['Craft Location', 'Open a mail', 'Run speed (yards per second)']) {
      expect(screen.queryByLabelText(gone)).not.toBeInTheDocument()
    }
    const ranked = urls(fetch, '/api/rank').length
    fireEvent.change(batch, { target: { value: '5' } })
    await waitFor(() => expect(saved).toEqual([{ city: null, config: { batch: 5 } }]), { timeout: 3000 })
    await waitFor(() => expect(urls(fetch, '/api/rank').length).toBeGreaterThan(ranked))
    expect(batch).toHaveValue('5')
  })

  it('folds the options into a closed Filters section on small screens', async () => {
    const real = window.matchMedia
    // Only the query for "narrower than sm" matches.
    window.matchMedia = (query: string) => ({
      ...real(query),
      matches: query.startsWith('not all'),
    })
    try {
      mockApi({
        '/api/status': status(),
        '/api/characters': characters,
        '/api/rank': noResults,
      })
      renderWithProviders(<SearchTab />)
      const filters = await screen.findByRole('button', { name: 'Filters' })
      expect(filters).toHaveAttribute('aria-expanded', 'false')
      expect(screen.getByRole('checkbox', { name: 'Include recipes I could learn', hidden: true })).not.toBeVisible()
      await userEvent.click(filters)
      expect(filters).toHaveAttribute('aria-expanded', 'true')
      expect(screen.getByRole('checkbox', { name: 'Include recipes I could learn' })).toBeVisible()
    } finally {
      window.matchMedia = real
    }
  })

  it('opens the Filters section on large screens, and it folds', async () => {
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByRole('checkbox', { name: 'Include recipes I could learn' })).toBeVisible()
    const filters = screen.getByRole('button', { name: 'Filters' })
    expect(filters).toHaveAttribute('aria-expanded', 'true')
    await userEvent.click(filters)
    expect(filters).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('checkbox', { name: 'Include recipes I could learn', hidden: true })).not.toBeVisible()
  })

  it('opens and closes Advanced Filters, remembering it, and ignores sections that are gone', async () => {
    localStorage.setItem('altarmy.search.open', JSON.stringify(['characters']))
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const advanced = await screen.findByRole('button', {
      name: 'Advanced Filters',
    })
    expect(advanced).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(advanced)
    expect(advanced).toHaveAttribute('aria-expanded', 'true')
    expect(localStorage.getItem('altarmy.search.gold.open')).toBe('["advanced"]')
    await userEvent.click(advanced)
    expect(localStorage.getItem('altarmy.search.gold.open')).toBe('[]')
  })

  it('sells every way, even when none was ticked before', async () => {
    localStorage.setItem('altarmy.search.gold.exits', '[]')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await screen.findByText(/No recipes match these filters/)
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('exits')).toEqual(['vendor', 'disenchant', 'ah'])
  })

  it('shows 50 more results at a time', { timeout: 15_000 }, async () => {
    table.stub = true
    // As many results as asked for, out of 120.
    const rank = (url: URL) => {
      const top = Math.min(Number(url.searchParams.get('top')), 120)
      const results = Array.from({ length: top }, (_, i) => ({
        ...robeResult,
        recipe_id: i,
      }))
      return { results, total: 120, items: {}, classes: {} }
    }
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': rank,
    })
    renderWithProviders(<SearchTab />)
    const slow = { timeout: 5000 }
    expect(await screen.findByText('Showing 50 of 120', {}, slow)).toBeInTheDocument()
    expect(screen.getByText('50 rows')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show more' }))
    expect(await screen.findByText('Showing 100 of 120', {}, slow)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Show more' }))
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Show more' })).not.toBeInTheDocument(), slow)
    expect(screen.getByText('120 rows')).toBeInTheDocument()
    expect(urls(fetch, '/api/rank').map((u) => u.searchParams.get('top'))).toEqual(['50', '100', '150'])
  })

  it('switches realm on the server', async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
      '/api/selection': status({
        selection: { realm: 'Dreamscythe', faction: 'Horde' },
      }),
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    await userEvent.click(realm())
    await userEvent.click(
      await screen.findByRole('option', {
        name: 'Dreamscythe (Horde) · 2 characters',
      }),
    )
    await waitFor(() => expect(urls(fetch, '/api/selection')).toHaveLength(1))
    const put = fetch.mock.calls.map(([r]) => r).find((r) => new URL(r.url).pathname === '/api/selection')
    expect(put?.method).toBe('PUT')
    expect(await put?.json()).toEqual({
      realm: 'Dreamscythe',
      faction: 'Horde',
    })
    await waitFor(() => expect(realm()).toHaveValue('Dreamscythe (Horde) · 2 characters'))
  })

  it('switches to a realm with prices but no characters', async () => {
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [house('Classic Beta PvE', ''), house('Atiesh', '')],
      '/api/rank': noResults,
      '/api/selection': status({ selection: { realm: 'Atiesh', faction: '' } }),
    })
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(realm()).toHaveValue('Classic Beta PvE (Horde) · 1 character'))
    await userEvent.click(realm())
    expect(
      screen.queryByRole('option', {
        name: 'Classic Beta PvE (both factions)',
      }),
    ).not.toBeInTheDocument()
    await userEvent.click(await screen.findByRole('option', { name: 'Atiesh (both factions)' }))
    await waitFor(() => expect(urls(fetch, '/api/selection')).toHaveLength(1))
    const put = fetch.mock.calls.map(([r]) => r).find((r) => new URL(r.url).pathname === '/api/selection')
    expect(await put?.json()).toEqual({ realm: 'Atiesh', faction: '' })
  })

  it('offers what may teach the recipes skilled up on', async () => {
    at(TAILOR)
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await openOptions()
    const taught = await screen.findByRole('group', {
      name: 'Recipes taught by',
    })
    const boxes = within(taught).getAllByRole<HTMLInputElement>('checkbox')
    expect(boxes.map((c) => [c.closest('.mantine-Checkbox-root')?.textContent, c.checked])).toEqual([
      ['Taught by trainers', true],
      ['Taught by normal recipes', true],
      ['Taught by bind on pickup recipes', false],
    ])
    expect(
      within(taught).getByRole('checkbox', {
        name: 'Taught by normal recipes',
      }),
    ).toHaveAccessibleDescription(
      'Includes recipes sold by vendors (even if they are bind-on-pickup) and non-soulbound recipes you could find on the auction house.',
    )
    expect(screen.queryByText('What is made')).not.toBeInTheDocument()
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    fireEvent.click(
      within(taught).getByRole('checkbox', {
        name: 'Taught by bind on pickup recipes',
      }),
    )
    fireEvent.click(within(taught).getByRole('checkbox', { name: 'Taught by trainers' }))
    expect(localStorage.getItem('altarmy.search.skill.sources')).toBe('["recipe","bop"]')
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(2))
    expect(urls(fetch, '/api/rank')[1]?.searchParams.getAll('sources')).toEqual(['recipe', 'bop'])
    expect(screen.queryByRole('slider')).not.toBeInTheDocument() // only what can be trained now
  })

  it('no longer asks what to plan for: the strategies side by side say', async () => {
    at(TAILOR)
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await openOptions()
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    expect(screen.queryByRole('radiogroup', { name: 'Plan for' })).not.toBeInTheDocument()
    expect(urls(fetch, '/api/rank')[0]?.searchParams.get('effort')).toBeNull()
  })

  it('asks how sure the materials bought for a run should be to reach its target, saying what that means', async () => {
    at(TAILOR)
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    await openOptions()
    const chance = await screen.findByRole('textbox', { name: 'Chance to reach target skill' })
    expect(chance).toHaveValue('75%')
    // the info icon beside the label says what it means
    const info = chance.closest('.mantine-InputWrapper-root')!.querySelector('label [aria-hidden="true"]')!
    await userEvent.hover(info)
    expect(await screen.findByText(/Since skill ups are random/)).toHaveTextContent(
      'so you have a 75% chance to reach the target skill level' +
        "Put another way: 75% of the time, you won't need to make a second trip to the auction house",
    )
    await waitFor(() => expect(urls(fetch, '/api/rank')).toHaveLength(1))
    fireEvent.change(chance, { target: { value: '95' } })
    expect(localStorage.getItem('altarmy.search.skill.reachTarget')).toBe('95')
    expect(screen.getByText(/Since skill ups are random/)).toHaveTextContent(/so you have a 95% chance.*95% of the time/)
    fireEvent.change(chance, { target: { value: '100' } })
    fireEvent.blur(chance)
    expect(chance).toHaveValue('95%') // at most 95%
    // only the checklist follows it: the ranking isn't asked for again
    expect(urls(fetch, '/api/rank')).toHaveLength(1)
  })

  it('saves changed parameters and ignores malformed stored values', async () => {
    localStorage.setItem('altarmy.search.maxProfit', 'garbage')
    localStorage.setItem('altarmy.search.exits', '["trade"]')
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    const maxProfit = await screen.findByLabelText('Max profit (gold)')
    expect(maxProfit).toHaveValue('')
    fireEvent.change(maxProfit, { target: { value: '40' } })
    expect(localStorage.getItem('altarmy.search.gold.maxProfit')).toBe('40')
    fireEvent.change(maxProfit, { target: { value: '' } })
    expect(localStorage.getItem('altarmy.search.gold.maxProfit')).toBe('null')
  })
})

describe('SearchTab: making gold', () => {
  beforeEach(() => at(GOLD))
  const scanned = (watched: number) => ({
    ...house('Classic Beta PvE', 'Horde'),
    watched_hours: watched,
  })

  it('sorts on the server by the headings, either way round, else by the better of the two', async () => {
    localStorage.setItem('altarmy.search.gold.sort', '"spend"') // a sort from before: the default now
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/rank': { ...noResults, results: [robeResult], total: 1 },
    })
    renderWithProviders(<SearchTab />)
    const sent = () => urls(fetch, '/api/rank').at(-1)?.searchParams
    const sorted = () => `${sent()?.get('sort')} ${sent()?.get('order') ?? 'desc'}`
    await screen.findByRole('button', { name: 'Sort by Safe profit' })
    expect(sorted()).toBe('likely desc')
    expect(screen.queryByRole('combobox', { name: 'Sort by' })).not.toBeInTheDocument() // the headings do it
    await userEvent.click(screen.getByRole('button', { name: 'Sort by Safe profit' }))
    await waitFor(() => expect(sorted()).toBe('safe desc'))
    await userEvent.click(screen.getByRole('button', { name: 'Sort by Safe profit' }))
    await waitFor(() => expect(sorted()).toBe('safe asc'))
    expect(localStorage.getItem('altarmy.search.gold.order')).toBe('"asc"')
    await userEvent.click(screen.getByRole('button', { name: 'Sort by Auction profit' }))
    await waitFor(() => expect(sorted()).toBe('ah desc'))
    expect(urls(fetch, '/api/rank').at(-1)?.searchParams.has('min_verdict')).toBe(false)
    await userEvent.click(screen.getByRole('checkbox', { name: 'Include recipes I could learn' }))
    await waitFor(() => expect(urls(fetch, '/api/rank').at(-1)?.searchParams.get('unlearned')).toBe('train'))
  })

  it("asks for a scan where nobody has made one, and says when sales aren't watched", async () => {
    const never = { ...scanned(0), last_scan: null }
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [never],
      '/api/rank': noResults,
    })
    const { unmount } = renderWithProviders(<SearchTab />)
    expect(await screen.findByText("Nobody has scanned this realm's auction house yet")).toBeInTheDocument()
    expect(screen.queryByText(/Sales aren't watched here yet/)).not.toBeInTheDocument()
    unmount()

    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/coverage': [scanned(0.3)],
      '/api/rank': noResults,
    })
    renderWithProviders(<SearchTab />)
    expect(await screen.findByText("Sales aren't watched here yet (0.3 h this week)")).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Dismiss' }))
    expect(screen.queryByText(/Sales aren't watched here yet/)).not.toBeInTheDocument()
    expect(localStorage.getItem('altarmy.notice.unwatched.1')).toBe('true')
  })
})

describe('SearchTab: enhancing items for the skill point alone', () => {
  const NAME = 'Enhance item for skill up only'
  const api = () =>
    mockApi({
      '/api/status': status(),
      '/api/characters': {
        ...withEnchanter,
        groups: withEnchanter.groups.map((g) => ({
          ...g,
          characters: g.characters.map((c) =>
            c.name === 'Enchy'
              ? {
                  ...c,
                  professions: [
                    ...c.professions,
                    {
                      name: 'Engineering',
                      rank: 280,
                      max_rank: 300,
                      recipes: 0,
                    },
                  ],
                }
              : c,
          ),
        })),
      },
      '/api/professions': ['Enchanting', 'Engineering', 'Tailoring'],
      '/api/rank': noResults,
    })
  const exitsSent = (fetch: ReturnType<typeof mockApi>) => urls(fetch, '/api/rank').at(-1)?.searchParams.getAll('exits')

  it.each([['Enchanting'], ['Engineering']])(
    'always ranks casts for the skill point while %s is skilled up, with nothing to tick',
    async (profession) => {
      at(`/profit/skill/classic-beta-pve-horde/Enchy/${profession.toLowerCase()}`)
      const fetch = api()
      renderWithProviders(<SearchTab />)
      await waitFor(() => expect(exitsSent(fetch)).toEqual(['vendor', 'disenchant', 'keep', 'skill']))
      expect(screen.queryByRole('checkbox', { name: NAME })).not.toBeInTheDocument()
    },
  )

  it('never sends them for another profession, even if the old option was ticked', async () => {
    at(TAILOR)
    localStorage.setItem('altarmy.search.skill.skillOnly', 'true')
    const fetch = api()
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(exitsSent(fetch)).toEqual(['vendor', 'disenchant', 'keep']))
    expect(screen.queryByRole('checkbox', { name: NAME })).not.toBeInTheDocument()
  })

  it('is never offered when making gold', async () => {
    at(GOLD)
    localStorage.setItem('altarmy.search.skillOnly', 'true')
    const fetch = api()
    renderWithProviders(<SearchTab />)
    await waitFor(() => expect(exitsSent(fetch)).toEqual(['vendor', 'disenchant', 'ah']))
    expect(screen.queryByRole('checkbox', { name: NAME })).not.toBeInTheDocument()
  })
})
