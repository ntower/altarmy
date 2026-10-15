import { Alert, Badge, Button, CopyButton, Group, Loader, Stack, Table, Tabs, Text, Title } from '@mantine/core'
import type { components } from '../api/schema'
import type { ItemMap } from '../api/client'
import { useVendorRuns } from '../api/queries'
import { Hover, ItemLink } from './ItemTooltip'
import { formatMoney } from '../lib/money'
import { Money } from './Money'
import { ZoneMap } from './ZoneMap'

type ZoneRun = components['schemas']['ZoneRun']

const hours = (seconds: number) => (seconds >= 3600 ? `${Math.round(seconds / 3600)}h` : `${Math.round(seconds / 60)}m`)

/** A run as text to paste anywhere: per zone, each vendor's buys. */
export function runText(runs: readonly ZoneRun[], items: ItemMap): string {
  return runs
    .map((z) =>
      [
        `${z.zone}:`,
        ...z.resells.map(
          (r) => `- ${r.vendor}: buy ${r.units} ${items[r.item_id]?.name ?? r.item_id}, sell at ${formatMoney(r.sell_price)}`,
        ),
      ].join('\n'),
    )
    .join('\n')
}

function UnderVendor({ rows, items }: { rows: components['schemas']['UnderVendorOut'][]; items: ItemMap }) {
  if (!rows.length) return <Text c="dimmed">Nothing is listed under what a vendor pays right now.</Text>
  return (
    <Table.ScrollContainer minWidth={560}>
      <Table aria-label="Listed under what a vendor pays">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Item</Table.Th>
            <Table.Th ta="right">Units</Table.Th>
            <Table.Th ta="right">From</Table.Th>
            <Table.Th ta="right">Vendor pays</Table.Th>
            <Table.Th ta="right">Profit</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((u) => (
            <Table.Tr key={u.item_id}>
              <Table.Td>
                <ItemLink item={items[u.item_id]} />
                {u.fresh && (
                  <Badge ml="xs" size="xs" color="orange" variant="light" title="Listed only since the last scan: it may be gone, or the vendor price wrong">
                    new
                  </Badge>
                )}
              </Table.Td>
              <Table.Td ta="right">{u.units}</Table.Td>
              <Table.Td ta="right" ff="monospace">
                <Money copper={u.cheapest} />
              </Table.Td>
              <Table.Td ta="right" ff="monospace">
                <Money copper={u.vendor} />
              </Table.Td>
              <Table.Td ta="right" ff="monospace" c="teal">
                <Money copper={u.profit} />
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  )
}

function Resells({ runs, items }: { runs: ZoneRun[]; items: ItemMap }) {
  if (!runs.length)
    return <Text c="dimmed">No vendor sells anything for less than this auction house pays, as far as its sales show.</Text>
  return (
    <Stack gap="lg">
      <Group>
        <CopyButton value={runText(runs, items)}>
          {({ copied, copy }) => (
            <Button size="xs" variant="light" onClick={copy}>
              {copied ? 'Copied' : 'Copy run list'}
            </Button>
          )}
        </CopyButton>
      </Group>
      {runs.map((z) => (
        <Stack key={z.zone} gap={4}>
          <Group justify="space-between">
            <Title order={4} size="h5">
              {z.zone}
            </Title>
            <Text size="sm" c="teal" ff="monospace">
              <Money copper={z.profit} />
            </Text>
          </Group>
          <Table.ScrollContainer minWidth={560}>
            <Table aria-label={`Vendor run: ${z.zone}`}>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Item</Table.Th>
                  <Table.Th>Vendor</Table.Th>
                  <Table.Th ta="right">Buy</Table.Th>
                  <Table.Th ta="right">Sell at</Table.Th>
                  <Table.Th ta="right">Profit</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {z.resells.map((r) => (
                  <Table.Tr key={`${r.item_id}-${r.vendor}`}>
                    <Table.Td>
                      <ItemLink item={items[r.item_id]} />
                    </Table.Td>
                    <Table.Td>
                      {r.area > 0 ? (
                        <Hover tooltip={<ZoneMap area={r.area} x={r.map_x} y={r.map_y} name={r.vendor} />}>
                          <Text span size="sm" td="underline dotted">
                            {r.vendor}
                          </Text>
                        </Hover>
                      ) : (
                        r.vendor
                      )}
                      {r.limited && (
                        <Text span size="xs" c="dimmed">
                          {' '}
                          · limited, back in {hours(r.restock_s)}
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td ta="right" ff="monospace">
                      {r.units} × <Money copper={r.unit_cost} />
                    </Table.Td>
                    <Table.Td ta="right" ff="monospace">
                      <Money copper={r.sell_price} />
                    </Table.Td>
                    <Table.Td ta="right" ff="monospace" c="teal">
                      <Money copper={r.profit} />
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Stack>
      ))}
    </Stack>
  )
}

/**
 * The Vendor runs page (`/profit/gold/vendor`, `VENDOR_RUNS`): what the selected auction house lists under what a
 * vendor pays, and what vendors the faction can use sell for less than it pays, as one run per zone
 * (`/api/vendor-runs`). The resale counts the auction house's cut and an estimated deposit.
 */
export function VendorRuns() {
  const { data, isPending, isError } = useVendorRuns()
  if (isPending) return <Loader aria-label="Loading vendor runs" />
  if (isError || !data) return <Alert color="red">Vendor runs could not be loaded.</Alert>
  return (
    <Tabs defaultValue="under" keepMounted={false}>
      <Tabs.List>
        <Tabs.Tab value="under">Under what a vendor pays ({data.under_vendor.length})</Tabs.Tab>
        <Tabs.Tab value="resell">Vendor to auction house ({data.runs.reduce((n, z) => n + z.resells.length, 0)})</Tabs.Tab>
      </Tabs.List>
      <Tabs.Panel value="under" pt="md">
        <UnderVendor rows={data.under_vendor} items={data.items} />
      </Tabs.Panel>
      <Tabs.Panel value="resell" pt="md">
        <Resells runs={data.runs} items={data.items} />
      </Tabs.Panel>
    </Tabs>
  )
}
