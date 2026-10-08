import { useState, type ReactNode } from 'react'
import { Button, Group, Progress, SegmentedControl, Stack, Tabs, Text, Tooltip } from '@mantine/core'
import { z } from 'zod'
import type { ItemInfo, ItemMap, RankResult } from '../api/client'
import { useAhCut } from '../api/queries'
import { EXIT_SHORT } from '../lib/exits'
import {
  cue,
  headerSummary,
  moveFromUsual,
  NOTABLE_MOVE,
  priceNow,
  seenSold,
  usualPrice,
  walkLadder,
  type Cue,
  type MarketGroup,
  type MarketItem,
} from '../lib/market'
import type { MarketMode } from '../lib/marketFocus'
import { breakEven, countedOn, expectedUnits, fallback, floodCheck, floor } from '../lib/selling'
import { useStoredState } from '../lib/storage'
import { IconChevron } from './icons'
import { Icon } from './ItemTooltip'
import tooltipClasses from './ItemTooltip.module.css'
import { DepthChart, LadderTable, ProfitChart, type Rule } from './MarketCharts'
import classes from './MarketSection.module.css'
import { Earned, Money } from './Money'

/** Tiles the strip shows before "+N more". */
const TILES_SHOWN = 8
/** Vendor items under this share of the cost wait behind "+N more". */
const MINOR_SHARE = 0.02

const CAPTIONS: Record<MarketGroup, string> = {
  buy: 'You buy',
  make: 'You make',
  sell: 'You sell',
  disenchant: 'If disenchanted',
}

/** A cue as the strip and the header show it: a word or two, coloured by whether it hurts the plan. */
function CueText({ value }: { value: Cue }) {
  return (
    <Tooltip label={value.label} withinPortal>
      <span className={classes.cue} data-tone={value.tone} aria-label={value.label}>
        {value.text}
      </span>
    </Tooltip>
  )
}

/** The section header's line: what selling counts on (else how it sells, or what a skill run buys), and the bought
 * item most of the cost goes on when its market has a cue (that part only from `sm` up). */
export function MarketSummary({
  result,
  list,
  items,
  mode,
}: {
  result: RankResult
  list: readonly MarketItem[]
  items: ItemMap
  mode: MarketMode
}) {
  const cut = useAhCut()
  const s = headerSummary(result, list, items, mode)
  return (
    <Text span size="sm" c="dimmed" className={classes.summary}>
      {s.kind === 'ah' && (
        <>
          Counting on <Money copper={s.price} /> for {s.units === s.of ? `all ${s.of}` : `${s.units} of ${s.of}`} ·
          break-even <Money copper={breakEven(result, cut)} />
        </>
      )}
      {s.kind === 'exit' && <>Selling via {EXIT_SHORT[s.exit] ?? s.exit}</>}
      {s.kind === 'skill' && (
        <>
          Buying {s.reagents} {s.reagents === 1 ? 'reagent' : 'reagents'} for <Money copper={s.cost} />
        </>
      )}
      {s.flag && (
        <Text span inherit visibleFrom="sm">
          {' '}
          · {s.flag.name} {Math.round(s.flag.share * 100)}% of cost, <CueText value={s.flag.cue} />
        </Text>
      )}
    </Text>
  )
}

/** A tile's second line: how many, and for what. */
function tileMeta(m: MarketItem): string {
  const units = Math.round(m.quantity).toLocaleString()
  if (m.group === 'sell') return `sell ${units}`
  if (m.group === 'make') return `${units} crafted`
  if (m.group === 'disenchant') return `~${expectedUnits(m.quantity)} expected`
  if (m.source === 'vendor') return `${units} · vendor`
  if (m.source === 'gather') return `${units} · gathered`
  return `${units} · ${Math.round((m.share ?? 0) * 100)}%`
}

/** The plan as a strip of items to pick from: bought, made, sold, disenchanted, each with one cue. Vendor items that
 * are hardly any of the cost, and tiles past `TILES_SHOWN`, wait behind "+N more". */
