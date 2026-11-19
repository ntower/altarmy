import { useState, type PointerEvent } from 'react'
import { Stack } from '@mantine/core'
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
const SOLD_H = 64 // the units bought panel under it
const LEFT = 70
const RIGHT = 16
const TOP = 12
const BOTTOM = 26
const DAY_MS = 86_400_000
// a day's high may be one silly listing: the scale stops this far above the highest median or market price
const HIGH_CAP = 1.5

const shortDay = (ms: number) => new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
const noon = (day: string) => Date.parse(`${day}T12:00:00Z`)

interface Day {
  t: number
  day: string
  low: number
  median: number | null
  high: number
  sold: number
}

/**
 * The Trends page's chart: an item's daily low-to-high band and median at one auction house over the range asked
 * for, with the hourly market price on top when the range is short enough to have it (two weeks), and what was
 * bought each day in a panel of its own under it (its own scale, not a second axis). Hovering reads a day.
 */
export function TrendChart({ history, name }: { history: MarketHistory; name: string }) {
  const { ref, width } = useChartWidth(WIDTH)
  const [hover, setHover] = useState<{ i: number; y: number } | null>(null)
  const soldBy = new Map(history.flows.map((f) => [f.day, f.sold]))
  const days: Day[] = history.days.map((d) => ({
    t: noon(d.day),
    day: d.day,
    low: d.low,
    median: d.median,
    high: d.high,
    sold: soldBy.get(d.day) ?? 0,
  }))
  const hours = history.hours.map((h) => ({ t: Date.parse(h.at), price: h.market }))
  const medians = days.filter((d): d is Day & { median: number } => d.median != null)
  const times = [...days.map((d) => d.t), ...hours.map((h) => h.t)]
  const t0 = Math.min(...times)
  const t1 = Math.max(t0 + DAY_MS, ...times)
  const centre = [...medians.map((d) => d.median), ...hours.map((h) => h.price), ...days.map((d) => d.low)]
  const cap = Math.max(...centre) * HIGH_CAP
  const { lo, hi } = priceRange([...centre, ...days.map((d) => Math.min(d.high, cap))])
  const narrow = width < NARROW
  const right = width - RIGHT
  const x = scaleLinear({ domain: [t0, t1], range: [LEFT, right] })
  const y = scaleLinear({ domain: [lo, hi], range: [H - BOTTOM, TOP], nice: 4 })
  const yMax = y.domain()[1]
  const clampY = (p: number) => y(Math.min(p, yMax))
  const maxSold = Math.max(1, ...days.map((d) => d.sold))
  const ySold = scaleLinear({ domain: [0, maxSold], range: [SOLD_H - 4, 4] })
  const barW = Math.max(1, Math.min(14, ((right - LEFT) / Math.max(1, (t1 - t0) / DAY_MS)) * 0.7))

  // the day nearest the pointer, kept on the plot
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const at = pointerAt(e)
    if (!at || !days.length || at.x < LEFT - 8 || at.x > right + 8) return setHover(null)
    const t = x.invert(at.x)
    let best = 0
    days.forEach((d, i) => {
      if (Math.abs(d.t - t) < Math.abs(days[best].t - t)) best = i
    })
    setHover({ i: best, y: at.y })
  }
  const over = hover ? days[hover.i] : undefined

  return (
    <Stack gap={4}>
      <div ref={ref} className={charts.frame}>
        <svg className={charts.chart} width={width} height={H} role="img" aria-label={`Price history of ${name}`}>
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
          {days.length > 1 && (
            <Area
              data={days}
              x={(d) => x(d.t)}
              y0={(d) => clampY(d.low)}
              y1={(d) => clampY(d.high)}
              className={charts.trendBand}
            />
          )}
          {hours.length > 1 && (
            <LinePath data={hours} x={(p) => x(p.t)} y={(p) => clampY(p.price)} className={charts.hourLine} />
          )}
          {medians.length > 1 && (
            <LinePath data={medians} x={(d) => x(d.t)} y={(d) => clampY(d.median)} className={charts.dayLine} />
          )}
          {medians.length === 1 && <circle cx={x(medians[0].t)} cy={clampY(medians[0].median)} r={4} className={charts.dot} />}
          <AxisBottom
            scale={x}
            top={H - BOTTOM}
            numTicks={narrow ? 3 : 6}
            tickFormat={(t) => shortDay(Number(t))}
            hideAxisLine
            tickLength={5}
            tickLineProps={{ className: charts.tickMark }}
            tickLabelProps={tickLabels('middle')}
          />
          {over && (
            <>
              <Line from={{ x: x(over.t), y: TOP }} to={{ x: x(over.t), y: H - BOTTOM }} className={charts.cross} />
              {over.median != null && <circle cx={x(over.t)} cy={clampY(over.median)} r={4} className={charts.dot} />}
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
        {over && hover && (
          <ChartTooltip left={x(over.t)} top={hover.y}>
            <div>
              <strong>{shortDay(over.t)}</strong>
            </div>
            <div>
              Median {over.median != null ? <Money copper={over.median} /> : <span className={charts.dim}>none</span>}
            </div>
            <div className={charts.dim}>
              Low <Money copper={over.low} /> · high <Money copper={over.high} />
            </div>
            <div className={charts.dim}>{over.sold} bought</div>
          </ChartTooltip>
        )}
      </div>
      <svg className={charts.chart} width={width} height={SOLD_H} role="img" aria-label={`Units of ${name} bought each day`}>
        <text x={LEFT - 8} y={12} textAnchor="end" className={charts.caption}>
          bought
        </text>
        <text x={LEFT - 8} y={26} textAnchor="end" className={charts.axis}>
          {maxSold}
        </text>
        <Line from={{ x: LEFT, y: SOLD_H - 4 }} to={{ x: right, y: SOLD_H - 4 }} className={charts.base} />
        {days
          .filter((d) => d.sold > 0)
          .map((d) => (
            <Bar
              key={d.day}
              x={x(d.t) - barW / 2}
              y={ySold(d.sold)}
              width={barW}
              height={SOLD_H - 4 - ySold(d.sold)}
              rx={Math.min(2, barW / 2)}
              className={over?.day === d.day ? charts.soldBarOver : charts.soldBar}
            />
          ))}
      </svg>
      <ul className={charts.trendLegend} aria-label="Legend">
        <li className={charts.keyMedian}>daily median</li>
        <li className={charts.keyBand}>daily low to high</li>
        {hours.length > 1 && <li className={charts.keyHour}>hourly market price</li>}
      </ul>
    </Stack>
  )
}
