import { useState, type PointerEvent } from 'react'
import { Table, Text } from '@mantine/core'
import { AxisBottom, AxisLeft } from '@visx/axis'
import { GridRows } from '@visx/grid'
import { scaleLinear } from '@visx/scale'
import { Bar, Line, LinePath } from '@visx/shape'
import type { ItemInfo, RankResult } from '../api/client'
import { depthSteps, priceRange, profitAt, valueRange, type DepthStep } from '../lib/depth'
import { EXIT_SHORT } from '../lib/exits'
import { formatMoney } from '../lib/money'
import { ChartTooltip, NotesLegend, RightNotes } from './ChartParts'
import { NARROW, pointerAt, tickLabels, TONE, useChartWidth, type Note } from './chartKit'
import charts from './Charts.module.css'
import classes from './MarketSection.module.css'
import { Money } from './Money'

/* The Market section's charts (visx on the theme's colours): the order book as a staircase and the session's profit
 * over the price it is listed at; and the order book as a table. */

type Level = ItemInfo['ah_levels'][number]

/** A dashed line across a chart at a price, named at its right end. */
export interface Rule {
  price: number
  label: string
  tone: 'cost' | 'profit' | 'plain'
}

const WIDTH = 640
const H = 206
const LEFT = 66
const RIGHT = 176
const NARROW_RIGHT = 16
const TOP = 14
const BOTTOM = 42
/** The order book has no caption under its axis: the same plot as the profit chart's, on less height. */
const DEPTH_BOTTOM = 26
const DEPTH_H = H - BOTTOM + DEPTH_BOTTOM
/** About how wide a character of the axis's 11 px monospace is, and the room left between two tick labels. */
const CHAR_PX = 6.7
const TICK_ROOM = 12

/** The x ticks in the order given (the ones that mean most first), leaving out any whose label would crowd one kept
 * before it. */
function apart(values: readonly number[], x: (v: number) => number): number[] {
  const half = (v: number) => (v.toLocaleString().length * CHAR_PX) / 2
  const kept: number[] = []
  for (const v of values)
    if (!kept.some((k) => k === v || Math.abs(x(k) - x(v)) < half(k) + half(v) + TICK_ROOM)) kept.push(v)
  return kept
}

/** What the order book's tooltip says of one stretch of it. */
function StepTip({ step: s, insertLabel }: { step: DepthStep; insertLabel: string | undefined }) {
  const units = s.x1 - s.x0
  if (s.kind === 'you')
    return (
      <>
        <div>
          Yours: {units} at <Money copper={s.price} />
        </div>
        {insertLabel && <div className={charts.dim}>{insertLabel} this price</div>}
      </>
    )
  return (
    <>
      <div>
        <Money copper={s.price} />
        {s.kind === 'tail' && ' and up'}: {units.toLocaleString()}
        {s.kind === 'tail' && '+'} {units === 1 ? 'unit' : 'units'}
      </div>
      <div className={charts.dim}>
        {s.listings} {s.listings === 1 ? 'listing' : 'listings'} ·{' '}
        {s.age === 0 ? 'just listed' : `listed for ${s.age + 1} scans`}
      </div>
      {s.taken > 0 && <div>You buy {s.taken}</div>}
      {s.kind === 'uncounted' && <div className={charts.dim}>Not counted on: it may be gone before you get there</div>}
    </>
  )
}

/**
 * The order book as a staircase: units listed along, price up, cheapest first. What the plan lists (`insert`) is put
 * in as a block where it would sit; what it buys (`taken`) is shaded. Levels plans don't count on are dashed, the
 * level pooling every higher-priced one is named at the right end; `rules` mark prices across it (break-even, the usual
 * price). Hovering a level tells its units, listings and age.
 */