function RecipeStrip({
  result,
  list,
  items,
  selected,
  onSelect,
}: {
  result: RankResult
  list: readonly MarketItem[]
  items: ItemMap
  selected: number | null
  onSelect: (itemId: number) => void
}) {
  const [all, setAll] = useState(false)
  const minor = (m: MarketItem) => m.group === 'buy' && m.source !== 'ah' && (m.share ?? 0) < MINOR_SHARE
  const main = list.filter((m) => !minor(m) || m.itemId === selected)
  const shown = all ? list : main.slice(0, TILES_SHOWN)
  const hidden = list.length - shown.length
  const groups = (['buy', 'make', 'sell', 'disenchant'] as const)
    .map((g) => ({ group: g, tiles: shown.filter((m) => m.group === g) }))
    .filter((g) => g.tiles.length)
  return (
    <div className={classes.strip} role="group" aria-label="Items in this plan">
      {groups.map(({ group, tiles }, i) => (
        <Group key={group} gap={6} wrap="nowrap" align="stretch">
          {i > 0 && (
            <span className={classes.arrow} aria-hidden>
              →
            </span>
          )}
          <div className={classes.group}>
            <span className={classes.caption}>{CAPTIONS[group]}</span>
            <div className={classes.tiles}>
              {tiles.map((m) => {
                const item = items[m.itemId]
                const c = cue(m, result, items)
                return (
                  <button
                    key={`${m.group}-${m.itemId}`}
                    type="button"
                    className={classes.tile}
                    aria-pressed={m.itemId === selected}
                    onClick={() => onSelect(m.itemId)}
                  >
                    <span className={`${tooltipClasses.link} ${classes.tileName}`} data-quality={item?.quality}>
                      {item && <Icon icon={item.icon} size="small" className={tooltipClasses.smallIcon} />}
                      {m.name}
                    </span>
                    <span className={classes.tileMeta}>{tileMeta(m)}</span>
                    {m.group === 'buy' && m.source === 'ah' && (
                      <span className={classes.share} style={{ width: `${Math.round((m.share ?? 0) * 100)}%` }} />
                    )}
                    {c && <CueText value={c} />}
                  </button>
                )
              })}
            </div>
          </div>
        </Group>
      ))}
      {(hidden > 0 || all) && list.length > main.length && (
        <Button size="compact-xs" variant="subtle" className={classes.more} onClick={() => setAll((a) => !a)}>
          {all ? 'Fewer' : `+${hidden} more`}
        </Button>
      )}
    </div>
  )
}

/** "(N days of scans)", or what there is to go on when that's too few to tell. */
const days = (item: ItemInfo) => `${item.scans_7d ?? 0} ${item.scans_7d === 1 ? 'day' : 'days'} of scans`

/** How the price compares with the usual one, in words that wait for enough days of scans. */
function UsualLine({ item, now }: { item: ItemInfo; now: number | null }) {
  const usual = usualPrice(item)
  if (usual === null) return <>too new to tell what it usually goes for ({days(item)})</>
  const move = moveFromUsual(now, item)
  if (move === null || Math.abs(move) < NOTABLE_MOVE)
    return (
      <>
        usually <Money copper={usual} /> ({days(item)})
      </>
    )
  return (
    <>
      about {Math.round(Math.abs(move) * 100)}% {move > 0 ? 'above' : 'below'} the usual <Money copper={usual} /> (
      {days(item)})
    </>
  )
}

/** Lines joined with dots. */
const Facts = ({ parts }: { parts: ReactNode[] }) => (
  <Text size="sm" c="dimmed">
    {parts.filter(Boolean).map((p, i) => (
      <span key={i}>
        {i > 0 && ' · '}
        {p}
      </span>
    ))}
  </Text>
)

