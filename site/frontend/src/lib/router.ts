import { useSyncExternalStore, type MouseEvent } from 'react'

/** The site's pages. Hosting (and the local server) serve index.html for each, so they are real paths; a page may
 * have paths under it (`/profit/gold`), which are still that page. */
export const ROUTES = ['/', '/addon', '/profit', '/manage', '/admin'] as const
export type Route = (typeof ROUTES)[number]

const listeners = new Set<() => void>()

function subscribe(listener: () => void) {
  listeners.add(listener)
  window.addEventListener('popstate', listener)
  return () => {
    listeners.delete(listener)
    window.removeEventListener('popstate', listener)
  }
}

/** A path without its trailing slashes ("/" stays). */
const normalized = (pathname: string) => (pathname.length > 1 ? pathname.replace(/\/+$/, '') || '/' : pathname)

/** The page for a path (a path under a page is that page); anything unknown is the main page. */
export function routeOf(pathname: string): Route {
  const path = normalized(pathname)
  return ROUTES.find((r) => r === path || (r !== '/' && path.startsWith(`${r}/`))) ?? '/'
}

/** The current page; re-renders on navigation and the browser's back and forward buttons. */
export function useRoute(): Route {
  return useSyncExternalStore(subscribe, () => routeOf(window.location.pathname))
}

/** The current path, without trailing slashes: for a page that shows different things at paths under it. */
export function usePath(): string {
  return useSyncExternalStore(subscribe, () => normalized(window.location.pathname))
}

/** A query string parameter of the current URL (null when absent); re-renders when it changes. */
export function useSearchParam(name: string): string | null {
  return useSyncExternalStore(subscribe, () => new URLSearchParams(window.location.search).get(name))
}

/** Set (or with null, drop) a query string parameter, in place of the current history entry and without scrolling:
 * a filter's state, not a new page. */
export function setSearchParam(name: string, value: string | null) {
  const params = new URLSearchParams(window.location.search)
  if (value === null) params.delete(name)
  else params.set(name, value)
  const search = params.toString()
  navigate(`${window.location.pathname}${search ? `?${search}` : ''}`, { replace: true })
}

// The page shown now and the one before it (null on the first), so a page can tell where the visitor came from.
let shown: Route = routeOf(window.location.pathname)
let previous: Route | null = null

/** The page shown before the current one: null until the visitor has moved. */
export function previousRoute(): Route | null {
  return previous
}

/** Records a move to the page now at `window.location` (from `navigate` and the back and forward buttons). */
function moved() {
  const now = routeOf(window.location.pathname)
  if (now === shown) return
  previous = shown
  shown = now
}

window.addEventListener('popstate', moved)

/**
 * Go to a path, adding a history entry; with `replace`, in place of the current one (a redirect: the back button then
 * skips it), and without scrolling to the top.
 */
export function navigate(to: string, { replace = false }: { replace?: boolean } = {}) {
  if (`${window.location.pathname}${window.location.search}` !== to) {
    if (replace) window.history.replaceState(null, '', to)
    else window.history.pushState(null, '', to)
  }
  moved()
  if (!replace) window.scrollTo?.({ top: 0 })
  listeners.forEach((l) => l())
}

/**
 * Props that make an anchor (or a Mantine Anchor/Button with `component="a"`) navigate within the app: a real
 * `href`, so modified clicks (new tab, copy link) still work, and plain left clicks handled here.
 */
export function linkProps(to: string) {
  return {
    href: to,
    onClick: (e: MouseEvent<HTMLElement>) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
      e.preventDefault()
      navigate(to)
    },
  }
}

/** Whether a move between these pages carries a showcase card over: the main page's card and the Profit page's banner. */
export function carriesCard(from: Route | null, to: Route): boolean {
  return (from === '/' && to === '/profit') || (from === '/profit' && to === '/')
}
