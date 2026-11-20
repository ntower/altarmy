import { useState } from 'react'
import { Group, Image, SegmentedControl, Select, Stack, Text } from '@mantine/core'
import { useDebouncedValue } from '@mantine/hooks'
import type { Coverage, FoundItem, MarketHistory } from '../api/client'
import { useAdminItemHistory, useAdminItemSearch, useCoverage, useStatus } from '../api/queries'
import { realmLabel, toKey } from '../lib/realms'
import { setSearchParam, useSearchParam } from '../lib/router'
import { useSession } from '../lib/session'
import { QUALITY_COLORS, iconUrl } from '../lib/wow'
import { Money } from './Money'
import { HOURLY_SPAN, TrendChart, hourPoints } from './TrendChart'

/** The ranges offered, in days; a week or less is drawn by the hour, and two weeks is as far back as the hours go. */
export const RANGES = [
  { label: '24h', value: '1' },
  { label: '3d', value: '3' },
  { label: '7d', value: '7' },
  { label: '14d', value: '14' },
  { label: '30d', value: '30' },
  { label: '90d', value: '90' },
  { label: '1y', value: '365' },
] as const
const DEFAULT_DAYS = 30

const qualityColor = (quality: number) => QUALITY_COLORS[quality] ?? QUALITY_COLORS[1]

/** The house the page opens on: the admin's own selection if it has prices, else the most recently scanned. */
function defaultHouse(coverage: readonly Coverage[], selection: { realm: string; faction: string } | null | undefined) {
  const priced = coverage.filter((c) => c.prices > 0)
  const mine = selection && priced.find((c) => toKey(c) === toKey(selection))
  if (mine) return mine.auction_house_id
  const newest = [...priced].sort((a, b) => (b.last_scan ?? '').localeCompare(a.last_scan ?? ''))[0]
  return newest?.auction_house_id ?? null
}

/** What the range came to: the last median (by the hour, the last market price), its change from the first, and the
 * units seen bought. */
function summary(h: MarketHistory, days: number) {
  const hours = hourPoints(h, days)
  const hourly = days * 86_400_000 <= HOURLY_SPAN && hours.length > 1
  const series = hourly ? hours.map((p) => p.market) : h.days.filter((d) => d.median != null).map((d) => d.median!)
  const first = series[0]
  const last = series[series.length - 1]
  const change = first && last !== undefined && series.length > 1 ? (last - first) / first : null
  const sold = h.flows.reduce((n, f) => n + f.sold, 0)
  return { hourly, last, change, sold }
}

const rangeText = (days: number) => (days === 1 ? '24 hours' : `${days} days`)

/**
 * The Trends page (admins only, `TrendsPage`): search an item by name or id, pick any auction house with prices and a
 * range, and see its price history (`/api/admin/items/{id}/history`). The item, house and range are in the URL
 * (`item`, `house`, `days`), so a view can be linked.
 */