export function DepthChart({
  name,
  levels,
  insert,
  taken,
  rules = [],
}: {
  name: string
  levels: readonly Level[]
  insert?: { price: number; units: number; label: string } | undefined
  taken?: readonly number[] | undefined
  rules?: readonly Rule[]
}) {
  const { ref, width } = useChartWidth(WIDTH)
  const [hovered, setHovered] = useState<{ i: number; x: number; y: number } | null>(null)
  const { steps, total } = depthSteps(levels, { insert, taken })
  if (!steps.length) return null
  const narrow = width < NARROW
  const right = width - (narrow ? NARROW_RIGHT : RIGHT)
  const { lo, hi } = priceRange([...steps.map((s) => s.price), ...rules.map((r) => r.price)])
  const x = scaleLinear({ domain: [0, Math.max(1, total)], range: [LEFT, right] })
  const y = scaleLinear({ domain: [lo, hi], range: [DEPTH_H - DEPTH_BOTTOM, TOP], nice: 4 })
  const base = DEPTH_H - DEPTH_BOTTOM
  const bought = steps.reduce((sum, s) => sum + s.taken, 0)
  const lastTaken = [...steps].reverse().find((s) => s.taken > 0)
  // the labels at the right end: the rules, what the plan lists or where its buying ends, and the pooled level
  const notes: Note[] = rules.map((r) => ({ y: y(r.price), text: `${r.label} ${formatMoney(r.price)}`, tone: r.tone }))
  const you = steps.find((s) => s.kind === 'you')
  if (you && insert) notes.push({ y: y(you.price), text: `${insert.label} ${formatMoney(you.price)}`, tone: 'you' })
  if (lastTaken)
    notes.push({ y: y(lastTaken.price), text: `your ${bought} end at ${formatMoney(lastTaken.price)}`, tone: 'you' })
  const tail = steps.find((s) => s.kind === 'tail')
  if (tail) notes.push({ y: y(tail.price), text: `${tail.x1 - tail.x0}+ from ${formatMoney(tail.price)}`, tone: 'plain' })
  // the ticks that mean something first, then round numbers of units between them, about one per 70 px
  const steady = x.ticks(Math.max(2, Math.floor((right - LEFT) / 70))).filter((v) => Number.isInteger(v))
  const xTicks = apart([0, total, ...(you ? [you.x0] : []), ...(bought ? [bought] : []), ...steady], x)
  // the level under the pointer, along the plot
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const at = pointerAt(e)
    if (!at || at.x < LEFT || at.x > right) return setHovered(null)
    const units = x.invert(at.x)
    const i = steps.findIndex((s) => units < s.x1)
    setHovered({ i: i < 0 ? steps.length - 1 : i, x: at.x, y: at.y })
  }
  const over = hovered ? steps[hovered.i] : undefined
  return (
    <div ref={ref} className={`${charts.frame} ${classes.chartFrame}`}>
      <svg
        className={charts.chart}
        width={width}
        height={DEPTH_H}
        role="img"
        aria-label={`Price levels listed for ${name}, cheapest first`}
      >
        <GridRows scale={y} left={LEFT} width={right - LEFT} numTicks={4} className={charts.grid} />
        <AxisLeft
          scale={y}
          left={LEFT}
          numTicks={4}
          tickFormat={(p) => formatMoney(Number(p))}
          hideAxisLine
          hideTicks
          tickLength={6}
          tickLabelProps={tickLabels('end')}
        />
        {over && (
          <Bar
            x={x(over.x0)}
            y={TOP}
            width={Math.max(2, x(over.x1) - x(over.x0))}
            height={base - TOP}
            className={classes.hovered}
          />
        )}
        {steps.map((s, i) => {
          const x0 = x(s.x0)
          const x1 = x(s.x1)
          const sy = y(s.price)
          const next = steps[i + 1]
          return (
            <g key={i} data-kind={s.kind}>
              {s.taken > 0 && (
                <Bar x={x0} y={sy} width={x(s.x0 + s.taken) - x0} height={base - sy} className={classes.taken} />
              )}
              {s.kind === 'you' ? (
                <>
                  <Bar x={x0} y={sy - 7} width={Math.max(2, x1 - x0)} height={14} rx={3} className={classes.you} />
                  {x1 - x0 > 46 && (
                    <text x={(x0 + x1) / 2} y={sy + 4} textAnchor="middle" className={classes.youText}>
                      YOU {s.x1 - s.x0}
                    </text>
                  )}
                </>
              ) : (
                <Line
                  from={{ x: x0, y: sy }}
                  to={{ x: x1, y: sy }}
                  className={s.kind === 'uncounted' ? classes.uncounted : classes.step}
                />
              )}
              {next && s.kind !== 'you' && next.kind !== 'you' && (
                <Line from={{ x: x1, y: sy }} to={{ x: x1, y: y(next.price) }} className={classes.riser} />
              )}
            </g>
          )
        })}
        {rules.map((r) => (
          <Line
            key={r.label}
            from={{ x: LEFT, y: y(r.price) }}
            to={{ x: right, y: y(r.price) }}
            className={`${charts.rule} ${TONE[r.tone]}`}
          />
        ))}
        {!narrow && <RightNotes notes={notes} x={right + 8} />}
        <Line from={{ x: LEFT, y: base }} to={{ x: right, y: base }} className={charts.base} />
        <AxisBottom
          scale={x}
          top={base}
          tickValues={xTicks}
          hideAxisLine
          tickLength={5}
          tickLineProps={{ className: charts.tickMark }}
          tickLabelProps={tickLabels('middle')}
        />
        <rect
          width={width}
          height={DEPTH_H}
          className={charts.hit}
          data-testid="chart-hover"
          onPointerMove={onMove}
          onPointerLeave={() => setHovered(null)}
        />
      </svg>
      {over && hovered && (
        <ChartTooltip left={hovered.x} top={hovered.y}>
          <StepTip step={over} insertLabel={insert?.label} />
        </ChartTooltip>
      )}
      {narrow && <NotesLegend notes={notes} />}
    </div>
  )
}

