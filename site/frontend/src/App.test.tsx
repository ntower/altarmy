import { Notifications } from '@mantine/notifications'
import { fireEvent, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { App } from './App'
import { characters, status } from './test/status'
import { ingestion } from './components/AdminTab.test'
import { ADMIN, GUEST, LINKED, mockApi, renderWithProviders } from './test/utils'

vi.mock('./lib/features', () => ({ MAKE_GOLD: true }))

function renderApp() {
  return renderWithProviders(
    <>
      <Notifications />
      <App />
    </>,
  )
}

describe('the shell by tier', () => {
  const hostedApi = () =>
    mockApi({
      '/api/status': status(),
      '/api/characters': characters,
      '/api/ah-blocked': { items: [], details: {} },
      '/api/favorites': { recipes: [] },
      '/api/coverage': [],
      '/api/rank': { results: [], total: 0, items: {}, classes: {} },
    })
  const nav = () => within(screen.getByRole('navigation', { name: 'Pages' })).getAllByRole('link').map((l) => l.textContent)

  it('names the site Alt Army and links the manage and addon pages', async () => {
    hostedApi()
    renderApp()
    expect(screen.getByRole('link', { name: 'Alt Army, main page' })).toHaveAttribute('href', '/')
    expect(nav()).toEqual(['Manage'])
    expect(screen.queryByRole('radiogroup', { name: 'Game version' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('link', { name: 'Get the Addon' }))
    expect(await screen.findByRole('article', { name: 'CurseForge' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/addon')
  })

  it("leads from the main page's addon card to the addon page", async () => {
    hostedApi()
    window.history.pushState(null, '', '/')
    renderApp()
    fireEvent.click(screen.getByRole('link', { name: 'Alt Army' }))
    expect(await screen.findByRole('article', { name: 'CurseForge' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/addon')
  })

  it('opens with the two showcase cards, the profit one leading to the search', async () => {
    hostedApi()
    renderApp()
    expect(screen.getByRole('link', { name: 'Alt Army' })).toHaveAttribute('href', '/addon')
    fireEvent.click(screen.getByRole('link', { name: 'Put your army to work' }))
    expect(window.location.pathname).toBe('/profit')
    expect(await screen.findByRole('button', { name: /^3 characters,/ })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('link', { name: 'Alt Army, main page' }))
    expect(await screen.findByRole('link', { name: 'Put your army to work' })).toBeInTheDocument()
  })

  it('opens a path under the profit page on that page', async () => {
    hostedApi()
    window.history.pushState(null, '', '/profit/gold')
    renderApp()
    expect(await screen.findByRole('region', { name: 'Realm' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /^3 characters,/ })).toBeInTheDocument()
  })

  it('gives anonymous users everything, with a way to sign in', async () => {
    hostedApi()
    window.history.pushState(null, '', '/profit')
    renderWithProviders(<App />, GUEST)
    expect(nav()).toEqual(['Manage'])
    expect(screen.getByRole('button', { name: 'Sign in' })).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: /^3 characters,/ })).toBeInTheDocument() // theirs, ready to rank
    expect(screen.queryByText(/guest/i)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('link', { name: 'Manage' }))
    expect(await screen.findByText('Never sold on the auction house')).toBeInTheDocument()
    expect(screen.getByText(/create one with Sign in \(top right\)/)).toBeInTheDocument()
  })

  it('gives signed-in users their AH blocks and Alt Army Sync', async () => {
    hostedApi()
    window.history.pushState(null, '', '/manage')
    renderWithProviders(<App />, LINKED)
    expect(screen.queryByRole('button', { name: 'Sign in' })).not.toBeInTheDocument()
    expect(await screen.findByText('Never sold on the auction house')).toBeInTheDocument()
    expect(screen.getByText('Upload automatically')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Alt Army Sync for Windows' })).toBeInTheDocument()
  })

  it('links the admin page for site admins only', async () => {
    const fetch = hostedApi()
    window.history.pushState(null, '', '/admin')
    const { unmount } = renderWithProviders(<App />, LINKED)
    expect(nav()).toEqual(['Manage'])
    expect(await screen.findByText(/This page is for site admins/)).toBeInTheDocument()
    expect(fetch.mock.calls.map(([r]) => new URL(r.url).pathname)).not.toContain('/api/admin/ingestion')
    unmount()

    mockApi({ '/api/status': status(), '/api/admin/ingestion': ingestion })
    window.history.pushState(null, '', '/manage')
    renderWithProviders(<App />, ADMIN)
    expect(nav()).toEqual(['Manage', 'Admin'])
    fireEvent.click(screen.getByRole('link', { name: 'Admin' }))
    expect(window.location.pathname).toBe('/admin')
    expect(await screen.findByRole('table', { name: 'Jobs' })).toBeInTheDocument()
  })
})

describe('theme toggle', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('switches between the dark and light schemes', () => {
    mockApi({ '/api/status': status(), '/api/characters': characters })
    renderApp()
    const root = document.documentElement
    const before = root.getAttribute('data-mantine-color-scheme')
    const toggle = screen.getByRole('button', { name: /Switch to (light|dark) theme/ })
    fireEvent.click(toggle)
    const after = root.getAttribute('data-mantine-color-scheme')
    expect(after).not.toBe(before)
    expect(screen.getByRole('button', { name: `Switch to ${before} theme` })).toBeInTheDocument()
  })
})