/** What the selected item's market says, for what the plan does with it: up to three lines. */
function Headline({ m, result: r, items }: { m: MarketItem; result: RankResult; items: ItemMap }) {
  const cut = useAhCut()
  const item = items[m.itemId]
  const listedParts = (it: ItemInfo) => [
    it.ah_price != null && (
      <>
        cheapest <Money copper={it.ah_price} />
      </>
    ),
    it.ah_quantity != null && `${it.ah_quantity.toLocaleString()} listed`,
  ]
  if (m.group === 'sell') {
    const exit = r.likely_exit || r.best_exit
    if (exit === 'ah' && item?.ah_sell_price != null) {
      const counted = countedOn(r, items)
      const other = fallback(r)
      const lowest = floor(r, cut)
      return (
        <Stack gap={2}>
          <Text fw={600}>
            We count on <Money copper={item.ah_sell_price} /> for{' '}
            {counted.units === counted.of ? `all ${counted.of}` : `${counted.units} of your ${counted.of}`}
            {r.excess_units > 0 && other && (
              <>
                ; the other {r.excess_units} at {EXIT_SHORT[other.kind] ?? other.kind}
              </>
            )}
          </Text>
          <Facts
            parts={[
              ...listedParts(item),
              <UsualLine key="usual" item={item} now={item.ah_sell_price} />,
              <>
                break-even <Money copper={breakEven(r, cut)} />
              </>,
              lowest !== null && (
                <>
                  below <Money copper={lowest} /> another way pays more
                </>
              ),
            ]}
          />
        </Stack>
      )
    }
    const exitValue = r.exits.find((e) => e.kind === r.best_exit)
    return (
      <Stack gap={2}>
        <Text fw={600}>
          {r.best_exit === 'keep' ? (
            <>Kept: no vendor buys it</>
          ) : (
            <>
              Sold via {EXIT_SHORT[r.best_exit] ?? r.best_exit}
              {exitValue && r.best_exit === 'vendor' && (
                <>
                  {' '}
                  for <Money copper={exitValue.value} /> each
                </>
              )}
            </>
          )}
        </Text>
        {item && item.ah_price != null ? (
          <Facts parts={['On the auction house', ...listedParts(item), <UsualLine key="usual" item={item} now={item.ah_sell_price} />]} />
        ) : (
          <Text size="sm" c="dimmed">
            Nothing known of it on this realm&apos;s auction house.
          </Text>
        )}
      </Stack>
    )
  }
  if (m.group === 'buy') {
    if (m.source === 'vendor') {
      const off = (m.node?.discount ?? 0) + (m.node?.rep_discount ?? 0)
      return (
        <Text fw={600}>
          Bought from a vendor: <Money copper={Math.round((m.cost ?? 0) / Math.max(1, m.quantity))} /> each,{' '}
          <Money copper={m.cost ?? 0} /> for your {m.quantity}
          {off > 0 && ` (${off}% off)`}
        </Text>
      )
    }
    if (m.source === 'gather') {
      return (
        <Text fw={600}>
          You gather {m.quantity}, valued at <Money copper={m.cost ?? 0} />
        </Text>
      )
    }
    const walk = item ? walkLadder(item.ah_levels, m.quantity) : null
    const uncounted = item?.ah_levels.filter((l) => !l.counted).reduce((n, l) => n + l.quantity, 0) ?? 0
    return (
      <Stack gap={2}>
        <Text fw={600}>
          Buying {m.quantity} for <Money copper={m.cost ?? 0} />
          {walk?.average != null && walk.last !== null && (
            <>
              : {m.shared && '~'}
              <Money copper={walk.average} /> each on average, the last at <Money copper={walk.last} />
            </>
          )}
          {m.short > 0 && walk?.dearest != null && (
            <>
              . {m.short} more than are listed, priced at the dearest <Money copper={walk.dearest} />
            </>
          )}
        </Text>
        {item && (
          <Facts
            parts={[
              <UsualLine key="usual" item={item} now={priceNow(m, item)} />,
              ...listedParts(item),
              uncounted > 0 && `${uncounted} just listed, not counted on`,
            ]}
          />
        )}
      </Stack>
    )
  }
  if (m.group === 'make') {
    const instead = m.node?.options.find((o) => o.key !== m.node?.option && o.source)
    return (
      <Stack gap={2}>
        <Text fw={600}>
          You craft {m.quantity} for <Money copper={m.cost ?? 0} />
          {instead && (
            <>
              ; buying them {instead.source === 'vendor' ? 'from a vendor' : 'on the auction house'} would cost{' '}
              <Money copper={instead.cost} />
            </>
          )}
        </Text>
        {item && item.ah_price != null && <Facts parts={listedParts(item)} />}
      </Stack>
    )
  }
  const material = r.exits.find((e) => e.kind === 'disenchant')?.materials.find((x) => x.item_id === m.itemId)
  return (
    <Stack gap={2}>
      <Text fw={600}>
        Disenchanting adds ~{expectedUnits(m.quantity)}
        {item?.ah_quantity != null ? ` to the ${item.ah_quantity.toLocaleString()} listed` : ''}
        {material?.value != null && (
          <>
            , valued at <Money copper={material.value} /> each
          </>
        )}
      </Text>
      {item && item.ah_price != null && (
        <Facts parts={[...listedParts(item), <UsualLine key="usual" item={item} now={item.ah_sell_price} />]} />
      )}
    </Stack>
  )
}

/** A button that shows or hides what follows it. */
function Disclosure({ open, onToggle, children }: { open: boolean; onToggle: () => void; children: ReactNode }) {
  return (
    <Button
      size="compact-sm"
      variant="subtle"
      aria-expanded={open}
      onClick={onToggle}
      leftSection={
        <span style={{ display: 'inline-flex', transform: open ? 'none' : 'rotate(-90deg)' }}>
          <IconChevron size={14} />
        </span>
      }
    >
      {children}
    </Button>
  )
}