/**
 * What the session makes if it is listed at each price: the auction house's line rising with the price, every other
 * way to sell flat, so the price under which another way pays more is where the lines cross. Markers show break-even,
 * the plan's own price and the usual one; hovering reads the profit at any price.
 */
export function ProfitChart({
  result: r,
  sellPrice,
  cut,
  marks,
}: {
  result: RankResult
  sellPrice: number
  cut: number
  marks: readonly Rule[]
}) {
  const { ref, width } = useChartWidth(WIDTH)
  const [hover, setHover] = useState<{ price: number; y: number } | null>(null)
  const narrow = width < NARROW
  const right = width - (narrow ? NARROW_RIGHT : RIGHT)
  const others = r.sell_options.filter((o) => o.kind !== 'ah' && o.kind !== 'keep')
  const prices = [sellPrice, ...marks.map((m) => m.price)]
  const p0 = Math.floor(Math.min(...prices) * 0.8)
  const p1 = Math.ceil(Math.max(...prices) * 1.2)
  const at = (p: number) => profitAt(r, sellPrice, cut, p) ?? 0
  const { lo, hi } = valueRange([at(p0), at(p1), 0, ...others.map((o) => o.profit)])
  const x = scaleLinear({ domain: [p0, p1], range: [LEFT, right] })
  const y = scaleLinear({ domain: [lo, hi], range: [H - BOTTOM, TOP], nice: 4 })
  const base = H - BOTTOM
  const notes: Note[] = [
    { y: y(at(p1)), text: 'auction house', tone: 'profit' },
    ...others.map((o) => ({
      y: y(o.profit),
      text: `${EXIT_SHORT[o.kind] ?? o.kind} ${formatMoney(o.profit)}`,
      tone: 'plain' as const,
    })),
  ]
  // the price under the pointer, kept on the plot
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const point = pointerAt(e)
    if (!point || point.x < LEFT - 8 || point.x > right + 8) return setHover(null)
    setHover({ price: Math.round(x.invert(Math.min(right, Math.max(LEFT, point.x)))), y: point.y })
  }
  const hoverProfit = hover ? at(hover.price) : 0
  const better = hover ? others.filter((o) => o.profit > hoverProfit).sort((a, b) => b.profit - a.profit)[0] : undefined
  return (
    <div ref={ref} className={`${charts.frame} ${classes.chartFrame}`}>
      <svg className={charts.chart} width={width} height={H} role="img" aria-label="Session profit at each listing price">
        <GridRows scale={y} left={LEFT} width={right - LEFT} numTicks={4} className={charts.grid} />
        <Line from={{ x: LEFT, y: y(0) }} to={{ x: right, y: y(0) }} className={charts.base} />
        <AxisLeft
          scale={y}
          left={LEFT}
          numTicks={4}
          tickFormat={(p) => formatMoney(Number(p))}
          hideAxisLine
          hideTicks
          tickLength={6}
          tickLabelProps={tickLabels('end')}
        />
        {others.map((o) => (
          <Line
            key={o.kind}
            from={{ x: LEFT, y: y(o.profit) }}
            to={{ x: right, y: y(o.profit) }}
            className={`${charts.rule} ${TONE.plain}`}
          />
        ))}
        <LinePath data={[p0, p1]} x={(p) => x(p)} y={(p) => y(at(p))} className={classes.profitLine} />
        {marks.map((m, i) => (
          <g key={m.label}>
            <Line from={{ x: x(m.price), y: TOP }} to={{ x: x(m.price), y: base }} className={`${charts.rule} ${TONE[m.tone]}`} />
            <text x={x(m.price) + 4} y={TOP + 10 + i * 13} className={`${charts.note} ${TONE[m.tone]}`}>
              {m.label}
            </text>
          </g>
        ))}
        <circle cx={x(sellPrice)} cy={y(at(sellPrice))} r={4.5} className={classes.you} />
        <text x={x(sellPrice) + 8} y={y(at(sellPrice)) + 16} className={`${charts.note} ${TONE.you}`}>
          {formatMoney(at(sellPrice))}
        </text>
        {!narrow && <RightNotes notes={notes} x={right + 8} />}
        <AxisBottom
          scale={x}
          top={base}
          numTicks={narrow ? 3 : 5}
          tickFormat={(p) => formatMoney(Number(p))}
          hideAxisLine
          tickLength={5}
          tickLineProps={{ className: charts.tickMark }}
          tickLabelProps={tickLabels('middle')}
        />
        <text x={right} y={H - 4} textAnchor="end" className={charts.caption}>
          your listing price
        </text>
        {hover && (
          <>
            <Line from={{ x: x(hover.price), y: TOP }} to={{ x: x(hover.price), y: base }} className={charts.cross} />
            <circle cx={x(hover.price)} cy={y(hoverProfit)} r={4} className={charts.dot} />
          </>
        )}
        <rect
          width={width}
          height={H}
          className={charts.hit}
          data-testid="chart-hover"
          onPointerMove={onMove}
          onPointerLeave={() => setHover(null)}
        />
      </svg>
      {hover && (
        <ChartTooltip left={x(hover.price)} top={hover.y}>
          <div>
            Listed at <Money copper={hover.price} />: <Money copper={hoverProfit} />
          </div>
          {better && (
            <div className={charts.dim}>
              {EXIT_SHORT[better.kind] ?? better.kind} pays more: <Money copper={better.profit} />
            </div>
          )}
        </ChartTooltip>
      )}
      {narrow && <NotesLegend notes={notes} />}
    </div>
  )
}

