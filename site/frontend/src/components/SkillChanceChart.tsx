import { useState, type PointerEvent } from 'react'
import { Text } from '@mantine/core'
import type { RankResult } from '../api/client'
import { chanceAt, chanceBands } from '../lib/skill'
import classes from './SkillChanceChart.module.css'

/* A recipe's skill-up chance by skill, in the game's difficulty colours (as wowcraft.io draws it), with the crafter's
 * Working Overtime counted and the area under the line shaded over the stretch the run crafts it. Plain SVG on the
 * theme's colours, like the Market section's charts. */

const W = 360
const H = 170
const LEFT = 38
const RIGHT = 12
const TOP = 18
const BOTTOM = 24
const GRID = [0, 0.25, 0.5, 0.75, 1]

const points = (xy: [number, number][], x: (s: number) => number, y: (c: number) => number) =>
  xy.map(([s, c]) => `${x(s)},${y(c)}`).join(' ')

/** The chart of `result`'s chance of a point from `from` (where the run starts) to grey; nothing for a recipe
 * without thresholds. */
export function SkillChanceChart({ result: r, from }: { result: RankResult; from: number }) {
  const [hover, setHover] = useState<number | null>(null)
  const bonus = r.skill_bonus
  const chart = chanceBands(r, from, bonus)
  if (!chart) return null
  const { bands, ticks, start, end, under } = chart
  const x = (skill: number) => LEFT + ((skill - start) / Math.max(1, end - start)) * (W - LEFT - RIGHT)
  const y = (chance: number) => TOP + (1 - chance) * (H - TOP - BOTTOM)
  const shaded = under(from, r.stop_skill || end)
  const runFrom = shaded[0]?.[0]
  const runTo = shaded.at(-1)?.[0]
  const greenFrom = bands.find((b) => b.difficulty === 'green')?.points[0]?.[0] ?? end
  const tickClass = (skill: number) =>
    skill >= end
      ? classes.grey
      : skill >= greenFrom
        ? classes.green
        : skill >= r.trivial_low
          ? classes.yellow
          : classes.orange
  // the skill under the pointer, on the plot
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const box = e.currentTarget.getBoundingClientRect()
    const along = (e.clientX - box.left) / Math.max(1, box.width)
    setHover(Math.round(start + along * (end - start)))
  }
  const chance = hover === null ? null : chanceAt(r, hover, bonus)
  const overtime = Math.round(bonus * 100)
  const label =
    `Skill-up chance for ${r.output_name} by skill: a sure point until ${r.trivial_low}, falling to none at ${end}` +
    (overtime ? `, with Working Overtime's +${overtime}%` : '') +
    (runFrom !== undefined && runTo !== undefined ? `; this run crafts it from ${runFrom} to ${runTo}` : '')
  return (
    <div>
      <svg className={classes.chart} viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label}>
        {GRID.map((g) => (
          <g key={g}>
            <line x1={LEFT} x2={W - RIGHT} y1={y(g)} y2={y(g)} className={g === 0 ? classes.base : classes.grid} />
            <text x={LEFT - 6} y={y(g) + 4} textAnchor="end" className={classes.axis}>
              {g * 100}%
            </text>
          </g>
        ))}
        {/* the area under the line over the stretch this run crafts it */}
        {runFrom !== undefined && runTo !== undefined && (
          <g data-testid="run-range">
            <polygon points={points(shaded, x, y)} className={classes.run} />
            <text x={(x(runFrom) + x(runTo)) / 2} y={TOP - 6} textAnchor="middle" className={classes.runLabel}>
              {runFrom}–{runTo}
            </text>
          </g>
        )}
        {bands.map((b) => (
          <polyline
            key={b.difficulty}
            points={points(b.points, x, y)}
            className={`${classes.line} ${classes[b.difficulty]}`}
          />
        ))}
        {ticks.map((t) => (
          <text key={t} x={x(t)} y={H - 6} textAnchor="middle" className={`${classes.tick} ${tickClass(t)}`}>
            {t}
          </text>
        ))}
        {hover !== null && chance !== null && (
          <g pointerEvents="none">
            <line x1={x(hover)} x2={x(hover)} y1={TOP} y2={H - BOTTOM} className={classes.cross} />
            <circle cx={x(hover)} cy={y(chance)} r={4} className={classes.dot} />
            <text
              x={Math.min(Math.max(x(hover), LEFT + 60), W - RIGHT - 60)}
              y={TOP + 12}
              textAnchor="middle"
              className={classes.readout}
            >
              {hover} skill: {Math.round(chance * 100)}%
              {chance > 0 && chance < 1 && ` (~${(1 / chance).toFixed(1)} crafts a point)`}
            </text>
          </g>
        )}
        <rect
          x={LEFT}
          y={TOP}
          width={W - LEFT - RIGHT}
          height={H - TOP - BOTTOM}
          className={classes.hit}
          onPointerMove={onMove}
          onPointerLeave={() => setHover(null)}
        />
      </svg>
      {overtime > 0 && (
        <Text size="xs" c="dimmed" ta="center">
          Includes Working Overtime: +{overtime}% on every chance until grey
        </Text>
      )}
    </div>
  )
}
