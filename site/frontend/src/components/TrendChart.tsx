import { useState, type PointerEvent } from 'react'
import { Button, Group, Stack, Text } from '@mantine/core'
import { AxisBottom, AxisLeft } from '@visx/axis'
import { GridRows } from '@visx/grid'
import { scaleLinear } from '@visx/scale'
import { Area, Bar, Line, LinePath } from '@visx/shape'
import type { MarketHistory } from '../api/client'
import { priceRange } from '../lib/depth'
import { formatMoney } from '../lib/money'
import { ChartTooltip } from './ChartParts'
import { NARROW, pointerAt, tickLabels, useChartWidth } from './chartKit'
import charts from './Charts.module.css'
import { Money } from './Money'

const WIDTH = 720
const H = 240 // the price panel
const SOLD_H = 64 // the units panel under it
const LEFT = 70
const RIGHT = 16
const TOP = 12
const BOTTOM = 26
const HOUR_MS = 3_600_000
const DAY_MS = 86_400_000
// a view this short or shorter is drawn hour by hour (when it has the hours)
export const HOURLY_SPAN = 7 * DAY_MS
// the narrowest a drag zooms to, and how far it must drag (px) to count as one
const MIN_ZOOM = 6 * HOUR_MS
const MIN_DRAG = 6
// hours further apart than this are not joined by a line: nothing was seen between them
const GAP = 3 * HOUR_MS
// a day's high may be one silly listing: the scale stops this far above the highest median or market price
const HIGH_CAP = 1.5

const shortDay = (ms: number) => new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
const clock = (ms: number) => new Date(ms).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
const noon = (day: string) => Date.parse(`${day}T12:00:00Z`)

interface Day {
  t: number
  day: string
  low: number
  median: number | null
  high: number
  sold: number
}

export interface Hour {
  t: number // the hour's start
  low: number
  market: number
  units: number
}

/** The history's hours within `days` of its newest (the server sends whole UTC days, so a day's range has two). */
export function hourPoints(history: MarketHistory, days: number): Hour[] {
  const hours = history.hours.map((h) => ({ t: Date.parse(h.at), low: h.low, market: h.market, units: h.units }))
  if (!hours.length) return hours
  const from = hours[hours.length - 1].t - days * DAY_MS
  return hours.filter((h) => h.t > from)
}

/** The points within [t0, t1], and one either side of it so a line runs on to the plot's edge (clipped there). */
function within<T extends { t: number }>(points: readonly T[], t0: number, t1: number): T[] {
  const first = points.findIndex((p) => p.t >= t0)
  if (first < 0) return points.slice(-1)
  let last = first
  while (last < points.length && points[last].t <= t1) last++
  return points.slice(Math.max(0, first - 1), Math.min(points.length, last + 1))
}

/** The hours with a break (null) wherever two are more than GAP apart. */
function withGaps(hours: readonly Hour[]): (Hour | null)[] {
  const out: (Hour | null)[] = []
  hours.forEach((h, i) => {
    if (i > 0 && h.t - hours[i - 1].t > GAP) out.push(null)
    out.push(h)
  })
  return out
}

/** Ticks on whole local hours or midnights for a view of two weeks or less; undefined (the scale's own) past that. */
function timeTicks(t0: number, t1: number, most: number): number[] | undefined {
  const span = t1 - t0
  if (span > 14 * DAY_MS) return undefined
  const step = [1, 2, 3, 6, 12, 24, 48, 72, 168].map((h) => h * HOUR_MS).find((s) => span / s <= most) ?? 168 * HOUR_MS
  const start = new Date(t0)
  start.setHours(0, 0, 0, 0)
  const ticks = []
  for (let t = start.getTime(); t <= t1; t += step) if (t >= t0) ticks.push(t)
  return ticks
}

const isMidnight = (t: number) => {
  const d = new Date(t)
  return d.getHours() === 0 && d.getMinutes() === 0
}

