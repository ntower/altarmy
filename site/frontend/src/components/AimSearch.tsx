import { memo, type ReactNode, useEffect, useId, useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Checkbox,
  Group,
  Loader,
  NumberInput,
  SegmentedControl,
  SimpleGrid,
  Stack,
  Text,
  Tooltip,
  UnstyledButton,
  useMantineTheme,
  VisuallyHidden,
} from '@mantine/core'
import { z } from 'zod'
import {
  ALL_SOURCES,
  type Effort,
  type RankParams,
  type RankSort,
  type Source,
  useAhBlocked,
  useDataVersion,
  useFavorites,
  useRank,
  useSetAhBlocked,
  useSetFavorite,
} from '../api/queries'
import { goldToCopper } from '../lib/money'
import {
  ALL_EXITS,
  type Aim,
  legacySearchKey,
  type ProfessionChoice,
  rankProfessions,
  rankSort,
  searchKey,
  type Setup as SetupAnswers,
  SKILL_EXITS,
  skillCrafters,
} from '../lib/setup'
import { DEFAULT_REACH_TARGET, MAX_REACH_TARGET, MIN_REACH_TARGET } from '../lib/skill'
import { useStoredState } from '../lib/storage'
import { IconChevron, IconInfo } from './icons'
import { HOW_TO_SCAN } from './PriceFreshness'
import { ProfessionIcon } from './ProfessionIcon'
import classes from './SearchTab.module.css'
import { type GoldSort, ResultsTable, type SortOrder } from './ResultsTable'
import { SkillWorkspace } from './SkillWorkspace'
import { CraftsPerSession } from './CraftsPerSession'

/** Results per page: the first request asks for this many, and each "Show more" for this many more. */
const PAGE = 50

/** The professions with spells that enhance an item and make none (enchants, Engineering's tinkers). Skilling one of
 * them up always ranks such casts for the skill point alone: they sell nothing, so they rank at a dead loss, and the
 * climb takes one only where nothing gives the point cheaper. */
const ENHANCING: ReadonlySet<string> = new Set(['enchanting', 'engineering'])
/** The Arcane Salvager checkbox is hidden for now: while it is, disenchants never count on a salvager. */
export const SHOW_ARCANE_SALVAGER = false

/**
 * One way to sell: its checkbox, with the explanation in a tooltip beside it (and as the checkbox's description for
 * screen readers), so the options stay one short row. A `warning` sentence follows the explanation in a warning
 * colour, an `aside` (a secondary detail) goes on a line of its own in smaller, fainter text, and a `note` (something
 * about the user's characters) on a line of its own in the warning colour.
 */
function SellVia({
  value,
  label,
  description,
  warning,
  aside,
  note,
}: {
  value: string
  label: string
  description: string
  warning?: string | undefined
  aside?: string | undefined
  note?: string | undefined
}) {
  const id = useId()
  const text = [description, warning, aside, note].filter(Boolean).join(' ')
  const tooltip = (
    <>
      {description}
      {warning && (
        <>
          {' '}
          <span className={classes.warning}>{warning}</span>
        </>
      )}
      {aside && <div className={classes.aside}>{aside}</div>}
      {note && <div className={classes.warning}>{note}</div>}
    </>
  )
  return (
    <Group gap={6} wrap="nowrap">
      <Checkbox value={value} label={label} aria-describedby={id} />
      <VisuallyHidden id={id}>{text}</VisuallyHidden>
      <Tooltip label={tooltip} multiline w={280} withArrow events={{ hover: true, focus: false, touch: true }}>
        <Text component="span" c="dimmed" lh={0} aria-hidden="true">
          <IconInfo size={15} />
        </Text>
      </Tooltip>
    </Group>
  )
}

/**
 * The options, a section named `label`. It starts open, except where its columns stack (below the `sm` breakpoint): there
 * it starts closed, so the results are not pushed a screen down. Its content stays mounted either way.
 */
