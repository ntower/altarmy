import { Fragment, useMemo, useState, type KeyboardEvent, type ReactNode } from 'react'
import { ActionIcon, Menu, Table, Text, Tooltip, UnstyledButton } from '@mantine/core'
import { AnimatePresence, motion } from 'motion/react'
import type { ItemMap, Learn, RankResult } from '../api/client'
import { useEvaluations, type EvaluateParams } from '../api/queries'
import { choose, type Choices, type PlanEditing } from '../lib/choices'
import { confidenceTitle } from '../lib/confidence'
import { formatRoi } from '../lib/money'
import { EXIT_SHORT } from '../lib/exits'
import { ahCount, ahProfit, depthNote, safeProfit } from '../lib/selling'
import { craftUntil, perPoint } from '../lib/skill'
import { byGroup, CRAFT_GROUP_LABELS, type CraftGroup } from '../lib/strategies'
import { CharacterClasses } from '../lib/characterClasses'
import { CharacterName } from './CharacterName'
import { DisenchantLabel, ItemLink, RecipeTooltip } from './ItemTooltip'
import { LearnTooltip } from './LearnTooltip'
import { Money } from './Money'
import { SessionDetails } from './SessionDetails'
import classes from './ResultsTable.module.css'

/** Profit after costs, AH cut and postage. */
const PROFIT = 'Net profit'
/** What a skill point the crafter can expect costs: what skilling up ranks by. */
const PER_POINT = 'Cost per point'
/** The columns in order. Skilling up shows what a skill point costs and how far each recipe's run goes instead of
 * the money a session makes. */
const columnsFor = (rankBy: RankBy | undefined): string[] =>
  rankBy === 'skill'
    ? ['Recipe', PER_POINT, CRAFT_UNTIL, 'Investment', 'Learn']
    : rankBy === 'gold'
      ? ['', 'Recipe', SAFE, AUCTION]
      : rankBy === 'craft'
        ? ['', 'Craft', WHAT_TO_DO, EACH]
        : ['', PROFIT, 'Investment', 'ROI', 'Recipe', 'Crafter', 'Sell via']
/** Craft and sell's columns: what to do with a craft, and what one likely makes. */
const WHAT_TO_DO = 'What to do'
const EACH = 'Each'
/** How far a skill-up run goes: "110 (~17 crafts)". */
const CRAFT_UNTIL = 'Craft until'
/** A gold list's two ways to sell, side by side: playing it safe (the better of a vendor and disenchanting) and the
 * auction house, each the session's profit selling everything that way. */
const SAFE = 'Safe profit'
const AUCTION = 'Auction profit'
/** The server's sort for each of them: a header click re-ranks the whole list, not just the rows loaded, best
 * first; another click on it, worst first, and so on. */
export type GoldSort = 'safe' | 'ah' | 'likely'
export type SortOrder = 'desc' | 'asc'
const GOLD_SORT: Readonly<Record<string, GoldSort>> = { [SAFE]: 'safe', [AUCTION]: 'ah' }
const GOLD_HEADER_TITLE: Readonly<Record<string, string>> = {
  [SAFE]: 'Sell to a vendor, or disenchant and auction the materials: it always sells, and you are never left holding stock',
  [AUCTION]:
    'Sell on the auction house, counting only as many as its market has shown it takes (the rest the safe way). Often more, but less sure',
}
/** A gold list's money columns: room for -999g 99s 99c and the line under it. */
const GOLD_MONEY_WIDTH = 150
/** Sell via column text per exit; unknown exits show as-is. */
const EXIT_LABELS: Readonly<Record<string, string>> = {
  ah: 'Auction',
  vendor: 'Vendor',
  disenchant: 'Disenchant',
  skill: 'Skill only', // an enchant: nothing is made, so nothing is sold
}
/** A conversion or a flip: no profession's recipe, so whoever the plan picks does it. */
const needsNoRecipe = (r: RankResult): boolean => r.kind === 'convert' || r.kind === 'flip'
/** The Recipe tooltip's profession line for what needs no profession. */
const KIND_NOTES: Readonly<Record<string, string>> = {
  convert: 'Essence conversion (use the item; no profession)',
  flip: 'Buy and disenchant (no crafting)',
}
const exitLabel = (exit: string): string => EXIT_LABELS[exit] ?? exit.charAt(0).toUpperCase() + exit.slice(1)
/** Sort key per sortable column; numbers sort largest first on the first click, text alphabetically. */
const SORT_KEYS: Readonly<Record<string, (r: RankResult) => number | string>> = {
  [PROFIT]: (r) => r.profit,
  [PER_POINT]: (r) => perPoint(r) ?? Infinity,
  [CRAFT_UNTIL]: (r) => r.stop_skill,
  Learn: (r) => learnLabel(r, undefined),
  ROI: (r) => r.roi,
  Recipe: (r) => r.output_name,
  Crafter: (r) => (r.crafters.length ? r.crafter : ''),
  Investment: (r) => r.cost,
  'Sell via': (r) => exitLabel(r.best_exit),
}
const NUMERIC_COLUMNS: ReadonlySet<string> = new Set(['Investment', PROFIT, 'ROI', CRAFT_UNTIL])
/** Money columns: fixed width, room for -99g 99s 99c on one line (larger amounts drop copper, then silver). */
const MONEY_COLUMNS: ReadonlySet<string> = new Set(['Investment', PROFIT, PER_POINT])
const MONEY_WIDTH = 110
/** A gold list's first column: the ▸ and a flag or two, no wider. */
const FLAGS_WIDTH = 56
/** Skilling up: each column's width (px), Learn taking what is left. Craft until is no wider than its text needs;
 * the room it would otherwise take goes to the money and the recipe, not to Learn. */
