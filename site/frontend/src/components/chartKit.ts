import type { PointerEvent } from 'react'
import type { TickLabelProps } from '@visx/axis'
import { localPoint } from '@visx/event'
import { useParentSize } from '@visx/responsive'
import classes from './Charts.module.css'

/* What the charts share besides components (ChartParts.tsx): their measured width, tick labels on the theme's
 * classes, the tones of their labels and the pointer's position. */

/** Under this width (px) a chart has no room for labels at its right edge: they go in a legend under it. */
export const NARROW = 480

/** The width of the chart's container, followed as it resizes; `fallback` until it is measured (and in tests, where
 * nothing is). Put `ref` on the chart's frame. */
export function useChartWidth(fallback: number): { ref: (node: HTMLDivElement | null) => void; width: number } {
  const { parentRef, width } = useParentSize({
    initialSize: { width: fallback },
    ignoreDimensions: ['height', 'top', 'left'],
    debounceTime: 100,
  })
  return { ref: parentRef, width: width || fallback }
}

type LabelProps = Exclude<TickLabelProps<number>, (...args: never[]) => unknown>

/** Tick labels in our classes (visx's defaults would set their own font and fill). Left axes centre on the tick. */
export function tickLabels(
  textAnchor: 'start' | 'middle' | 'end',
  className: (value: number) => string = () => classes.axis,
): (value: { valueOf(): number }) => LabelProps {
  return (value) => ({ className: className(Number(value)), textAnchor, dy: textAnchor === 'end' ? '0.32em' : 0 })
}

export type Tone = 'cost' | 'profit' | 'plain' | 'you'

export const TONE: Record<Tone, string> = {
  cost: classes.toneCost,
  profit: classes.toneProfit,
  plain: classes.tonePlain,
  you: classes.toneYou,
}

/** A label for something drawn across a chart at height `y`. */
export interface Note {
  y: number
  text: string
  tone: Tone
}

/** Where the pointer is over a chart, in its own pixels. Give the chart a hover target covering it from its top-left
 * corner, so the browser's answer (from the SVG's transform) and a test's (from the target's box) agree. */
export function pointerAt(event: PointerEvent<SVGElement>): { x: number; y: number } | null {
  const point = localPoint(event)
  return point ? { x: point.x, y: point.y } : null
}
