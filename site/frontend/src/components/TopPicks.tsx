import { Badge, Group, Paper, Stack, Text, UnstyledButton } from '@mantine/core'
import type { ItemMap, RankResult } from '../api/client'
import { PROCESS_GROUP_LABELS } from '../lib/strategies'
import { type PickKind, pickKind } from '../lib/topPicks'
import { CharacterName } from './CharacterName'
import { Money } from './Money'
import { WhatToDo } from './ResultsTable'
import classes from './TopPicks.module.css'

const KIND_LABELS: Readonly<Record<PickKind, string>> = {
  craft: 'Craft',
  process: 'Process',
  flip: 'Buy & disenchant',
  convert: 'Essence',
  enchant: 'Enchant',
}

/** A pick's badge: what kind of thing to do (processing by its group). */
const badgeOf = (r: RankResult): string =>
  r.process ? `${KIND_LABELS.process} · ${PROCESS_GROUP_LABELS[r.process.group]}` : KIND_LABELS[pickKind(r)]

/**
 * Best right now: the few things most worth doing (`topPicks`, from the rows the list already loaded), each with what
 * to do and what a day of it makes. Clicking one opens its row in the list below.
 */
export function TopPicks({
  picks,
  items,
  onPick,
}: {
  picks: readonly RankResult[]
  items: ItemMap
  onPick: (r: RankResult) => void
}) {
  if (!picks.length) return null
  return (
    <Paper withBorder p="sm" radius="md" component="section" aria-label="Best right now">
      <Group justify="space-between" mb="xs">
        <Text fw={700} size="sm" tt="uppercase">
          Best right now
        </Text>
        <Text size="xs" c="dimmed">
          ranked by gold a day
        </Text>
      </Group>
      <Stack gap={4}>
        {picks.map((r, i) => (
          <UnstyledButton
            key={r.recipe_id}
            className={classes.pick}
            onClick={() => onPick(r)}
            aria-label={`Pick ${i + 1}: ${r.output_name}`}
          >
            <Text span fw={700} c="dimmed" className={classes.rank}>
              {i + 1}
            </Text>
            <div className={classes.body}>
              <Group gap={6} wrap="nowrap">
                <Text span fw={600} size="sm" truncate>
                  {r.output_name}
                </Text>
                <Badge size="xs" variant="light">
                  {badgeOf(r)}
                </Badge>
                {r.crafter && (
                  <Text span size="xs" c="dimmed">
                    <CharacterName name={r.crafter} />
                  </Text>
                )}
              </Group>
              <WhatToDo result={r} items={items} />
            </div>
            <Text span ff="monospace" fw={700} c={r.per_day < 0 ? 'red' : 'teal'} className={classes.money}>
              <Money copper={r.per_day} />
              /day
            </Text>
          </UnstyledButton>
        ))}
      </Stack>
      <Text size="xs" c="dimmed" mt="xs">
        Click a pick to open its row in the list.
      </Text>
    </Paper>
  )
}
