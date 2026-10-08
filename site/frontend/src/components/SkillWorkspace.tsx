import { type CSSProperties, Fragment, type ReactNode, type Ref, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Accordion, Alert, Badge, Box, Button, Checkbox, Divider, Group, Loader, NumberInput, Paper, Stack, Text, Title, Tooltip, UnstyledButton } from '@mantine/core'
import { LayoutGroup, animate, motion } from 'motion/react'
import { useDebouncedValue } from '@mantine/hooks'
import { z } from 'zod'
import type { ItemMap, Learn, ProfessionRank, RankResult } from '../api/client'
import {
  type EvaluateParams,
  type RankParams,
  useDataVersion,
  useProfessionRanks,
  useRank,
  usePrefetchSessionPlans,
  useSessionPlan,
  useStatus,
  useTrack,
} from '../api/queries'
import { choose as chooseAt, type Choices, type PlanEditing } from '../lib/choices'
import { MarketFocus, useMarket } from '../lib/marketFocus'
import { layoutTop, scrollTarget } from '../lib/scroll'
import { useStoredState } from '../lib/storage'
import type { Holder } from '../lib/setup'
import {
  an,
  AT_WHICH_POINT,
  CHEAPER,
  craftsToReach,
  DEFAULT_REACH_TARGET,
  rangeText,
  ranksToTrain, runLead, runText, scaleRun, stepsText, tailText } from '../lib/skill'
import { CharacterClasses } from '../lib/characterClasses'
import { IconSwap } from './icons'
import { ItemLink } from './ItemTooltip'
import { LearnStep, LearnTooltip } from './LearnTooltip'
import { MarketSection, MarketSummary } from './MarketSection'
import { Earned, Money } from './Money'
import { RecipeFlow } from './RecipeFlow'
import { PlanViewSwitch, type PlanView } from './SessionDetails'
import { StepList } from './StepList'
import classes from './SkillWorkspace.module.css'

/** Options laid out side by side (the API's `SKILL_OPTIONS`): all the overview asks for. */
const OPTIONS = 4
/** The runs the chain holds at first (the API's `SKILL_CHAIN`). */
const CHAIN = 2
/** How many more runs each Show more asks for. */
const CHAIN_MORE = 3
const NO_RUNS: RankResult[] = []
/** How a chosen option opens out into its run (as the Profit page's cards do). */
const LAYOUT = { duration: 0.3, ease: [0.25, 0.8, 0.25, 1] as const }

type Filters = Omit<RankParams, 'top'>

/** What a run comes to per skill point it is expected to give, its pattern included: gained in green, spent in red
 * with a minus sign. */
function NetPerPoint({ result }: { result: RankResult }) {
  const net = netPerPoint(result)
  if (net === null) return <>no skill point</>
  return (
    <>
      <Earned copper={Math.round(net)} minus /> per skill point
    </>
  )
}

/** What a run comes to per skill point, its pattern included (gained positive, spent negative); null without one. */
function netPerPoint(r: RankResult): number | null {
  return r.skill_ups ? (r.profit - (r.learn_cost ?? 0)) / r.skill_ups : null
}

/** How a run's crafts spread: where its last points get slow (`tailText`) and, with `range`, how many crafts it
 * usually takes (`rangeText`); nothing for a run that is all orange. */
function RunSpread({ result: r, range }: { result: RankResult; range?: boolean }) {
  const lines = [range ? rangeText(r) : null, tailText(r)].filter((line) => line !== null)
  if (!lines.length) return null
  return (
    <Text size="xs" c="dimmed">
      {lines.join('. ')}
    </Text>
  )
}

/** What the Recommended badge weighs, on hover. */
const RECOMMENDED_TIP =
  'Reaches the highest skill of these options for the least: fewest patterns of unknown price first, then copper, ' +
  'counting spare materials for unlucky runs and what each craft is worth to you'

/** What the climb a run starts is expected to come to by each profession rank's cap it reaches (those reached
 * already left out): spent in red, earned in green, patterns without a price named apart. It moves with its
 * option's card between the single column and the options side by side (by position: text isn't stretched);
 * `fade`: it fades in as the other options open out. */
