import { type CSSProperties, Fragment, type ReactNode, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Accordion, Alert, Badge, Box, Button, Checkbox, Divider, Group, List, Loader, NumberInput, Paper, SimpleGrid, Slider, Stack, Text, Title, Tooltip, UnstyledButton } from '@mantine/core'
import { LayoutGroup, animate, motion } from 'motion/react'
import { useDebouncedValue } from '@mantine/hooks'
import { z } from 'zod'
import type { ItemMap, Learn, RankResult } from '../api/client'
import {
  type EvaluateParams,
  type RankParams,
  type Source,
  type Strategy,
  useDataVersion,
  useProfessionRanks,
  useRank,
  usePrefetchSessionPlans,
  useSessionPlan,
  useStatus,
  useTrack,
  WHOLE_CHAIN,
} from '../api/queries'
import { choose as chooseAt, type Choices, type PlanEditing } from '../lib/choices'
import { MarketFocus, useMarket } from '../lib/marketFocus'
import { layoutTop, scrollTarget } from '../lib/scroll'
import { useStoredState } from '../lib/storage'
import type { Holder } from '../lib/setup'
import {
  an,
  craftsToReach,
  REACH_TARGET,
  customDetail,
  MAX_TIME_VALUE,
  mustLearn,
  rangeText,
  ranksToTrain, runText, sameSettings, strategySettings, type StrategySettings, scaleRun, stepsText, STRATEGY_LABELS, tailText } from '../lib/skill'
import {
  BARTERING,
  BARTERING_PERCENT,
  BARTERING_RANKS,
  MASTER_CHEF,
  MASTER_CHEF_PERCENT,
  MASTER_CHEF_RANKS,
  WORKING_OVERTIME,
  WORKING_OVERTIME_PERCENT,
  WORKING_OVERTIME_RANKS,
} from '../lib/talents'
import { CharacterClasses } from '../lib/characterClasses'
import { IconChevron, IconSwap } from './icons'
import { ItemLink } from './ItemTooltip'
import { LadderTable, type Training } from './LadderTable'
import { LearnStep, LearnTooltip } from './LearnTooltip'
import { SkillChanceChart } from './SkillChanceChart'
import { MarketSection, MarketSummary } from './MarketSection'
import { Earned, Money } from './Money'
import { RecipeFlow } from './RecipeFlow'
import { PlanViewSwitch, type PlanView } from './SessionDetails'
import { StepList } from './StepList'
import classes from './SkillWorkspace.module.css'

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

/** One strategy's card side by side (`StrategyOut`): its climb's first run and the runs after it. */
type Option = { key: Strategy; run: RankResult; chain: RankResult[] }

/** The Legacy talents a climb can be planned with at another rank than the climber's (the API's
 * `working_overtime`, `bartering`, `master_chef`), each with what a point of it does; Master Chef only for Cooking. */
const TALENT_SLIDERS = [
  {
    spellId: WORKING_OVERTIME,
    name: 'Working Overtime',
    maxRank: WORKING_OVERTIME_RANKS,
    tip: `Increases your chance to gain a skill increase by ${WORKING_OVERTIME_PERCENT}% per talent point`,
  },
  {
    spellId: BARTERING,
    name: 'Bartering',
    maxRank: BARTERING_RANKS,
    tip: `Reduces the gold price of items from all vendors by ${BARTERING_PERCENT}% per talent point`,
  },
  {
    spellId: MASTER_CHEF,
    name: 'Master Chef',
    maxRank: MASTER_CHEF_RANKS,
    tip: `Gives your cooking recipes a ${MASTER_CHEF_PERCENT}% chance per talent point to create an extra result`,
  },
] as const
type TalentRanks = Record<(typeof TALENT_SLIDERS)[number]['spellId'], number>

/** The sliders shown when skilling up `profession`. */
const slidersFor = (profession: string) =>
  TALENT_SLIDERS.filter((t) => t.spellId !== MASTER_CHEF || profession.toLowerCase() === 'cooking')