export function TrendsTab() {
  const { admin } = useSession()
  const itemParam = useSearchParam('item')
  const houseParam = useSearchParam('house')
  const daysParam = useSearchParam('days')
  const itemId = itemParam && /^\d+$/.test(itemParam) ? Number(itemParam) : null
  const days = RANGES.some((r) => r.value === daysParam) ? Number(daysParam) : DEFAULT_DAYS

  const coverage = useCoverage().data ?? []
  const selection = useStatus().data?.selection
  const houseId = houseParam && /^\d+$/.test(houseParam) ? Number(houseParam) : defaultHouse(coverage, selection)
  const house = coverage.find((c) => c.auction_house_id === houseId)

  const [search, setSearch] = useState('')
  const [debounced] = useDebouncedValue(search, 200)
  // an item opened from the URL is found by its id, so its name shows before anything is typed
  const found = useAdminItemSearch(debounced || (itemId !== null ? String(itemId) : ''), admin).data ?? []
  const [picked, setPicked] = useState<FoundItem | null>(null)
  const seen = found.find((f) => f.id === itemId)
  // remember the item once found, so typing another search keeps its name (state adjusted while rendering)
  if (seen && picked?.id !== seen.id) setPicked(seen)
  const item = picked?.id === itemId ? picked : (seen ?? null)
  const options = [...(item && !found.some((f) => f.id === item.id) ? [item] : []), ...found]
  const byId = new Map(options.map((f) => [String(f.id), f]))

  const history = useAdminItemHistory(itemId, houseId, days, admin)

  const houseOptions = coverage
    .filter((c) => c.prices > 0 || c.auction_house_id === houseId)
    .map((c) => ({
      value: String(c.auction_house_id),
      label: `${realmLabel(c)}${c.last_scan ? ` · scanned ${c.last_scan.slice(0, 10)}` : ''}`,
    }))

  const name = item?.name ?? (itemId !== null ? `item ${itemId}` : '')
  const s = history.data && summary(history.data, days)
  const empty = history.data && history.data.days.length + history.data.hours.length < 2

  return (
    <Stack gap="md">
      <Group gap="sm" align="flex-end" wrap="wrap">
        <Select
          label="Item"
          placeholder="Search by name or id"
          searchable
          clearable
          w={320}
          data={options.map((f) => ({ value: String(f.id), label: f.name }))}
          value={itemId !== null ? String(itemId) : null}
          searchValue={search}
          onSearchChange={setSearch}
          filter={({ options }) => options}
          nothingFoundMessage={debounced.trim().length >= 2 ? 'No items found' : 'Type 2 letters or an id'}
          onChange={(value) => {
            setPicked(value ? (byId.get(value) ?? null) : null)
            setSearchParam('item', value)
          }}
          renderOption={({ option }) => {
            const f = byId.get(option.value)
            return (
              <Group gap={8} wrap="nowrap">
                {f?.icon && <Image src={iconUrl(f.icon, 'small')} alt="" w={18} h={18} radius={2} />}
                <Text size="sm" style={{ color: f ? qualityColor(f.quality) : undefined }}>
                  {option.label}
                </Text>
                {f && !f.priced && (
                  <Text size="xs" c="dimmed">
                    never listed
                  </Text>
                )}
              </Group>
            )
          }}
        />
        <Select
          label="Auction house"
          placeholder="Pick a house"
          w={340}
          data={houseOptions}
          value={houseId !== null ? String(houseId) : null}
          onChange={(value) => setSearchParam('house', value)}
          allowDeselect={false}
        />
        <SegmentedControl
          aria-label="Range"
          data={RANGES.map((r) => ({ ...r }))}
          value={String(days)}
          onChange={(value) => setSearchParam('days', value)}
        />
      </Group>

      {itemId === null ? (
        <Text c="dimmed">Search for an item to see its prices over time.</Text>
      ) : houseId === null ? (
        <Text c="dimmed">No auction house has prices yet.</Text>
      ) : !history.data ? (
        <Text c="dimmed">Loading…</Text>
      ) : empty ? (
        <Text c="dimmed">
          Not enough of {name}&apos;s prices recorded at {house ? realmLabel(house) : 'this house'} over the last {rangeText(days)} to
          draw.
        </Text>
      ) : (
        <Stack gap="xs">
          {s && (
            <Text size="sm">
              {s.last !== undefined && (
                <>
                  {s.hourly ? 'Last market price' : 'Last median'} <Money copper={s.last} />
                </>
              )}
              {s.change !== null && (
                <Text span c={s.change >= 0 ? 'teal' : 'red'} ml="xs">
                  {s.change >= 0 ? '+' : '−'}
                  {Math.abs(s.change * 100).toFixed(1)}% over the range
                </Text>
              )}
              <Text span c="dimmed" ml="xs">
                · {s.sold} bought, as far as scans saw
              </Text>
            </Text>
          )}
          <TrendChart key={`${itemId}-${houseId}-${days}`} history={history.data} name={name} days={days} />
        </Stack>
      )}
    </Stack>
  )
}