function Milestones({ result, column, fade }: { result: RankResult | undefined; column?: number; fade?: boolean }) {
  const milestones = result?.milestones ?? []
  if (!result || !milestones.length) return null
  return (
    <motion.div
      layout="position"
      layoutId={`skill-milestones-${result.recipe_id}`}
      transition={LAYOUT}
      initial={fade ? { opacity: 0 } : false}
      animate={{ opacity: 1 }}
      role="group"
      className={classes.milestones}
      style={column ? ({ '--column': column } as CSSProperties) : undefined}
      aria-label={`Cost to reach each rank with ${result.output_name} first`}
    >
      <Text size="xs" c="dimmed">
        Estimated cost to reach
      </Text>
      {/* skills aligned on the left, amounts on the right; patterns without a price under their row */}
      <table className={classes.milestoneTable}>
        <tbody>
          {milestones.map((m) => (
            <Fragment key={m.skill}>
              <tr>
                <th scope="row">{m.skill} skill:</th>
                <td>
                  <Earned copper={-m.cost} minus />
                </td>
              </tr>
              {m.unknown > 0 && (
                <tr>
                  <td colSpan={2} className={classes.milestoneNote}>
                    + {m.unknown} pattern{m.unknown === 1 ? '' : 's'} of unknown price
                  </td>
                </tr>
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </motion.div>
  )
}

/** A recipe's name. */
function RecipeName({ result, items }: { result: RankResult; items: ItemMap }) {
  return <ItemLink item={items[result.output_item_id]} name={result.output_name} />
}

/** How far to craft and why then, the recipe that gives a cheaper point by then as an item link (icon, its
 * quality's colour, tooltip). */
function RunText({ result: r, items }: { result: RankResult; items: ItemMap }) {
  if (r.stop_reason !== 'rival') return <>{runText(r)}</>
  const rival = r.overtaken_by_item ? items[r.overtaken_by_item] : undefined
  return (
    <>
      {runLead(r)}
      {AT_WHICH_POINT}
      <ItemLink item={rival} name={r.overtaken_by || 'another recipe'} />
      {CHEAPER}
    </>
  )
}

// The size of the spinner beside the odds (px).
const SPINNER = 16
// The most crafts the checklist buys for.
const MAX_BUY = 999

/** The chance, in whole percent (never rounded up), that `crafts` crafts reach the run's `stop_skill`; past the
 * odds the server sent, the last of them. */
function reachPercent(r: RankResult, crafts: number): number {
  const odds = r.reach_chances ?? []
  const chance = odds.length === 0 ? 1 : (odds[Math.min(crafts, odds.length) - 1] ?? 0)
  return Math.floor(chance * 100 + 1e-9)
}

/** Whether the climber must learn a run's recipe first. */
const mustLearn = (r: RankResult): boolean => !!r.crafter && !r.crafters.includes(r.crafter)

/** What the climber must do to learn a run's recipe; null when they know it. */
function learnNote(r: RankResult, learn: Learn | undefined): ReactNode {
  if (!mustLearn(r)) return null
  if (r.learn_cost === null) return 'You must find the pattern (price unknown)'
  if (learn?.source === 'trainer')
    return r.learn_cost ? (
      <>
        You must learn it from a trainer (<Money copper={r.learn_cost} cost />)
      </>
    ) : (
      'You must learn it from a trainer'
    )
  if (!r.learn_cost) return 'You must learn it first'
  return (
    <>
      You must buy the pattern (<Money copper={r.learn_cost} cost />)
    </>
  )
}

/** An option card's last row when the climber lacks the recipe and what learning it costs is counted. */
function includedNote(learn: Learn | undefined): string {
  if (learn?.source === 'trainer') return 'You will need to train this recipe (included in the cost)'
  if (learn) return 'You will need to buy the pattern (included in the cost)'
  return 'You will need to learn this recipe (included in the cost)'
}

/** One option in the overview: the recipe, what its run comes to per skill point, how far it goes, how it is
 * learned. Without `onChoose`, a summary of a run to come (in the chain), with nothing to click; `fade`: it fades
 * in as the other options open out; `lit`: lit on hover, which says it opens (anywhere on it, as ever); `grow`: it
 * also grows a little on hover, where a click opens it out (not where a click only picks it). `action` names its
 * button ("Choose", "Open"), `layoutId` what it opens out into (by default the option's); a run in the chain stays
 * an `article` named after its recipe. A summary given a `layoutId` moves with it (the run crafted now's chain, between
 * the single column and the options side by side). */
function OptionCard({
  result: r,
  items,
  learn,
  fade,
  lit,
  grow,
  onChoose,
  action = 'Choose',
  layoutId,
  article,
  recommended,
}: {
  result: RankResult
  items: ItemMap
  learn: Learn | undefined
  fade?: boolean
  lit?: boolean
  grow?: boolean
  onChoose?: () => void
  action?: string
  layoutId?: string
  article?: boolean
  /** the server's best among the options side by side, reaching as high as any: badged Recommended */
  recommended?: boolean
}) {
  const body = (
          <Stack gap={4}>
            <Group justify="space-between" align="flex-start" gap="xs" wrap="nowrap">
              <Text fw={600} size="sm">
                <RecipeName result={r} items={items} />
              </Text>
              {recommended && (
                <Tooltip label={RECOMMENDED_TIP} withArrow multiline w={260}>
                  <Badge size="sm" variant="light" color="green" style={{ flexShrink: 0 }}>
                    Recommended
                  </Badge>
                </Tooltip>
              )}
            </Group>
            <Text size="lg" fw={700}>
              <NetPerPoint result={r} />
            </Text>
            <Text size="xs" c="dimmed">
              <RunText result={r} items={items} />
            </Text>
            {/* a recipe the climber lacks: its pattern is counted in the cost, unless nobody can price it */}
            {mustLearn(r) && (
              <Text size="xs" c={r.learn_cost === null ? 'orange' : 'dimmed'}>
                {r.learn_cost === null ? learnNote(r, learn) : includedNote(learn)}
              </Text>
            )}
            <RunSpread result={r} />
          </Stack>
  )
  if (!onChoose) {
    const summary = (
      <Paper withBorder radius="md" p="sm" component="article" aria-label={r.output_name}>
        {body}
      </Paper>
    )
    return layoutId ? (
      <motion.div layoutId={layoutId} transition={LAYOUT} style={{ borderRadius: 8 }}>
        {summary}
      </motion.div>
    ) : (
      summary
    )
  }
  return (
    <motion.div
      layoutId={layoutId ?? `skill-option-${r.recipe_id}`}
      transition={LAYOUT}
      initial={fade ? { opacity: 0 } : false}
      animate={{ opacity: 1 }}
      style={{ borderRadius: 8 }}
    >
      <Paper
        withBorder
        radius="md"
        p="sm"
        h="100%"
        className={[lit && classes.lit, grow && classes.grow].filter(Boolean).join(' ') || undefined}
        {...(article ? { component: 'article', 'aria-label': r.output_name } : {})}
      >
        <UnstyledButton
          onClick={onChoose}
          aria-label={`${action} ${r.output_name}`}
          w="100%"
          h="100%"
          // a button centres its content: cards of three lines and of four start at the same height
          style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-start' }}
        >
          {body}
        </UnstyledButton>
      </Paper>
    </motion.div>
  )
}

/** A chain fading out where it was, over the options: what it showed and its box within them. */
type Departing = {
  key: number
  runs: RankResult[]
  start: number
  preview: boolean
  muted: boolean
  top: number
  left: number
  width: number
}

/** What the reminders to train the next profession rank need: the version's ranks, the cap the climber has and the
 * profession. */
type Training = { ranks: readonly ProfessionRank[]; maxRank: number; profession: string }

/** Reminders to train each profession rank a run from `from` to `to` skill reaches (`ranksToTrain`); none when it
 * reaches none. */
function TrainNote({ training, from, to, first }: { training: Training; from: number; to: number; first: boolean }) {
  const due = ranksToTrain(training.ranks, training.maxRank, from, to, first)
  if (!due.length) return null
  return (
    <Stack gap={4} className={classes.train}>
      {due.map(({ rank }) => {
        const name = `${rank.name} ${training.profession}`
        return (
          <Alert key={rank.name} variant="light" color="yellow" p="xs" title={`Train ${name}`}>
            <Text size="xs">
              Available at {rank.train_at} skill and level {rank.level}
            </Text>
          </Alert>
        )
      })}
    </Stack>
  )
}

/** A run's card with the reminders to train beside it (to its left on a wide screen with room, else above it). */
function Trained({
  training,
  from,
  to,
  first,
  children,
}: {
  training: Training
  from: number
  to: number
  first: boolean
  children: ReactNode
}) {
  return (
    <div className={classes.trained}>
      <TrainNote training={training} from={from} to={to} first={first} />
      {children}
    </div>
  )
}

/** The short arrow from one run to the run after it; with a `layoutId`, it moves with the chain (in a `div`: Motion
 * doesn't animate an SVG element's layout). */
function ChainArrow({ layoutId }: { layoutId?: string }) {
  return (
    <motion.div layoutId={layoutId} transition={LAYOUT} className={classes.arrow}>
      <svg width="16" height="24" viewBox="0 0 16 24" display="block" aria-hidden>
        <path d="M8 2v18M3 15l5 5 5-5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    </motion.div>
  )
}

/** The runs that follow a run, each under an arrow, hung under that run's card. `muted` while it isn't the chosen
 * option's own: the options are side by side, or its chain is on its way; `preview`: side by side, only the next run,
 * fading out downwards. `onOpen`: each card opens out in place, `opened` the one that has (its index and what it
 * shows instead of its card). `onMore`: Show more under the last, when
 * there may be more after it. The run crafted now's chain carries `layoutId` (named after the run it follows), so
 * its cards, arrows and skills move with that run's card, each on its own (the section is as wide as the row in the
 * single column, one column side by side: moved as one, its centred contents would start out of place); `column` places another option's under it, side by side. `fade`: it fades
 * in, arrows and all (a chain new to the run crafted now). */
function Chain({
  runs,
  start,
  items,
  learn,
  muted,
  pending,
  onMore,
  label = 'What comes after',
  layoutId,
  column,
  training,
  preview,
  onOpen,
  opened,
  fade,
  ref,
}: {
  runs: RankResult[]
  /** the skill the first of `runs` starts at: where the run they follow stops */
  start: number
  items: ItemMap
  learn: Record<string, Learn>
  muted: boolean
  pending: boolean
  onMore?: () => void
  label?: string
  layoutId?: string
  column?: number
  /** the reminders to train the next profession rank beside the cards (the single column only) */
  training?: Training
  preview?: boolean
  onOpen?: (index: number) => void
  opened?: { index: number; panel: ReactNode }
  fade?: boolean
  ref?: Ref<HTMLElement>
}) {
  if (preview) runs = runs.slice(0, 1)
  if (!runs.length && !pending) return null
  return (
    <motion.section
      ref={ref}
      transition={LAYOUT}
      // fading in, to the opacity its muting asks for (side by side, the next run alone isn't muted)
      initial={fade ? { opacity: 0 } : false}
      animate={fade ? { opacity: muted && !preview ? 0.4 : 1 } : undefined}
      className={classes.chain}
      style={column ? ({ '--column': column } as CSSProperties) : undefined}
      data-muted={muted || undefined}
      data-preview={preview || undefined}
      aria-disabled={muted || undefined}
      aria-label={label}
    >
      {runs.map((r, i) => {
        const from = i === 0 ? start : (runs[i - 1]?.stop_skill ?? 0)
        const card = (
          <OptionCard
            result={r}
            items={items}
            learn={learn[r.recipe_id]}
            // the run crafted now's chain: each card moves with it, opened out or not
            layoutId={layoutId && `${layoutId}-run-${i}`}
            {...(onOpen && {
              onChoose: () => onOpen(i),
              action: 'Open',
              lit: true,
              grow: true,
              article: true,
            })}
          />
        )
        const isOpen = opened?.index === i
        return (
          // a climb may come back to a recipe: keyed by place
          <Stack key={`${i}-${r.recipe_id}`} gap={4} className={isOpen ? undefined : classes.link}>
            <div className={classes.step}>
              <ChainArrow layoutId={layoutId && `${layoutId}-arrow-${i}`} />
              {from > 0 && (
                // by position: text isn't stretched
                <motion.div
                  layout={layoutId ? 'position' : false}
                  layoutId={layoutId && `${layoutId}-at-${i}`}
                  transition={LAYOUT}
                  className={classes.at}
                >
                  <Text size="xs" c="dimmed">
                    At {from} skill
                  </Text>
                </motion.div>
              )}
            </div>
            {isOpen ? (
              opened?.panel
            ) : training ? (
              <Trained training={training} from={from} to={r.stop_skill} first={false}>
                {card}
              </Trained>
            ) : (
              card
            )}
          </Stack>
        )
      })}
      {pending && <Loader size="xs" aria-label="Working out what comes after" className={classes.arrow} />}
      {onMore && !pending && (
        <Button size="compact-sm" variant="subtle" className={classes.chainMore} onClick={onMore}>
          Show more
        </Button>
      )}
    </motion.section>
  )
}

/**
 * Skilling up one profession on one character. First an overview: the run to craft now (the first of the cheapest
 * climb up the profession; each option counted as the first run of the cheapest climb starting with it, until the
 * climb goes on with another recipe, it turns trivial or the skill reaches its cap), centred, with the rest of its
 * climb hung below; Show me other options lays
 * the best few side by side, the chain muted under the one it follows until another is picked, which then folds
 * back to be the one crafted now. Clicking a card in the single column (the run crafted now or one of its chain, one at a time) opens it out in place into the full run: what to make until when, what it costs,
 * what the next best was, what comes after it, and a checklist per character to take into the game. The list holds still while new prices come in, until the
 * user refreshes it.
 */
export function SkillWorkspace({
  filters,
  climber,
  profession,
  reachTarget = DEFAULT_REACH_TARGET,
  hypothetical = false,
}: {
  filters: Filters
  climber: Holder
  profession: string
  /** the chance, in percent, that the crafts the checklist buys for reach the run's target */
  reachTarget?: number
  /** the climber is a character nobody uploaded (`filters.climberSkill`): no cap to have uploaded */
  hypothetical?: boolean
}) {
  const track = useTrack()
  const status = useStatus().data
  const livePrices = status?.price_version ?? 0
  // The price version the list was made at: it moves only on Refresh.
  const [frozen, setFrozen] = useState<number | undefined>(undefined)
  if (frozen === undefined && status) setFrozen(livePrices)
  const params = useMemo<RankParams>(() => ({ ...filters, top: OPTIONS }), [filters])
  const rank = useRank(params, { priceVersion: frozen })
  const version = useDataVersion()
  // The card opened out in the single column, at most one: 0 the run to craft now, i + 1 the chain's i-th run;
  // null: none.
  const [openAt, setOpenAt] = useState<number | null>(null)
  const results = rank.data?.results ?? []
  // The options side by side: the runs starting the cheapest climbs, each what picking it gives, else as listed;
  // in the server's order (a climb that ends lower may cost less, but isn't the better one).
  const options = rank.data?.options?.length ? rank.data.options : results.slice(0, OPTIONS)
  const bestId = results[0]?.recipe_id
  // the highest skill any option's climb reaches: Recommended only goes to the best if it gets there
  const highest = Math.max(0, ...options.map((r) => r.climb_end))
  // The option to craft now: the best unless the user picked another of the first few (null: the best).
  const [pickedId, setPickedId] = useState<number | null>(null)
  const nowIndex = Math.max(
    0,
    options.findIndex((r) => r.recipe_id === (pickedId ?? bestId)),
  )
  const ranked = options[nowIndex]
  const picked = ranked !== undefined && ranked.recipe_id !== bestId
  // Whether the first few options are laid out side by side, the user choosing among them.
  const [expanded, setExpanded] = useState(false)
  // How many runs the chain holds: CHAIN, and CHAIN_MORE more with each Show more (back to CHAIN on a pick).
  const [chainLength, setChainLength] = useState(CHAIN)
  const longer = chainLength > CHAIN
  // A picked option's run and the rest of its climb (the ranking itself is the server's cached one); the best's
  // come with the list, unless more of them are shown.
  const chainRank = useRank(
    { ...params, top: 1, chainFrom: ranked?.recipe_id, chainLength: longer ? chainLength : undefined },
    { priceVersion: frozen, enabled: picked || longer },
  )
  const restart = chainRank.data?.chain_start
  const now = picked && restart?.recipe_id === ranked?.recipe_id ? restart : ranked
  // The chain's layout id, named after the run it follows: another run's chain never moves into its place
  const chainId = `skill-chain-${now?.recipe_id ?? 0}`
  const chainData = picked || longer ? chainRank.data : rank.data
  // The chain on its way: a picked option's (the one shown before it stays, muted) or a longer one.
  const chainPending = (picked || longer) && (chainRank.isPlaceholderData || !chainRank.data)
  // A picked option's chain on its way: its own as it came with the list meanwhile, never the one shown before
  const current =
    picked && chainPending && !longer
      ? (rank.data?.option_chains?.[options.indexOf(ranked)] ?? NO_RUNS)
      : (chainData?.chain ?? rank.data?.chain ?? NO_RUNS)
  // The chain as last settled: what stays shown while a longer one is on its way.
  const [settled, setSettled] = useState(current)
  if (!chainPending && current !== settled) setSettled(current)
  const chain = chainPending && longer ? settled : current
  // muted among the options side by side, and while another chain is on its way (a longer one on its way keeps the
  // runs already shown as they are)
  const chainMuted = expanded || (chainPending && !longer)
  // the run opened out: the one crafted now as it stands after a pick (else as ranked), or one of its chain
  const open = expanded || openAt === null ? undefined : openAt === 0 ? now : chain[openAt - 1]
  // the skill the run opened out starts at
  const openFrom = !openAt ? climber.rank : openAt === 1 ? (now?.stop_skill ?? 0) : (chain[openAt - 2]?.stop_skill ?? 0)
  // a made-up climber is taken to train each rank as they come to it: never stuck at a cap
  const atCap = !hypothetical && climber.rank >= climber.maxRank
  const training: Training = { ranks: useProfessionRanks(), maxRank: climber.maxRank, profession }
  const planParams: EvaluateParams = {
    unlearned: filters.unlearned,
    lookAhead: filters.lookAhead,
    sources: filters.sources,
    includeTrivial: filters.includeTrivial,
    skillCrafters: filters.skillCrafters,
    exits: filters.exits,
    arcaneSalvager: filters.arcaneSalvager,
    runs: filters.runs,
    version,
    ...(filters.climberSkill !== undefined ? { climberSkill: filters.climberSkill } : {}),
  }
  const evaluate: EvaluateParams =
    openAt && now
      ? // a run of the chain, planned again as the chain has it: at the skill it starts from, in the climb of the run
        // crafted now (which never comes back to what that one leaves out)
        { ...planParams, climbWithout: now.climb_without, chain: { from: now.recipe_id, at: openAt } }
      : // an option side by side never comes back to those before it: planned again the same way
        { ...planParams, climbWithout: open?.climb_without }
  // The crafts the checklist buys for: what the user typed, else enough to reach the run's target with the chance
  // the Options ask for; planned again (debounced) when that isn't the ranked run's own count.
  const [typed, setTyped] = useState<number | null>(null)
  const buyCount = open ? (typed ?? craftsToReach(open, reachTarget)) : 0
  const [settledCount] = useDebouncedValue(buyCount, 400)
  // Each option's plan for the crafts it opens with, fetched ahead: opening one finds it ready.
  usePrefetchSessionPlans(
    [...options, ...(now && now !== ranked ? [now] : [])].flatMap((r) => {
      const copies = craftsToReach(r, reachTarget)
      return copies > r.crafts ? [{ recipeId: r.recipe_id, copies }] : []
    }),
    planParams,
  )
  const buyFor = open && settledCount > 0 && settledCount !== open.crafts ? settledCount : null
  // The user's changes to the run's plan (another source for a reagent, another way to sell); undefined: as ranked.
  const [choices, setChoices] = useState<Choices | undefined>(undefined)
  const modified = choices !== undefined
  const planning = buyFor !== null || modified
  const plan = useSessionPlan(open?.recipe_id ?? 0, evaluate, choices, buyFor, null, null, planning)
  // The server's plan for the count and choices when it has one, else the last plan in proportion, so the
  // quantities follow the count at once.
  const planned = (planning && plan.data?.result) || open
  // kept while neither moves: a new one would rebuild the flow chart's nodes, closing a menu open on it
  const checklist = useMemo(() => planned && scaleRun(planned, buyCount), [planned, buyCount])
  // The skill points Working Overtime adds to the crafts bought for (the ranked run's until their plan is back).
  const overtime = planned?.skill_ups_bonus ?? 0
  // Planning a count the user typed. The count a run opens with is fetched ahead; should it still be on its way, the
  // ranked run in proportion shows meanwhile, close enough to need no spinner.
  const replanning = typed !== null && plan.isFetching && !modified
  const editing: PlanEditing = {
    onChoose: (paths, key) => setChoices((prev) => paths.reduce((c, path) => chooseAt(c, path, key), prev ?? {})),
    modified,
    onReset: () => setChoices(undefined),
    pending: modified && plan.isFetching,
    error: modified ? (plan.error?.message ?? null) : null,
  }
  const items = useMemo(
    () => ({ ...rank.data?.items, ...chainRank.data?.items, ...plan.data?.items }),
    [rank.data, chainRank.data, plan.data],
  )
  // The run's market: closed at first; an item name in the plan opens it on that item.
  const [marketOpen, setMarketOpen] = useState<string | null>(null)
  const market = useMarket(checklist, 'skill', () => setMarketOpen('market'))
  const watchedHours = plan.data?.watched_hours ?? rank.data?.watched_hours ?? 0
  useEffect(() => {
    if (bestId !== undefined) track('next_up_shown', { profession })
  }, [bestId, profession, track])

  const [copied, setCopied] = useState(false)
  // The run's plan as its steps (first) or a flow chart.
  const [view, setView] = useState<PlanView>('steps')
  // The steps with where to go in between: one setting with the gold list's
  const [detailed, setDetailed] = useStoredState('altarmy.steps.detailed', z.boolean(), false)
  // The chain under the run crafted now is new to it (another run was picked): it fades in.
  const [freshChain, setFreshChain] = useState(false)
  // The chain shown before another run was picked, fading out where it was.
  const [departing, setDeparting] = useState<Departing | null>(null)
  const chainRef = useRef<HTMLElement>(null)
  const areaRef = useRef<HTMLDivElement>(null)
  // Scrolls an option being opened out fully into view as it grows: its layout is final as soon as it renders (the
  // growing is a transform), so the scroll runs alongside, with the same timing. A wheel or touch stops it.
  const runRef = useRef<HTMLElement>(null)
  const scrollPending = useRef(false)
  useLayoutEffect(() => {
    const el = runRef.current
    if (openAt === null || !scrollPending.current || !el) return
    scrollPending.current = false
    const target = scrollTarget(layoutTop(el), el.offsetHeight, window.scrollY, window.innerHeight)
    if (target === null) return
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      window.scrollTo(0, target)
      return
    }
    const scroll = animate(window.scrollY, target, { ...LAYOUT, onUpdate: (y) => window.scrollTo(0, y) })
    const stop = () => scroll.stop()
    window.addEventListener('wheel', stop, { passive: true })
    window.addEventListener('touchstart', stop, { passive: true })
    return () => {
      scroll.stop()
      window.removeEventListener('wheel', stop)
      window.removeEventListener('touchstart', stop)
    }
  }, [openAt])
  const choose = (at: number | null) => {
    setOpenAt(at)
    scrollPending.current = at !== null
    setTyped(null)
    setChoices(undefined)
    setView('steps')
    setCopied(false)
    if (at !== null) track('row_opened', { profession })
  }
  const copy = () => {
    if (!checklist) return
    const heading = `${profession}: ${checklist.output_name}. ${runText(open ?? checklist)}`
    const name = (id: number) => items[id]?.name ?? `item ${id}`
    const text = stepsText(heading, checklist.steps, detailed ? checklist.details : [], name)
    void navigator.clipboard?.writeText(text).then(() => setCopied(true))
    track('copy_steps', { profession })
  }

  if (rank.isPending) return <Loader />
  if (rank.isError) return <Alert color="red">{rank.error.message}</Alert>
  const learn = rank.data.learn
  const refresh = frozen !== undefined && livePrices !== frozen && (
    <Alert color="blue" title="Prices updated since this list was made">
      <Group justify="space-between">
        <Text size="sm">The list holds still while you work through it.</Text>
        <Button size="xs" variant="light" onClick={() => setFrozen(livePrices)}>
          Refresh
        </Button>
      </Group>
    </Alert>
  )
  const capCard = atCap && (
    <Alert color="orange" title={`You're at your ${profession} cap (${climber.maxRank})`}>
      Visit {an(profession)} {profession} trainer to learn the next rank, then /reload so Alt Army Sync uploads it.
    </Alert>
  )
  if (!results.length) {
    return (
      <Stack>
        {capCard}
        {refresh}
        {!atCap && <Alert>No path was found for {climber.name} to gain skill in {profession}</Alert>}
      </Stack>
    )
  }

  // Another run to craft now: its chain fades in under it, the one shown before fading out where it was (a copy,
  // laid over the options, since what it hung under is gone).
  const leave = (id: number) => {
    if (id === now?.recipe_id) return
    setFreshChain(true)
    const el = chainRef.current
    const area = areaRef.current
    if (!el || !area) return
    const box = el.getBoundingClientRect()
    const within = area.getBoundingClientRect()
    setDeparting({
      key: (departing?.key ?? 0) + 1,
      runs: chain,
      start: now?.stop_skill ?? 0,
      preview: expanded,
      muted: chainMuted,
      top: box.top - within.top,
      left: box.left - within.left,
      width: box.width,
    })
  }
  // Picking one of the options side by side makes it the one to craft now, the others folding away around it.
  const pick = (id: number) => {
    leave(id)
    setPickedId(id === bestId ? null : id)
    setChainLength(CHAIN)
    setExpanded(false)
  }
  // Back to the recommended climb, when another run to craft now was picked: the best and its own chain.
  const reset = () => {
    if (bestId !== undefined) leave(bestId)
    choose(null)
    setPickedId(null)
    setChainLength(CHAIN)
    setExpanded(false)
  }
  // The run opened out, in place of the card it grows out of
  const panel = open && (
    <motion.div
      layoutId={openAt === 0 ? `skill-option-${open.recipe_id}` : `${chainId}-run-${(openAt ?? 1) - 1}`}
      transition={LAYOUT}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      style={{ borderRadius: 8 }}
      className={classes.opened}
    >
        <Paper ref={runRef} withBorder p="md" radius="md" aria-label="Run details" component="section">
          <Stack gap="xs">
            {/* the recipe (and whether its plan was changed) on the left, Close on the right */}
            <Group justify="space-between" align="center" wrap="nowrap">
              <Group gap="xs" wrap="wrap">
                <Title order={4}>
                  <RecipeName result={open} items={items} />
                </Title>
                {modified && (
                  <Badge size="sm" variant="light" color="yellow">
                    Changed plan
                  </Badge>
                )}
              </Group>
              <Button size="compact-sm" variant="subtle" onClick={() => choose(null)} style={{ flexShrink: 0 }}>
                Close
              </Button>
            </Group>
            <Text size="lg" fw={700}>
              {/* the user's changed plan costs what it costs; otherwise the run as ranked */}
              <NetPerPoint result={(modified && planned) || open} />
            </Text>
            <Text size="sm">
              <RunText result={open} items={items} />
            </Text>
            <RunSpread result={open} range />
            <TrainNote training={training} from={openFrom} to={open.stop_skill} first={openAt === 0} />
            {learn[open.recipe_id] && mustLearn(open) && (
              <Text size="sm">
                {learnNote(open, learn[open.recipe_id])}:{' '}
                <LearnTooltip learn={learn[open.recipe_id]}>where to get it</LearnTooltip>
              </Text>
            )}
            <Divider my={4} />
            {open.stop_skill > 0 && (
              <Group gap="xs" wrap="nowrap">
                <NumberInput
                  size="xs"
                  w={90}
                  min={1}
                  max={MAX_BUY}
                  allowDecimal={false}
                  aria-label="Crafts to buy for"
                  value={buyCount}
                  onChange={(v) => setTyped(typeof v === 'number' && v >= 1 ? Math.min(v, MAX_BUY) : null)}
                />
                <Text size="xs" c="dimmed">
                  {reachPercent(open, buyCount)}% chance to reach your target of {open.stop_skill} skill
                  {overtime >= 0.05 && ` (includes ~${overtime.toFixed(1)} skill points from Working Overtime)`}
                </Text>
                {/* A slot of its own size, so the spinner never moves anything */}
                <Box w={SPINNER} h={SPINNER} style={{ flexShrink: 0 }}>
                  {replanning && <Loader size={SPINNER} aria-label="Planning" />}
                </Box>
              </Group>
            )}
            <Group gap="sm">
              <PlanViewSwitch value={view} onChange={setView} />
              {modified && (
                <Button size="compact-xs" variant="light" onClick={editing.onReset}>
                  Reset
                </Button>
              )}
              {editing.pending && <Loader size="xs" aria-label="Re-costing" />}
              {editing.error && (
                <Text size="xs" c="red">
                  {editing.error}
                </Text>
              )}
            </Group>
            {view === 'steps' && (
              <Checkbox
                label="Detailed view"
                size="xs"
                checked={detailed}
                onChange={(e) => {
                  setDetailed(e.currentTarget.checked)
                  setCopied(false)
                }}
              />
            )}
            <MarketFocus.Provider value={market.focus}>
            {checklist &&
              (view === 'flow' ? (
                <RecipeFlow result={checklist} items={items} editing={editing} />
              ) : (
                <StepList
                  result={checklist}
                  items={items}
                  editing={editing}
                  detailed={detailed}
                  mode="skill"
                  learn={
                    learn[open.recipe_id] &&
                    mustLearn(open) && (
                      <LearnStep
                        learn={learn[open.recipe_id]!}
                        recipe={open.output_name}
                        cost={open.learn_cost}
                        items={items}
                      />
                    )
                  }
                />
              ))}
            {checklist && (
              <Accordion variant="separated" transitionDuration={0} value={marketOpen} onChange={setMarketOpen}>
                <Accordion.Item value="market" ref={market.ref}>
                  <Accordion.Control>
                    Market <MarketSummary result={checklist} list={market.list} items={items} mode="skill" />
                  </Accordion.Control>
                  <Accordion.Panel>
                    <MarketSection
                      result={checklist}
                      items={items}
                      list={market.list}
                      selected={market.selected}
                      onSelect={market.select}
                      watchedHours={watchedHours}
                    />
                  </Accordion.Panel>
                </Accordion.Item>
              </Accordion>
            )}
            </MarketFocus.Provider>
            <Group gap="xs">
              <Button size="xs" variant="light" onClick={copy}>
                {copied ? 'Copied' : 'Copy steps'}
              </Button>
            </Group>
          </Stack>
        </Paper>
    </motion.div>
  )
  // The run crafted now's chain: under its card, opened out or not, and muted under it among the options
  const chainView = (
    <Chain
      runs={chain}
      start={now?.stop_skill ?? 0}
      items={items}
      learn={{ ...learn, ...chainRank.data?.learn }}
      key={chainId}
      ref={chainRef}
      layoutId={chainId}
      column={nowIndex + 1}
      fade={freshChain}
      // among the options side by side: the next run alone, and no reminders
      preview={expanded}
      training={expanded ? undefined : training}
      muted={chainMuted}
      pending={chainPending && !expanded}
      onMore={!expanded && chain.length >= chainLength ? () => setChainLength((n) => n + CHAIN_MORE) : undefined}
      // in the single column each run opens out in place; not while another chain is on its way
      onOpen={expanded || chainPending ? undefined : (i) => choose(openAt === i + 1 ? null : i + 1)}
      opened={panel && openAt !== null && openAt > 0 ? { index: openAt - 1, panel } : undefined}
    />
  )
  // Each option's chain as it came with the list, by recipe
  const optionChains = new Map(options.map((r, i) => [r.recipe_id, rank.data?.option_chains?.[i] ?? NO_RUNS]))

  return (
    <CharacterClasses.Provider value={rank.data.classes}>
      <Stack>
        {capCard}
        {refresh}
        <LayoutGroup>
          <Stack ref={areaRef} gap="xs" component="section" aria-label="Your options" pos="relative">
            <div className={classes.heading}>
              <Text size="lg" fw={600} ta="center" className={classes.title}>
                What to craft next
              </Text>
              {picked && (
                <Button size="compact-sm" variant="light" className={classes.reset} onClick={reset}>
                  Reset to recommended
                </Button>
              )}
            </div>
            {expanded ? (
              <div
                className={classes.options}
                style={
                  {
                    '--options': options.length,
                    '--now': nowIndex + 1,
                  } as CSSProperties
                }
              >
                {options.map((r, i) => (
                  <Fragment key={r.recipe_id}>
                    <Milestones
                      result={r.recipe_id === now?.recipe_id ? now : r}
                      column={i + 1}
                      fade={r.recipe_id !== now?.recipe_id}
                    />
                    <div className={classes.option} style={{ '--column': i + 1 } as CSSProperties}>
                      <OptionCard
                        result={r}
                        items={items}
                        learn={learn[r.recipe_id]}
                        fade={r.recipe_id !== now?.recipe_id}
                        lit
                        recommended={r.recipe_id === bestId && r.climb_end >= highest}
                        onChoose={() => pick(r.recipe_id)}
                      />
                    </div>
                    {/* every option's chain under it, muted until one is picked */}
                    {r.recipe_id === now?.recipe_id ? (
                      chainView
                    ) : (
                      <Chain
                        runs={optionChains.get(r.recipe_id) ?? NO_RUNS}
                        start={r.stop_skill}
                        items={items}
                        learn={learn}
                        label={`What comes after ${r.output_name}`}
                        column={i + 1}
                        muted
                        preview
                        pending={false}
                      />
                    )}
                  </Fragment>
                ))}
              </div>
            ) : (
              now && (
                <div className={classes.single}>
                  <Milestones result={now} />
                  {openAt === 0 && panel ? (
                    <div className={classes.nowOpen}>{panel}</div>
                  ) : (
                    <div className={classes.now}>
                      <Trained training={training} from={climber.rank} to={now.stop_skill} first>
                        <OptionCard
                          result={now}
                          items={items}
                          learn={learn[now.recipe_id]}
                          lit
                          grow
                          onChoose={() => choose(0)}
                        />
                      </Trained>
                    </div>
                  )}
                  {options.length > 1 && openAt !== 0 && (
                    <Button
                      variant="subtle"
                      size="compact-sm"
                      className={classes.more}
                      leftSection={<IconSwap size={16} />}
                      onClick={() => {
                        choose(null)
                        setFreshChain(false)
                        setExpanded(true)
                      }}
                    >
                      Other options ({options.length - 1})
                    </Button>
                  )}
                  {chainView}
                </div>
              )
            )}
            {departing && (
              <motion.div
                key={departing.key}
                aria-hidden
                className={classes.departing}
                data-single={!departing.preview || undefined}
                style={{ top: departing.top, left: departing.left, width: departing.width }}
                initial={{ opacity: 1 }}
                animate={{ opacity: 0 }}
                transition={LAYOUT}
                onAnimationComplete={() => setDeparting((d) => (d?.key === departing.key ? null : d))}
              >
                <Chain
                  runs={departing.runs}
                  start={departing.start}
                  items={items}
                  learn={learn}
                  muted={departing.muted}
                  preview={departing.preview}
                  pending={false}
                />
              </motion.div>
            )}
          </Stack>
        </LayoutGroup>
      </Stack>
    </CharacterClasses.Provider>
  )
}