/** The climber's ranks of the talents the sliders set: as uploaded, 0 for one they lack (or a made-up climber). */
const climberRanks = (climber: Holder): TalentRanks =>
  Object.fromEntries(
    TALENT_SLIDERS.map(({ spellId }) => [spellId, climber.talents?.find((t) => t.spellId === spellId)?.rank ?? 0]),
  ) as TalentRanks

/** A slider per talent the climb is planned with, what a point of it does on hover. */
function TalentSliders({
  ranks,
  profession,
  onChange,
}: {
  ranks: TalentRanks
  profession: string
  onChange: (ranks: TalentRanks) => void
}) {
  return (
    <Group justify="center" gap="xl" className={classes.talents} role="group" aria-label="Legacy talents">
      {slidersFor(profession).map((t) => {
        const rank = ranks[t.spellId]
        return (
          <Stack key={t.spellId} gap={4} className={classes.talent}>
            <Group justify="space-between" gap="xs">
              <Tooltip label={t.tip} withArrow>
                <Text size="sm" fw={500}>
                  {t.name}
                </Text>
              </Tooltip>
              <Text size="sm" c="dimmed">
                {rank}/{t.maxRank}
              </Text>
            </Group>
            <Slider
              min={0}
              max={t.maxRank}
              step={1}
              value={rank}
              label={null}
              marks={Array.from({ length: t.maxRank + 1 }, (_, value) => ({ value }))}
              thumbLabel={t.name}
              onChange={(value) => onChange({ ...ranks, [t.spellId]: value })}
            />
          </Stack>
        )
      })}
    </Group>
  )
}

/** A strategy's summary: its name, with a button opening what it plans for, then what the climb its run starts is
 * expected to come to by each profession rank's cap above the climber's (spent in red, earned in green, and the
 * crafts it takes, patterns without a price named apart; a cap it never reaches said to be unreachable). Over the
 * strategy's table, or a card (its name a plain title, what it plans for always shown under the table): with
 * `onChoose`, among the strategies side by side, picking it on a click, with Customize under it (`onCustomize`);
 * with `card`, as it stands, beside a strategy being customized. It moves between them (by position: text isn't
 * stretched; `layoutKey` names it, by default its strategy); `fade`: it fades in as the other strategies open out.
 * `name` and `detail` stand in for the strategy's own (a custom strategy's from its settings). */
