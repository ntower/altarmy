import { memo, type ReactNode, useEffect, useMemo, useState } from 'react'
import {
  Accordion,
  Alert,
  Button,
  Checkbox,
  Group,
  Loader,
  NumberInput,
  SegmentedControl,
  Select,
  SimpleGrid,
  Stack,
  Text,
  useMantineTheme,
} from '@mantine/core'
import { z } from 'zod'
import {
  type RankParams,
  type RankSort,
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
  legacySearchKey,
  type ProfessionChoice,
  rankProfessions,
  rankSort,
  searchKey,
  type SearchScope,
  type Setup as SetupAnswers,
  SKILL_EXITS,
  skillCrafters,
} from '../lib/setup'
import { BUILT_IN_SOURCES } from '../lib/skill'
import type { GoldStrategy } from '../lib/profitRoute'
import { setSearchParam, useSearchParam } from '../lib/router'
import { useStoredState } from '../lib/storage'
import { parseSellVia, SELL_VIA, SELL_VIA_LABELS, sellViaExits, sellViaKinds } from '../lib/strategies'
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
        rankBy={filters.sort === 'skill' ? 'skill' : filters.sort === 'per_day' ? 'craft' : 'gold'}
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

/**
 * A filter of the search: kept under the aim's own key, or a gold strategy's (`altarmy.search.craft.*`), starting from
 * where it was kept before: the gold list's for a strategy, else where every filter used to be kept.
 */
function useFilter<T>(scope: SearchScope, name: string, schema: z.ZodType<T>, defaultValue: T) {
  const legacy = scope === 'gold' || scope === 'skill' ? legacySearchKey(name) : searchKey('gold', name)
  return useStoredState(searchKey(scope, name), schema, defaultValue, legacy)
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
  lastScan,
  strategy,
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
  /** the auction house's newest scan; null: never scanned; undefined: unknown yet */
  lastScan?: string | null | undefined
  /** making gold one way (`STRATEGY_PICKER`): Craft and sell ranks by what a day makes, in its groups, with Sell via */
  strategy?: GoldStrategy | undefined
}) {
  const { aim } = setup
  const skill = aim === 'skill'
  const craft = !skill && strategy === 'craft'
  const sellVia = parseSellVia(useSearchParam('exit'))
  const scope: SearchScope = !skill && strategy ? strategy : aim
  // Stored as strings: sections that no longer exist (the old Characters and Time assumptions ones) are dropped,
  // not an error.
  const [stored, setOpen] = useFilter(scope, 'open', z.array(z.string()), NONE_OPEN)
  const open = SECTIONS.filter((s) => stored.includes(s))
  // null until the user ticks or unticks it: then it follows whether any character can make an Arcane Salvager.
  const [salvagerPick, setSalvagerPick] = useFilter<boolean | null>(scope, 'arcaneSalvager', z.boolean().nullable(), null)
  const arcaneSalvager = SHOW_ARCANE_SALVAGER && (salvagerPick ?? salvagerDefault)
  // Craft and sell's Disenchant: who disenchants, when several characters can (the best by default).
  const enchanters = useMemo(
    () =>
      [...(professions.find((p) => p.name.toLowerCase() === 'enchanting')?.holders ?? [])].sort(
        (a, b) => b.rank - a.rank || a.name.localeCompare(b.name),
      ),
    [professions],
  )
  const [enchanterPick, setEnchanterPick] = useFilter<string | null>(scope, 'disenchanter', z.string().nullable(), null)
  const disenchanter =
    craft && sellVia === 'disenchant' ? enchanters.find((e) => e.name === enchanterPick)?.name : undefined
  // Money in gold and ROI in percent, as typed; converted for the API below.
  const [minCost, setMinCost] = useFilter(scope, 'minCost', bound, 0)
  const [maxCost, setMaxCost] = useFilter(scope, 'maxCost', bound, null)
  // 1 copper: only profitable recipes by default.
  const [minProfit, setMinProfit] = useFilter(scope, 'minProfit', bound, 0.0001)
  const [maxProfit, setMaxProfit] = useFilter(scope, 'maxProfit', bound, null)
  const [minRoi, setMinRoi] = useFilter(scope, 'minRoi', bound, 0)
  const [maxRoi, setMaxRoi] = useFilter(scope, 'maxRoi', bound, null)
  const [goldSort, setGoldSort] = useFilter<RankSort>(scope, 'sort', goldSortSchema, 'likely')
  const [goldOrder, setGoldOrder] = useFilter<SortOrder>(scope, 'order', sortOrderSchema, 'desc')
  const [learnable, setLearnable] = useFilter(scope, 'learnable', z.boolean(), false)
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
            // the built-in strategies' (a custom one brings its own)
            sources: BUILT_IN_SOURCES,
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
            ...(climberSkill !== undefined ? { climberSkill } : {}),
          }
        : {
            // The recipes the characters know (and, if asked, can train now), trivial or not.
            unlearned: learnable ? 'train' : 'none',
            lookAhead: 0,
            sources: BUILT_IN_SOURCES,
            includeTrivial: true,
            // every way to sell, side by side: the list shows playing it safe and the auction house apart; Craft and
            // sell, only those Sell via allows
            exits: craft ? sellViaExits(sellVia) : [...ALL_EXITS],
            ...(craft ? { kinds: sellViaKinds(sellVia) } : {}),
            arcaneSalvager,
            ...(disenchanter ? { disenchanter } : {}),
            minCost: scaled(minCost, goldToCopper),
            maxCost: scaled(maxCost, goldToCopper),
            minProfit: scaled(minProfit, goldToCopper),
            maxProfit: scaled(maxProfit, goldToCopper),
            minRoi: scaled(minRoi, (p) => p / 100),
            maxRoi: scaled(maxRoi, (p) => p / 100),
            minConfidence: null,
            professions: [],
            skillCrafters: [],
            sort: craft ? 'per_day' : sort,
            order: goldOrder,
            runs: false,
          },
    [
      skill,
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
      craft,
      sellVia,
      disenchanter,
      profession,
      skilled,
      climberSkill,
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
      {craft && (
        <Group gap="sm">
          <Text size="sm">Sell via</Text>
          <SegmentedControl
            size="xs"
            aria-label="Sell via"
            value={sellVia}
            onChange={(v) => setSearchParam('exit', v === 'all' ? null : v)}
            data={SELL_VIA.map((v) => ({ value: v, label: SELL_VIA_LABELS[v] }))}
          />
          {sellVia === 'disenchant' && enchanters.length > 1 && (
            <Select
              size="xs"
              aria-label="Disenchanted by"
              w={200}
              allowDeselect={false}
              value={disenchanter ?? enchanters[0]!.name}
              onChange={(v) => setEnchanterPick(v)}
              data={enchanters.map((e) => ({ value: e.name, label: `${e.name} (Enchanting ${e.rank})` }))}
            />
          )}
        </Group>
      )}
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
      {!skill && lastScan !== undefined && (
        <Text size="sm" c="dimmed">
          An item sells on the auction house here once enough of its auctions have ended; until then it counts what a
          vendor pays.
        </Text>
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
