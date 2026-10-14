import { Fragment, type KeyboardEvent, type ReactNode } from 'react'
import { Loader, Table, Text } from '@mantine/core'
import { AnimatePresence, motion } from 'motion/react'
import type { ItemMap, ProfessionRank, RankResult } from '../api/client'
import { mustLearn, ranksToTrain } from '../lib/skill'
import { ItemLink } from './ItemTooltip'
import { Earned } from './Money'
import classes from './LadderTable.module.css'

/** What the reminders to train the next profession rank need: the version's ranks, the cap the climber has and the
 * profession. */
export type Training = { ranks: readonly ProfessionRank[]; maxRank: number; profession: string }

const MotionTr = motion.create(Table.Tr)
/** A details row opens and closes by its content's height (a table row's own height can't be animated), so its
 * cell has no padding of its own. */
const UNFOLD = {
  initial: { height: 0, opacity: 0 },
  animate: { height: 'auto', opacity: 1 },
  exit: { height: 0, opacity: 0 },
  transition: { duration: 0.25, ease: [0.25, 0.8, 0.25, 1] as const },
  style: { overflow: 'hidden' },
}
const COLUMNS = 4

/** The whole ladder as a table, the run to craft now first: the skill each run covers (with a reminder to train the
 * next rank where it reaches one), its recipe, the crafts it is expected to take and what it comes to once what it
 * makes is sold, its pattern included (spent in red with a minus sign, earned in green). A row opens out in place
 * into `details`, the run's full view (`openAt` its index); `pending` while the runs after those shown are on their
 * way. Shown at once, with no animation of its rows. */
export function LadderTable({
  runs,
  start,
  items,
  training,
  pending,
  openAt,
  onOpen,
  details,
  className,
}: {
  runs: RankResult[]
  /** the skill the first run starts at */
  start: number
  items: ItemMap
  training: Training
  pending: boolean
  openAt: number | null
  onOpen: (index: number) => void
  details: ReactNode
  /** where it goes in the workspace's layout */
  className?: string
}) {
  return (
    <div
      className={[classes.ladder, className].filter(Boolean).join(' ')}
      role="region"
      aria-label="The whole ladder"
    >
      <Table.ScrollContainer minWidth={480}>
        <Table highlightOnHover aria-label="The climb">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Skill</Table.Th>
              <Table.Th>Recipe</Table.Th>
              <Table.Th ta="right">Crafts</Table.Th>
              <Table.Th ta="right">Cost</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {runs.map((r, i) => {
              const from = i === 0 ? start : (runs[i - 1]?.stop_skill ?? 0)
              const due = ranksToTrain(training.ranks, training.maxRank, from, r.stop_skill, i === 0)
              const isOpen = openAt === i
              const open = () => onOpen(i)
              return (
                // a climb may come back to a recipe: keyed by place
                <Fragment key={`${i}-${r.recipe_id}`}>
                  <Table.Tr
                    role="button"
                    tabIndex={0}
                    aria-label={`Open ${r.output_name}`}
                    aria-expanded={isOpen}
                    onClick={open}
                    onKeyDown={(e: KeyboardEvent) => {
                      if (e.key !== 'Enter' && e.key !== ' ') return
                      e.preventDefault()
                      open()
                    }}
                    style={{ cursor: 'pointer' }}
                  >
                    <Table.Td className={classes.skill}>
                      {from}–{r.stop_skill}
                      {due.map(({ rank }) => (
                        <Text key={rank.name} size="xs" c="yellow" className={classes.train}>
                          Train {rank.name}
                        </Text>
                      ))}
                    </Table.Td>
                    <Table.Td>
                      <ItemLink item={items[r.output_item_id]} name={r.output_name} />
                    </Table.Td>
                    <Table.Td ta="right" className={classes.figure}>
                      ~{Math.round(r.crafts)}
                    </Table.Td>
                    <Table.Td ta="right" ff="monospace" className={classes.figure}>
                      <Earned copper={r.profit - (r.learn_cost ?? 0)} minus />
                      {mustLearn(r) && r.learn_cost === null && (
                        <Text size="xs" c="dimmed" ff="text">
                          pattern price unknown
                        </Text>
                      )}
                    </Table.Td>
                  </Table.Tr>
                  <AnimatePresence initial={false}>
                    {isOpen && (
                      <MotionTr key="details" className={classes.details}>
                        <Table.Td py={0} colSpan={COLUMNS}>
                          <motion.div {...UNFOLD}>{details}</motion.div>
                        </Table.Td>
                      </MotionTr>
                    )}
                  </AnimatePresence>
                </Fragment>
              )
            })}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {pending && <Loader size="xs" aria-label="Working out what comes after" className={classes.loader} />}
    </div>
  )
}