function Options({ label, children }: { label: string; children: ReactNode }) {
  const theme = useMantineTheme()
  // the complement of SimpleGrid's own `sm` query, so the section starts closed exactly where the columns stack
  const [open, setOpen] = useState<string | null>(() =>
    window.matchMedia(`not all and (min-width: ${theme.breakpoints.sm})`).matches ? null : 'filters',
  )
  return (
    <Accordion
      variant="separated"
      transitionDuration={0}
      keepMountedMode="display-none"
      value={open}
      onChange={setOpen}
    >
      <Accordion.Item value="filters">
        <Accordion.Control>{label}</Accordion.Control>
        <Accordion.Panel>{children}</Accordion.Panel>
      </Accordion.Item>
    </Accordion>
  )
}

const SOURCES: { value: Source; label: string; description?: string }[] = [
  { value: 'trainer', label: 'Taught by trainers' },
  {
    value: 'recipe',
    label: 'Taught by normal recipes',
    description:
      'Includes recipes sold by vendors (even if they are bind-on-pickup) and non-soulbound recipes you could find on the auction house.',
  },
  { value: 'bop', label: 'Taught by bind on pickup recipes' },
]
const sourceList = z.array(z.enum(['trainer', 'recipe', 'bop']))
const DEFAULT_SOURCES: Source[] = ['trainer', 'recipe']
const effortSchema = z.enum(['cheapest', 'balanced', 'fewest'])
const EFFORTS: { value: Effort; label: string }[] = [
  { value: 'cheapest', label: 'Cheapest' },
  { value: 'balanced', label: 'Balanced' },
  { value: 'fewest', label: 'Fewest crafts' },
]
/** What each Plan for weighs (the API's `CRAFT_VALUES`). */
const EFFORT_NOTES: Record<Effort, string> = {
  cheapest: 'The least gold, however many crafts the last points before grey take.',
  balanced: 'Counts each craft as worth 50 copper: no point takes dozens of crafts unless nothing else gives it.',
  fewest: 'Counts each craft as worth 2 silver: fewer crafts for a little more gold.',
}
const SECTIONS = ['advanced'] as const
const NONE_OPEN: string[] = []

const bound = z.number().nullable()
/** NumberInput reports an empty field as ''; that means no bound. */
const toBound = (v: number | string) => (typeof v === 'number' ? v : null)
const scaled = (v: number | null, f: (v: number) => number) => (v === null ? null : f(v))

type Filters = Omit<RankParams, 'top'>

/** The gold list's orders, all the server's (over the whole ranking, not just the rows loaded), picked by its
 * Safe and Auction house headers; none picked: the better of the two. A stored sort from before (all sell, ROI,
 * least spent, profit each) reads as that default. */
const goldSortSchema = z.enum(['likely', 'safe', 'ah'])
const sortOrderSchema = z.enum(['desc', 'asc'])
/** Under this many hours of back-to-back scans this week, a house's sales are barely seen. */
const WATCHED_ENOUGH_HOURS = 3

/**
 * `value` once it has stopped changing for `wait` ms (typing a bound re-ranks once, not per key), except that a new
 * `flush` (the characters just loaded) takes it at once, so the results never show a request with stale filters.
 */
function useSettled<T>(value: T, wait: number, flush: number): T {
  const [settled, setSettled] = useState({ value, flush })
  const flushing = settled.flush !== flush
  if (flushing) setSettled({ value, flush })
  useEffect(() => {
    // A timer already queued before the flush must not bring the older value back after it.
    const timer = setTimeout(() => setSettled((prev) => (prev.flush === flush ? { value, flush } : prev)), wait)
    return () => clearTimeout(timer)
  }, [value, wait, flush])
  return flushing ? value : settled.value
}

