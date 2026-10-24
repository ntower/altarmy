import { Notifications } from '@mantine/notifications'
import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { UploadResult } from '../api/client'
import { characters, status } from '../test/status'
import { ADMIN, GUEST, mockApi, renderWithProviders } from '../test/utils'
import { navigate } from '../lib/router'
import { SYNC_DOWNLOAD } from './SyncCard'
import { ProfitPage } from './Profit'

// Making gold switched on, as these tests walk it, except where a test switches it off.
const features = vi.hoisted(() => ({ makeGold: true }))
vi.mock('../lib/features', () => ({
  get MAKE_GOLD() {
    return features.makeGold
  },
  STRATEGY_PICKER: false,
  PROCESSING: false,
  VENDOR_RUNS: false,
  WHAT_I_HOLD: false,
}))
afterEach(() => {
  features.makeGold = true
})

const noResults = { results: [], total: 0, items: {}, classes: {} }
const nobody = { groups: [], selection: { realm: 'Classic Beta PvE', faction: '' } }
const imported: UploadResult = {
  kind: 'altarmy',
  detail: '',
  characters: 3,
  groups: [{ realm: 'Classic Beta PvE', faction: 'Horde', characters: 1 }],
  realms: [],
}

function paths(fetch: ReturnType<typeof mockApi>, pathname: string) {
  return fetch.mock.calls.map(([r]) => r).filter((r) => new URL(r.url).pathname === pathname)
}

const cards = () => screen.queryByRole('group', { name: 'Ways to start' })
const hero = () => screen.queryByRole('heading', { name: 'Put your army to work' })