const SKILL_WIDTHS: Readonly<Record<string, number>> = {
  [PER_POINT]: 162,
  [CRAFT_UNTIL]: 147,
  Investment: 139,
  Recipe: 347,
}
/** Crafter lists wrap at this width (px). */
const CRAFTER_WIDTH = 219
/** Columns dropped as the screen narrows (ResultsTable.module.css): Investment, Crafter and Learn first, then
 * Sell via and Craft until. */
const COLUMN_HIDDEN: Readonly<Record<string, string | undefined>> = {
  Investment: classes.hideBelowSm,
  Crafter: classes.hideBelowSm,
  Learn: classes.hideBelowSm,
  'Sell via': classes.hideBelowXs,
  [CRAFT_UNTIL]: classes.hideBelowXs,
}
/** What the server ranks by here (the whole ranking, not just this page): profit per session, best first; the
 * cost of an expected skill point, cheapest first; or a gold list (sorted by the server: its headers don't sort). */
export type RankBy = 'profit' | 'skill' | 'gold' | 'craft'
/** The column showing each ranking, and whether the server's order is largest first on it. */
const RANK_COLUMN: Readonly<Record<RankBy, Sort | null>> = {
  profit: { column: PROFIT, descending: true },
  skill: { column: PER_POINT, descending: false },
  gold: null,
  craft: null, // by what a day makes, in its groups (`byGroup`)
}

type Sort = { column: string; descending: boolean }

/** Rows slide to their new place when the order changes (a favorite, a re-rank, a sort). */
const MotionTr = motion.create(Table.Tr)
const REORDER = { layout: { duration: 0.35, ease: [0.25, 0.8, 0.25, 1] as const } }
/** A details row opens and closes by its content's height (a table row's own height can't be animated), so
 * its cells have no padding of their own. */
const UNFOLD = {
  initial: { height: 0, opacity: 0 },
  animate: { height: 'auto', opacity: 1 },
  exit: { height: 0, opacity: 0 },
  transition: { duration: 0.25, ease: [0.25, 0.8, 0.25, 1] as const },
  style: { overflow: 'hidden' },
}

/** `results` ordered by `sort`, stably, favorites first; unsorted keeps the server's order (favorites, then
 * profit, best first). */
function sorted(results: RankResult[], sort: Sort | null, favorites: ReadonlySet<number>): RankResult[] {
  const key = sort && SORT_KEYS[sort.column]
  const sign = sort?.descending ? -1 : 1
  return results.toSorted((a, b) => {
    const f = Number(favorites.has(b.recipe_id)) - Number(favorites.has(a.recipe_id))
    if (f || !key) return f
    const x = key(a)
    const y = key(b)
    const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y))
    return sign * c
  })
}

/** A row's cost of an expected skill point (as a loss, in red; what it earns in green), with the chance of one on
 * hover. */
function PerPointCell({ result: r }: { result: RankResult }) {
  const value = perPoint(r)
  const crafts = `${r.crafts} ${r.crafts === 1 ? 'craft' : 'crafts'}`
  return (
    <Table.Td
      ff="monospace"
      ta="right"
      title={`${Math.round(r.skill_chance * 100)}% chance of a skill point on the first craft ·${r.skill_ups.toFixed(1)} expected from ${crafts}`}
    >
      {value === null ? (
        <Text span size="sm" c="dimmed">
          –
        </Text>
      ) : (
        <Text span inherit c={value > 0 ? 'red' : 'teal'}>
          <Money copper={Math.round(-value)} padded />
        </Text>
      )}
    </Table.Td>
  )
}

/** A skill-up row's numbers: what a point costs, where the run stops and how many crafts it takes, and what it
 * costs. */
function SkillCells({ result: r }: { result: RankResult }) {
  return (
    <>
      <PerPointCell result={r} />
      <Table.Td className={COLUMN_HIDDEN[CRAFT_UNTIL]} ta="right">
        {craftUntil(r)}
      </Table.Td>
      <Table.Td className={COLUMN_HIDDEN.Investment} ff="monospace" ta="right">
        <Money copper={r.cost} cost padded />
      </Table.Td>
    </>
  )
}

