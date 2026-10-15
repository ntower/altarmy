import { useEffect, useRef, useState } from 'react'
import { Anchor, Button, Code, Group, Loader, Stack, Text, UnstyledButton } from '@mantine/core'
import { useDisclosure } from '@mantine/hooks'
import { notifications } from '@mantine/notifications'
import { AnimatePresence, LayoutGroup, motion, useReducedMotion } from 'motion/react'
import { z } from 'zod'
import type { CharacterGroup, Characters, UploadResult } from '../api/client'
import { useCharacters, useTrack } from '../api/queries'
import { CharacterList } from './CharacterList'
import { age, parseUtc } from '../lib/age'
import { MAKE_GOLD, STRATEGY_PICKER } from '../lib/features'
import { realmLabel } from '../lib/realms'
import { parseProfitPath, profitPath } from '../lib/profitRoute'
import { liveStrategies } from '../lib/strategies'
import { EASE, LAYOUT } from '../lib/motion'
import { linkProps, navigate, previousRoute, usePath } from '../lib/router'
import { useSession } from '../lib/session'
import { setupSchema, storePresets, type Aim, type Setup as SetupAnswers } from '../lib/setup'
import { useStoredState } from '../lib/storage'
import { Hero } from './Hero'
import { AutoImportBody } from './AutoImport'
import { AUTO_IMPORT_CARD } from './autoImportCard'
import cards from './Cards.module.css'
import { IconChevron, IconCompass, IconPaste } from './icons'
import classes from './Profit.module.css'
import { PasteForm } from './PasteForm'
import { SearchTab } from './SearchTab'
import { AimQuestion } from './Setup'
import { type CardSpec, type Phase, StartCard } from './StartCard'
import { VendorCheck } from './VendorCheck'

type CardKey = 'import' | 'auto' | 'browse'

const landingSchema = z.object({ browsed: z.boolean() })
const NOT_BROWSED = { browsed: false }
const NO_GROUPS: readonly CharacterGroup[] = []
const storedSetup = setupSchema.nullable()
/** The aims switched off by a feature flag, each with what its card says. */
const unavailableAims = (): Partial<Record<Aim, string>> => (MAKE_GOLD ? {} : { gold: 'Coming soon' })
/** Alt Army Sync counts as set up while it has uploaded anything within this many days. */
const AUTO_IMPORT_DAYS = 30

/** The layout id a start card shares with the characters strip while it is the card the strip grows into. */
const cardLayoutId = (key: CardKey) => `start-card-${key}`

/** Whether Alt Army Sync (or the CLI watcher) is uploading for the user: it sent something recently. */
function autoImportOn(lastAt: string | null | undefined, now: Date = new Date()): boolean {
  if (!lastAt) return false
  return now.getTime() - parseUtc(lastAt) < AUTO_IMPORT_DAYS * 86_400_000
}

const CARDS: readonly CardSpec<CardKey>[] = [
  {
    key: 'import',
    title: 'Upload your characters',
    blurb:
      "Paste one line from the Alt Army addon: every alt's professions and learned recipes, so results show who crafts what and what mailing reagents between them costs.",
    short: 'Paste the Alt Army export.',
    icon: <IconPaste />,
    recommended: true,
  },
  AUTO_IMPORT_CARD,
  {
    key: 'browse',
    title: 'Skip for now',
    blurb: 'The results shown will not be customized for you. You can add characters any time.',
    short: 'Every recipe, no character optimization.',
    icon: <IconCompass />,
  },
]

/** The third card once the user has characters: it no longer offers browsing without them, only moving on. */
const CONTINUE: CardSpec<CardKey> = {
  key: 'browse',
  title: 'Continue',
  blurb: 'Done adding characters.',
  short: 'Done adding characters.',
  icon: <IconCompass />,
}

/** The three start cards for a user with or without characters. */
function cardsFor(hasCharacters: boolean): readonly CardSpec<CardKey>[] {
  return hasCharacters ? CARDS.map((c) => (c.key === 'browse' ? CONTINUE : c)) : CARDS
}

function ImportBody({ onImported }: { onImported: (r: UploadResult) => void }) {
  return (
    <Stack gap="md">
      <ol className={classes.steps}>
        <li>
          Install the Alt Army addon (<Anchor {...linkProps('/addon')}>Get the Addon</Anchor>) and log in to each character
          once.
        </li>
        <li>
          In game, type <Code>/altarmy export</Code> and press Ctrl+C.
        </li>
        <li>Paste it here.</li>
      </ol>
      <PasteForm onImported={onImported} autoFocus />
    </Stack>
  )
}

/**
 * Once started: what the search works with (how many characters, when they were gathered, whether auto-upload is
 * on; it opens to show every character), and Upload again, which opens the start cards (Auto-upload among them).
 */