/** Every price level listed, cheapest first: units, listings and how long it has been up (levels plans don't count on
 * dimmed); with `taken`, the units the plan buys of each ("~" when other branches share the walk). */
export function LadderTable({
  levels,
  taken,
  shared = false,
}: {
  levels: readonly Level[]
  taken?: readonly number[] | undefined
  shared?: boolean
}) {
  return (
    <div className={classes.tableWrap}>
      <Table className={classes.ladder} verticalSpacing={2} horizontalSpacing="xs" withRowBorders={false}>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Price</Table.Th>
            <Table.Th>Units</Table.Th>
            <Table.Th>Listings</Table.Th>
            <Table.Th>Listed for</Table.Th>
            {taken && <Table.Th>You buy</Table.Th>}
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {levels.map((l, i) => (
            <Table.Tr key={`${l.price}-${i}`} data-uncounted={!l.counted || undefined} data-taken={(taken?.[i] ?? 0) > 0 || undefined}>
              <Table.Td>
                <Money copper={l.price} />
                {l.more && ' and up'}
              </Table.Td>
              <Table.Td>
                {l.quantity.toLocaleString()}
                {l.more && '+'}
              </Table.Td>
              <Table.Td>{l.listings}</Table.Td>
              <Table.Td>
                {l.age === 0 ? 'just listed' : `${l.age + 1} scans`}
                {!l.counted && ' · not counted on'}
              </Table.Td>
              {taken && <Table.Td>{taken[i] ? `${shared ? '~' : ''}${taken[i]}` : ''}</Table.Td>}
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
      {levels.some((l) => !l.counted) && (
        <Text size="xs" c="dimmed">
          Levels first seen in the newest scan far under the usual price aren&apos;t counted on: they may be gone before you
          get there.
        </Text>
      )}
    </div>
  )
}