/** Memoized: opening or closing a filter section re-renders the search, and the table is the costly part. */
const Results = memo(function Results({
  filters,
  browsing,
  onGoldSort,
}: {
  filters: Filters
  browsing: boolean
  /** Re-rank a gold list by a column's header. */
  onGoldSort?: (sort: GoldSort, order: SortOrder) => void
}) {
  // Back to one page whenever the filters change.
  const [page, setPage] = useState({ filters, top: PAGE })
  const top = page.filters === filters ? page.top : PAGE
  const rank = useRank({ ...filters, top })
  const version = useDataVersion()
  const ahBlockedList = useAhBlocked().data
  const ahBlocked = useMemo(() => new Set(ahBlockedList?.items.map((i) => i.item_id)), [ahBlockedList])
  const { mutate: setAhBlocked } = useSetAhBlocked()
  const favoriteList = useFavorites().data
  const favorites = useMemo(() => new Set(favoriteList?.recipes.map((f) => f.recipe_id)), [favoriteList])
  const { mutate: setFavorite } = useSetFavorite()
  if (rank.isPending) return <Loader />
  if (rank.isError) return <Alert color="red">{rank.error.message}</Alert>
  const { results, total, items } = rank.data
  const skill = filters.sort === 'skill'
  if (!results.length) {
    return (
      <Stack>
        <Alert>
          {browsing
            ? 'No recipes match these filters with the current prices.'
            : 'No recipes match these filters for these characters with the current prices.'}
        </Alert>
      </Stack>
    )
  }
  return (
    <Stack>
      <ResultsTable
        results={results}
        items={items}
        classes={rank.data.classes}
        learn={rank.data.learn}
        watchedHours={rank.data.watched_hours}
        params={{
          unlearned: filters.unlearned,
          lookAhead: filters.lookAhead,
          sources: filters.sources,
          includeTrivial: filters.includeTrivial,
          skillCrafters: filters.skillCrafters,
          exits: filters.exits,
          arcaneSalvager: filters.arcaneSalvager,
          runs: filters.runs,
          version,
        }}
        ahBlocked={ahBlocked}
        onSetAhBlocked={(itemId, blocked) => setAhBlocked({ itemId, blocked })}
        favorites={favorites}
        onSetFavorite={(recipeId, favorite) => setFavorite({ recipeId, favorite })}
        rankBy={filters.sort === 'skill' ? 'skill' : 'gold'}
        goldSort={filters.sort}
        goldOrder={filters.order}
        onGoldSort={onGoldSort}
      />
      {total > results.length && (
        <Group justify="center">
          <Text size="sm" c="dimmed">
            Showing {results.length} of {total}
          </Text>
          <Button
            variant="light"
            loading={rank.isPlaceholderData}
            onClick={() => setPage({ filters, top: top + PAGE })}
          >
            Show more
          </Button>
        </Group>
      )}
      {skill && (
        <Text size="xs" c="dimmed">
          Skill points from crafting a recipe&apos;s reagents yourself (bolts of cloth, say) aren&apos;t counted yet.
        </Text>
      )}
    </Stack>
  )
})

type RangeProps = {
  name: string // e.g. "cost (gold)"
  min: number | null
  max: number | null
  onMin: (v: number | null) => void
  onMax: (v: number | null) => void
  step: number
}

function Range({ name, min, max, onMin, onMax, step }: RangeProps) {
  return (
    <Group grow gap="xs" align="flex-start">
      <NumberInput
        label={`Min ${name}`}
        value={min ?? ''}
        onChange={(v) => onMin(toBound(v))}
        step={step}
        decimalScale={4}
      />
      <NumberInput
        label={`Max ${name}`}
        placeholder="No max"
        value={max ?? ''}
        onChange={(v) => onMax(toBound(v))}
        step={step}
        decimalScale={4}
      />
    </Group>
  )
}

/** A chance to reach a run's target, in whole percent within what is offered. */
const reachTarget = (v: number) => Math.min(MAX_REACH_TARGET, Math.max(MIN_REACH_TARGET, Math.round(v)))

/** "a" or "an" before a percent as said aloud ("an 80%", "a 95%"), for the percents on offer. */
const article = (percent: number) => (String(percent).startsWith('8') ? 'an' : 'a')

