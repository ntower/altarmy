import { useState, type PointerEvent } from 'react'
import { Text } from '@mantine/core'
import { AxisBottom, AxisLeft } from '@visx/axis'
import { GridRows } from '@visx/grid'
import { scaleLinear } from '@visx/scale'
import { AreaClosed, Line, LinePath } from '@visx/shape'
import type { RankResult } from '../api/client'
import { chanceAt, chanceBands } from '../lib/skill'
import { ChartTooltip } from './ChartParts'
import { pointerAt, tickLabels, useChartWidth } from './chartKit'
import charts from './Charts.module.css'
import classes from './SkillChanceChart.module.css'

/* A recipe's skill-up chance by skill, in the game's difficulty colours (as wowcraft.io draws it), with the crafter's
 * Working Overtime counted and the area under the line shaded over the stretch the run crafts it. */

const H = 170
const LEFT = 38
const RIGHT = 12
const TOP = 18
const BOTTOM = 24
const WIDTH = 360

const skillOf = ([s]: [number, number]) => s
const chanceOf = ([, c]: [number, number]) => c

/** The chart of `result`'s chance of a point from `from` (where the run starts) to grey; nothing for a recipe
 * without thresholds. */
export function SkillChanceChart({ result: r, from }: { result: RankResult; from: number }) {
  const { ref, width } = useChartWidth(WIDTH)
  const [hover, setHover] = useState<number | null>(null)
  const bonus = r.skill_bonus
  const chart = chanceBands(r, from, bonus)
  if (!chart) return null
  const { bands, ticks, start, end, under } = chart
  const x = scaleLinear({ domain: [start, Math.max(start + 1, end)], range: [LEFT, width - RIGHT] })
  const y = scaleLinear({ domain: [0, 1], range: [H - BOTTOM, TOP] })
  const sx = (p: [number, number]) => x(skillOf(p))
  const sy = (p: [number, number]) => y(chanceOf(p))
  const shaded = under(from, r.stop_skill || end)
  const runFrom = shaded[0]?.[0]
  const runTo = shaded.at(-1)?.[0]
  const greenFrom = bands.find((b) => b.difficulty === 'green')?.points[0]?.[0] ?? end
  const tickClass = (skill: number) =>
    `${classes.tick} ${
      skill >= end
        ? classes.grey
        : skill >= greenFrom
          ? classes.green
          : skill >= r.trivial_low
            ? classes.yellow
            : classes.orange
    }`
  // the skill under the pointer, kept on the plot
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const at = pointerAt(e)
    if (at) setHover(Math.min(end, Math.max(start, Math.round(x.invert(at.x)))))
  }
  const chance = hover === null ? null : chanceAt(r, hover, bonus)
  const overtime = Math.round(bonus * 100)
  const label =
    `Skill-up chance for ${r.output_name} by skill: a sure point until ${r.trivial_low}, falling to none at ${end}` +
    (overtime ? `, with Working Overtime's +${overtime}%` : '') +
    (runFrom !== undefined && runTo !== undefined ? `; this run crafts it from ${runFrom} to ${runTo}` : '')
  return (
    <div ref={ref} className={`${charts.frame} ${classes.frame}`}>
      <svg className={charts.chart} width={width} height={H} role="img" aria-label={label}>
        <GridRows scale={y} width={width - LEFT - RIGHT} left={LEFT} tickValues={[0.25, 0.5, 0.75, 1]} className={charts.dashedGrid} />
        <Line from={{ x: LEFT, y: y(0) }} to={{ x: width - RIGHT, y: y(0) }} className={charts.base} />
        <AxisLeft
          scale={y}
          left={LEFT}
          tickValues={[0, 0.25, 0.5, 0.75, 1]}
          tickFormat={(c) => `${Number(c) * 100}%`}
          hideAxisLine
          hideTicks
          tickLength={6}
          tickLabelProps={tickLabels('end')}
        />
        {/* the area under the line over the stretch this run crafts it */}
        {runFrom !== undefined && runTo !== undefined && (
          <g data-testid="run-range">
            <AreaClosed data={shaded} x={sx} y={sy} yScale={y} className={classes.run} />
            <text x={(x(runFrom) + x(runTo)) / 2} y={TOP - 6} textAnchor="middle" className={classes.runLabel}>
              {runFrom}–{runTo}
            </text>
          </g>
        )}
        {bands.map((b) => (
          <LinePath
            key={b.difficulty}
            data={b.points}
            x={sx}
            y={sy}
            className={`${classes.line} ${classes[b.difficulty]}`}
            data-band={b.difficulty}
          />
        ))}
        <AxisBottom
          scale={x}
          top={H - BOTTOM}
          tickValues={ticks}
          hideAxisLine
          hideTicks
          tickLength={2}
          tickLabelProps={tickLabels('middle', tickClass)}
        />
        {hover !== null && chance !== null && (
          <>
            <Line from={{ x: x(hover), y: TOP }} to={{ x: x(hover), y: H - BOTTOM }} className={charts.cross} />
            <circle cx={x(hover)} cy={y(chance)} r={4} className={charts.dot} />
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
      {hover !== null && chance !== null && (
        <ChartTooltip left={x(hover)} top={y(chance)}>
          {hover} skill: {Math.round(chance * 100)}%
          {chance > 0 && chance < 1 && ` (~${(1 / chance).toFixed(1)} crafts a point)`}
        </ChartTooltip>
      )}
      {overtime > 0 && (
        <Text size="xs" c="dimmed" ta="center">
          Includes Working Overtime: +{overtime}% on every chance until grey
        </Text>
      )}
    </div>
  )
}
