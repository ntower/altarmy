import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Ingestion } from '../api/client'
import { mockApi, renderWithProviders } from '../test/utils'
import { AdminTab } from './AdminTab'

export const ingestion: Ingestion = {
  now: '2026-09-27 12:00:00',
  jobs: [
    {
      job: 'ingest',
      game_version: null,
      last_started: null,
      last_finished: null,
      ok: null,
      late: true,
      summary: '',
    },
    {
      job: 'merge',
      game_version: null,
      last_started: '2026-09-27 11:30:00',
      last_finished: '2026-09-27 11:30:40',
      ok: true,
      late: false,
      summary: 'Merged 3 auction houses of every game version (1 changed); 90 price observations stored.',
    },
    {
      job: 'prune',
      game_version: null,
      last_started: '2026-09-27 11:59:00',
      last_finished: null,
      ok: null,
      late: false,
      summary: '',
    },
  ],
  runs: [
    {
      id: 7,
      job: 'merge',
      game_version: null,
      started_at: '2026-09-27 11:30:00',
      finished_at: '2026-09-27 11:30:40',
      ok: true,
      summary: 'Merged 3 auction houses',
    },
    {
      id: 6,
      job: 'ahledger', // a run from before the feed was removed
      game_version: null,
      started_at: '2026-09-27 11:20:00',
      finished_at: '2026-09-27 11:21:00',
      ok: false,
      summary: '1 of 4 AHledger markets failed.',
    },
  ],
  uploads: {
    accepted_24h: 4,
    rejected_24h: 1,
    accepted_7d: 20,
    rejected_7d: 2,
    uploaders_7d: 3,
    recent: [
      {
        id: 1,
        game_version: 'forever',
        kind: 'altarmy',
        via: 'watcher',
        size: 2048,
        received_at: '2026-09-27 10:00:00',
        outcome: 'rejected',
        detail: 'Not an Alt Army file',
        user_uid: 'abcdefghijklmnop',
      },
    ],
  },
  snapshots: [
    {
      source: 'altarmy',
      snapshots_24h: 2,
      snapshots_7d: 9,
      quarantined_7d: 1,
      items_7d: 12345,
      newest_received_at: '2026-09-27 10:00:00',
    },
  ],
  can_run: ['ingest'],
}

describe('AdminTab', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('shows each job with its status, lateness and last words', async () => {
    mockApi({ '/api/admin/ingestion': ingestion })
    renderWithProviders(<AdminTab />)
    const jobs = await screen.findByRole('table', { name: 'Jobs' })
    const rows = within(jobs).getAllByRole('row').slice(1)
    expect(rows.map((r) => within(r).getAllByRole('cell')[0]?.textContent)).toEqual([
      'Game data ingest',
      'Price merge',
      'Prune',
    ])
    const [ingest, merge, prune] = rows.map((r) => within(r))
    expect(ingest?.getByText('never')).toBeInTheDocument()
    expect(ingest?.getByText('late')).toBeInTheDocument()
    expect(ingest?.queryByText('running')).not.toBeInTheDocument()
    expect(merge?.getByText('ok')).toBeInTheDocument()
    expect(merge?.getByText('30 min ago')).toHaveAttribute('title', '2026-09-27 11:30:00 UTC')
    expect(prune?.getByText('running')).toBeInTheDocument()
  })

  it('shows the runs, uploads and snapshots', async () => {
    mockApi({ '/api/admin/ingestion': ingestion })
    renderWithProviders(<AdminTab />)
    const runs = await screen.findByRole('table', { name: 'Recent runs' })
    expect(within(runs).getByText('40 s')).toBeInTheDocument()
    expect(within(runs).getByText('1 of 4 AHledger markets failed.')).toBeInTheDocument() // old runs stay
    expect(screen.getByText(/Last 24 hours: 4 accepted, 1 rejected\. Last 7 days: 20 accepted, 2 rejected, from 3 users\./)).toBeInTheDocument()
    const uploads = screen.getByRole('table', { name: 'Uploads' })
    expect(within(uploads).getByText('abcdefgh')).toHaveAttribute('title', 'abcdefghijklmnop')
    expect(within(uploads).getByText('rejected')).toBeInTheDocument()
    expect(within(screen.getByRole('table', { name: 'Price snapshots' })).getByText((12345).toLocaleString())).toBeInTheDocument()
    expect(screen.queryByRole('table', { name: 'AHledger feeds' })).not.toBeInTheDocument()
  })

  it('starts the ingest from its row', async () => {
    const fetch = mockApi({
      '/api/admin/ingestion': ingestion,
      '/api/admin/jobs/ingest': { job: 'ingest', game_version: 'forever', detail: 'Started altarmy-ingest-forever.' },
    })
    renderWithProviders(<AdminTab />)
    const jobs = await screen.findByRole('table', { name: 'Jobs' })
    const [ingestRow, ...others] = within(jobs).getAllByRole('row').slice(1)
    for (const row of others) expect(within(row).queryByRole('button')).not.toBeInTheDocument()
    await userEvent.click(within(ingestRow!).getByRole('button', { name: 'Run now' }))
    await waitFor(() => expect(fetch.mock.calls.some(([r]) => r.method === 'POST')).toBe(true))
    const posted = new URL(fetch.mock.calls.find(([r]) => r.method === 'POST')![0].url)
    expect([posted.pathname, posted.searchParams.get('game_version')]).toEqual(['/api/admin/jobs/ingest', 'forever'])
  })

  it('offers no Run now while the ingest runs, or where the server cannot start it', async () => {
    const running = { ...ingestion.jobs[0]!, last_started: '2026-09-27 11:58:00' }
    mockApi({ '/api/admin/ingestion': { ...ingestion, jobs: [running, ...ingestion.jobs.slice(1)] } })
    const { unmount } = renderWithProviders(<AdminTab />)
    expect(await screen.findByRole('button', { name: 'Run now' })).toBeDisabled()
    unmount()
    mockApi({ '/api/admin/ingestion': { ...ingestion, can_run: [] } })
    renderWithProviders(<AdminTab />)
    await screen.findByRole('table', { name: 'Jobs' })
    expect(screen.queryByRole('button', { name: 'Run now' })).not.toBeInTheDocument()
  })

  it('lists the vendor prices to check in game', async () => {
    mockApi({
      '/api/admin/ingestion': ingestion,
      '/api/admin/vendor-suspects': {
        listed_under: [{ item_id: 3, name: 'Green Robe', vendor: 500, cheapest: 300, units: 2, houses: 4 }],
        moved: [{ item_id: 11287, name: 'Lesser Magic Wand', build: '1.60.2', before: 110, after: 1 }],
        overridden: [{ item_id: 11288, name: 'Greater Magic Wand', vendor: 200 }],
      },
    })
    renderWithProviders(<AdminTab />)
    const under = await screen.findByRole('table', { name: 'Listed under what a vendor pays' })
    expect(within(under).getByText('Green Robe')).toBeInTheDocument()
    expect(within(under).getByText('4')).toBeInTheDocument()
    const moved = screen.getByRole('table', { name: 'Moved by the newest build' })
    expect(within(moved).getByText('Lesser Magic Wand')).toBeInTheDocument()
    expect(screen.getByText('Overridden: Greater Magic Wand')).toBeInTheDocument()
  })

  it('says what went wrong', async () => {
    mockApi({})
    renderWithProviders(<AdminTab />)
    expect(await screen.findByText('no mock for /api/admin/ingestion')).toBeInTheDocument()
  })
})