/** The selected item's order book: its price levels as a staircase (or, for an output sold on the auction house,
 * the session's profit at each price) and as a table, then what was seen sold. */
function OrderBook({
  m,
  result: r,
  items,
  watchedHours,
}: {
  m: MarketItem
  result: RankResult
  items: ItemMap
  watchedHours: number
}) {
  const cut = useAhCut()
  const [view, setView] = useState<'book' | 'undercut'>('book')
  const item = items[m.itemId]
  if (!item || !item.ah_levels.length)
    return (
      <Text size="sm" c="dimmed">
        {item?.listed === false ? 'None listed in the newest scan.' : 'Nothing listed on this realm’s auction house.'}
      </Text>
    )
  const usual = usualPrice(item)
  const rules: Rule[] = []
  if (usual !== null) rules.push({ price: usual, label: 'usually', tone: 'profit' })
  const selling = m.group === 'sell' && (r.likely_exit || r.best_exit) === 'ah' && item.ah_sell_price != null
  let insert: { price: number; units: number; label: string } | undefined
  let taken: number[] | undefined
  if (m.group === 'sell' && item.ah_sell_price != null) {
    insert = { price: item.ah_sell_price, units: Math.round(m.quantity), label: 'we count on' }
    rules.push({ price: breakEven(r, cut), label: 'break-even', tone: 'cost' })
  } else if (m.group === 'disenchant' && item.ah_sell_price != null) {
    insert = { price: item.ah_sell_price, units: Math.max(1, Math.round(m.quantity)), label: 'yours at' }
  } else if (m.group === 'buy' && m.source === 'ah') {
    taken = walkLadder(item.ah_levels, m.quantity).taken
  }
  const marks: Rule[] = [
    { price: breakEven(r, cut), label: 'break-even', tone: 'cost' },
    ...(usual !== null ? [{ price: usual, label: 'usually', tone: 'profit' as const }] : []),
  ]
  return (
    <Stack gap="xs">
      {selling && (
        <SegmentedControl
          size="xs"
          style={{ alignSelf: 'flex-start' }}
          value={view}
          onChange={(v) => setView(v as 'book' | 'undercut')}
          data={[
            { value: 'book', label: 'Order book' },
            { value: 'undercut', label: 'If I undercut' },
          ]}
        />
      )}
      {selling && view === 'undercut' ? (
        <ProfitChart result={r} sellPrice={item.ah_sell_price!} cut={cut} marks={marks} />
      ) : (
        <DepthChart name={m.name} levels={item.ah_levels} insert={insert} taken={taken} rules={rules} />
      )}
      <LadderTable levels={item.ah_levels} taken={taken} shared={m.shared} />
      <Text size="sm">{seenSold(item.sold_7d, watchedHours, item.sold_pairs_7d ?? null)}.</Text>
    </Stack>
  )
}

/** Every way to sell with the session's profit; what goes elsewhere past the market's depth, and what disenchanting
 * adds to each material's market. */
function WaysToSell({ result: r, items }: { result: RankResult; items: ItemMap }) {
  const best = Math.max(1, ...r.sell_options.map((o) => Math.abs(o.profit)))
  return (
    <Stack gap={4}>
      {r.sell_options.map((o) => (
        <Group key={o.kind} gap="xs" wrap="nowrap">
          <Text size="sm" w={110}>
            {EXIT_SHORT[o.kind] ?? o.kind}
          </Text>
          <Text size="sm" ff="monospace" w={90}>
            <Earned copper={o.profit} minus />
          </Text>
          <Progress
            value={(100 * Math.abs(o.profit)) / best}
            color={o.profit < 0 ? 'red' : 'teal'}
            size="sm"
            w={80}
            aria-hidden
          />
        </Group>
      ))}
      {r.excess_units > 0 && (
        <Text size="xs" c="dimmed">
          The market has taken about {r.depth_units} lately: the other {r.excess_units} are counted at{' '}
          {EXIT_SHORT[r.likely_exit === 'ah' ? 'vendor' : r.likely_exit] ?? 'the next best way'}.
        </Text>
      )}
      {floodCheck(r, items).map((f) => (
        <Text key={f.itemId} size="xs" c="dimmed">
          Disenchanting adds ~{f.adds} {f.name}
          {f.listed != null && ` to the ${f.listed.toLocaleString()} listed`}
        </Text>
      ))}
    </Stack>
  )
}

