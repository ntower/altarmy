import { Alert, Button, Checkbox, CopyButton, Group, Loader, Stack, Table, Text, Title } from '@mantine/core'
import type { components } from '../api/schema'
import type { ItemMap } from '../api/client'
import { useHoldings, useSetKept } from '../api/queries'
import { formatMoney } from '../lib/money'
import { CharacterName } from './CharacterName'
import { ItemLink } from './ItemTooltip'
import { Money } from './Money'

type Holder = components['schemas']['HolderOut']
type Held = components['schemas']['HeldOut']
type Verdict = Held['verdict']

/** The verdicts in the order shown, and what each says to do. */
const VERDICTS: readonly Verdict[] = ['auction', 'disenchant', 'vendor', 'keep']
const VERDICT_LABELS: Readonly<Record<Verdict, string>> = {
  auction: 'Post on the auction house',
  disenchant: 'Disenchant',
  vendor: 'Vendor',
  keep: 'Keep',
}
const WHY: Readonly<Record<string, string>> = {
  kept: 'you keep it',
  bound: 'soulbound, and no vendor pays for it',
  reagent: 'a reagent of a recipe your characters know',
  nothing: 'nothing pays for it',
}

/** How long ago a Unix time was, in words: "3 days ago". */
export function ago(seconds: number | null | undefined, now = Date.now() / 1000): string {
  if (seconds == null) return 'never'
  const hours = Math.max(0, (now - seconds) / 3600)
  if (hours < 1) return 'within the hour'
  if (hours < 48) return `${Math.round(hours)} hours ago`
  return `${Math.round(hours / 24)} days ago`
}

/** One character's clean-out list as text: what to sell where, the most first. */
export function cleanOutText(holder: Holder, items: ItemMap): string {
  return holder.held
    .filter((h) => h.verdict !== 'keep')
    .map(
      (h) =>
        `${VERDICT_LABELS[h.verdict]}: ${h.count} ${items[h.item_id]?.name ?? h.item_id} (${holder.name}, ${h.place}) · ${formatMoney(h.value)}`,
    )
    .join('\n')
}

function HolderSection({ holder, items, kept }: { holder: Holder; items: ItemMap; kept: ReadonlySet<number> }) {
  const setKept = useSetKept()
  const worth = holder.held.reduce((n, h) => n + (h.verdict === 'keep' ? 0 : h.value), 0)
  return (
    <Stack gap="xs">
      <Group justify="space-between" align="baseline">
        <Title order={3} size="h4">
          <CharacterName name={holder.name} classFile={holder.class_file} />
        </Title>
        <Text size="xs" c="dimmed">
          Bags scanned {ago(holder.bags_at)} · bank {ago(holder.bank_at)}
        </Text>
      </Group>
      {holder.held.length === 0 ? (
        <Text c="dimmed" size="sm">
          Nothing saved yet: open their bags and bank in game, then upload again.
        </Text>
      ) : (
        <>
          <Group justify="space-between">
            <Text size="sm">
              Selling it all brings <Money copper={worth} />
            </Text>
            <CopyButton value={cleanOutText(holder, items)}>
              {({ copied, copy }) => (
                <Button size="xs" variant="light" onClick={copy}>
                  {copied ? 'Copied' : 'Copy clean-out list'}
                </Button>
              )}
            </CopyButton>
          </Group>
          <Table.ScrollContainer minWidth={560}>
            <Table aria-label={`What ${holder.name} holds`}>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Item</Table.Th>
                  <Table.Th ta="right">Count</Table.Th>
                  <Table.Th>Where</Table.Th>
                  <Table.Th ta="right">Brings</Table.Th>
                  <Table.Th>Keep</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {VERDICTS.flatMap((v) => {
                  const rows = holder.held.filter((h) => h.verdict === v)
                  if (!rows.length) return []
                  return [
                    <Table.Tr key={v}>
                      <Table.Td colSpan={5}>
                        <Text size="sm" fw={500}>
                          {VERDICT_LABELS[v]} ({rows.length})
                        </Text>
                      </Table.Td>
                    </Table.Tr>,
                    ...rows.map((h) => (
                      <Table.Tr key={`${h.item_id}-${h.place}-${h.bound}`}>
                        <Table.Td>
                          <ItemLink item={items[h.item_id]} />
                          {h.verdict === 'keep' && WHY[h.why] && (
                            <Text size="xs" c="dimmed">
                              {WHY[h.why]}
                            </Text>
                          )}
                        </Table.Td>
                        <Table.Td ta="right">{h.count}</Table.Td>
                        <Table.Td>
                          {h.place}
                          {h.bound ? ' · soulbound' : ''}
                        </Table.Td>
                        <Table.Td ta="right" ff="monospace">
                          {h.verdict === 'keep' ? '–' : <Money copper={h.value} />}
                        </Table.Td>
                        <Table.Td>
                          <Checkbox
                            aria-label={`Keep ${items[h.item_id]?.name ?? h.item_id}`}
                            checked={kept.has(h.item_id)}
                            onChange={(e) => setKept.mutate({ itemId: h.item_id, kept: e.currentTarget.checked })}
                          />
                        </Table.Td>
                      </Table.Tr>
                    )),
                  ]
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </>
      )}
    </Stack>
  )
}

/**
 * The What I hold page (`/profit/gold/held`, `WHAT_I_HOLD`): per character of the selected realm, what their bags and
 * bank hold (as their last file upload had it) and what to do with each thing: post it, disenchant it, vendor it or
 * keep it (`/api/holdings`). Keep marks an item kept for good; Copy clean-out list gives the rest as text.
 */
export function WhatIHold() {
  const { data, isPending, isError } = useHoldings()
  if (isPending) return <Loader aria-label="Loading what your characters hold" />
  if (isError || !data) return <Alert color="red">What your characters hold could not be loaded.</Alert>
  if (!data.characters.length)
    return (
      <Alert color="blue">
        No bags or banks saved for this realm yet. Upload Alt Army's file (the export doesn't carry them) after
        opening each character's bags and bank in game.
      </Alert>
    )
  const kept = new Set(data.kept)
  return (
    <Stack gap="xl">
      {data.characters.map((c) => (
        <HolderSection key={c.name} holder={c} items={data.items} kept={kept} />
      ))}
    </Stack>
  )
}
