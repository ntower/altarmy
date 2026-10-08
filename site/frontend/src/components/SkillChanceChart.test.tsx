import { fireEvent, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { robeResult } from '../test/results'
import { renderWithProviders } from '../test/utils'
import { SkillChanceChart } from './SkillChanceChart'

// the Green Robe: learned at 50, yellow from 30, grey at 60 (green from 45); the run crafts it from 50 to 58
const run = { ...robeResult, learn_skill: 1, stop_skill: 58 }

describe('SkillChanceChart', () => {
  it('draws the chance in the difficulty colours, with the run shaded', () => {
    const { container } = renderWithProviders(<SkillChanceChart result={run} from={50} />)
    const chart = screen.getByRole('img', { name: /Skill-up chance for Green Robe by skill/ })
    expect(chart).toHaveAccessibleName(
      'Skill-up chance for Green Robe by skill: a sure point until 30, falling to none at 60; this run crafts it from 50 to 58',
    )
    // orange to yellow, yellow to green, green to grey, each marked where it starts
    expect(container.querySelectorAll('polyline')).toHaveLength(3)
    expect(Array.from(chart.querySelectorAll('text[class*="tick"]'), (t) => t.textContent)).toEqual(['1', '30', '45', '60'])
    expect(screen.getByTestId('run-range')).toHaveTextContent('50–58')
    // shaded under the line, not a box: from the axis at 50, along the line, back down at 58
    const shaded = container.querySelector('polygon')!.getAttribute('points')!.split(' ')
    expect(shaded).toHaveLength(4)
    expect(shaded[0]!.split(',')[1]).toBe(shaded[3]!.split(',')[1]) // both ends on the axis
    expect(Number(shaded[2]!.split(',')[1])).toBeGreaterThan(Number(shaded[1]!.split(',')[1])) // lower at 58
    expect(screen.queryByText(/Working Overtime/)).not.toBeInTheDocument()
  })

  it("counts the crafter's Working Overtime", () => {
    const { container } = renderWithProviders(<SkillChanceChart result={{ ...run, skill_bonus: 0.2 }} from={50} />)
    expect(screen.getByRole('img')).toHaveAccessibleName(/with Working Overtime's \+20%/)
    expect(screen.getByText('Includes Working Overtime: +20% on every chance until grey')).toBeInTheDocument()
    // a grey step drops the chance to nothing at grey
    expect(container.querySelectorAll('polyline')).toHaveLength(4)
    const plot = container.querySelector('rect[class*="hit"]')!
    plot.getBoundingClientRect = () => ({ left: 0, width: 590, top: 0, height: 100, right: 590, bottom: 100, x: 0, y: 0, toJSON: () => ({}) })
    fireEvent.pointerMove(plot, { clientX: 500 }) // skill 51: 30% + 20%
    expect(screen.getByText(/51 skill: 50%/)).toHaveTextContent('51 skill: 50% (~2.0 crafts a point)')
  })

  it('reads out the chance at the skill under the pointer', () => {
    const { container } = renderWithProviders(<SkillChanceChart result={run} from={50} />)
    const plot = container.querySelector('rect[class*="hit"]')!
    plot.getBoundingClientRect = () => ({ left: 0, width: 590, top: 0, height: 100, right: 590, bottom: 100, x: 0, y: 0, toJSON: () => ({}) })
    fireEvent.pointerMove(plot, { clientX: 500 }) // 1 + 500/590 x 59 = skill 51
    expect(screen.getByText(/51 skill: 30%/)).toHaveTextContent('51 skill: 30% (~3.3 crafts a point)')
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
