import { Fragment, type ReactNode } from 'react'
import { List, Text } from '@mantine/core'
import type { ItemMap, RankResult, Step } from '../api/client'
import { useAhCut } from '../api/queries'
import { ChooseContext, SELL_PATH, type PlanEditing } from '../lib/choices'
import { breakEven, countedOn, expectedUnits, floor, materialSales } from '../lib/selling'
import { stepSource } from '../lib/steps'
import { bonusNote, discountLabel } from '../lib/talents'
import { formatCoords } from '../lib/time'
import { CharacterName } from './CharacterName'
import { DiscountTooltip } from './DiscountTooltip'
import { ChoiceMenu } from './ChoiceMenu'
import { DisenchantHover, Hover, ItemLink } from './ItemTooltip'
import { Earned, Money } from './Money'
import { sellChoices, sourceChoices } from './planChoices'
import classes from './ResultsTable.module.css'
import { ZoneMap } from './ZoneMap'

/** A step's amount: spending is a cost (red, unsigned), income is a signed gain. */
const StepMoney = ({ value }: { value: number }) =>
  value < 0 ? <Money copper={-value} cost /> : <Money copper={value} signed />

/** A sale's gross and the recipe's net profit. */
const Sale = ({ gross, net }: { gross: number; net: number }) => (
  <>
    (Gross <Earned copper={gross} /> · Net <Earned copper={net} />)
  </>
)

/** What to watch for when posting the craft: the price under which another exit pays more, the price under which
 * the session loses gold, and what the plan counted on. */
function SaleNotes({ result, items }: { result: RankResult; items: ItemMap }) {
  const cut = useAhCut()
  const lowest = floor(result, cut)
  const even = breakEven(result, cut)
  const counted = countedOn(result, items)
  return (
    <Text component="span" size="xs" c="dimmed" display="block">
      {lowest !== null && (
        <>
          Don&apos;t go under <Money copper={lowest} /> each: below that the {result.exits.find((e) => e.kind !== 'ah')?.kind === 'vendor' ? 'vendor' : 'other way to sell'} pays more.{' '}
        </>
      )}
      Under <Money copper={even} /> each this run loses gold (deposit not included).
      {counted.price !== null && (
        <>
          {' '}
          We counted on <Money copper={counted.price} /> for {counted.units} of your {counted.of}.
        </>
      )}
    </Text>
  )
}

/**
 * A step as one or more instruction lines (whose they are is the group they are listed under); disenchanting splits
 * into disenchant, then sell the mats (`detailed`: each material on its own line). `vendor` names the vendor bought
 * from or sold to (the detailed view knows it).
 */