/** A gold row's line under its recipe: who makes it, the session's crafts and what they spend; and, when its AH sale
 * may take long, how long. */
function RecipeLine({ result: r }: { result: RankResult }) {
  const what = r.profession || KIND_SHORT[r.kind]
  const who = r.crafter && (r.crafters.includes(r.crafter) || needsNoRecipe(r)) ? r.crafter : null
  return (
    <Text size="xs" c="dimmed">
      {what && <>{what} · </>}
      {who && (
        <>
          <CharacterName name={who} /> ·{' '}
        </>
      )}
      {r.crafts} {r.kind === 'flip' ? 'bought' : r.crafts === 1 ? 'craft' : 'crafts'} · spend <Money copper={r.cost} />
      {r.slow && r.days_to_sell != null && (
        <>
          {' · '}
          <Text span inherit c="orange" title={slowTitle(r.days_to_sell)}>
            slow: ~{Math.round(r.days_to_sell)} days
          </Text>
        </>
      )}
    </Text>
  )
}
/** What needs no profession, in the recipe line's place of one. */
const KIND_SHORT: Readonly<Record<string, string>> = { convert: 'Essence conversion', flip: 'Buy and disenchant' }

/** How playing it safe sells, in the small text under its figure. */
const SAFE_NOTES: Readonly<Record<string, string>> = {
  vendor: 'vendor',
  disenchant: 'disenchant',
  convert: 'essences sell',
}

/** A gold row's two profits, which pays more, and what to say under and about each. */
type TwoWays = {
  safe: number | null
  ah: number | null
  /** the better of the two (safe on a tie); none when neither is open to the row */
  primary: 'safe' | 'ah' | null
  safeNote: string | null
  /** what a disenchant yields, for the safe figure's tooltip */
  safeWhy: string | null
  ahNote: { text: string; warn: boolean } | null
}

function twoWays(r: RankResult, items: ItemMap): TwoWays {
  const safe = safeProfit(r)
  const ah = ahProfit(r)
  const primary =
    safe === null && ah === null ? null : ah === null || (safe !== null && safe.profit >= ah) ? 'safe' : 'ah'
  const materials =
    safe?.kind === 'disenchant'
      ? (r.exits.find((e) => e.kind === 'disenchant')?.materials ?? [])
          .toSorted((a, b) => (b.value ?? 0) - (a.value ?? 0))
          .map((m) => m.name)
      : []
  return {
    safe: safe?.profit ?? null,
    ah,
    primary,
    safeNote: safe && (SAFE_NOTES[safe.kind] ?? safe.kind),
    safeWhy: materials.length
      ? `Disenchants into ${materials.join(', ')}, valued at what they sell for on the auction house`
      : null,
    ahNote: depthNote(r, items),
  }
}

/** How the auction house's figure was counted, for its tooltip. */
function AhWhy({ result: r, items }: { result: RankResult; items: ItemMap }) {
  const count = ahCount(r, items)
  if (!count) return null
  const at = count.price != null && (
    <>
      {' '}
      at <Money copper={count.price} /> each
    </>
  )
  if (count.counted === count.made)
    return (
      <>
        Counts all {count.made} sold on the auction house{at}, after its cut.
      </>
    )
  const rest = count.restKind ? `go to ${(EXIT_SHORT[count.restKind] ?? count.restKind).toLowerCase()}` : 'are worth nothing'
  return (
    <>
      Counts {count.counted} of {count.made} sold on the auction house{at}: as many as its market has shown it takes.
      The other {count.made - count.counted} {rest}.
      {count.allSold != null && (
        <>
          {' '}
          If all {count.made} sold there: <Money copper={count.allSold} signed />.
        </>
      )}
    </>
  )
}

/** One profit: the better of a row's two in bold, the other muted (a loss stays red); a dash when the row can't sell
 * that way. */
function Profit({
  profit,
  primary,
  padded = false,
}: {
  profit: number | null
  primary: boolean
  /** lined up in a column */
  padded?: boolean
}) {
  return profit === null ? (
    <Text span c="dimmed" title="Can't be sold this way">
      –
    </Text>
  ) : (
    <Text
      span
      ff="monospace"
      fw={primary ? 700 : 400}
      c={profit < 0 ? 'red' : primary ? 'teal' : 'dimmed'}
      className={primary ? classes.figure : `${classes.figure} ${classes.secondary}`}
    >
      <Money copper={profit} padded={padded} />
    </Text>
  )
}

/** A figure with its explanation on hover, focus or tap, when there is one. */
function Explained({ why, children }: { why: ReactNode; children: ReactNode }) {
  return why ? (
    <Tooltip label={why} multiline maw={300} withArrow openDelay={200}>
      <span className={classes.explained}>{children}</span>
    </Tooltip>
  ) : (
    children
  )
}