/** How sure the materials bought for a run are to get it to its target skill, what that means in a tooltip beside it. */
function ReachTarget({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const shown = reachTarget(value)
  return (
    <NumberInput
      label={
        <Group gap={6} wrap="nowrap" component="span">
          Chance to reach target skill
          <Tooltip
            label={
              <>
                Since skill ups are random, we can&apos;t predict exactly how many times you&apos;ll need to craft each
                recipe. With this setting, we&apos;ll choose the number of crafts so you have {article(shown)} {shown}% chance to reach
                the target skill level
                <br />
                <br />
                Put another way: {shown}% of the time, you won&apos;t need to make a second trip to the auction house
              </>
            }
            multiline
            w={280}
            withArrow
            events={{ hover: true, focus: false, touch: true }}
          >
            <Text component="span" c="dimmed" lh={0} aria-hidden="true">
              <IconInfo size={15} />
            </Text>
          </Tooltip>
        </Group>
      }
      value={value}
      onChange={(v) => {
        if (typeof v === 'number') onChange(v)
      }}
      onBlur={() => onChange(shown)}
      min={MIN_REACH_TARGET}
      max={MAX_REACH_TARGET}
      clampBehavior="blur"
      allowDecimal={false}
      allowNegative={false}
      suffix="%"
      step={5}
      styles={{ wrapper: { maxWidth: 120 } }}
    />
  )
}

/** A filter of the aim's search: kept under the aim's own key, starting from where every filter used to be kept. */
function useFilter<T>(aim: Aim, name: string, schema: z.ZodType<T>, defaultValue: T) {
  return useStoredState(searchKey(aim, name), schema, defaultValue, legacySearchKey(name))
}


/**
 * Skilling up's Options as two pieces for the skill page's top row to place: a button (`.optionsControl`) and, while it
 * is open, the options under it (`.optionsPanel`): what may teach the recipes, then the chance to reach the target, one
 * column. Closed at first. Kept under the skill search's own keys, which `AimSearch` reads (the stored values stay in
 * step across the two).
 */
export function SkillOptions({ salvagerDefault }: { salvagerDefault: boolean }) {
  const [open, setOpen] = useState(false)
  const id = useId()
  const [sources, setSources] = useFilter<Source[]>('skill', 'sources', sourceList, DEFAULT_SOURCES)
  const [reach, setReach] = useFilter('skill', 'reachTarget', z.number(), DEFAULT_REACH_TARGET)
  const [effort, setEffort] = useFilter<Effort>('skill', 'effort', effortSchema, 'balanced')
  const [salvagerPick, setSalvagerPick] = useFilter<boolean | null>(
    'skill',
    'arcaneSalvager',
    z.boolean().nullable(),
    null,
  )
  return (
    <>
      <UnstyledButton
        className={classes.optionsControl}
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((o) => !o)}
      >
        <Text fw={500}>Options</Text>
        <span className={classes.chevron} data-open={open || undefined}>
          <IconChevron size={16} />
        </span>
      </UnstyledButton>
      {open && (
        <div id={id} className={classes.optionsPanel}>
          <Stack gap="lg">
            <Checkbox.Group
              label="Recipes taught by"
              value={sources}
              onChange={(v) => setSources(ALL_SOURCES.filter((s) => v.includes(s)))}
            >
              <Stack mt={4} gap="xs">
                {SOURCES.map((s) =>
                  s.description ? (
                    <SellVia key={s.value} value={s.value} label={s.label} description={s.description} />
                  ) : (
                    <Checkbox key={s.value} value={s.value} label={s.label} />
                  ),
                )}
              </Stack>
            </Checkbox.Group>
            <Stack gap={4}>
              <Text size="sm" fw={500} id={`${id}-effort`}>
                Plan for
              </Text>
              <SegmentedControl
                aria-labelledby={`${id}-effort`}
                value={effort}
                onChange={(v) => setEffort(effortSchema.parse(v))}
                data={EFFORTS}
              />
              <Text size="xs" c="dimmed">
                {EFFORT_NOTES[effort]}
              </Text>
            </Stack>
            <ReachTarget value={reach} onChange={setReach} />
            {SHOW_ARCANE_SALVAGER && (
              <Checkbox
                label="Use Arcane Salvager for disenchanting"
                description="10% chance of extra disenchanting materials. Usable only at campfires."
                checked={salvagerPick ?? salvagerDefault}
                onChange={(e) => setSalvagerPick(e.currentTarget.checked)}
              />
            )}
          </Stack>
        </div>
      )}
    </>
  )
}

