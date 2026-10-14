import { Fragment, type ReactNode, useState } from 'react'
import { z } from 'zod'
import { Alert, Checkbox, Group, Loader, Pagination, Stack, Table, Text, Title, UnstyledButton } from '@mantine/core'
import type { VendorCheck as VendorCheckOut } from '../api/client'
import { useVendorCheck, useVendorCheckItem, type VendorCheckParams } from '../api/queries'
import { realmLabel } from '../lib/realms'
import { useStoredState } from '../lib/storage'
import { iconUrl, itemClassName, QUALITY_COLORS, qualityName } from '../lib/wow'
import { DepthChart, type Rule } from './MarketCharts'
import { Earned, Money } from './Money'
import classes from './VendorCheck.module.css'

type Row = VendorCheckOut['items'][number]

/** Where the unticked item types and qualities are remembered (localStorage); empty: every one shown. */
export const HIDDEN_TYPES_KEY = 'altarmy.vendorcheck.hiddenTypes'
export const HIDDEN_QUALITIES_KEY = 'altarmy.vendorcheck.hiddenQualities'
const hiddenSchema = z.array(z.number().int())
const NONE_HIDDEN: number[] = []

/** What a vendor pays over the cheapest listing: the gain of buying it out and vendoring it a unit. */
const difference = (r: Row) => r.sell_price - r.ah_price

/** That gain as a percentage of the listing's price. */
const percent = (r: Row) => (difference(r) / r.ah_price) * 100

const canVendor = (r: Row) => r.sell_price > 0

/** "+160%" or "-90%", whole percents. */
const percentText = (pct: number) => `${pct > 0 ? '+' : ''}${pct.toFixed(0)}%`

type SortKey = VendorCheckParams['sort']
/** The columns, each with the server's sort key for it. */
const COLUMNS: readonly (readonly [string, SortKey])[] = [
  ['Item', 'item'],
  ['Type', 'type'],
  ['AH price', 'ah_price'],
  ['Vendor pays', 'vendor'],
  ['Difference', 'difference'],
  ['% Difference', 'percent'],
]
const TEXT_SORTS: ReadonlySet<SortKey> = new Set(['item', 'type'])

type Sort = { column: SortKey; descending: boolean }
/** Underpriced items first: the biggest gain at the top. */
const DEFAULT_SORT: Sort = { column: 'difference', descending: true }

/** An opened row: the item's order book as a staircase, the price a vendor pays drawn across it, so what is listed
 * under it shows at a glance. Its levels are fetched when it opens. */
function RowDetails({ row }: { row: Row }) {
  const item = useVendorCheckItem(row.id)
  if (item.isPending) return <Loader size="sm" aria-label={`Loading ${row.name}'s order book`} />
  if (item.isError) return <Alert color="red">{item.error.message}</Alert>
  const rules: Rule[] = canVendor(row) ? [{ price: row.sell_price, label: 'vendor pays', tone: 'profit' }] : []
  const under = item.data.ah_levels.filter((l) => l.price < row.sell_price).reduce((n, l) => n + l.quantity, 0)
  return (
    <Stack gap="xs" className={classes.details} aria-label={`${row.name}'s order book`} role="region">
      <Text size="sm">
        {item.data.ah_levels.length === 0
          ? 'No price levels from a scan: this price was set by hand.'
          : !canVendor(row)
            ? 'No vendor buys this item.'
            : under > 0
              ? `${under.toLocaleString()} ${under === 1 ? 'unit is' : 'units are'} listed under what a vendor pays.`
              : 'Nothing is listed under what a vendor pays.'}
      </Text>
      <DepthChart name={row.name} levels={item.data.ah_levels} rules={rules} />
    </Stack>
  )
}