function Milestones({
  result,
  strategy,
  column,
  fade,
  onChoose,
  onCustomize,
  customizeLabel = 'Customize',
  card = false,
  name: ownName,
  detail: ownDetail,
  layoutKey,
}: {
  result: RankResult | undefined
  strategy: Strategy
  column?: number
  fade?: boolean
  onChoose?: () => void
  onCustomize?: () => void
  /** the button's word: Customize, or Edit for the custom strategy */
  customizeLabel?: string
  card?: boolean
  name?: string
  detail?: string[]
  layoutKey?: string
}) {
  const [about, setAbout] = useState(false)
  const aboutId = useId()
  if (!result) return null
  const milestones = result.milestones
  const name = ownName ?? STRATEGY_LABELS[strategy].name
  const detail = ownDetail ?? STRATEGY_LABELS[strategy].detail
  const asCard = card || !!onChoose
  const plans = (
    <List id={aboutId} size="xs" c="dimmed" ta="left" className={classes.strategyAbout}>
      {detail.map((line) => (
        <List.Item key={line}>{line}</List.Item>
      ))}
    </List>
  )
  const summary = (
    <div
      role="group"
      className={classes.summary}
      aria-label={`Cost to reach each rank with ${result.output_name} first`}
    >
      {/* on a card, its name a plain title and what it plans for always shown, under the table */}
      {asCard ? (
        <Text fw={600}>{name}</Text>
      ) : (
        <UnstyledButton
          className={classes.strategyName}
          aria-expanded={about}
          aria-controls={aboutId}
          onClick={() => setAbout((open) => !open)}
        >
          <Text fw={600}>{name}</Text>
          <span className={classes.chevron} data-open={about || undefined}>
            <IconChevron size={16} />
          </span>
        </UnstyledButton>
      )}
      {!asCard && about && plans}
      {/* skills on the left, amounts and crafts on the right; patterns without a price under their row */}
      {milestones.length > 0 && (
      <table className={classes.milestoneTable}>
        <thead>
          <tr>
            <th scope="col">Skill</th>
            <th scope="col">Cost</th>
            <th scope="col">Crafts</th>
          </tr>
        </thead>
        <tbody>
          {milestones.map((m) => (
            <Fragment key={m.skill}>
              {m.reachable === false ? (
                // the climb ends short of it: the word laid over both columns, so it widens neither
                <tr>
                  <th scope="row">{m.skill}</th>
                  <td colSpan={2} className={classes.unreachable}>
                    {' '}
                    <span>Unreachable</span>
                  </td>
                </tr>
              ) : (
                <tr>
                  <th scope="row">{m.skill}</th>
                  <td>
                    <Earned copper={-m.cost} minus />
                  </td>
                  <td>~{m.crafts}</td>
                </tr>
              )}
              {m.unknown > 0 && (
                <tr>
                  <td colSpan={3} className={classes.milestoneNote}>
                    + {m.unknown} pattern{m.unknown === 1 ? '' : 's'} of unknown price
                  </td>
                </tr>
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
      )}
      {asCard && plans}
    </div>
  )
  return (
    <motion.div
      layout="position"
      layoutId={`skill-milestones-${layoutKey ?? strategy}`}
      transition={LAYOUT}
      initial={fade ? { opacity: 0 } : false}
      animate={{ opacity: 1 }}
      className={classes.milestones}
      style={column ? ({ '--column': column } as CSSProperties) : undefined}
    >
      {card && !onChoose ? (
        <Paper withBorder radius="md" p="sm" className={classes.card} component="section" aria-label={name}>
          {summary}
        </Paper>
      ) : onChoose ? (
        <Paper
          withBorder
          radius="md"
          p="sm"
          className={classes.choice}
          role="button"
          tabIndex={0}
          aria-label={`Choose ${name}: ${result.output_name}`}
          onClick={onChoose}
          onKeyDown={(e) => {
            if (e.key !== 'Enter' && e.key !== ' ') return
            e.preventDefault()
            onChoose()
          }}
        >
          {summary}
        </Paper>
      ) : (
        summary
      )}
      {onCustomize && (
        <Button
          variant="subtle"
          size="compact-sm"
          className={classes.customize}
          onClick={onCustomize}
          aria-label={`${customizeLabel} ${name}`}
        >
          {customizeLabel}
        </Button>
      )}
    </motion.div>
  )
}

/** The settings of a custom strategy, being made from another: the sources its recipes may be taught by, what a
 * minute of the climber's time is worth (in silver, sent in copper), and the least chance of a point it crafts at;
 * Use this strategy (unless no source is ticked) or Cancel. */
function CustomizeForm({
  settings,
  onChange,
  onDone,
  onCancel,
}: {
  settings: StrategySettings
  onChange: (settings: StrategySettings) => void
  onDone: () => void
  onCancel: () => void
}) {
  return (
    <Stack gap="sm" className={classes.customizeForm} component="form" aria-label="Custom strategy" onSubmit={(e) => {
      e.preventDefault()
      if (settings.sources.length) onDone()
    }}>
      <Checkbox.Group
        label="Recipes taught by"
        value={settings.sources}
        onChange={(sources) => onChange({ ...settings, sources: sources as Source[] })}
        error={settings.sources.length ? undefined : 'Pick at least one'}
      >
        <Group gap="md" mt={4}>
          <Checkbox value="trainer" label="Trainers" />
          <Checkbox value="recipe" label="Patterns you can buy" />
          <Checkbox value="bop" label="Bind on pickup patterns" />
        </Group>
      </Checkbox.Group>
      <NumberInput
        label="How much is your time worth to you?"
        description="If an option takes 1 minute longer, it has to save you at least this much money."
        min={0}
        max={MAX_TIME_VALUE / 100}
        // never past the most the server takes, even while typing (it answers more with a 422)
        clampBehavior="strict"
        step={1}
        decimalScale={2}
        allowNegative={false}
        suffix=" silver per minute"
        value={settings.timeValue / 100}
        onChange={(v) =>
          onChange({
            ...settings,
            timeValue: Math.min(MAX_TIME_VALUE, Math.round(Math.max(0, asNumber(v)) * 100)),
          })
        }
      />
      <NumberInput
        label="Lowest chance of a skill point"
        description="Do not craft a recipe with a skill up chance less than this (unless there's no other option)"
        min={0}
        max={100}
        clampBehavior="strict"
        allowDecimal={false}
        allowNegative={false}
        suffix="%"
        value={Math.round(settings.minChance * 100)}
        onChange={(v) => onChange({ ...settings, minChance: Math.min(100, Math.max(0, asNumber(v))) / 100 })}
      />
      <Group gap="sm">
        <Button type="submit" disabled={!settings.sources.length}>
          Use this strategy
        </Button>
        <Button variant="subtle" onClick={onCancel}>
          Cancel
        </Button>
      </Group>
    </Stack>
  )
}

/** A recipe's name. */
function RecipeName({ result, items }: { result: RankResult; items: ItemMap }) {
  return <ItemLink item={items[result.output_item_id]} name={result.output_name} />
}

/** How far to craft and, unless another recipe takes over there, why it stops. */
function RunText({ result: r }: { result: RankResult }) {
  return <>{runText(r)}</>
}

/** What a NumberInput holds: it reports a number, or the text as typed when that isn't one yet (a leading zero,
 * a trailing point, nothing at all); 0 when the text says no number. */
const asNumber = (v: number | string): number => {
  const n = typeof v === 'number' ? v : Number.parseFloat(v)
  return Number.isFinite(n) ? n : 0
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

/** Reminders to train each profession rank a run from `from` to `to` skill reaches (`ranksToTrain`); none when it
 * reaches none. */
function TrainNote({ training, from, to, first }: { training: Training; from: number; to: number; first: boolean }) {
  const due = ranksToTrain(training.ranks, training.maxRank, from, to, first)
  if (!due.length) return null
  return (
    <Stack gap={4}>
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

/**
 * Skilling up one profession on one character: the strategy's whole climb as a table (`LadderTable`), the run to
 * craft now first (each run counted as the cheapest climb's, until the climb goes on with another recipe, it turns
 * trivial or the skill reaches its cap), under what the climb comes to by each rank. Compare strategies lays the
 * strategies' summaries side by side as cards; picking one shows its climb's table. A row
 * opens out under itself into the full run: what to make until when, what it costs, what the next best was, and a
 * checklist per character to take into the game. The list holds still while new prices come in, until the user
 * refreshes it.
 */
export function SkillWorkspace({
  filters,
  climber,
  profession,
  reachTarget = REACH_TARGET,
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
  // The talent ranks the climbs are planned with: the climber's own until the user moves a slider (again theirs for
  // another climber); planned once the slider settles.
  const [talents, setTalents] = useState({ who: climber.name, ranks: climberRanks(climber) })
  if (talents.who !== climber.name) setTalents({ who: climber.name, ranks: climberRanks(climber) })
  const [ranks] = useDebouncedValue(talents.ranks, 300)
  const overtimeRank = ranks[WORKING_OVERTIME]
  const barteringRank = ranks[BARTERING]
  // Master Chef only counts for Cooking: not sent otherwise
  const chefRank = profession.toLowerCase() === 'cooking' ? ranks[MASTER_CHEF] : undefined
  const params = useMemo<RankParams>(
    () => ({
      ...filters,
      workingOvertime: overtimeRank,
      bartering: barteringRank,
      ...(chefRank !== undefined ? { masterChef: chefRank } : {}),
      top: 1,
      // the table shows the whole climb
      chainLength: WHOLE_CHAIN,
    }),
    [filters, overtimeRank, barteringRank, chefRank],
  )
  const rank = useRank(params, { priceVersion: frozen })
  const version = useDataVersion()
  // The card opened out in the single column, at most one: 0 the run to craft now, i + 1 the chain's i-th run;
  // null: none.
  const [openAt, setOpenAt] = useState<number | null>(null)
  const results = rank.data?.results ?? []
  // The strategies side by side, each what picking it gives, in the server's order (the recommended one first);
  // without them, the recommended one as ranked.
  const options = useMemo<Option[]>(() => {
    const strategies = rank.data?.strategies ?? []
    if (strategies.length)
      return strategies.map((o) => ({ key: o.key, run: o.run, chain: o.chain }))
    const first = rank.data?.results[0]
    return first ? [{ key: 'recommended', run: first, chain: rank.data?.chain ?? NO_RUNS }] : []
  }, [rank.data])
  const bestId = results[0]?.recipe_id
  // The strategy to craft now: the recommended one unless the user picked another (null: the recommended one).
  const [pickedKey, setPickedKey] = useState<Strategy | null>(null)
  // The user's own strategy, once they made one unlike every built-in one; null: none.
  const [custom, setCustom] = useState<StrategySettings | null>(null)
  // A strategy being customized: the one it started from, and the settings so far.
  const [customizing, setCustomizing] = useState<{ base: Strategy; draft: StrategySettings } | null>(null)
  const customParams = (c: StrategySettings) => ({
    strategy: 'custom' as const,
    sources: c.sources,
    timeValue: c.timeValue,
    minChance: c.minChance,
  })
  // The custom strategy's whole climb: its card among the others, and its table once picked.
  const customRank = useRank(custom ? { ...params, ...customParams(custom) } : params, {
    priceVersion: frozen,
    enabled: custom !== null,
  })
  const customRun = custom ? customRank.data?.results[0] : undefined
  const customOption: Option | null = customRun
    ? { key: 'custom', run: customRun, chain: customRank.data?.chain ?? NO_RUNS }
    : null
  // The strategies side by side: the custom one first, when there is one, unless the search's sources have since made
  // it one of the built-in ones (picked, it stays)
  const BUILT_IN = ['recommended', 'cheapest', 'no_patterns'] as const
  const customIsBuiltIn = (c: StrategySettings) =>
    BUILT_IN.find((k) => sameSettings(c, strategySettings(k, filters.sources)))
  const compared =
    customOption && custom && (pickedKey === 'custom' || !customIsBuiltIn(custom)) ? [customOption, ...options] : options
  // The settings being customized, planned once they settle: only the start of the climb, its summary
  const [draft] = useDebouncedValue(customizing?.draft ?? null, 400)
  const draftRank = useRank(draft ? { ...params, ...customParams(draft), chainLength: undefined } : params, {
    priceVersion: frozen,
    enabled: customizing !== null && draft !== null,
  })
  // The draft's run as last planned: never another query's kept while the first one loads
  const [draftShown, setDraftShown] = useState<RankResult | undefined>(undefined)
  const draftFresh =
    customizing && draft && draftRank.data && !draftRank.isPlaceholderData ? draftRank.data.results[0] : undefined
  if (draftFresh && draftFresh !== draftShown) setDraftShown(draftFresh)
  const nowIndex = Math.max(
    0,
    compared.findIndex((o) => o.key === (pickedKey ?? 'recommended')),
  )
  // the custom strategy picked: nothing to show until its climb comes
  const waitingForCustom = pickedKey === 'custom' && !customOption
  const nowOption = waitingForCustom ? undefined : compared[nowIndex]
  const nowKey: Strategy = waitingForCustom ? 'custom' : (nowOption?.key ?? 'recommended')
  const ranked = nowOption?.run
  const picked = nowKey !== 'recommended'
  // Whether the first few options are laid out side by side, the user choosing among them.
  const [expanded, setExpanded] = useState(false)
  // A picked strategy's run and the rest of its climb, ranked under it; the recommended one's come with the list.
  const chainRank = useRank(nowKey === 'custom' && custom ? { ...params, ...customParams(custom) } : { ...params, strategy: nowKey }, {
    priceVersion: frozen,
    enabled: picked,
  })
  const restart = picked && !chainRank.isPlaceholderData ? chainRank.data?.results[0] : undefined
  const now = restart?.recipe_id === ranked?.recipe_id ? restart : ranked
  // A picked strategy's climb on its way: the start of it as it came with the list meanwhile, never another's
  const chainPending = picked && (chainRank.isPlaceholderData || !chainRank.data)
  const chain = picked
    ? chainPending
      ? (nowOption?.chain ?? NO_RUNS)
      : (chainRank.data?.chain ?? NO_RUNS)
    : (rank.data?.chain ?? NO_RUNS)
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
    sources: nowKey === 'custom' && custom ? custom.sources : filters.sources,
    ...(nowKey === 'custom' && custom ? { timeValue: custom.timeValue, minChance: custom.minChance } : {}),
    includeTrivial: filters.includeTrivial,
    skillCrafters: filters.skillCrafters,
    exits: filters.exits,
    arcaneSalvager: filters.arcaneSalvager,
    runs: filters.runs,
    version,
    strategy: nowKey,
    workingOvertime: overtimeRank,
    bartering: barteringRank,
    ...(chefRank !== undefined ? { masterChef: chefRank } : {}),
    ...(filters.climberSkill !== undefined ? { climberSkill: filters.climberSkill } : {}),
  }
  // a run of the chain, planned again as the chain has it: at the skill it starts from, in the climb of the run
  // crafted now; any run under the strategy it was planned by
  const evaluate: EvaluateParams =
    openAt && now ? { ...planParams, chain: { from: now.recipe_id, at: openAt } } : planParams
  // The crafts the checklist buys for: what the user typed, else enough to reach the run's target with the chance
  // the Options ask for; planned again (debounced) when that isn't the ranked run's own count.
  const [typed, setTyped] = useState<number | null>(null)
  // Other talent ranks change the run's chances: the count follows the target again.
  const [typedAt, setTypedAt] = useState(ranks)
  if (typedAt !== ranks) {
    setTypedAt(ranks)
    setTyped(null)
  }
  const buyCount = open ? (typed ?? craftsToReach(open, reachTarget)) : 0
  const [settledCount] = useDebouncedValue(buyCount, 400)
  // Each strategy's plan for the crafts it opens with, fetched ahead: opening one finds it ready.
  // (the custom strategy's settings ride on the plan's parameters: with it picked, only its own run)
  usePrefetchSessionPlans(
    [
      ...(nowKey === 'custom' ? [] : options.map((o) => ({ r: o.run, strategy: o.key }))),
      ...(now && (now !== ranked || nowKey === 'custom') ? [{ r: now, strategy: nowKey }] : []),
    ].flatMap(({ r, strategy }) => {
      const copies = craftsToReach(r, reachTarget)
      return copies > r.crafts ? [{ recipeId: r.recipe_id, copies, strategy }] : []
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
    () => ({ ...rank.data?.items, ...customRank.data?.items, ...chainRank.data?.items, ...plan.data?.items }),
    [rank.data, customRank.data, chainRank.data, plan.data],
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
  const learn = { ...rank.data.learn, ...chainRank.data?.learn }
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

  // Picking one of the strategies side by side shows its climb, the others folding away.
  const pick = (key: Strategy) => {
    setPickedKey(key === 'recommended' ? null : key)
    setExpanded(false)
  }
  // Back to the recommended climb, when another strategy was picked.
  const reset = () => {
    choose(null)
    setPickedKey(null)
    setExpanded(false)
  }
  // Customizing a strategy side by side: its settings to start from.
  const customize = (key: Strategy) => {
    choose(null)
    setDraftShown(undefined)
    const from = key === 'custom' ? custom : strategySettings(key, filters.sources)
    if (from) setCustomizing({ base: key, draft: from })
  }
  // The strategy customized: its climb's table. Settings a built-in strategy has pick that one instead.
  const finishCustomizing = () => {
    if (!customizing) return
    const { draft } = customizing
    setCustomizing(null)
    const builtIn = customIsBuiltIn(draft)
    if (builtIn) {
      pick(builtIn)
      return
    }
    setCustom(draft)
    pick('custom')
  }
  // The run opened out: its full view, under its row
  const details = open && (
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
            {/* what the run comes to and how far it goes on the left, its skill-up chance on the right */}
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md" verticalSpacing="xs">
              <Stack gap="xs">
                <Text size="lg" fw={700}>
                  {/* the user's changed plan costs what it costs; otherwise the run as ranked */}
                  <NetPerPoint result={(modified && planned) || open} />
                </Text>
                <Text size="sm">
                  <RunText result={open} />
                </Text>
                <RunSpread result={open} range />
              </Stack>
              <SkillChanceChart result={open} from={openFrom} />
            </SimpleGrid>
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
                  onChange={(v) => setTyped(asNumber(v) >= 1 ? Math.min(Math.floor(asNumber(v)), MAX_BUY) : null)}
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
  )
  return (
    <CharacterClasses.Provider value={rank.data.classes}>
      <Stack>
        {capCard}
        {refresh}
        <LayoutGroup>
          <Stack gap="xs" component="section" aria-label="Your options" pos="relative">
            {picked && (
              <div className={classes.heading}>
                <Button size="compact-sm" variant="light" className={classes.reset} onClick={reset}>
                  Reset to recommended
                </Button>
              </div>
            )}
            <TalentSliders
              ranks={talents.ranks}
              profession={profession}
              onChange={(ranks) => setTalents({ who: climber.name, ranks })}
            />
            {customizing ? (
              <div className={classes.customizing}>
                <Milestones
                  result={(() => {
                    const base = compared.find((o) => o.key === customizing.base)
                    return customizing.base === nowKey && now ? now : base?.run
                  })()}
                  strategy={customizing.base}
                  detail={customizing.base === 'custom' && custom ? customDetail(custom) : undefined}
                  column={1}
                  card
                />
                {draftShown ? (
                  <Milestones
                    result={draftShown}
                    strategy="custom"
                    name="Your strategy"
                    detail={customDetail(customizing.draft)}
                    layoutKey="draft"
                    column={2}
                    card
                  />
                ) : (
                  <div className={classes.milestones} style={{ '--column': 2 } as CSSProperties}>
                    <Paper withBorder radius="md" p="sm" className={classes.card} component="section" aria-label="Your strategy">
                      <Stack align="center" gap="xs">
                        <Text fw={600}>Your strategy</Text>
                        <Loader size="sm" aria-label="Planning your strategy" />
                      </Stack>
                    </Paper>
                  </div>
                )}
                <CustomizeForm
                  settings={customizing.draft}
                  onChange={(settings) => setCustomizing({ ...customizing, draft: settings })}
                  onDone={finishCustomizing}
                  onCancel={() => setCustomizing(null)}
                />
              </div>
            ) : expanded ? (
              <div
                className={classes.options}
                style={
                  {
                    '--options': compared.length,
                    '--now': nowIndex + 1,
                  } as CSSProperties
                }
              >
                {compared.map(({ key, run: r }, i) => (
                  <Milestones
                    key={key}
                    result={key === nowKey && now ? now : r}
                    strategy={key}
                    detail={key === 'custom' && custom ? customDetail(custom) : undefined}
                    column={i + 1}
                    fade={key !== nowKey}
                    onChoose={() => pick(key)}
                    onCustomize={() => customize(key)}
                    // the custom one is edited, the built-in ones customized
                    customizeLabel={key === 'custom' ? 'Edit' : 'Customize'}
                  />
                ))}
              </div>
            ) : waitingForCustom ? (
              <Loader aria-label="Planning your strategy" />
            ) : (
              now && (
                <div className={classes.single}>
                  <Milestones
                    result={now}
                    strategy={nowKey}
                    detail={nowKey === 'custom' && custom ? customDetail(custom) : undefined}
                  />
                  {compared.length > 1 && (
                    <Button
                      variant="subtle"
                      size="compact-sm"
                      className={classes.more}
                      leftSection={<IconSwap size={16} />}
                      onClick={() => {
                        choose(null)
                        setExpanded(true)
                      }}
                    >
                      Compare strategies
                    </Button>
                  )}
                  <LadderTable
                    runs={[now, ...chain]}
                    start={climber.rank}
                    items={items}
                    training={training}
                    pending={chainPending}
                    openAt={openAt}
                    onOpen={(i) => choose(openAt === i ? null : i)}
                    details={details}
                    className={classes.ladder}
                  />
                </div>
              )
            )}
          </Stack>
        </LayoutGroup>
      </Stack>
    </CharacterClasses.Provider>
  )
}