/** How the section's numbers are counted, with the item's own. */
function HowWeCount({ item }: { item: ItemInfo }) {
  const gear = item.class_id === 2 || item.class_id === 4
  return (
    <Stack gap={6}>
      <Text size="sm">
        <b>What is asked</b> is the price 15% of the way into the units listed
        {item.market_price != null && (
          <>
            {' '}
            (<Money copper={item.market_price} /> here)
          </>
        )}
        , so one cheap or overpriced listing doesn&apos;t set it.
      </Text>
      <Text size="sm">
        <b>Usually</b> is the median over the latest days with scans, up to 7 of them within 30 days ({days(item)} here). It
        counts days, not scans, and says nothing until there are 3.
      </Text>
      <Text size="sm">
        <b>Sales seen</b> are the units gone off the cheap end between two scans at most 30 minutes apart: a lower bound,
        since sales are only seen while someone scans back to back.
      </Text>
      {gear && (
        <Text size="sm">
          <b>All suffixes pooled:</b> random-suffix gear shares one set of price levels with its base item.
        </Text>
      )}
    </Stack>
  )
}

/** More about the selected item: every way to sell (for what is sold), the sales seen, and how it is all counted. */
function MoreAbout({
  m,
  result,
  items,
  watchedHours,
}: {
  m: MarketItem
  result: RankResult
  items: ItemMap
  watchedHours: number
}) {
  const item = items[m.itemId]
  const tabs = [
    ...(m.group === 'sell' ? [{ value: 'ways', label: 'Ways to sell' }] : []),
    ...(item ? [{ value: 'sales', label: 'Sales seen' }, { value: 'how', label: 'How we count' }] : []),
  ]
  if (!tabs.length) return null
  return (
    <Tabs defaultValue={tabs[0]!.value} key={m.itemId}>
      <Tabs.List>
        {tabs.map((t) => (
          <Tabs.Tab key={t.value} value={t.value}>
            {t.label}
          </Tabs.Tab>
        ))}
      </Tabs.List>
      <Tabs.Panel value="ways" pt="xs">
        <WaysToSell result={result} items={items} />
      </Tabs.Panel>
      {item && (
        <>
          <Tabs.Panel value="sales" pt="xs">
            <Stack gap={4}>
              <Text size="sm">{seenSold(item.sold_7d, watchedHours, item.sold_pairs_7d ?? null)}.</Text>
              {item.sale_price != null && (
                <Text size="sm">
                  It went for <Money copper={item.sale_price} /> on average when it sold.
                </Text>
              )}
              <Text size="xs" c="dimmed">
                A day with no sales seen may mean nobody scanned twice within 30 minutes, not that nothing sold.
              </Text>
            </Stack>
          </Tabs.Panel>
          <Tabs.Panel value="how" pt="xs">
            <HowWeCount item={item} />
          </Tabs.Panel>
        </>
      )}
    </Tabs>
  )
}

/**
 * The plan's market, item by item: the plan as a strip of items to pick from (bought, made, sold, disenchanted, each
 * with the one thing most worth knowing about its market), what the picked one's market says, then on a click its
 * order book (the levels as a chart and a table) and more about it. Which of those stay open is remembered.
 */
export function MarketSection({
  result,
  items,
  list,
  selected,
  onSelect,
  watchedHours,
}: {
  result: RankResult
  items: ItemMap
  list: readonly MarketItem[]
  selected: number | null
  onSelect: (itemId: number) => void
  watchedHours: number
}) {
  const [book, setBook] = useStoredState('altarmy.market.book', z.boolean(), false)
  const [more, setMore] = useStoredState('altarmy.market.more', z.boolean(), false)
  const m = list.find((x) => x.itemId === selected)
  if (!m)
    return (
      <Text size="sm" c="dimmed">
        Nothing in this plan has a market.
      </Text>
    )
  const item = items[m.itemId]
  const hasBook = !!item && (item.ah_levels.length > 0 || item.listed === false)
  return (
    <Stack gap="sm">
      <RecipeStrip result={result} list={list} items={items} selected={selected} onSelect={onSelect} />
      <Headline m={m} result={result} items={items} />
      <Group gap="md">
        {hasBook && (
          <Disclosure open={book} onToggle={() => setBook(!book)}>
            Show the order book
          </Disclosure>
        )}
        <Disclosure open={more} onToggle={() => setMore(!more)}>
          More about {m.name}
        </Disclosure>
      </Group>
      {hasBook && book && <OrderBook m={m} result={result} items={items} watchedHours={watchedHours} />}
      {more && <MoreAbout m={m} result={result} items={items} watchedHours={watchedHours} />}
    </Stack>
  )
}
