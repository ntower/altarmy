import type { ReactNode } from 'react'
import { TooltipWithBounds } from '@visx/tooltip'
import { spread } from '../lib/depth'
import { TONE, type Note } from './chartKit'
import classes from './Charts.module.css'

/* The charts' shared components: labels at the right edge (or a legend under a narrow chart) and the hover's
 * tooltip. Their measured width, tick labels and tones are in chartKit.ts. */

/** The notes at a chart's right edge from `x`, spread apart so none overlaps another. */
export function RightNotes({ notes, x }: { notes: readonly Note[]; x: number }) {
  const placed = spread(notes.map((n) => n.y + 4))
  return notes.map((n, i) => (
    <text key={i} x={x} y={placed[i]} className={`${classes.note} ${TONE[n.tone]}`}>
      {n.text}
    </text>
  ))
}

/** The notes as a legend under a narrow chart, top to bottom as they would stand at its edge. */
export function NotesLegend({ notes }: { notes: readonly Note[] }) {
  if (!notes.length) return null
  return (
    <ul className={classes.legend}>
      {[...notes]
        .sort((a, b) => a.y - b.y)
        .map((n, i) => (
          <li key={i} className={TONE[n.tone]}>
            {n.text}
          </li>
        ))}
    </ul>
  )
}

/** A hover's tooltip, kept inside the chart's frame. */
export function ChartTooltip({ left, top, children }: { left: number; top: number; children: ReactNode }) {
  return (
    <TooltipWithBounds
      left={left}
      top={top}
      offsetLeft={14}
      offsetTop={14}
      unstyled
      applyPositionStyle
      className={classes.tooltip}
    >
      {children}
    </TooltipWithBounds>
  )
}