/** The line under the auction house's figure; orange when the market takes under half of what the session makes. */
function AhNote({ note }: { note: { text: string; warn: boolean } }) {
  return (
    <Text span inherit c={note.warn ? 'orange' : undefined}>
      {note.text}
    </Text>
  )
}

/** A gold row's two profit cells, each with its note in small text under it (under the recipe, below `xs`). */
function GoldCells({ ways, result, items }: { ways: TwoWays; result: RankResult; items: ItemMap }) {
  return (
    <>
      <Table.Td ta="right" className={classes.hideBelowXs}>
        <Explained why={ways.safeWhy}>
          <Profit profit={ways.safe} primary={ways.primary === 'safe'} padded />
        </Explained>
        {ways.safeNote && (
          <Text size="xs" c="dimmed" className={classes.cellNote}>
            {ways.safeNote}
          </Text>
        )}
      </Table.Td>
      <Table.Td ta="right" className={classes.hideBelowXs}>
        <Explained why={ways.ah === null ? null : <AhWhy result={result} items={items} />}>
          <Profit profit={ways.ah} primary={ways.primary === 'ah'} padded />
        </Explained>
        {ways.ahNote && (
          <Text size="xs" c="dimmed" className={classes.cellNote}>
            <AhNote note={ways.ahNote} />
          </Text>
        )}
      </Table.Td>
    </>
  )
}

/** Below `xs`, where the two columns give way: both profits on one line under the recipe, the better in bold, and
 * the auction house's note on its own line. */
function PhoneProfits({ ways }: { ways: TwoWays }) {
  return (
    <div className={classes.onlyBelowXs}>
      <span className={`${classes.figure} ${classes.phoneSafe}`}>
        <Text span size="xs" c="dimmed">
          Safe
        </Text>{' '}
        <Profit profit={ways.safe} primary={ways.primary === 'safe'} />
      </span>{' '}
      <span className={classes.figure}>
        <Text span size="xs" c="dimmed">
          AH
        </Text>{' '}
        <Profit profit={ways.ah} primary={ways.primary === 'ah'} />
      </span>
      {ways.ahNote && (
        <Text size="xs" c="dimmed">
          <AhNote note={ways.ahNote} />
        </Text>
      )}
    </div>
  )
}

/** What to do with a craft, in words: post it (how many, in what stacks, at what price) or sell it another way;
 * and under it what that rests on. */
function craftWhat(r: RankResult, items: ItemMap): { action: ReactNode; basis: string | null } {
  const item = items[r.output_item_id]
  if (r.likely_exit === 'ah' && r.post_price != null && r.post_units) {
    const stack = r.post_stack && r.post_stack > 1 ? `, in stacks of ${r.post_stack}` : ''
    const sold = item?.sold_7d ? `~${Math.round(item.sold_7d / 7)} sold a day` : 'no sales seen yet'
    const listed = item?.ah_quantity ? `${item.ah_quantity} listed` : 'none listed'
    return {
      action: (
        <>
          Post {r.post_units}
          {stack} at <Money copper={r.post_price} />
        </>
      ),
      basis: `${sold} · ${listed}`,
    }
  }
  const verb: Readonly<Record<string, string>> = {
    vendor: 'Vendor them',
    disenchant: 'Disenchant them',
    skill: 'Cast for the skill point',
    ah: 'Post them',
  }
  return {
    action: verb[r.likely_exit] ?? exitLabel(r.likely_exit),
    basis: r.group === 'waiting' ? "AH: not proven here yet" : r.group === 'full' ? 'AH: more listed than sells a day' : null,
  }
}

/** A Craft and sell row's two cells: what to do, and what a craft likely makes (with a day's posts under it). */
function CraftCells({ result: r, items }: { result: RankResult; items: ItemMap }) {
  const { action, basis } = craftWhat(r, items)
  return (
    <>
      <Table.Td>
        <Text size="sm">{action}</Text>
        {basis && (
          <Text size="xs" c="dimmed">
            {basis}
          </Text>
        )}
      </Table.Td>
      <Table.Td ta="right" ff="monospace" c={r.likely_each < 0 ? 'red' : 'teal'}>
        <Money copper={r.likely_each} padded />
        {r.post_units ? (
          <Text size="xs" c="dimmed">
            x{r.post_units} = <Money copper={r.per_day} />
          </Text>
        ) : null}
        {r.deposit_est ? (
          <Text size="xs" c="dimmed" title="Estimated until the deposit is checked in game">
            less <Money copper={r.deposit_est} /> deposit
          </Text>
        ) : null}
      </Table.Td>
    </>
  )
}