describe('ProfitPage', () => {
  it('welcomes a new visitor with the banner, three ways to start and no search yet', async () => {
    const fetch = mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody })
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('heading', { name: 'Put your army to work' })).toBeInTheDocument()
    expect(screen.getByText(/steps through all of your characters/)).toBeInTheDocument()
    const group = await screen.findByRole('group', { name: 'Ways to start' })
    expect(within(group).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual([
      'Upload your characters',
      'Auto-upload',
      'Skip for now',
    ])
    expect(screen.queryByRole('region', { name: 'Search' })).not.toBeInTheDocument()
    expect(paths(fetch, '/api/rank')).toEqual([])
  })

  it('arriving from the main page, shows the banner at once and folds it away once the characters load', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    navigate('/')
    navigate('/profit')
    try {
      renderWithProviders(<ProfitPage />)
      // before the characters answer: the main page's card has somewhere to land
      expect(hero()).toBeInTheDocument()
      expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
      await waitFor(() => expect(hero()).not.toBeInTheDocument())
    } finally {
      navigate('/manage') // the other tests arrive from elsewhere
    }
  })

  it('skipping folds the cards away, asks the setup questions, then ranks, remembering both', async () => {
    window.history.replaceState(null, '', '/profit') // so the back button comes back here
    const fetch = mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody, '/api/rank': noResults })
    const { unmount } = renderWithProviders(<ProfitPage />)
    await userEvent.click(await screen.findByRole('button', { name: 'Skip for now' }))
    const search = await screen.findByRole('region', { name: 'Search' })
    expect(await screen.findByText('No characters uploaded.')).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    await waitFor(() => expect(hero()).not.toBeInTheDocument())
    expect(JSON.parse(localStorage.getItem('altarmy.landing.g1') ?? '')).toEqual({ browsed: true })
    // nothing is ranked until the setup is complete; skilling up is open without characters too (one is made up)
    const aims = within(search).getByRole('group', { name: "What's your goal?" })
    expect(within(aims).getByRole('button', { name: 'Skill up' })).toBeEnabled()
    // making gold asks nothing more: its own path, where the list shows both ways to sell
    await userEvent.click(within(aims).getByRole('button', { name: 'Make gold' }))
    expect(window.location.pathname).toBe('/profit/gold')
    await waitFor(() => expect(paths(fetch, '/api/rank')).toHaveLength(1))
    expect(screen.queryByRole('group', { name: "What's your goal?" })).not.toBeInTheDocument()
    expect(new URL(paths(fetch, '/api/rank')[0]!.url).searchParams.get('sort')).toBe('likely')
    expect(JSON.parse(localStorage.getItem('altarmy.setup.g1') ?? '')).toEqual({ aim: 'gold' })

    // the back button asks again, the answer given marked
    act(() => window.history.back())
    const again = await screen.findByRole('group', { name: "What's your goal?" })
    expect(within(again).getByRole('button', { name: 'Make gold' })).toHaveAttribute('aria-pressed', 'true')

    unmount()
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('group', { name: "What's your goal?" })).toBeInTheDocument()
    expect(cards()).not.toBeInTheDocument()
    expect(hero()).not.toBeInTheDocument()
  })

  it('with making gold switched off, its card says coming soon and its path goes back to the start', async () => {
    features.makeGold = false
    const fetch = mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    const aims = await screen.findByRole('group', { name: "What's your goal?" })
    expect(within(aims).getByRole('button', { name: 'Make gold' })).toBeDisabled()
    expect(within(aims).getByText('Coming soon')).toBeInTheDocument()
    expect(within(aims).getByRole('button', { name: 'Skill up' })).toBeEnabled()

    act(() => navigate('/profit/gold'))
    await waitFor(() => expect(window.location.pathname).toBe('/profit'))
    expect(paths(fetch, '/api/rank')).toEqual([])
  })

  it('an admin can make gold while it is switched off', async () => {
    features.makeGold = false
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />, ADMIN)
    const aims = await screen.findByRole('group', { name: "What's your goal?" })
    expect(within(aims).getByRole('button', { name: 'Make gold' })).toBeEnabled()
    expect(within(aims).queryByText('Coming soon')).not.toBeInTheDocument()

    act(() => navigate('/profit/gold'))
    await new Promise((r) => setTimeout(r, 50))
    expect(window.location.pathname).toBe('/profit/gold')
  })

  it('without the strategy pages, a strategy path goes back to the gold list, and an old one to its filter', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    window.history.replaceState(null, '', '/profit/gold/craft')
    renderWithProviders(<ProfitPage />)
    await waitFor(() => expect(window.location.pathname).toBe('/profit/gold'))
    act(() => navigate('/profit/gold/disenchant'))
    await waitFor(() => expect(`${window.location.pathname}${window.location.search}`).toBe('/profit/gold'))
  })

  it('skilling up goes on to which profession, at its own path', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    await userEvent.click(await screen.findByRole('button', { name: 'Skill up' }))
    expect(window.location.pathname).toBe('/profit/skill')
    expect(await screen.findByRole('group', { name: 'Which profession?' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /^3 characters/ })).toBeInTheDocument() // the characters above it
    await userEvent.click(screen.getByRole('button', { name: 'Tailoring' }))
    expect(window.location.pathname).toBe('/profit/skill/classic-beta-pve-horde/Tailor%20Guy/tailoring')
  })

  it('shows the characters beside the realm card past the start, across the whole width while uploading', async () => {
    navigate('/profit/gold')
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    const summary = await screen.findByRole('button', { name: /^3 characters/ })
    const realm = await screen.findByRole('region', { name: 'Realm' })
    const strip = summary.closest('[class*="strip"]')!
    expect(strip.parentElement).toBe(realm.parentElement)
    expect(strip).not.toHaveAttribute('data-wide')
    await userEvent.click(screen.getByRole('button', { name: 'Upload again' }))
    const ways = await screen.findByRole('group', { name: 'Ways to start' })
    expect(ways).toHaveAttribute('data-wide')
    expect(ways.parentElement).toBe(realm.parentElement)
    expect(window.location.pathname).toBe('/profit/gold')
  })

  it('takes a path under it that means nothing back to the start', async () => {
    navigate('/profit/nope')
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    await waitFor(() => expect(window.location.pathname).toBe('/profit'))
    expect(await screen.findByRole('group', { name: "What's your goal?" })).toBeInTheDocument()
  })

  it('shows the vendor check at its path, with nothing of the start, and no redirect', async () => {
    navigate('/profit/vendorcheck')
    const fetch = mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/vendorcheck': {
        realm: 'Classic Beta PvE',
        faction: 'Horde',
        items: [],
        total: 0,
        listed: 0,
        page: 1,
        page_size: 50,
        classes: [],
        qualities: [],
      },
    })
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('heading', { name: 'Vendor check' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/profit/vendorcheck')
    expect(cards()).not.toBeInTheDocument()
    expect(hero()).not.toBeInTheDocument()
    expect(paths(fetch, '/api/rank')).toEqual([])
  })

  it('uploads pasted characters, then shows them above the search', async () => {
    let have = false
    const fetch = mockApi({
      '/api/status': () => status({ characters: have ? 3 : 0, data_version: have ? 2 : 1 }),
      '/api/characters': () => (have ? characters : nobody),
      '/api/uploads/paste': () => {
        have = true
        return imported
      },
      '/api/rank': noResults,
    })
    renderWithProviders(
      <>
        <Notifications />
        <ProfitPage />
      </>,
    )
    await userEvent.click(await screen.findByRole('button', { name: 'Upload your characters' }))
    const box = await screen.findByRole('textbox', { name: 'Alt Army export' })
    expect(screen.getByText('/altarmy export')).toBeInTheDocument()
    // the other two ways stay at hand, smaller
    expect(screen.getByRole('button', { name: 'Skip for now' })).toBeInTheDocument()
    expect(screen.getByText('Set up Alt Army Sync.')).toBeInTheDocument()
    expect(screen.getByText('Every recipe, no character optimization.')).toBeInTheDocument()
    await userEvent.type(box, 'AAX1:abc')
    await userEvent.click(screen.getByRole('button', { name: 'Upload characters' }))
    expect(await screen.findByText('Characters uploaded')).toBeInTheDocument()
    expect(await screen.findByText(/^3 characters on Classic Beta PvE/)).toBeInTheDocument()
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    const [post] = paths(fetch, '/api/uploads/paste')
    expect(await post?.json()).toEqual({ text: 'AAX1:abc' })
  })

  it('starts folded with the search when the user already has characters, and sets up auto-upload', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('region', { name: 'Search' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '3 characters, Auto-upload off' })).toBeInTheDocument()
    expect(cards()).not.toBeInTheDocument()
    expect(hero()).not.toBeInTheDocument()
    // the strip has no Auto-upload of its own: it is one of the start cards Upload again opens
    expect(screen.queryByRole('button', { name: 'Auto-upload' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Upload again' }))
    expect(await screen.findByRole('group', { name: 'Ways to start' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Auto-upload' }))
    expect(await screen.findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    expect(screen.getByText(/never changes a game file/)).toBeInTheDocument()
    expect(screen.getByText('Signed in.')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Sign in to the app' })).toBeInTheDocument()
    expect(screen.getByText(/never your password/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Download Alt Army Sync' })).toHaveAttribute('href', SYNC_DOWNLOAD)
    await userEvent.click(screen.getByRole('button', { name: 'Back to the three ways to start' }))
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
  })

  it('offers a guest an account first, which keeps what the browser has', async () => {
    mockApi({ '/api/status': status({ characters: 0 }), '/api/characters': nobody })
    renderWithProviders(<ProfitPage />, GUEST)
    await userEvent.click(await screen.findByRole('button', { name: 'Auto-upload' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Sign in or create an account' }))
    expect(await screen.findByRole('dialog', { name: 'Your account' })).toBeInTheDocument()
    expect(screen.getByText(/tick Create a new account there/)).toBeInTheDocument()
  })

  it("moves on by itself when Alt Army Sync's first upload brings characters in", async () => {
    let have = false
    mockApi({
      '/api/status': () => status({ characters: have ? 3 : 0, data_version: have ? 2 : 1 }),
      '/api/characters': () => (have ? characters : nobody),
      '/api/rank': noResults,
    })
    renderWithProviders(
      <>
        <Notifications />
        <ProfitPage />
      </>,
    )
    await userEvent.click(await screen.findByRole('button', { name: 'Auto-upload' }))
    expect(await screen.findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    have = true
    window.dispatchEvent(new Event('visibilitychange')) // what the status poll would notice
    expect(await screen.findByText('Characters uploaded')).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: /^3 characters/ })).toBeInTheDocument()
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
  })

  it('offers Continue instead of Skip for now once the user has characters', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    await userEvent.click(await screen.findByRole('button', { name: 'Upload again' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Auto-upload' }))
    expect(await screen.findByRole('heading', { name: 'Auto-upload' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Skip for now' })).not.toBeInTheDocument()
    const cont = screen.getByRole('button', { name: 'Continue' })
    expect(within(cont).getByText('Done adding characters.')).toBeInTheDocument()
    await userEvent.click(cont)
    await waitFor(() => expect(cards()).not.toBeInTheDocument())
    expect(screen.getByRole('button', { name: /^3 characters/ })).toBeInTheDocument()
  })

  it('sums up the characters: how many, when they were gathered, and whether auto-upload is on', async () => {
    const utc = (hoursAgo: number) => new Date(Date.now() - hoursAgo * 3_600_000).toISOString().slice(0, 19).replace('T', ' ')
    mockApi({
      '/api/status': status(),
      '/api/characters': { ...characters, imported_at: utc(3), imported_via: 'watcher', auto_import_at: utc(1) },
      '/api/rank': noResults,
    })
    renderWithProviders(<ProfitPage />)
    const summary = await screen.findByRole('button', { name: '3 characters, updated 3 h ago, Auto-upload on' })
    expect(within(summary).queryByText(/Dreamscythe/)).not.toBeInTheDocument()
  })

  it('says auto-upload is off once Alt Army Sync has been quiet for a month', async () => {
    const longAgo = new Date(Date.now() - 31 * 86_400_000).toISOString().slice(0, 19).replace('T', ' ')
    mockApi({
      '/api/status': status(),
      '/api/characters': { ...characters, imported_at: longAgo, imported_via: 'paste', auto_import_at: longAgo },
      '/api/rank': noResults,
    })
    renderWithProviders(<ProfitPage />)
    expect(await screen.findByRole('button', { name: '3 characters, updated 31 days ago, Auto-upload off' })).toBeInTheDocument()
  })

  it('opens the summary to show every character', async () => {
    mockApi({ '/api/status': status(), '/api/characters': characters, '/api/rank': noResults })
    renderWithProviders(<ProfitPage />)
    const summary = await screen.findByRole('button', { name: /^3 characters/ })
    expect(summary).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByText('Tailor Guy')).not.toBeInTheDocument()
    await userEvent.click(summary)
    expect(summary).toHaveAttribute('aria-expanded', 'true')
    expect(await screen.findByText('Tailor Guy')).toBeInTheDocument()
    expect(screen.getByText(/Cooking 1\/75, Tailoring 50\/75/)).toBeInTheDocument()
    expect(screen.getByText('Frell')).toBeInTheDocument() // every realm, not just the selected one
    expect(screen.getByText('Dreamscythe (Horde)')).toBeInTheDocument()

    expect(screen.queryByRole('button', { name: 'Remove Frell' })).not.toBeInTheDocument()

    await userEvent.click(summary)
    await waitFor(() => expect(screen.queryByText('Tailor Guy')).not.toBeInTheDocument())
  })
})