/** One row of checkboxes: every value ticked but the hidden ones; a change stores the unticked ones. */
function FilterGroup({
  label,
  values,
  hidden,
  onHide,
  name,
}: {
  label: string
  values: readonly number[]
  hidden: readonly number[]
  onHide: (hidden: number[]) => void
  name: (value: number) => ReactNode
}) {
  // Hidden values not listed now (none of them on the AH at the moment) stay hidden.
  const elsewhere = hidden.filter((h) => !values.includes(h))
  return (
    <Checkbox.Group
      label={label}
      value={values.filter((v) => !hidden.includes(v)).map(String)}
      onChange={(ticked) => onHide([...elsewhere, ...values.filter((v) => !ticked.includes(String(v)))])}
    >
      <Group gap="md" mt={4}>
        {values.map((v) => (
          <Checkbox key={v} value={String(v)} label={name(v)} />
        ))}
      </Group>
    </Checkbox.Group>
  )
}

/**
 * The vendor check (/profit/vendorcheck, reached by its path alone): what the selected realm's auction house lists,
 * its cheapest listing beside what a vendor pays for it, so items sold under their vendor price stand out. The server
 * filters, sorts and pages (`/api/vendorcheck`, 50 a page): checkboxes leave item types and qualities out
 * (remembered in localStorage), and the headers sort (a number largest first on the first click, text A first;
 * another click reverses it). A change of filter or sort goes back to the first page. A row clicked opens into its
 * order book (`RowDetails`).
 */