/**
 * One aim's search, once the setup is complete and a realm is selected: its options and ranked recipes. Mounted per
 * aim (`key={aim}`), so each remembers its own filters: making gold and skilling up never overwrite each other's.
 *
 * Making gold ranks every recipe the characters know by the profit of a session, with Filters (how to sell, crafts
 * per session) and Advanced Filters (bounds, price confidence).
 *
 * Skilling up ranks every recipe the one skilled up can make or train now that still gives them a skill point, each
 * as a useful run (the crafts until it turns green, or yellow: `stop`), by what a skill point costs; what is made is
 * sold to a vendor or disenchanted, else kept. Its Options (`SkillOptions`, on the page's top row): what may teach the recipes, where a run stops
 * and, for Enchanting and Engineering, casts made for the skill point alone.
 */
export function AimSearch({
  setup,
  professions,
  browsing,
  noEnchanter,
  noPrices,
  salvagerDefault,
  flush,
  onUpload,
  lastScan,
  watchedHours,
  houseId,
}: {
  setup: SetupAnswers
  /** the selected realm's professions, with who has them */
  professions: readonly ProfessionChoice[]
  /** no characters on the selected realm: every recipe, for one unnamed crafter */
  browsing: boolean
  noEnchanter: boolean
  noPrices: boolean
  /** whether a character can make an Arcane Salvager: the checkbox's default */
  salvagerDefault: boolean
  /** changes once the characters load, so the first request already has their defaults */
  flush: number
  /** open the realm card's Upload your scan */
  onUpload: () => void
  /** the auction house's newest scan; null: never scanned; undefined: unknown yet */
  lastScan?: string | null | undefined
  /** hours of back-to-back scans of it this week (sales are seen only then); undefined: unknown */
  watchedHours?: number | undefined
  houseId?: number | null
}) {
  const { aim } = setup
  const skill = aim === 'skill'
  // Skilling up's options are set in `SkillOptions` (on the skill page's top row), kept under the same keys.
  const [sources] = useFilter<Source[]>(aim, 'sources', sourceList, DEFAULT_SOURCES)
  const [effort] = useFilter<Effort>(aim, 'effort', effortSchema, 'balanced')
  // Stored as strings: sections that no longer exist (the old Characters and Time assumptions ones) are dropped,
  // not an error.
  const [stored, setOpen] = useFilter(aim, 'open', z.array(z.string()), NONE_OPEN)
  const open = SECTIONS.filter((s) => stored.includes(s))
  // null until the user ticks or unticks it: then it follows whether any character can make an Arcane Salvager.
  const [salvagerPick, setSalvagerPick] = useFilter<boolean | null>(aim, 'arcaneSalvager', z.boolean().nullable(), null)
  const arcaneSalvager = SHOW_ARCANE_SALVAGER && (salvagerPick ?? salvagerDefault)
  // Money in gold and ROI in percent, as typed; converted for the API below.
  const [minCost, setMinCost] = useFilter(aim, 'minCost', bound, 0)
  const [maxCost, setMaxCost] = useFilter(aim, 'maxCost', bound, null)
  // 1 copper: only profitable recipes by default.
  const [minProfit, setMinProfit] = useFilter(aim, 'minProfit', bound, 0.0001)
  const [maxProfit, setMaxProfit] = useFilter(aim, 'maxProfit', bound, null)
  const [minRoi, setMinRoi] = useFilter(aim, 'minRoi', bound, 0)
  const [maxRoi, setMaxRoi] = useFilter(aim, 'maxRoi', bound, null)
  const [goldSort, setGoldSort] = useFilter<RankSort>(aim, 'sort', goldSortSchema, 'likely')
  const [goldOrder, setGoldOrder] = useFilter<SortOrder>(aim, 'order', sortOrderSchema, 'desc')
  const [learnable, setLearnable] = useFilter(aim, 'learnable', z.boolean(), false)
  // Skill up only: how sure the materials bought for a run are to get there, in percent.
  const [reach] = useFilter(aim, 'reachTarget', z.number(), DEFAULT_REACH_TARGET)
  // The newest scan's notice, dismissed per auction house.
  const [dismissed, setDismissed] = useStoredState(
    `altarmy.notice.unwatched.${houseId ?? 0}`,
    z.boolean(),
    false,
  )
  // By value, not the stored object: a new but equal setup must not count as new filters (that resets paging).
  const sort = skill ? rankSort(setup) : goldSort
  const [profession = null] = rankProfessions(setup)
  // Whether casts made for the skill point alone are ranked: whenever such a profession is the one skilled up.
  const skilling = skill && ENHANCING.has(profession?.toLowerCase() ?? '')
  // Joined, for the same reason (character names never hold a comma).
  const skilled = skillCrafters(setup, professions).join(',')
  // Skilling up a character nobody uploaded: the skill they start from (the climber is then `CLIMBER_NAME`).
  const climberSkill = setup.aim === 'skill' ? setup.climberSkill : undefined
  const filters = useMemo<Filters>(
    () =>
      skill
        ? {
            // Recipes they know or can train now that still give a point, sold to a vendor or kept; no bounds.
            unlearned: 'train',
            lookAhead: 0,
            sources: ALL_SOURCES.filter((s) => sources.includes(s)),
            includeTrivial: false,
            exits: [
              // disenchanting only counts where someone can: the server drops it otherwise
              ...SKILL_EXITS,
              ...(skilling ? (['skill'] as const) : []),
            ],
            arcaneSalvager,
            minCost: null,
            maxCost: null,
            minProfit: null,
            maxProfit: null,
            minRoi: null,
            maxRoi: null,
            minConfidence: null,
            professions: profession === null ? [] : [profession],
            skillCrafters: skilled ? skilled.split(',') : [],
            sort,
            runs: true,
            effort,
            ...(climberSkill !== undefined ? { climberSkill } : {}),
          }
        : {
            // The recipes the characters know (and, if asked, can train now), trivial or not.
            unlearned: learnable ? 'train' : 'none',
            lookAhead: 0,
            sources: DEFAULT_SOURCES,
            includeTrivial: true,
            // every way to sell, side by side: the list shows playing it safe and the auction house apart
            exits: [...ALL_EXITS],
            arcaneSalvager,
            minCost: scaled(minCost, goldToCopper),
            maxCost: scaled(maxCost, goldToCopper),
            minProfit: scaled(minProfit, goldToCopper),
            maxProfit: scaled(maxProfit, goldToCopper),
            minRoi: scaled(minRoi, (p) => p / 100),
            maxRoi: scaled(maxRoi, (p) => p / 100),
            minConfidence: null,
            professions: [],
            skillCrafters: [],
            sort,
            order: goldOrder,
            runs: false,
          },
    [
      skill,
      sources,
      skilling,
      arcaneSalvager,
      minCost,
      maxCost,
      minProfit,
      maxProfit,
      minRoi,
      maxRoi,
      learnable,
      sort,
      goldOrder,
      profession,
      skilled,
      climberSkill,
      effort,
    ],
  )
  const debouncedFilters = useSettled(filters, 300, flush)
  // One character climbing one profession: the skill workspace (the table only until the characters load).
  const climber =
    skill && profession !== null && skilled && !skilled.includes(',')
      ? professions
          .find((p) => p.name.toLowerCase() === profession.toLowerCase())
          ?.holders.find((h) => h.name === skilled)
      : undefined

  const salvager = SHOW_ARCANE_SALVAGER && (
    <Checkbox
      label="Use Arcane Salvager for disenchanting"
      description="10% chance of extra disenchanting materials. Usable only at campfires."
      checked={arcaneSalvager}
      onChange={(e) => setSalvagerPick(e.currentTarget.checked)}
    />
  )

  return (
    <>
      {!skill && (
        <Options label="Filters">
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="xl">
            <CraftsPerSession />
            <Stack gap="md">
              <Checkbox
                label="Include recipes I could learn"
                description="Recipes a character can train or buy the pattern for now"
                checked={learnable}
                onChange={(e) => setLearnable(e.currentTarget.checked)}
              />
              {salvager}
            </Stack>
          </SimpleGrid>
        </Options>
      )}
      {!skill && lastScan === null && (
        <Alert color="yellow" title="Nobody has scanned this realm's auction house yet">
          <Group justify="space-between" gap="sm">
            <Text size="sm">Until someone does, only vendor and disenchant values are known. {HOW_TO_SCAN}</Text>
            <Button size="xs" variant="light" onClick={onUpload}>
              Upload your scan
            </Button>
          </Group>
        </Alert>
      )}
      {!skill && lastScan && watchedHours !== undefined && watchedHours < WATCHED_ENOUGH_HOURS && !dismissed && (
        <Alert
          color="blue"
          withCloseButton
          closeButtonLabel="Dismiss"
          onClose={() => setDismissed(true)}
          title={`Sales aren't watched here yet (${watchedHours} h this week)`}
        >
          Two scans 15–30 minutes apart, any time, let everyone here see what sells.
        </Alert>
      )}
      {noEnchanter && (
        <Alert color="yellow" title="You do not have a disenchanter">
          Making a character with{' '}
          <span className={classes.inlineIcon}>
            <ProfessionIcon profession="Enchanting" />
          </span>{' '}
          Enchanting can significantly increase your profits and can be done at level 1
        </Alert>
      )}
      {browsing && (
        <Text size="sm" c="dimmed">
          No characters uploaded for this realm. We&apos;ll show you every recipe, as if one character crafts and sells
          it all, but it won&apos;t be customized for you.
        </Text>
      )}
      {!skill && (
        // A section remembering whether it is open, half the width on large screens. It opens without animating: a
        // height transition re-lays out the results table below on every frame. The panel stays mounted and is
        // only hidden when closed (Mantine's default hides it in an Activity, which re-runs every input's effects
        // on each open).
        <SimpleGrid cols={{ base: 1, lg: 2 }} style={{ alignItems: 'start' }}>
          <Accordion
            multiple
            variant="separated"
            transitionDuration={0}
            keepMountedMode="display-none"
            value={open}
            onChange={(v) => setOpen(SECTIONS.filter((s) => v.includes(s)))}
          >
            <Accordion.Item value="advanced">
              <Accordion.Control>Advanced Filters</Accordion.Control>
              <Accordion.Panel>
                <Stack>
                  <SimpleGrid cols={{ base: 1, sm: 3, lg: 1 }}>
                    <Range
                      name="cost (gold)"
                      min={minCost}
                      max={maxCost}
                      onMin={setMinCost}
                      onMax={setMaxCost}
                      step={1}
                    />
                    <Range
                      name="profit (gold)"
                      min={minProfit}
                      max={maxProfit}
                      onMin={setMinProfit}
                      onMax={setMaxProfit}
                      step={0.5}
                    />
                    <Range name="ROI (%)" min={minRoi} max={maxRoi} onMin={setMinRoi} onMax={setMaxRoi} step={10} />
                  </SimpleGrid>
                </Stack>
              </Accordion.Panel>
            </Accordion.Item>
          </Accordion>
        </SimpleGrid>
      )}
      {noPrices && <Alert color="yellow">No data collected for this auction house</Alert>}
      {!skill && (
        <Text size="sm" c="dimmed">
          <b>Safe profit</b>: sold to a vendor or disenchanted, so it always sells. <b>Auction profit</b>: counts only as
          many as its market has been taking, the rest the safe way. Ranked by the better of the two, in bold; click a
          heading to rank by it, and again to reverse it.
        </Text>
      )}
      {climber && profession !== null ? (
        <SkillWorkspace
          // a new climber, profession or starting skill starts afresh: nothing picked or opened out
          key={`${climber.name}/${profession}/${climberSkill ?? ''}`}
          filters={debouncedFilters}
          climber={climber}
          profession={profession}
          reachTarget={reachTarget(reach)}
          hypothetical={climberSkill !== undefined}
        />
      ) : (
        <Results
          filters={debouncedFilters}
          browsing={browsing}
          onGoldSort={
            skill
              ? undefined
              : (s, o) => {
                  setGoldSort(s)
                  setGoldOrder(o)
                }
          }
        />
      )}
    </>
  )
}
