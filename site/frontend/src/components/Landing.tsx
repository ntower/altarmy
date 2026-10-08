import { useState } from 'react'
import { Stack, Text, Title } from '@mantine/core'
import { motion } from 'motion/react'
import { EASE } from '../lib/motion'
import { linkProps, previousRoute, type Route } from '../lib/router'
import { Carousel, type Slide } from './Carousel'
import classes from './Landing.module.css'


type Showcase = {
  key: string
  to: Route
  eyebrow: string
  title: string
  copy: string
  /** A short line under the copy. */
  note?: string
  cue: string
  slides: readonly Slide[]
  /** The screenshots' shape, as a CSS aspect ratio (the carousel's default is 3:2). */
  aspect?: string
  /** Pictures on the left, copy on the right (on wide screens; phones always read the copy first). */
  reverse?: boolean
}

const ADDON_SHOWCASE: Showcase = {
  key: 'addon',
  to: '/addon',
  eyebrow: 'The addon',
  title: 'Alt Army',
  copy:
    'Alt Army remembers every one of your characters: their items, professions, levels, etc. You can then ' +
    "quickly view a summary of their current state, or search for that item or recipe you're interested in.",
  note: 'Versions supported: Forever, and Burning Crusade',
  cue: 'Get the Addon',
  slides: [
    { src: '/landing/addon-summary.png', alt: 'Alt Army: a summary of every character' },
    { src: '/landing/addon-search.png', alt: 'Alt Army: searching every character for an item' },
    { src: '/landing/addon-economy.png', alt: 'Alt Army: Waylaid Crates priced from the auction house' },
    { src: '/landing/addon-gear.png', alt: "Alt Army: a character's gear" },
    { src: '/landing/addon-inventory.png', alt: "Alt Army: a character's bags" },
    { src: '/landing/addon-reputation.png', alt: 'Alt Army: reputations' },
    { src: '/landing/addon-graphs.png', alt: 'Alt Army: graphs of time played per level, character by character' },
  ],
}

const PROFIT_SHOWCASE: Showcase = {
  key: 'profit',
  to: '/profit',
  eyebrow: 'Crafting profits for WoW: Forever',
  title: 'Put your army to work',
  copy:
    'Combine your character details with the latest auction house prices and find the best recipes for you to ' +
    "make a profit. We'll show you where to source your materials, what to craft, and how best to sell the " +
    'results.',
  cue: 'Find profitable crafts',
  slides: [
    { src: '/landing/profit-search.png', alt: 'Profit: recipes ranked by profit and return' },
    { src: '/landing/profit-flow.png', alt: 'Profit: the flow chart of what to buy and craft for Hard Gold Bracers' },
    { src: '/landing/profit-steps.png', alt: 'Profit: the step-by-step plan, with the run to each spot on the city map' },
  ],
  aspect: '16 / 9',
  reverse: true,
}

const SHOWCASES: readonly Showcase[] = [ADDON_SHOWCASE, PROFIT_SHOWCASE]

/**
 * One full-width card on the main page: copy on one side, screenshots on the other. Its title is the link,
 * stretched over the whole card (so clicking anywhere goes to the page), with the carousel's buttons above it. It
 * has the layout id `showcase-<key>` (the Profit page's banner uses `showcase-profit`), so moving between the pages
 * shrinks or grows the card in place instead of fading it out and in. The copy keeps its size while the card
 * does (its own `layout`, which Motion corrects for the card's scale).
 */
export function ShowcaseCard({ spec, index = 0 }: { spec: Showcase; index?: number }) {
  const titleId = `showcase-${spec.key}-title`
  // Coming from the other page, the card is already on screen: no entrance.
  const [carried] = useState(() => previousRoute() === spec.to)
  return (
    <motion.article
      className={classes.card}
      data-reverse={spec.reverse || undefined}
      aria-labelledby={titleId}
      layoutId={`showcase-${spec.key}`}
      // Inline, so Motion keeps the corners round while the card changes size.
      style={{ borderRadius: 12 }}
      initial={carried ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, delay: carried ? 0 : 0.08 * index, ease: EASE }}
    >
      <motion.div layout="position" className={classes.copy}>
        <Text className={classes.eyebrow}>{spec.eyebrow}</Text>
        <Title order={2} id={titleId} className={classes.title}>
          <a className={classes.link} {...linkProps(spec.to)}>
            {spec.title}
          </a>
        </Title>
        <Text className={classes.lead}>{spec.copy}</Text>
        {spec.note && <Text className={classes.note}>{spec.note}</Text>}
        <span className={classes.cue}>
          {spec.cue}
          <span className={classes.arrow} aria-hidden="true">
            →
          </span>
        </span>
      </motion.div>
      <div className={classes.shots}>
        {/* The cards take turns: the second one's first step comes half an interval after the first one's. */}
        <Carousel slides={spec.slides} label={`${spec.title} screenshots`} offset={index * 3000} aspect={spec.aspect} />
      </div>
    </motion.article>
  )
}

/** The main page: what the addon and the Profit page are, each a card leading to its page. */
export function Landing() {
  return (
    <Stack gap="lg">
      {SHOWCASES.map((spec, i) => (
        <ShowcaseCard key={spec.key} spec={spec} index={i} />
      ))}
    </Stack>
  )
}