function Strip({
  data,
  onOpen,
  layoutId,
}: {
  data: Characters | undefined
  onOpen: (k: CardKey) => void
  /** the card it turns into, and back from: the one opened last */
  layoutId: string
}) {
  const [details, { toggle }] = useDisclosure(false)
  const groups = data?.groups ?? NO_GROUPS
  const count = groups.reduce((n, g) => n + g.characters.length, 0)
  const auto = autoImportOn(data?.auto_import_at)
  const counted = `${count} ${count === 1 ? 'character' : 'characters'}`
  const updated = data?.imported_at ? `updated ${age(data.imported_at)}` : null
  const autoText = `Auto-upload ${auto ? 'on' : 'off'}`
  const dot = (
    <Text span c="dimmed" size="sm" aria-hidden>
      {' · '}
    </Text>
  )
  return (
    <motion.div layoutId={layoutId} transition={LAYOUT} className={cards.strip} style={{ borderRadius: 12 }}>
      <motion.div layout="position">
        <Group justify="space-between" gap="sm">
          {count > 0 ? (
            <UnstyledButton
              className={classes.summary}
              onClick={toggle}
              aria-expanded={details}
              aria-controls="your-characters"
              aria-label={[counted, updated, autoText].filter(Boolean).join(', ')}
            >
              <Text size="sm" span>
                <b>{counted}</b>
                {updated && (
                  <>
                    {dot}
                    <Text span c="dimmed" size="sm">
                      {updated}
                    </Text>
                  </>
                )}
                {dot}
                <Text span size="sm" c={auto ? 'green' : 'dimmed'}>
                  {autoText}
                </Text>
              </Text>
              <span className={classes.chevron} data-open={details || undefined}>
                <IconChevron size={16} />
              </span>
            </UnstyledButton>
          ) : (
            <Text size="sm">
              <b>No characters uploaded.</b>{' '}
              <Text span c="dimmed" size="sm">
                We&apos;ll show you what we have, but it won&apos;t be customized for you.
              </Text>
            </Text>
          )}
          {/* Auto-upload is the card beside the paste once the start cards are open. */}
          <Button size="xs" variant="light" leftSection={<IconPaste size={16} />} onClick={() => onOpen('import')}>
            {count > 0 ? 'Upload again' : 'Upload your characters'}
          </Button>
        </Group>
      </motion.div>
      <AnimatePresence initial={false}>
        {details && count > 0 && (
          <motion.div
            key="details"
            id="your-characters"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.25, ease: EASE }}
            style={{ overflow: 'hidden' }}
          >
            <div className={classes.details}>
              <CharacterList groups={groups} />
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  )
}

/**
 * The Profit page. At /profit: the welcome banner and three ways to start (paste an upload, set up the auto-upload,
 * skip) and, once the visitor has characters or skipped, what they are after, which leads to /profit/gold or
 * /profit/skill: the search (`SearchTab`), with the characters (the strip, or the start cards again) beside its realm
 * card. Whether they browsed is remembered per user; having characters comes from the server, so another browser's
 * upload counts too.
 */