/**
 * The Trends page's chart: an item's price at one auction house over the range asked for. A view longer than a week
 * is drawn by the day: the low-to-high band, the median and, where it has them (two weeks), the hourly market price,
 * with what was bought each day in a panel of its own under it. A week or less is drawn by the hour: the market price
 * and the lowest listing, on a scale fitted to them so hour-to-hour moves show, with the units listed each hour
 * under it. Dragging across the chart zooms in on that stretch (by the hour once it is a week or less); double-click
 * or Zoom out goes back. Hovering reads the day or hour.
 */
export function TrendChart({ history, name, days: rangeDays }: { history: MarketHistory; name: string; days: number }) {
  const { ref, width } = useChartWidth(WIDTH)
  const [pointer, setPointer] = useState<{ x: number; y: number } | null>(null)
  const [drag, setDrag] = useState<{ from: number; to: number } | null>(null)
  const [zoom, setZoom] = useState<[number, number] | null>(null)

  const soldBy = new Map(history.flows.map((f) => [f.day, f.sold]))
  const allDays: Day[] = history.days.map((d) => ({
    t: noon(d.day),
    day: d.day,
    low: d.low,
    median: d.median,
    high: d.high,
    sold: soldBy.get(d.day) ?? 0,
  }))
  const allHours = hourPoints(history, rangeDays)

  // the whole range: by the hour when it is short and has them, else by the day
  const byHour = rangeDays * DAY_MS <= HOURLY_SPAN && allHours.length > 1
  const times = byHour ? allHours.map((h) => h.t) : [...allDays.map((d) => d.t), ...allHours.map((h) => h.t)]
  const full0 = Math.min(...times)
  const full1 = Math.max(full0 + (byHour ? HOUR_MS : DAY_MS), ...times)
  const [t0, t1] = zoom ?? [full0, full1]

  const hoursIn = within(allHours, t0, t1)
  const hourly = (zoom ? t1 - t0 <= HOURLY_SPAN : byHour) && hoursIn.length > 1
  const daysIn = within(allDays, t0, t1)
  const inView = <T extends { t: number }>(p: T) => p.t >= t0 && p.t <= t1
  const shownHours = hoursIn.filter(inView)
  const shownDays = daysIn.filter(inView)

  // the price scale, fitted to what is in view
  let centre: number[]
  let highs: number[] = []
  if (hourly) {
    centre = (shownHours.length ? shownHours : hoursIn).flatMap((h) => [h.low, h.market])
  } else {
    const ds = shownDays.length ? shownDays : daysIn
    centre = [
      ...ds.flatMap((d) => (d.median != null ? [d.median, d.low] : [d.low])),
      ...(shownHours.length ? shownHours : []).map((h) => h.market),
    ]
    const cap = Math.max(...centre) * HIGH_CAP
    highs = ds.map((d) => Math.min(d.high, cap))
  }
  if (!centre.length) centre = allDays.length ? allDays.map((d) => d.low) : allHours.map((h) => h.market)
  const { lo, hi } = priceRange([...centre, ...highs])

  const narrow = width < NARROW
  const right = width - RIGHT
  const x = scaleLinear({ domain: [t0, t1], range: [LEFT, right] })
  const y = scaleLinear({ domain: [lo, hi], range: [H - BOTTOM, TOP], nice: 4 })
  const yMax = y.domain()[1]
  const clampY = (p: number) => y(Math.min(p, yMax))
  const ticks = timeTicks(t0, t1, narrow ? 3 : 6)

  // the panel under the prices: units listed each hour, or bought each day
  const bars = hourly
    ? shownHours.map((h) => ({ key: String(h.t), t: h.t, n: h.units }))
    : shownDays.map((d) => ({ key: d.day, t: d.t, n: d.sold }))
  const maxBar = Math.max(1, ...bars.map((b) => b.n))
  const yBar = scaleLinear({ domain: [0, maxBar], range: [SOLD_H - 4, 4] })
  const slot = hourly ? HOUR_MS : DAY_MS
  const barW = Math.max(1, Math.min(14, ((right - LEFT) / Math.max(1, (t1 - t0) / slot)) * 0.7))

  const medians = daysIn.filter((d): d is Day & { median: number } => d.median != null)
  const hourLine = withGaps(hoursIn)

  // the day or hour nearest the pointer, kept on the plot
  const onPlot = (px: number) => px >= LEFT - 8 && px <= right + 8
  const nearest = <T extends { t: number }>(points: readonly T[], t: number) =>
    points.reduce<T | undefined>((best, p) => (!best || Math.abs(p.t - t) < Math.abs(best.t - t) ? p : best), undefined)
  const hoverT = pointer && !drag && onPlot(pointer.x) ? x.invert(pointer.x) : null
  const overHour = hourly && hoverT !== null ? nearest(shownHours, hoverT) : undefined
  const overDay = !hourly && hoverT !== null ? nearest(shownDays, hoverT) : undefined
  const overT = overHour?.t ?? overDay?.t

  const onDown = (e: PointerEvent<SVGRectElement>) => {
    const at = pointerAt(e)
    if (!at || !onPlot(at.x)) return
    e.currentTarget.setPointerCapture?.(e.pointerId)
    setDrag({ from: at.x, to: at.x })
  }
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const at = pointerAt(e)
    setPointer(at)
    if (drag && at) setDrag({ ...drag, to: Math.max(LEFT, Math.min(right, at.x)) })
  }
  const onUp = () => {
    if (drag && Math.abs(drag.to - drag.from) >= MIN_DRAG) {
      let a = x.invert(Math.min(drag.from, drag.to))
      let b = x.invert(Math.max(drag.from, drag.to))
      if (b - a < MIN_ZOOM) {
        const mid = (a + b) / 2
        a = mid - MIN_ZOOM / 2
        b = mid + MIN_ZOOM / 2
      }
      setZoom([Math.max(full0, a), Math.min(full1, b)])
    }
    setDrag(null)
  }

  return (
    <Stack gap={4}>
      <div ref={ref} className={charts.frame}>
        <svg className={charts.chart} width={width} height={H} role="img" aria-label={`Price history of ${name}`}>
          <defs>
            <clipPath id="trend-plot">
              <rect x={LEFT} y={0} width={right - LEFT} height={H - BOTTOM} />
            </clipPath>
          </defs>
          <GridRows scale={y} left={LEFT} width={right - LEFT} numTicks={4} className={charts.grid} />
          <AxisLeft
            scale={y}
            left={LEFT}
            numTicks={4}
            tickFormat={(p) => formatMoney(Number(p))}
            hideAxisLine
            hideTicks
            tickLabelProps={tickLabels('end')}
          />
          <g clipPath="url(#trend-plot)">
            {hourly ? (
              <>
                <LinePath
                  data={hourLine}
                  defined={(h) => h !== null}
                  x={(h) => x(h!.t)}
                  y={(h) => y(h!.low)}
                  className={charts.lowLine}
                />
                <LinePath
                  data={hourLine}
                  defined={(h) => h !== null}
                  x={(h) => x(h!.t)}
                  y={(h) => y(h!.market)}
                  className={charts.marketLine}
                />
              </>
            ) : (
              <>
                {daysIn.length > 1 && (
                  <Area
                    data={daysIn}
                    x={(d) => x(d.t)}
                    y0={(d) => clampY(d.low)}
                    y1={(d) => clampY(d.high)}
                    className={charts.trendBand}
                  />
                )}
                {hoursIn.length > 1 && (
                  <LinePath
                    data={hourLine}
                    defined={(h) => h !== null}
                    x={(h) => x(h!.t)}
                    y={(h) => clampY(h!.market)}
                    className={charts.hourLine}
                  />
                )}
                {medians.length > 1 && (
                  <LinePath data={medians} x={(d) => x(d.t)} y={(d) => clampY(d.median)} className={charts.dayLine} />
                )}
                {medians.length === 1 && (
                  <circle cx={x(medians[0].t)} cy={clampY(medians[0].median)} r={4} className={charts.dot} />
                )}
              </>
            )}
          </g>
          <AxisBottom
            scale={x}
            top={H - BOTTOM}
            numTicks={narrow ? 3 : 6}
            tickValues={ticks}
            tickFormat={(t) => (ticks && !isMidnight(Number(t)) ? clock(Number(t)) : shortDay(Number(t)))}
            hideAxisLine
            tickLength={5}
            tickLineProps={{ className: charts.tickMark }}
            tickLabelProps={tickLabels('middle')}
          />
          {overT !== undefined && (
            <>
              <Line from={{ x: x(overT), y: TOP }} to={{ x: x(overT), y: H - BOTTOM }} className={charts.cross} />
              {overHour && <circle cx={x(overHour.t)} cy={y(overHour.market)} r={4} className={charts.dot} />}
              {overDay?.median != null && <circle cx={x(overDay.t)} cy={clampY(overDay.median)} r={4} className={charts.dot} />}
            </>
          )}
          {drag && (
            <rect
              x={Math.min(drag.from, drag.to)}
              y={TOP}
              width={Math.abs(drag.to - drag.from)}
              height={H - BOTTOM - TOP}
              className={charts.brush}
              data-testid="chart-brush"
            />
          )}
          <rect
            width={width}
            height={H}
            className={charts.hit}
            data-testid="chart-hover"
            onPointerDown={onDown}
            onPointerMove={onMove}
            onPointerUp={onUp}
            onPointerLeave={() => {
              setPointer(null)
              setDrag(null)
            }}
            onDoubleClick={() => setZoom(null)}
          />
        </svg>
        {pointer && overHour && (
          <ChartTooltip left={x(overHour.t)} top={pointer.y}>
            <div>
              <strong>
                {shortDay(overHour.t)}, {clock(overHour.t)}
              </strong>
            </div>
            <div>
              Market <Money copper={overHour.market} />
            </div>
            <div className={charts.dim}>
              Lowest listing <Money copper={overHour.low} />
            </div>
            <div className={charts.dim}>{overHour.units} listed</div>
          </ChartTooltip>
        )}
        {pointer && overDay && (
          <ChartTooltip left={x(overDay.t)} top={pointer.y}>
            <div>
              <strong>{shortDay(overDay.t)}</strong>
            </div>
            <div>
              Median {overDay.median != null ? <Money copper={overDay.median} /> : <span className={charts.dim}>none</span>}
            </div>
            <div className={charts.dim}>
              Low <Money copper={overDay.low} /> · high <Money copper={overDay.high} />
            </div>
            <div className={charts.dim}>{overDay.sold} bought</div>
          </ChartTooltip>
        )}
      </div>
      <svg
        className={charts.chart}
        width={width}
        height={SOLD_H}
        role="img"
        aria-label={hourly ? `Units of ${name} listed each hour` : `Units of ${name} bought each day`}
      >
        <text x={LEFT - 8} y={12} textAnchor="end" className={charts.caption}>
          {hourly ? 'listed' : 'bought'}
        </text>
        <text x={LEFT - 8} y={26} textAnchor="end" className={charts.axis}>
          {maxBar}
        </text>
        <Line from={{ x: LEFT, y: SOLD_H - 4 }} to={{ x: right, y: SOLD_H - 4 }} className={charts.base} />
        {bars
          .filter((b) => b.n > 0)
          .map((b) => (
            <Bar
              key={b.key}
              x={x(b.t) - barW / 2}
              y={yBar(b.n)}
              width={barW}
              height={SOLD_H - 4 - yBar(b.n)}
              rx={Math.min(2, barW / 2)}
              className={overT === b.t ? charts.soldBarOver : charts.soldBar}
            />
          ))}
      </svg>
      <Group justify="space-between" gap="xs" wrap="wrap">
        <ul className={charts.trendLegend} aria-label="Legend">
          {hourly ? (
            <>
              <li className={charts.keyMarket}>hourly market price</li>
              <li className={charts.keyLow}>hourly lowest listing</li>
            </>
          ) : (
            <>
              <li className={charts.keyMedian}>daily median</li>
              <li className={charts.keyBand}>daily low to high</li>
              {hoursIn.length > 1 && <li className={charts.keyHour}>hourly market price</li>}
            </>
          )}
        </ul>
        <Group gap="xs">
          <Text size="xs" c="dimmed">
            {zoom ? 'Double-click to zoom out' : 'Drag across the chart to zoom in'}
          </Text>
          {zoom && (
            <Button size="compact-xs" variant="light" onClick={() => setZoom(null)}>
              Zoom out
            </Button>
          )}
        </Group>
      </Group>
    </Stack>
  )
}
