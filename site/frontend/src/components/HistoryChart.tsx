import { Stack, Text } from '@mantine/core'
import { AxisBottom, AxisLeft } from '@visx/axis'
import { GridRows } from '@visx/grid'
import { scaleLinear } from '@visx/scale'
import { LinePath } from '@visx/shape'
import { useItemMarket } from '../api/queries'
import { formatMoney } from '../lib/money'
import { priceRange } from '../lib/depth'
import { NARROW, tickLabels, useChartWidth } from './chartKit'
import charts from './Charts.module.css'

const WIDTH = 640
const H = 190
const LEFT = 66
const RIGHT = 16
const TOP = 12
const BOTTOM = 26
const DAY_MS = 86_400_000

const shortDay = (ms: number) => new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })

/**
 * The Market section's History tab: what an item went for at the selected auction house (`/api/items/{id}/market`),
 * the hourly market price of the last two weeks as a thin line and each day's median of the last month as a bold one,
 * with what was bought each day under it. Says so when nothing is recorded yet.
 */
export function HistoryChart({ itemId, name }: { itemId: number; name: string }) {
  const { data } = useItemMarket(itemId)
  const { ref, width } = useChartWidth(WIDTH)
  if (!data) return null
  const hours = data.hours.map((h) => ({ t: Date.parse(h.at), price: h.market }))
  const days = data.days
    .filter((d) => d.median != null)
    .map((d) => ({ t: Date.parse(`${d.day}T12:00:00Z`), price: d.median! }))
  if (hours.length + days.length < 2)
    return (
      <Text size="sm" c="dimmed">
        Not enough of {name}&apos;s prices recorded here yet to draw.
      </Text>
    )
  const points = [...hours, ...days]
  const t0 = Math.min(...points.map((p) => p.t))
  const t1 = Math.max(t0 + DAY_MS, ...points.map((p) => p.t))
  const { lo, hi } = priceRange(points.map((p) => p.price))
  const right = width - RIGHT
  const x = scaleLinear({ domain: [t0, t1], range: [LEFT, right] })
  const y = scaleLinear({ domain: [lo, hi], range: [H - BOTTOM, TOP], nice: 4 })
  const sold = data.flows.reduce((n, f) => n + f.sold, 0)
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
          {hours.length > 1 && <LinePath data={hours} x={(p) => x(p.t)} y={(p) => y(p.price)} className={charts.hourLine} />}
          {days.length > 1 && <LinePath data={days} x={(p) => x(p.t)} y={(p) => y(p.price)} className={charts.dayLine} />}
          <AxisBottom
            scale={x}
            top={H - BOTTOM}
            numTicks={width < NARROW ? 3 : 6}
            tickFormat={(t) => shortDay(Number(t))}
            hideAxisLine
            tickLength={5}
            tickLineProps={{ className: charts.tickMark }}
            tickLabelProps={tickLabels('middle')}
          />
        </svg>
      </div>
      <Text size="xs" c="dimmed">
        Thin: the market price each hour (two weeks). Bold: each day&apos;s median (a month). {sold} bought over the
        month as far as scans saw.
      </Text>
    </Stack>
  )
}