function describe(
  { action, item_id, name, quantity, value, via, who, discount, rep_discount, rep_faction, convert, enchant }: Step,
  result: RankResult,
  items: ItemMap,
  vendor?: string,
  skill = false,
  detailed = false,
): ReactNode[] {
  const item = <ItemLink item={items[item_id]} name={name} />
  const discounted = discountLabel(discount, rep_discount)
  // Master Chef's extra results come from the crafts: said where they are made (the sale's `bonus` counts them)
  const made =
    action === 'craft' && !convert && !enchant
      ? (result.steps.find((s) => s.action === 'sell' && s.item_id === item_id && s.bonus > 0)?.bonus ?? 0)
      : 0
  const extra = made > 0 ? ` (${bonusNote(made)})` : ''
  switch (action) {
    case 'buy':
      return [
        <>
          Purchase {quantity}x {item} {via === 'vendor' ? `from ${vendor ?? 'a vendor'}` : 'on the AH'} (
          <StepMoney value={value} />
          {discounted && (
            <>
              ,{' '}
              <Hover
                tooltip={
                  <DiscountTooltip who={who} discount={discount} repDiscount={rep_discount} repFaction={rep_faction} />
                }
              >
                <span className={classes.hint}>{discounted}</span>
              </Hover>
            </>
          )}
          )
        </>,
      ]
    case 'gather':
      // the user's own: what it costs is what selling it would have made
      return [
        <>
          Gather {quantity}x {item} (worth <Money copper={-value} /> to sell)
        </>,
      ]
    case 'craft':
      // an enchant makes no item: the step is the spell, cast on anything it can go on
      if (enchant) return [<>Cast {name} {quantity === 1 ? 'once' : `${quantity} times`}</>]
      return [
        <>
          {convert ? 'Convert into' : 'Craft'} {quantity}x {item}
          {extra}
        </>,
      ]
    case 'mail':
      return [
        <>
          Mail {quantity}x {item} to <CharacterName name={via} /> (<StepMoney value={value} />)
        </>,
      ]
    case 'sell': {
      const materials = via === 'disenchant' && detailed ? materialSales(result, quantity, value, result.profit) : []
      if (materials.length > 0)
        return [
          <>
            Disenchant {quantity > 1 ? `${quantity}x ` : ''}
            {item}
          </>,
          ...materials.map((m) => (
            <>
              Auction ~{expectedUnits(m.units)}x <ItemLink item={items[m.item_id]} name={m.name} />{' '}
              {m.gross === null || m.net === null ? (
                <Text span inherit c="dimmed">
                  (no price)
                </Text>
              ) : (
                <Sale gross={m.gross} net={m.net} />
              )}
            </>
          )),
        ]
      if (via === 'disenchant')
        return [
          <>
            Disenchant {quantity > 1 ? `${quantity}x ` : ''}
            {item} (
            <DisenchantHover result={result} items={items}>
              <span className={classes.hint}>view expected materials</span>
            </DisenchantHover>
            )
          </>,
          <>
            <DisenchantHover result={result} items={items}>
              Auction materials
            </DisenchantHover>{' '}
            <Sale gross={value} net={result.profit} />
          </>,
        ]
      if (via === 'keep')
        return [
          <>
            Keep the {quantity > 1 ? `${quantity}x ` : ''}
            {item} (no vendor buys it)
          </>,
        ]
      // skilling up sells what was made only to win some of the cost back: no notes on how to post it
      return [
        <>
          Sell {quantity}x {item} {via === 'ah' ? 'on the AH' : `to ${vendor ?? 'a vendor'}`} <Sale gross={value} net={result.profit} />
          {via === 'ah' && !skill && <SaleNotes result={result} items={items} />}
        </>,
      ]
    }
  }
}

/** The menu changing how a step is done, if it has alternatives: a reagent's source, or the way to sell. */
function StepChoice({ step, result }: { step: Step; result: RankResult }) {
  if (step.action === 'sell')
    return (
      <ChoiceMenu
        label="Change how it is sold"
        paths={[SELL_PATH]}
        choices={sellChoices(result.sell_options, result.best_exit)}
      />
    )
  const source = stepSource(step, result.tree)
  if (!source) return null
  return (
    <ChoiceMenu
      label={`Change source of ${step.name}`}
      paths={source.paths}
      choices={sourceChoices(source.options, source.option, source.holder)}
    />
  )
}

/** A step's lines (a disenchant sale's split: disenchanting, then selling the materials), the last ending in a
 * menu of its alternatives, if it has any; in the detailed view every material's line does. */
function stepLines(
  step: Step,
  result: RankResult,
  items: ItemMap,
  vendor?: string,
  skill = false,
  detailed = false,
): ReactNode[] {
  const perMaterial = detailed && step.action === 'sell' && step.via === 'disenchant'
  return describe(step, result, items, vendor, skill, detailed).map((line, i, all) =>
    i < all.length - 1 && !(perMaterial && i > 0) ? (
      line
    ) : (
      <>
        {line}
        <span className={classes.stepChoice}>
          <StepChoice step={step} result={result} />
        </span>
      </>
    ),
  )
}

type Detail = RankResult['details'][number]

