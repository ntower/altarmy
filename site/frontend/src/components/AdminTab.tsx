import type { ReactNode } from 'react'
import { Alert, Badge, Button, Card, Group, Loader, Stack, Table, Text, Title } from '@mantine/core'
import type { Ingestion } from '../api/client'
import { useAdminIngestion, useRunIngest, useVendorSuspects } from '../api/queries'
import { age, parseUtc } from '../lib/age'
import { Money } from './Money'

type Job = Ingestion['jobs'][number]
type Run = Ingestion['runs'][number]

const JOB_NAMES: Readonly<Record<string, string>> = {
  ingest: 'Game data ingest',
  merge: 'Price merge',
  prune: 'Prune',
  ahledger: 'AHledger poll',
}

/** When a server timestamp was, relative to the server's `now`, with the exact UTC time on hover. */
function When({ utc, now }: { utc: string | null; now: Date }) {
  if (!utc) return <Text span c="dimmed">never</Text>
  return <span title={`${utc} UTC`}>{age(utc, now)}</span>
}

function RunBadge({
  ok,
  started,
  finished,
}: {
  ok: boolean | null
  started: string | null
  finished: string | null
}) {
  if (started === null) return null // never ran
  if (ok === true) return <Badge color="green" variant="light">ok</Badge>
  if (ok === false) return <Badge color="red" variant="light">failed</Badge>
  return finished === null ? <Badge color="yellow" variant="light">running</Badge> : null
}

/** The summary's last line (where failures are), with the whole of it on hover. */
function Summary({ text }: { text: string }) {
  const last = text.trim().split('\n').at(-1) ?? ''
  return (
    <Text size="sm" title={text || undefined} lineClamp={2}>
      {last}
    </Text>
  )
}

function Section({ title, lead, children }: { title: string; lead?: ReactNode; children: ReactNode }) {
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>{title}</Title>
        {lead && (
          <Text size="sm" c="dimmed">
            {lead}
          </Text>
        )}
        <Table.ScrollContainer minWidth={560}>{children}</Table.ScrollContainer>
      </Stack>
    </Card>
  )
}

/** Whether the job's newest run is still going (the server refuses another until it ends). */
function isRunning(job: Job): boolean {
  return job.last_started !== null && job.last_finished === null && job.ok === null
}

/** Start the ingest now (the only job the server starts on demand). */
function RunNow({ job }: { job: Job }) {
  const ingest = useRunIngest()
  return (
    <Button
      size="compact-sm"
      variant="light"
      title="Load the newest game build now, unless it is loaded already"
      loading={ingest.isPending}
      disabled={isRunning(job)}
      onClick={() => ingest.mutate()}
    >
      Run now
    </Button>
  )
}