/** How a recipe is learned, in a word: known, or where the climber learns it (and who already knows it). */
function learnLabel(r: RankResult, learn: Learn | undefined): string {
  if (!r.crafter || r.crafters.includes(r.crafter) || needsNoRecipe(r)) return 'known'
  const how = learn ? LEARN_FROM[learn.source] : 'not learned'
  return r.crafters.length ? `${how} · ${r.crafters[0]} knows it` : how
}
const LEARN_FROM: Readonly<Record<Learn['source'], string>> = {
  trainer: 'trainer',
  recipe: 'pattern',
  bop: 'bind on pickup pattern',
}

/** The characters who know the recipe, the one doing the craft first. */
const byCrafter = (crafters: string[], crafter: string) =>
  crafters.includes(crafter) ? [crafter, ...crafters.filter((c) => c !== crafter)] : crafters

const DEFAULT_PARAMS: EvaluateParams = {
  unlearned: 'none',
  lookAhead: 0,
  sources: ['trainer', 'recipe'],
  includeTrivial: true,
  skillCrafters: [],
  exits: ['vendor', 'ah', 'disenchant'],
  arcaneSalvager: false,
}

const NONE: ReadonlySet<number> = new Set()
const NO_LEARN: Readonly<Record<string, Learn>> = {}

const DOTS = (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden>
    <circle cx="3" cy="8" r="1.5" />
    <circle cx="8" cy="8" r="1.5" />
    <circle cx="13" cy="8" r="1.5" />
  </svg>
)

/** Why a row's sale is flagged as slow: how long it may take. */
function slowTitle(daysToSell: number): string {
  const days = Math.round(daysToSell)
  return `May take about ${days} ${days === 1 ? 'day' : 'days'} to sell at the rate it sold lately`
}

/** Why a row is flagged as buying more than the auction house lists. */
function shortTitle(short: number): string {
  return `Needs ${short.toLocaleString()} more ${short === 1 ? 'unit' : 'units'} than the auction house lists; they are counted at the dearest price listed`
}

/** A flag icon in a row's first column, explained in a tooltip that opens at once on hover, focus or tap. */
function Flag({ label, why, color, children }: { label: string; why: string; color: string; children: ReactNode }) {
  return (
    <Tooltip
      label={why}
      multiline
      maw={280}
      withArrow
      openDelay={0}
      transitionProps={{ duration: 0 }}
      events={{ hover: true, focus: true, touch: true }}
    >
      <Text
        span
        c={color}
        ml={4}
        aria-label={label}
        tabIndex={0}
        style={{ cursor: 'help' }}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </Text>
    </Tooltip>
  )
}

/** A row's ⋯ menu: mark the recipe as a favorite or not, stop or allow selling its output on the AH (only
 * for a craft: a flip is only disenchanted, a conversion's AH sale does not follow the AH exit, and an enchant
 * makes nothing). */
function RowActions({
  result,
  blocked,
  onSetAhBlocked,
  favorite,
  onSetFavorite,
}: {
  result: RankResult
  blocked: boolean
  onSetAhBlocked?: (itemId: number, blocked: boolean) => void
  favorite: boolean
  onSetFavorite?: (recipeId: number, favorite: boolean) => void
}) {
  return (
    <Menu position="bottom-end" withinPortal>
      <Menu.Target>
        <ActionIcon variant="subtle" color="gray" aria-label={`Actions for ${result.recipe}`}>
          {DOTS}
        </ActionIcon>
      </Menu.Target>
      <Menu.Dropdown>
        {onSetFavorite && (
          <Menu.Item onClick={() => onSetFavorite(result.recipe_id, !favorite)}>
            {favorite ? 'Remove from favorites' : 'Add to favorites'}
          </Menu.Item>
        )}
        {onSetAhBlocked && result.kind === 'craft' && (
          <Menu.Item onClick={() => onSetAhBlocked(result.output_item_id, !blocked)}>
            {blocked ? 'Allow selling on auction house' : 'Never sell on auction house'}
          </Menu.Item>
        )}
      </Menu.Dropdown>
    </Menu>
  )
}