export function ProfitPage() {
  const { uid } = useSession()
  const view = parseProfitPath(usePath())
  const characters = useCharacters()
  const track = useTrack()
  const [lastSetup, setLastSetup] = useStoredState<SetupAnswers | null>(`altarmy.setup.${uid}`, storedSetup, null)
  const [landing, setLanding] = useStoredState(`altarmy.landing.${uid}`, landingSchema, NOT_BROWSED)
  const [open, setOpenKey] = useState<CardKey | null>(null)
  // The card the strip grows into and shrinks back from: the one picked last.
  const [lastPicked, setLastPicked] = useState<CardKey>('import')
  // Whether the visitor has moved between the cards and the strip yet: until then nothing fades in.
  const [moved, setMoved] = useState(false)
  const setOpen = (key: CardKey | null) => {
    if (key) setLastPicked(key)
    setMoved(true)
    setOpenKey(key)
  }
  const reduced = useReducedMotion()
  const searchRef = useRef<HTMLElement>(null)
  const shownBefore = useRef<boolean | null>(null)

  const groups = characters.data?.groups ?? NO_GROUPS
  // Past the start (a path under /profit), the visitor has started whatever they did before.
  // A path under /profit that means nothing is the start, as is making gold while it is switched off: shown as the
  // start at once, so nothing under it mounts (and asks for a ranking) before the redirect below.
  const unknown = view === null || (view.kind === 'gold' && !MAKE_GOLD)
  // A path kept for old links goes to its page; a way to make gold that isn't offered, back to the question.
  const elsewhere =
    view?.kind === 'moved'
      ? view.to
      : view?.kind === 'gold' && view.strategy && !(STRATEGY_PICKER && liveStrategies().some((s) => s.key === view.strategy))
        ? '/profit/gold'
        : null
  const atStart = view?.kind === 'start' || unknown
  const started = !atStart || groups.length > 0 || landing.browsed
  const phase: Phase = open ? 'expanded' : started ? 'collapsed' : 'choose'
  const ready = characters.data !== undefined
  // Arriving from the main page, its card turns into the banner, so the banner is there at once (not after the
  // characters load) and folds away once they show the visitor has already started.
  const [carried] = useState(() => previousRoute() === '/')
  const showHero = atStart && ((ready && !started) || (carried && !ready))

  useEffect(() => {
    if (unknown) navigate(profitPath({ kind: 'start' }), { replace: true })
    else if (elsewhere) navigate(elsewhere, { replace: true })
  }, [unknown, elsewhere])

  // Bring the search into view when it first appears, not when the page loads with it.
  useEffect(() => {
    if (!ready) return
    if (shownBefore.current === false && started) {
      searchRef.current?.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' })
    }
    shownBefore.current = started
  }, [ready, started, reduced])

  // Alt Army Sync's first upload brings characters in while its card is open (the status poll notices): move on.
  const hadCharacters = useRef(false)
  useEffect(() => {
    if (!ready) return
    const has = groups.length > 0
    if (has && !hadCharacters.current && open === 'auto') {
      setOpen(null)
      const count = groups.reduce((n, g) => n + g.characters.length, 0)
      notifications.show({
        color: 'green',
        title: 'Characters uploaded',
        message: `${count} ${count === 1 ? 'character' : 'characters'} on ${groups.map((g) => realmLabel(g)).join(', ')}.`,
      })
    }
    hadCharacters.current = has
  }, [ready, groups, open])

  const pick = (key: CardKey) => {
    if (key === 'browse') {
      setLastPicked('browse')
      setMoved(true)
      setLanding({ browsed: true })
      setOpen(null)
    } else {
      setOpen(key)
    }
  }

  const pickAim = (aim: Aim) => {
    setLastSetup((prev) => ({ ...prev, aim }))
    storePresets(aim)
    track('aim_chosen', { aim })
    navigate(profitPath({ kind: aim }))
  }

  const imported = (r: UploadResult) => {
    setOpen(null)
    notifications.show({
      color: 'green',
      title: 'Characters uploaded',
      message: `${r.characters} ${r.characters === 1 ? 'character' : 'characters'}${
        r.groups.length ? ` on ${r.groups.map((g) => realmLabel(g)).join(', ')}` : ''
      }.`,
    })
  }

  // The vendor check is its own page under /profit, reached by its path alone: none of the start or search below.
  if (view?.kind === 'vendorcheck') return <VendorCheck />

  // The strip, or the start cards while one is open (or nothing is started): beside the realm card past the start,
  // taking the whole width while open.
  const charactersArea =
    phase === 'collapsed' ? (
      <Strip key="strip" data={characters.data} onOpen={setOpen} layoutId={cardLayoutId(lastPicked)} />
    ) : (
      <div key="cards" className={cards.cards} data-phase={phase} data-wide role="group" aria-label="Ways to start">
        {cardsFor(groups.length > 0).map((spec) => (
          <StartCard
            key={spec.key}
            spec={spec}
            phase={phase}
            layoutId={cardLayoutId(spec.key)}
            fade={moved && spec.key !== lastPicked}
            open={open === spec.key}
            onPick={() => pick(spec.key)}
            onClose={() => setOpen(null)}
          >
            {spec.key === 'import' && <ImportBody onImported={imported} />}
            {spec.key === 'auto' && <AutoImportBody />}
          </StartCard>
        ))}
      </div>
    )

  return (
    <Stack gap="lg">
      <AnimatePresence initial={false}>
        {showHero && (
          <motion.div
            key="hero"
            layoutId="showcase-profit"
            layout
            exit={{ opacity: 0, height: 0, marginBottom: 'calc(-1 * var(--mantine-spacing-lg))' }}
            transition={{ duration: 0.3, ease: EASE }}
            // The banner's radius, so Motion keeps its corners round while the main page's card resizes into it.
            style={{ overflow: 'hidden', borderRadius: 12 }}
          >
            <Hero />
          </motion.div>
        )}
      </AnimatePresence>
      {!ready ? (
        <Group justify="center" py="xl">
          <Loader aria-label="Loading your characters" />
        </Group>
      ) : (
        <LayoutGroup>
          {/* The strip and the card picked last share a layout id, so one resizes into the other (as the Realm card
              does) while the other cards fade in. No AnimatePresence: Motion would hold a leaving shared-layout box
              until the new one's animation ends, and the resize needs nothing more than the old box's last layout. */}
          {atStart && charactersArea}
          <AnimatePresence>
            {started && (
              <motion.section
                key="search"
                ref={searchRef}
                aria-label="Search"
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.35, delay: 0.1, ease: EASE }}
                style={{ scrollMarginTop: 16 }}
              >
                {atStart ? (
                  <AimQuestion current={lastSetup} unavailable={unavailableAims()} onPick={pickAim} />
                ) : (
                  <SearchTab
                    characters={charactersArea}
                    charactersOpen={phase !== 'collapsed'}
                    onUploadCharacters={() => setOpen('import')}
                  />
                )}
              </motion.section>
            )}
          </AnimatePresence>
        </LayoutGroup>
      )}
    </Stack>
  )
}