function JobsCard({ jobs, now, canRun }: { jobs: readonly Job[]; now: Date; canRun: readonly string[] }) {
  const runnable = canRun.length > 0
  return (
    <Section title="Jobs" lead="Each scheduled job's newest run. Late: it has not run for twice its schedule.">
      <Table aria-label="Jobs">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Job</Table.Th>
            <Table.Th>Last run</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Said</Table.Th>
            {runnable && <Table.Th aria-label="Actions" />}
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {jobs.map((j) => (
            <Table.Tr key={j.job}>
              <Table.Td>{JOB_NAMES[j.job] ?? j.job}</Table.Td>
              <Table.Td>
                <When utc={j.last_started} now={now} />
              </Table.Td>
              <Table.Td>
                <Group gap={4} wrap="nowrap">
                  <RunBadge ok={j.ok} started={j.last_started} finished={j.last_finished} />
                  {j.late && (
                    <Badge color="red" variant="outline">
                      late
                    </Badge>
                  )}
                </Group>
              </Table.Td>
              <Table.Td>
                <Summary text={j.summary} />
              </Table.Td>
              {runnable && <Table.Td>{j.job === 'ingest' && canRun.includes(j.job) && <RunNow job={j} />}</Table.Td>}
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function duration(run: Run): string {
  if (!run.finished_at) return ''
  const seconds = Math.round((parseUtc(run.finished_at) - parseUtc(run.started_at)) / 1000)
  return seconds < 60 ? `${seconds} s` : `${Math.round(seconds / 60)} min`
}

function RunsCard({ runs, now }: { runs: readonly Run[]; now: Date }) {
  if (!runs.length) return null
  return (
    <Section title="Recent runs">
      <Table aria-label="Recent runs">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Started</Table.Th>
            <Table.Th>Job</Table.Th>
            <Table.Th>Took</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Said</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {runs.map((r) => (
            <Table.Tr key={r.id}>
              <Table.Td>
                <When utc={r.started_at} now={now} />
              </Table.Td>
              <Table.Td>
                {JOB_NAMES[r.job] ?? r.job}
                {r.game_version ? ` (${r.game_version})` : ''}
              </Table.Td>
              <Table.Td>{duration(r)}</Table.Td>
              <Table.Td>
                <RunBadge ok={r.ok} started={r.started_at} finished={r.finished_at} />
              </Table.Td>
              <Table.Td>
                <Summary text={r.summary} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function UploadsCard({ uploads, now }: { uploads: Ingestion['uploads']; now: Date }) {
  const lead =
    `Last 24 hours: ${uploads.accepted_24h} accepted, ${uploads.rejected_24h} rejected. ` +
    `Last 7 days: ${uploads.accepted_7d} accepted, ${uploads.rejected_7d} rejected, from ${uploads.uploaders_7d} users.`
  return (
    <Section title="Uploads" lead={lead}>
      <Table aria-label="Uploads">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Received</Table.Th>
            <Table.Th>User</Table.Th>
            <Table.Th>File</Table.Th>
            <Table.Th>Outcome</Table.Th>
            <Table.Th>Detail</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {uploads.recent.map((u) => (
            <Table.Tr key={u.id}>
              <Table.Td>
                <When utc={u.received_at} now={now} />
              </Table.Td>
              <Table.Td>
                <Text size="sm" ff="monospace" title={u.user_uid}>
                  {u.user_uid.slice(0, 8)}
                </Text>
              </Table.Td>
              <Table.Td>
                {u.kind} ({u.via}, {Math.ceil(u.size / 1024).toLocaleString()} KB)
              </Table.Td>
              <Table.Td>
                <Badge color={u.outcome === 'accepted' ? 'green' : 'red'} variant="light">
                  {u.outcome}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Text size="sm" lineClamp={2} title={u.detail}>
                  {u.detail}
                </Text>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

function SnapshotsCard({ snapshots, now }: { snapshots: Ingestion['snapshots']; now: Date }) {
  return (
    <Section title="Price snapshots" lead="Scans recorded in the last 7 days, per source.">
      <Table aria-label="Price snapshots">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Source</Table.Th>
            <Table.Th ta="right">24 hours</Table.Th>
            <Table.Th ta="right">7 days</Table.Th>
            <Table.Th ta="right">Not used (7 days)</Table.Th>
            <Table.Th ta="right">Items (7 days)</Table.Th>
            <Table.Th>Newest</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {snapshots.map((s) => (
            <Table.Tr key={s.source}>
              <Table.Td>{s.source}</Table.Td>
              <Table.Td ta="right">{s.snapshots_24h}</Table.Td>
              <Table.Td ta="right">{s.snapshots_7d}</Table.Td>
              <Table.Td ta="right">{s.quarantined_7d}</Table.Td>
              <Table.Td ta="right">{s.items_7d.toLocaleString()}</Table.Td>
              <Table.Td>
                <When utc={s.newest_received_at} now={now} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Section>
  )
}

/** Vendor prices to check in game: a listing that sits under what a vendor pays says the price may be wrong (on a
 * live realm someone would buy it and vendor it), as does a price the newest build moved. A row in
 * data/<version>/vendor_overrides.csv closes one; nothing here changes a price. */
function VendorSuspectsCard() {
  const suspects = useVendorSuspects(true)
  if (suspects.isPending) return <Loader aria-label="Loading vendor price suspects" />
  if (suspects.isError) return <Alert color="red">{suspects.error.message}</Alert>
  const { listed_under: under, moved, overridden } = suspects.data
  return (
    <Section
      title="Vendor price suspects"
      lead={`${under.length} listed under what a vendor pays, ${moved.length} moved by the newest build, ${overridden.length} overridden. Check them in game; an override in vendor_overrides.csv settles one.`}
    >
      {under.length > 0 && (
        <Table aria-label="Listed under what a vendor pays">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Item</Table.Th>
              <Table.Th ta="right">Vendor pays</Table.Th>
              <Table.Th ta="right">Listed from</Table.Th>
              <Table.Th ta="right">Units</Table.Th>
              <Table.Th ta="right">Houses</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {under.map((s) => (
              <Table.Tr key={s.item_id}>
                <Table.Td>{s.name}</Table.Td>
                <Table.Td ta="right">
                  <Money copper={s.vendor} />
                </Table.Td>
                <Table.Td ta="right">
                  <Money copper={s.cheapest} />
                </Table.Td>
                <Table.Td ta="right">{s.units}</Table.Td>
                <Table.Td ta="right">{s.houses}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
      {moved.length > 0 && (
        <Table aria-label="Moved by the newest build">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Item</Table.Th>
              <Table.Th>Build</Table.Th>
              <Table.Th ta="right">Before</Table.Th>
              <Table.Th ta="right">Now</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {moved.map((s) => (
              <Table.Tr key={s.item_id}>
                <Table.Td>{s.name}</Table.Td>
                <Table.Td>{s.build}</Table.Td>
                <Table.Td ta="right">
                  <Money copper={s.before} />
                </Table.Td>
                <Table.Td ta="right">
                  <Money copper={s.after} />
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
      {overridden.length > 0 && (
        <Text size="sm">
          Overridden: {overridden.map((s) => s.name).join(', ')}
        </Text>
      )}
    </Section>
  )
}

/** The ingestion log and statistics: jobs, their runs, every user's uploads, snapshots per source. */
export function AdminTab() {
  const ingestion = useAdminIngestion(true)
  if (ingestion.isPending) return <Loader aria-label="Loading" />
  if (ingestion.isError) return <Alert color="red">{ingestion.error.message}</Alert>
  const data = ingestion.data
  const now = new Date(parseUtc(data.now))
  return (
    <Stack gap="lg">
      <JobsCard jobs={data.jobs} now={now} canRun={data.can_run} />
      <RunsCard runs={data.runs} now={now} />
      <UploadsCard uploads={data.uploads} now={now} />
      <SnapshotsCard snapshots={data.snapshots} now={now} />
      <VendorSuspectsCard />
    </Stack>
  )
}