export function VendorCheck() {
  const [hiddenTypes, setHiddenTypes] = useStoredState(HIDDEN_TYPES_KEY, hiddenSchema, NONE_HIDDEN)
  const [hiddenQualities, setHiddenQualities] = useStoredState(HIDDEN_QUALITIES_KEY, hiddenSchema, NONE_HIDDEN)
  const [sort, setSort] = useState<Sort>(DEFAULT_SORT)
  const [page, setPage] = useState(1)
  // The row opened into its order book (one at a time); another page, sort or filter closes it.
  const [open, setOpen] = useState<number | null>(null)
  const check = useVendorCheck({
    hideClasses: hiddenTypes,
    hideQualities: hiddenQualities,
    sort: sort.column,
    descending: sort.descending,
    page,
  })

  const sortBy = (column: SortKey) => {
    setSort((prev) =>
      prev.column === column
        ? { column, descending: !prev.descending }
        : { column, descending: !TEXT_SORTS.has(column) },
    )
    toPage(1)
  }
  const toPage = (to: number) => {
    setPage(to)
    setOpen(null)
  }
  const hideTypes = (hidden: number[]) => {
    setHiddenTypes(hidden)
    toPage(1)
  }
  const hideQualities = (hidden: number[]) => {
    setHiddenQualities(hidden)
    toPage(1)
  }

  if (check.isPending) return <Loader aria-label="Loading" />
  if (check.isError) return <Alert color="red">{check.error.message}</Alert>
  const data = check.data
  const pages = Math.max(1, Math.ceil(data.total / data.page_size))
  const first = (data.page - 1) * data.page_size + 1
  const house = data.realm ? realmLabel({ realm: data.realm, faction: data.faction }) : null
  const pager = (where: string) =>
    pages > 1 && (
      <Pagination value={data.page} onChange={toPage} total={pages} size="sm" aria-label={`Pages ${where}`} />
    )

  return (
    <Stack gap="md">
      <div>
        <Title order={2}>Vendor check</Title>
        <Text c="dimmed">
          {house
            ? `What the auction house on ${house} lists, beside what a vendor pays for it.`
            : 'Select a realm on the Profit page first.'}
        </Text>
      </div>
      {data.listed === 0 ? (
        <Text>No scan of this realm yet.</Text>
      ) : (
        <>
          <Group gap="xl" align="flex-start">
            <FilterGroup
              label="Item types"
              values={data.classes}
              hidden={hiddenTypes}
              onHide={hideTypes}
              name={itemClassName}
            />
            <FilterGroup
              label="Quality"
              values={data.qualities}
              hidden={hiddenQualities}
              onHide={hideQualities}
              name={(q) => (
                <Text span inherit c={QUALITY_COLORS[q]} fw={500}>
                  {qualityName(q)}
                </Text>
              )}
            />
          </Group>
          <Group justify="space-between">
            <Text size="sm" c="dimmed">
              {data.total} of {data.listed} items
              {pages > 1 && `, ${first}–${first + data.items.length - 1} shown`}
            </Text>
            {pager('above')}
          </Group>
          <Table.ScrollContainer minWidth={640}>
            <Table highlightOnHover aria-label="Vendor check" aria-busy={check.isFetching || undefined}>
              <Table.Thead>
                <Table.Tr>
                  {COLUMNS.map(([label, key]) => {
                    const active = sort.column === key
                    return (
                      <Table.Th
                        key={key}
                        ta={TEXT_SORTS.has(key) ? undefined : 'right'}
                        aria-sort={!active ? 'none' : sort.descending ? 'descending' : 'ascending'}
                      >
                        <UnstyledButton
                          className={classes.sort}
                          aria-label={`Sort by ${label}`}
                          onClick={() => sortBy(key)}
                        >
                          {label}
                          <span className={classes.arrow} data-active={active || undefined}>
                            {active && !sort.descending ? '▲' : '▼'}
                          </span>
                        </UnstyledButton>
                      </Table.Th>
                    )
                  })}
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {data.items.map((r) => (
                  <Fragment key={r.id}>
                    <Table.Tr
                      className={classes.row}
                      data-open={open === r.id || undefined}
                      onClick={() => setOpen((o) => (o === r.id ? null : r.id))}
                    >
                      <Table.Td>
                        <div className={classes.item}>
                          {r.icon && <img className={classes.icon} src={iconUrl(r.icon, 'small')} alt="" />}
                          <div>
                            <UnstyledButton
                              className={classes.name}
                              aria-expanded={open === r.id}
                              // the row's click toggles it; this is the keyboard's way in
                              onClick={(e) => {
                                e.stopPropagation()
                                setOpen((o) => (o === r.id ? null : r.id))
                              }}
                            >
                              <Text span fw={500} c={QUALITY_COLORS[r.quality]}>
                                {r.name}
                              </Text>
                            </UnstyledButton>
                            {r.subclass_name && (
                              <Text size="xs" c="dimmed">
                                {r.subclass_name}
                              </Text>
                            )}
                          </div>
                        </div>
                      </Table.Td>
                      <Table.Td>{itemClassName(r.class_id)}</Table.Td>
                      <Table.Td ta="right" ff="monospace" className={classes.figure}>
                        <Money copper={r.ah_price} padded />
                      </Table.Td>
                      <Table.Td ta="right" ff="monospace" className={classes.figure}>
                        {canVendor(r) ? <Money copper={r.sell_price} padded /> : '—'}
                      </Table.Td>
                      <Table.Td ta="right" ff="monospace" className={classes.figure}>
                        {canVendor(r) ? <Earned copper={difference(r)} minus /> : '—'}
                      </Table.Td>
                      <Table.Td ta="right" ff="monospace" className={classes.figure}>
                        {canVendor(r) ? (
                          <Text span inherit c={difference(r) < 0 ? 'red' : 'teal'}>
                            {percentText(percent(r))}
                          </Text>
                        ) : (
                          '—'
                        )}
                      </Table.Td>
                    </Table.Tr>
                    {open === r.id && (
                      <Table.Tr className={classes.detailsRow}>
                        <Table.Td colSpan={COLUMNS.length}>
                          <RowDetails row={r} />
                        </Table.Td>
                      </Table.Tr>
                    )}
                  </Fragment>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
          {pages > 1 && <Group justify="flex-end">{pager('below')}</Group>}
        </>
      )}
    </Stack>
  )
}
