import { Anchor, Group, SegmentedControl, SimpleGrid, Stack, Text, Title, UnstyledButton } from '@mantine/core'
import { useTrack } from '../api/queries'
import { linkProps, navigate } from '../lib/router'
import type { GoldStrategy } from '../lib/profitRoute'
import { liveStrategies } from '../lib/strategies'
import { useFeatures } from '../lib/useFeatures'
import cards from './Cards.module.css'

/**
 * Making gold's question (`STRATEGY_PICKER`): one card per way to make gold, each opening its page. It ranks nothing
 * and shows no copper: the page does. Skilling up, which costs gold, stays the other answer at /profit.
 */
export function StrategyPicker() {
  const track = useTrack()
  const features = useFeatures()
  const pick = (key: GoldStrategy) => {
    track('strategy_chosen', { strategy: key })
    navigate(`/profit/gold/${key}`)
  }
  return (
    <Stack component="section" aria-label="Ways to make gold">
      <Title order={2} size="h3">
        How do you want to make gold?
      </Title>
      <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
        {liveStrategies(features).map((s) => (
          <UnstyledButton key={s.key} className={cards.card} onClick={() => pick(s.key)} aria-label={s.title} p="md">
            <Stack gap={4}>
              <Text fw={600}>{s.title}</Text>
              <Text size="sm">{s.blurb}</Text>
              <Text size="xs" c="dimmed">
                {s.errand}
              </Text>
            </Stack>
          </UnstyledButton>
        ))}
      </SimpleGrid>
      <Text size="sm" c="dimmed">
        Skilling up instead?{' '}
        <Anchor size="sm" {...linkProps('/profit/skill')}>
          The cheapest climb up one profession
        </Anchor>
      </Text>
    </Stack>
  )
}

/** Above each way to make gold: back to the question, and the other ways a click away (when there are others). */
export function StrategyBar({ current }: { current: GoldStrategy }) {
  const live = liveStrategies(useFeatures())
  return (
    <Group justify="space-between" gap="sm" wrap="wrap">
      <Anchor size="sm" {...linkProps('/profit/gold')}>
        ‹ Ways to make gold
      </Anchor>
      {live.length > 1 && (
        <SegmentedControl
          size="xs"
          aria-label="Way to make gold"
          value={current}
          onChange={(key) => navigate(`/profit/gold/${key}`, { replace: true })}
          data={live.map((s) => ({ value: s.key, label: s.title }))}
        />
      )}
    </Group>
  )
}
