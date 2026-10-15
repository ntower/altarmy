import { Paper, Table, Text, Title } from '@mantine/core'
import type { components } from '../api/schema'
import { useEssences } from '../api/queries'
import { ItemLink } from './ItemTooltip'
import { Money } from './Money'

type Tier = components['schemas']['EssenceTierOut']

/** Which way converting a tier pays, in words: the better direction, or none. */
export function essenceAdvice(t: Tier): { text: string; gain: number | null } {
  const up = t.up ?? null
  const down = t.down ?? null
  const best = Math.max(up ?? -Infinity, down ?? -Infinity)
  if (best === -Infinity) return { text: 'Not priced yet', gain: null }
  if (best <= 0) return { text: 'Neither way pays', gain: null }
  return best === up
    ? { text: `Buy ${t.per} lesser, combine, sell the greater`, gain: up }
    : { text: `Buy the greater, split it, sell ${t.per} lesser`, gain: down }
}

/**
 * Process trade goods' essences strip: per tier, the lesser and greater essence's prices at the selected auction house
 * and which way converting pays (`/api/essences`). Nothing while loading or with no tiers.
 */
export function EssencesStrip() {
  const { data } = useEssences()
  if (!data?.tiers.length) return null
  return (
    <Paper withBorder p="sm" radius="md">
      <Title order={4} size="h5" mb="xs">
        Essences
      </Title>
      <Table.ScrollContainer minWidth={520}>
        <Table verticalSpacing={4} aria-label="Essences">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Greater</Table.Th>
              <Table.Th ta="right">Greater</Table.Th>
              <Table.Th ta="right">Lesser</Table.Th>
              <Table.Th>What pays</Table.Th>
              <Table.Th ta="right">Each</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {data.tiers.map((t) => {
              const advice = essenceAdvice(t)
              return (
                <Table.Tr key={t.greater}>
                  <Table.Td>
                    <ItemLink item={data.items[t.greater]} />
                  </Table.Td>
                  <Table.Td ta="right" ff="monospace">
                    {t.greater_buy != null ? <Money copper={t.greater_buy} /> : '–'}
                  </Table.Td>
                  <Table.Td ta="right" ff="monospace">
                    {t.lesser_buy != null ? <Money copper={t.lesser_buy} /> : '–'}
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm" c={advice.gain == null ? 'dimmed' : undefined}>
                      {advice.text}
                    </Text>
                  </Table.Td>
                  <Table.Td ta="right" ff="monospace" c="teal">
                    {advice.gain != null ? <Money copper={advice.gain} /> : null}
                  </Table.Td>
                </Table.Tr>
              )
            })}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Paper>
  )
}