export function ResultsTable({
  results,
  items: rankItems,
  classes: characterClasses = {},
  params = DEFAULT_PARAMS,
  ahBlocked = NONE,
  onSetAhBlocked,
  favorites = NONE,
  onSetFavorite,
  rankBy,
  learn = NO_LEARN,
  onOpen,
  goldSort,
  goldOrder = 'desc',
  onGoldSort,
  watchedHours = 0,
}: {
  results: RankResult[]
  items: ItemMap
  /** Character name -> class file, for class-coloured names. */
  classes?: Readonly<Record<string, string>>
  /** The search the results came from: a recipe whose plan the user changes is re-costed the same way. */
  params?: EvaluateParams
  /** Item ids never sold on the AH. */
  ahBlocked?: ReadonlySet<number>
  /** Stop or allow selling an item on the AH; without it and `onSetFavorite` rows have no actions menu. */
  onSetAhBlocked?: (itemId: number, blocked: boolean) => void
  /** Favorite recipe ids: listed first and highlighted. */
  favorites?: ReadonlySet<number>
  /** Mark a recipe as a favorite or not. */
  onSetFavorite?: (recipeId: number, favorite: boolean) => void
  /** What the server ranked `results` by (best first): its column shows as sorted until the user sorts the page
   * by a header (which orders only the rows loaded, like every other column). */
  rankBy?: RankBy
  /** Recipe id -> where to learn it, for the rows saying "not learned". */
  learn?: Readonly<Record<string, Learn>>
  /** Open a row's recipe elsewhere (the skill workspace's run card) instead of unfolding it here. */
  onOpen?: (r: RankResult) => void
  /** A gold list's server sort, shown on the Safe or Auction house header (neither when ranked by the better of the
   * two), and re-ranking by a header: clicking the sorted one again goes back to the better of the two. */
  goldSort?: string
  goldOrder?: SortOrder
  onGoldSort?: (sort: GoldSort, order: SortOrder) => void
  /** The hours the auction house was watched this week, for what an expanded row's market says was seen sold. */
  watchedHours?: number
}) {
  const actions = Boolean(onSetAhBlocked || onSetFavorite)
  const shownColumns = columnsFor(rankBy)
  const columns = shownColumns.length + (actions ? 1 : 0)
  const [open, setOpen] = useState<ReadonlySet<number>>(new Set())
  const toggle = (id: number) =>
    setOpen((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  const [sort, setSort] = useState<Sort | null>(null)
  // With no column picked here, the server's order shows on the column it ranked by.
  const shownSort: Sort | null = sort ?? (rankBy ? RANK_COLUMN[rankBy] : null)
  const gold = rankBy === 'gold'
  const skill = rankBy === 'skill'
  const craft = rankBy === 'craft'
  const sortBy = (column: string) =>
    setSort(
      shownSort?.column === column
        ? { column, descending: !shownSort.descending }
        : { column, descending: NUMERIC_COLUMNS.has(column) },
    )
  // The user's changes to each recipe's plan, by recipe id; a row shows its changed plan once it is costed.
  const [choices, setChoices] = useState<Readonly<Record<number, Choices>>>({})
  const evaluations = useEvaluations(choices, params)
  const current = useMemo(
    () => results.map((r) => (choices[r.recipe_id] && evaluations[r.recipe_id]?.data?.result) || r),
    [results, choices, evaluations],
  )
  const items = useMemo(
    () => Object.assign({}, rankItems, ...Object.values(evaluations).map((e) => e.data?.items ?? {})) as ItemMap,
    [rankItems, evaluations],
  )
  const rows = useMemo(
    () => (rankBy === 'craft' ? byGroup(sorted(current, null, favorites)) : sorted(current, sort, favorites)),
    [current, sort, favorites, rankBy],
  )
  // Craft and sell's groups: what pays is open, the rest folded until asked for.
  const [openGroups, setOpenGroups] = useState<ReadonlySet<CraftGroup>>(() => new Set(['paying']))
  const editing = (id: number): PlanEditing => {
    const evaluation = evaluations[id]
    return {
      onChoose: (paths, key) =>
        setChoices((prev) => ({ ...prev, [id]: paths.reduce((c, path) => choose(c, path, key), prev[id] ?? {}) })),
      modified: id in choices,
      onReset: () => setChoices((prev) => Object.fromEntries(Object.entries(prev).filter(([k]) => Number(k) !== id))),
      pending: evaluation?.isFetching ?? false,
      error: evaluation?.error?.message ?? null,
    }
  }

  return (
    <CharacterClasses.Provider value={characterClasses}>
      <Table.ScrollContainer minWidth={360}>
        <Table striped highlightOnHover stickyHeader>
          <Table.Thead>
            <Table.Tr>
              {shownColumns.map((c) => {
                const goldColumn = gold ? GOLD_SORT[c] : undefined
                if (goldColumn) {
                  const on = goldSort === goldColumn
                  return (
                    <Table.Th
                      key={c}
                      className={classes.hideBelowXs}
                      w={GOLD_MONEY_WIDTH}
                      ta="right"
                      aria-sort={!on ? 'none' : goldOrder === 'asc' ? 'ascending' : 'descending'}
                      title={GOLD_HEADER_TITLE[c]}
                    >
                      <UnstyledButton
                        className={`${classes.sort} ${classes.goldSort}`}
                        aria-label={`Sort by ${c}`}
                        onClick={() => onGoldSort?.(goldColumn, on && goldOrder === 'desc' ? 'asc' : 'desc')}
                      >
                        {c}
                        <span className={classes.arrow} data-active={on || undefined}>
                          {on && goldOrder === 'asc' ? '▲' : '▼'}
                        </span>
                      </UnstyledButton>
                    </Table.Th>
                  )
                }
                const active = shownSort?.column === c
                return (
                  <Table.Th
                    key={c}
                    className={COLUMN_HIDDEN[c]}
                    w={
                      rankBy === 'skill' && c in SKILL_WIDTHS
                        ? SKILL_WIDTHS[c]
                        : MONEY_COLUMNS.has(c)
                          ? MONEY_WIDTH
                          : c === 'Crafter'
                            ? CRAFTER_WIDTH
                            : gold && c === ''
                              ? FLAGS_WIDTH
                              : undefined
                    }
                    ta={MONEY_COLUMNS.has(c) ? 'right' : undefined}
                    aria-sort={
                      !(c in SORT_KEYS)
                        ? undefined
                        : !active
                          ? 'none'
                          : shownSort.descending
                            ? 'descending'
                            : 'ascending'
                    }
                  >
                    {c in SORT_KEYS && !gold ? (
                      <UnstyledButton className={classes.sort} aria-label={`Sort by ${c}`} onClick={() => sortBy(c)}>
                        {c}
                        <span className={classes.arrow} data-active={active || undefined}>
                          {active && !shownSort.descending ? '▲' : '▼'}
                        </span>
                      </UnstyledButton>
                    ) : (
                      c
                    )}
                  </Table.Th>
                )
              })}
              {actions && <Table.Th w={44} aria-label="Actions" />}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {rows.map((r, index) => {
              const expanded = open.has(r.recipe_id)
              const modified = r.recipe_id in choices
              const favorite = favorites.has(r.recipe_id)
              // Measured only when the row's place in the order changes, so expanding a row above doesn't
              // slide the rows below it.
              const reorder = { layout: 'position', layoutDependency: index, transition: REORDER } as const
              const ways = gold ? twoWays(r, items) : null
              const recipeCell = (
                <Table.Td>
                  {r.kind === 'flip' && (
                    // buy the item and disenchant it: no recipe to name
                    <>
                      <DisenchantLabel />{' '}
                    </>
                  )}
                  <ItemLink
                    item={items[r.output_item_id]}
                    name={r.output_name}
                    tooltip={
                      <RecipeTooltip
                        name={r.recipe}
                        profession={KIND_NOTES[r.kind] ?? r.profession}
                        reagents={r.reagents}
                        output={items[r.output_item_id]}
                        items={items}
                      />
                    }
                  />
                  {ways && (
                    <>
                      <RecipeLine result={r} />
                      <PhoneProfits ways={ways} />
                    </>
                  )}
                  {craft && <RecipeLine result={r} />}
                </Table.Td>
              )
              const groupStart = craft && (index === 0 || rows[index - 1]?.group !== r.group)
              const folded = craft && !openGroups.has(r.group)
              return (
                <Fragment key={r.recipe_id}>
                  {groupStart && (
                    <Table.Tr className={classes.groupHeading}>
                      <Table.Td colSpan={columns}>
                        <UnstyledButton
                          aria-expanded={!folded}
                          onClick={() =>
                            setOpenGroups((prev) => {
                              const next = new Set(prev)
                              if (next.has(r.group)) next.delete(r.group)
                              else next.add(r.group)
                              return next
                            })
                          }
                        >
                          <Text span size="sm" fw={500}>
                            {folded ? '▸' : '▾'} {CRAFT_GROUP_LABELS[r.group]} (
                            {rows.filter((x) => x.group === r.group).length})
                          </Text>
                        </UnstyledButton>
                      </Table.Td>
                    </Table.Tr>
                  )}
                  {!folded && (
                  <>
                  <MotionTr
                    {...reorder}
                    onClick={() => (onOpen ? onOpen(r) : toggle(r.recipe_id))}
                    // a row that opens elsewhere is a button of its own (it has no ▸)
                    {...(onOpen && {
                      tabIndex: 0,
                      role: 'button',
                      'aria-label': `Open ${r.recipe}`,
                      onKeyDown: (e: KeyboardEvent) => {
                        if (e.key !== 'Enter' && e.key !== ' ') return
                        e.preventDefault()
                        onOpen(r)
                      },
                    })}
                    style={{ cursor: 'pointer' }}
                    className={favorite ? classes.favorite : undefined}
                  >
                    {!skill && (
                      <Table.Td>
                        <UnstyledButton
                          aria-expanded={expanded}
                          aria-label={`Details for ${r.recipe}`}
                          onClick={(e) => {
                            e.stopPropagation()
                            toggle(r.recipe_id)
                          }}
                        >
                          {expanded ? '▾' : '▸'}
                        </UnstyledButton>
                        {favorite && (
                          <Flag color="yellow" label="Favorite" why="Favorite">
                            ★
                          </Flag>
                        )}
                        {!gold && r.confidence && r.confidence.level !== 'high' && (
                          <Flag
                            color={r.confidence.level === 'low' ? 'orange' : 'yellow'}
                            label={`${r.confidence.level === 'low' ? 'Low' : 'Medium'} price confidence`}
                            why={confidenceTitle(r.confidence)}
                          >
                            ?
                          </Flag>
                        )}
                        {!gold && r.slow && r.days_to_sell != null && (
                          <Flag color="orange" label="Slow to sell" why={slowTitle(r.days_to_sell)}>
                            ⚠
                          </Flag>
                        )}
                        {craft && r.no_vendor_floor && (
                          <Flag color="orange" label="No vendor floor" why="A vendor pays nothing for it: unsold, it is worth nothing">
                            !
                          </Flag>
                        )}
                        {r.short > 0 && (
                          <Flag color="orange" label="Not enough listed" why={shortTitle(r.short)}>
                            ◔
                          </Flag>
                        )}
                        {modified && (
                          <Flag color="yellow" label="Changed plan" why="Your changed plan, not the best one">
                            ●
                          </Flag>
                        )}
                      </Table.Td>
                    )}
                    {ways ? (
                      <>
                        {recipeCell}
                        <GoldCells ways={ways} result={r} items={items} />
                      </>
                    ) : craft ? (
                      <>
                        {recipeCell}
                        <CraftCells result={r} items={items} />
                      </>
                    ) : skill ? (
                      <>
                        {recipeCell}
                        <SkillCells result={r} />
                      </>
                    ) : (
                      <>
                        <Table.Td c={r.profit < 0 ? 'red' : 'teal'} ff="monospace" ta="right">
                          <Money copper={r.profit} padded />
                        </Table.Td>
                        <Table.Td className={COLUMN_HIDDEN.Investment} ff="monospace" ta="right">
                          <Money copper={r.cost} cost padded />
                        </Table.Td>
                        <Table.Td c={r.roi < 0 ? 'red' : undefined}>{formatRoi(r.roi)}</Table.Td>
                      </>
                    )}
                    {!skill && !gold && !craft && recipeCell}
                    {gold || craft ? null : rankBy === 'skill' ? (
                      <Table.Td className={COLUMN_HIDDEN.Learn}>
                        {learn[r.recipe_id] && !r.crafters.includes(r.crafter) ? (
                          <LearnTooltip learn={learn[r.recipe_id]}>{learnLabel(r, learn[r.recipe_id])}</LearnTooltip>
                        ) : (
                          <Text span size="sm" c="dimmed">
                            {learnLabel(r, undefined)}
                          </Text>
                        )}
                      </Table.Td>
                    ) : (
                      <Table.Td
                        className={COLUMN_HIDDEN.Crafter}
                        title={r.crafters.length > 1 ? byCrafter(r.crafters, r.crafter).join(', ') : undefined}
                      >
                        {needsNoRecipe(r) && r.crafter ? (
                          // a conversion or flip needs no recipe: whoever the plan picks does it
                          <CharacterName name={r.crafter} />
                        ) : r.crafters.length ? (
                          <>
                            <CharacterName name={byCrafter(r.crafters, r.crafter)[0]} />
                            {r.crafters.length > 1 &&
                              ` (and ${r.crafters.length - 1} other${r.crafters.length > 2 ? 's' : ''})`}
                          </>
                        ) : r.crafter && !needsNoRecipe(r) && learn[r.recipe_id] ? (
                          <LearnTooltip learn={learn[r.recipe_id]}>not learned</LearnTooltip>
                        ) : (
                          <Text span size="sm" c="dimmed">
                            {/* no crafter named: browsing without characters */}
                            {r.crafter && !needsNoRecipe(r) ? 'not learned' : 'anyone'}
                          </Text>
                        )}
                      </Table.Td>
                    )}
                    {rankBy !== 'skill' && !gold && !craft && (
                      <Table.Td className={COLUMN_HIDDEN['Sell via']}>{exitLabel(r.best_exit)}</Table.Td>
                    )}
                    {actions && (
                      // Menu clicks (in its portal too) bubble here in React, not to the row.
                      <Table.Td onClick={(e) => e.stopPropagation()}>
                        <RowActions
                          result={r}
                          blocked={ahBlocked.has(r.output_item_id)}
                          onSetAhBlocked={onSetAhBlocked}
                          favorite={favorite}
                          onSetFavorite={onSetFavorite}
                        />
                      </Table.Td>
                    )}
                  </MotionTr>
                  <AnimatePresence initial={false}>
                    {expanded && !onOpen && (
                      <MotionTr key="details" {...reorder} className={classes.details}>
                        <Table.Td py={0} />
                        <Table.Td py={0} colSpan={columns - 1}>
                          <motion.div {...UNFOLD}>
                            <SessionDetails
                              result={r}
                              items={items}
                              editing={editing(r.recipe_id)}
                              params={params}
                              choices={choices[r.recipe_id]}
                              market={gold || craft}
                              watchedHours={watchedHours}
                            />
                          </motion.div>
                        </Table.Td>
                      </MotionTr>
                    )}
                  </AnimatePresence>
                  </>
                  )}
                </Fragment>
              )
            })}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </CharacterClasses.Provider>
  )
}