/** "`verb` <place> at x, y", showing the zone map with the spot marked on hover when it is known. */
function Place({ verb, location }: { verb: string; location: NonNullable<Detail['location']> }) {
  const { name, map_x: x, map_y: y, map_area: area } = location
  const text = (
    <>
      {verb} {name}
      {x != null && y != null && ` at ${formatCoords(x, y)}`}
    </>
  )
  return area != null && x != null && y != null ? (
    <Hover tooltip={<ZoneMap area={area} x={x} y={y} name={name} />}>
      <span className={classes.mapLink}>{text}</span>
    </Hover>
  ) : (
    text
  )
}

/** A run to somewhere, with what to take from the mailbox there. */
function goLine({ location, retrieve }: Detail, items: ItemMap): ReactNode {
  if (!location) return null
  return (
    <>
      <Place verb="Run to" location={location} />
      .
      {retrieve.length > 0 && (
        <>
          {' '}
          Retrieve{' '}
          {retrieve.map(({ item_id, count }, i) => (
            <Fragment key={item_id}>
              {i > 0 && ', '}
              {count}x <ItemLink item={items[item_id]} name={items[item_id]?.name ?? `item ${item_id}`} />
            </Fragment>
          ))}
          .
        </>
      )}
    </>
  )
}

/** A character's stretch of the plan: the lines they do, in order. */
type Stretch = { who: string; lines: ReactNode[] }

/** The plan's lines per character in the order they do them: its steps, or with `detailed` its steps with where to
 * go in between (a switch of character starts the next one's stretch). */
function stretches(result: RankResult, items: ItemMap, detailed: boolean, skill: boolean): Stretch[] {
  const all: Stretch[] = []
  const add = (who: string, ...lines: ReactNode[]) => {
    const last = all.at(-1)
    if (last && last.who === who) last.lines.push(...lines)
    else all.push({ who, lines })
  }
  if (!detailed || result.details.length === 0) {
    for (const step of result.steps) add(step.who, ...stepLines(step, result, items, undefined, skill, detailed))
    return all
  }
  let vendor: string | undefined // the vendor the character stands at, to name in buy and sell lines
  for (const d of result.details) {
    if (d.kind === 'switch') {
      vendor = undefined
      add(d.who)
    } else if (d.kind === 'start' || d.kind === 'go') {
      vendor = d.location?.kind === 'vendor' ? d.location.name : undefined
      const line =
        d.kind === 'go' ? goLine(d, items) : d.location && <Place verb="Start at" location={d.location} />
      if (line) add(d.who, line)
    } else {
      const step = d.step == null ? undefined : result.steps[d.step]
      if (step) add(step.who, ...stepLines(step, result, items, vendor, skill, true))
    }
  }
  return all.filter((s) => s.lines.length > 0)
}

/**
 * The plan as numbered instructions grouped under each character in the order they do them; with `detailed`, with
 * where to go in between; with `editing`, a step with alternatives ends in a menu of them. In `skill` mode (skilling
 * up) an AH sale has no posting notes. `learn`, a step learning the recipe, comes first among the final crafter's.
 */
export function StepList({
  result,
  items,
  editing,
  detailed = false,
  mode = 'default',
  learn,
}: {
  result: RankResult
  items: ItemMap
  editing?: PlanEditing
  detailed?: boolean
  mode?: 'default' | 'skill'
  learn?: ReactNode
}) {
  const groups = stretches(result, items, detailed, mode === 'skill')
  if (learn) {
    const crafter = groups.find((g) => g.who === result.crafter)
    if (crafter) crafter.lines.unshift(learn)
    else groups.unshift({ who: result.crafter, lines: [learn] })
  }
  return (
    <ChooseContext.Provider value={editing?.onChoose}>
      {groups.map((g, n) => (
        <div key={n} role="group" aria-label={g.who ? `${g.who}'s steps` : 'Steps'}>
          {g.who && (
            <Text size="sm" fw={600} mt={n ? 'xs' : 0}>
              <CharacterName name={g.who} />
            </Text>
          )}
          <List type="ordered" size="sm">
            {g.lines.map((line, i) => (
              <List.Item key={i}>{line}</List.Item>
            ))}
          </List>
        </div>
      ))}
    </ChooseContext.Provider>
  )
}
