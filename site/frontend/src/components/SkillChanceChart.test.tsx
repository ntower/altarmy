import { fireEvent, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { renderWithProviders } from '../test/utils'
import { SkillChanceChart } from './SkillChanceChart'

// the Green Robe: learned at 50, yellow from 30, grey at 60 (green from 45); the run crafts it from 50 to 58
const run = { ...robeResult, learn_skill: 1, stop_skill: 58 }

/** The chart's hover target, covering it from its top-left corner (jsdom measures nothing: the chart is 360 px wide). */
function hoverTarget(): Element {
  const target = screen.getByTestId('chart-hover')
  target.getBoundingClientRect = () => ({ left: 0, width: 360, top: 0, height: 170, right: 360, bottom: 170, x: 0, y: 0, toJSON: () => ({}) })
  return target
}

describe('SkillChanceChart', () => {
  it('draws the chance in the difficulty colours, with the run shaded', () => {
    const { container } = renderWithProviders(<SkillChanceChart result={run} from={50} />)
    const chart = screen.getByRole('img', { name: /Skill-up chance for Green Robe by skill/ })
    expect(chart).toHaveAccessibleName(
      'Skill-up chance for Green Robe by skill: a sure point until 30, falling to none at 60; this run crafts it from 50 to 58',
    )
    // orange to yellow, yellow to green, green to grey, each marked where it starts
    expect(Array.from(container.querySelectorAll('path[data-band]'), (p) => p.getAttribute('data-band'))).toEqual([
      'orange',
      'yellow',
      'green',
    ])
    expect(Array.from(chart.querySelectorAll('text[class*="tick"]'), (t) => t.textContent)).toEqual(['1', '30', '45', '60'])
    // the run's stretch shaded under the line
    expect(screen.getByTestId('run-range')).toHaveTextContent('50–58')
    expect(screen.getByTestId('run-range').querySelector('path')).toHaveAttribute('d')
    expect(screen.queryByText(/Working Overtime/)).not.toBeInTheDocument()
  })

  it("counts the crafter's Working Overtime", () => {
    const { container } = renderWithProviders(<SkillChanceChart result={{ ...run, skill_bonus: 0.2 }} from={50} />)
    expect(screen.getByRole('img')).toHaveAccessibleName(/with Working Overtime's \+20%/)
    expect(screen.getByText('Includes Working Overtime: +20% on every chance until grey')).toBeInTheDocument()
    // a grey step drops the chance to nothing at grey
    expect(container.querySelectorAll('path[data-band]')).toHaveLength(4)
    fireEvent.pointerMove(hoverTarget(), { clientX: 301 }) // skill 51: 30% + 20%
    expect(screen.getByText(/51 skill: 50%/)).toHaveTextContent('51 skill: 50% (~2.0 crafts a point)')
  })

  it('reads out the chance at the skill under the pointer', () => {
    renderWithProviders(<SkillChanceChart result={run} from={50} />)
    const plot = hoverTarget()
    fireEvent.pointerMove(plot, { clientX: 301 }) // the plot spans 38 to 348 px of 360: 1 + 263/310 x 59 = skill 51
    expect(screen.getByText(/51 skill: 30%/)).toHaveTextContent('51 skill: 30% (~3.3 crafts a point)')
    fireEvent.pointerMove(plot, { clientX: 5 }) // left of the plot: its first skill
    expect(screen.getByText(/^1 skill: 100%$/)).toBeInTheDocument()
    fireEvent.pointerLeave(plot)
    expect(screen.queryByText(/51 skill/)).not.toBeInTheDocument()
  })

  it('draws nothing for a recipe without thresholds', () => {
    const { container } = renderWithProviders(
      <SkillChanceChart result={{ ...run, trivial_low: 0, trivial_high: 0 }} from={50} />,
    )
    expect(container.querySelector('svg')).toBeNull()
  })
})
