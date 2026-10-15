import { type ReactNode, useEffect, useRef, useState } from 'react'
import { Anchor, Code, Group, Stack, Text } from '@mantine/core'
import { AnimatePresence, LayoutGroup, motion } from 'motion/react'
import { savedVariablesPath } from '../lib/gameVersion'
import { LAYOUT } from '../lib/motion'
import { AutoImportBody } from './AutoImport'
import { AUTO_IMPORT_CARD } from './autoImportCard'
import cards from './Cards.module.css'
import { IconCompass, IconUpload } from './icons'
import { PriceFreshness } from './PriceFreshness'
import { type CardSpec, OpenCardBody, OpenCardHeader, StartCard } from './StartCard'
import { ScanSteps, UploadForm, UploadScanButton } from './UploadForm'

const FILE = 'AltArmy_TBC.lua'

type Mode = 'realm' | 'upload' | 'auto'

const UPLOAD_CARD: CardSpec<'upload'> = {
  key: 'upload',
  title: 'Upload your scan',
  blurb: `Upload ${FILE} by hand.`,
  short: `Upload ${FILE} by hand.`,
  icon: <IconUpload />,
}

const CONTINUE_CARD: CardSpec<'realm'> = {
  key: 'realm',
  title: 'Continue',
  blurb: 'Done uploading auction house data.',
  short: 'Done uploading auction house data.',
  icon: <IconCompass />,
}

const BACK = 'Back to the realm'

/**
 * The realm and faction the search is for (a picker, unless the realm is set elsewhere) and how fresh its auction
 * house prices are, with Upload your scan on the right. Upload your scan lays it out like the Profit page's start cards: this card, large on the left, turns into the
 * upload's steps, with Auto-upload (Alt Army Sync's steps, in its place) and Continue (back to the realm) beside it.
 */
export function RealmCard({
  select,
  lastScan,
}: {
  /** the realm and faction picker; none: the card shows only how old the prices are and the upload */
  select?: ReactNode
  /** the auction house's newest scan; undefined while unknown or with no realm selected */
  lastScan: string | null | undefined
}) {
  const [mode, setMode] = useState<Mode>('realm')
  const upload = () => setMode('upload')
  const section = useRef<HTMLElement>(null)

  // Alt Army Sync's first scan lands while its steps are open: back to the realm, where its age now shows.
  const shownScan = useRef(lastScan)
  useEffect(() => {
    if (lastScan !== shownScan.current && mode === 'auto' && lastScan) setMode('realm')
    shownScan.current = lastScan
  }, [lastScan, mode])

  // On the right like the characters strip's Upload again; Auto-upload is the card beside the upload once it is open.
  const uploadButton = <UploadScanButton onClick={upload} />

  const side: readonly CardSpec<Mode>[] =
    mode === 'upload' ? [AUTO_IMPORT_CARD, CONTINUE_CARD] : mode === 'auto' ? [UPLOAD_CARD, CONTINUE_CARD] : []

  return (
    <LayoutGroup id="realm-card">
      <section
        ref={section}
        aria-label="Realm"
        className={cards.cards}
        data-phase={mode === 'realm' ? undefined : 'expanded'}
        // open, it takes the whole width when it shares a row
        data-wide={mode === 'realm' ? undefined : true}
        style={{ position: 'relative' }}
      >
        <motion.div layout transition={LAYOUT} className={cards.slot} data-open style={{ borderRadius: 12 }}>
          <motion.div layout transition={LAYOUT} className={cards.card} style={{ borderRadius: 12 }}>
            <motion.div layout="position" className={cards.open}>
              {mode === 'realm' && select !== undefined ? (
                <Stack gap="sm">
                  <Group justify="space-between" align="center" gap="sm">
                    {select}
                    {uploadButton}
                  </Group>
                  {lastScan !== undefined && <PriceFreshness lastScan={lastScan} />}
                </Stack>
              ) : mode === 'realm' ? (
                // no picker (the skill page's realm is its climber's): how old the prices are, and the upload
                <Group justify="space-between" align="center" gap="sm">
                  {lastScan !== undefined ? <PriceFreshness lastScan={lastScan} /> : <span />}
                  {uploadButton}
                </Group>
              ) : (
                <div key={mode}>
                  <OpenCardHeader
                    spec={mode === 'upload' ? UPLOAD_CARD : AUTO_IMPORT_CARD}
                    onClose={() => setMode('realm')}
                    closeLabel={BACK}
                  />
                  <OpenCardBody>
                    {mode === 'upload' ? (
                      <Stack gap="sm">
                        <ScanSteps upload={`Upload ${FILE} here.`} />
                        <Text size="xs" c="dimmed">
                          It is in <Code>{savedVariablesPath(FILE)}</Code>.
                        </Text>
                        <UploadForm kind="altarmy" name={FILE} />
                        <Text size="sm" c="dimmed">
                          To skip this step, run{' '}
                          <Anchor component="button" size="sm" onClick={() => setMode('auto')}>
                            Alt Army Sync
                          </Anchor>{' '}
                          on the computer you play on: it uploads {FILE} whenever WoW writes it.
                        </Text>
                      </Stack>
                    ) : (
                      <AutoImportBody />
                    )}
                  </OpenCardBody>
                </div>
              )}
            </motion.div>
          </motion.div>
        </motion.div>
        {/* popLayout: leaving cards step out of the grid at once, so the realm card can widen over them. */}
        <AnimatePresence initial={false} mode="popLayout">
          {side.map((spec) => (
            <motion.div
              key={spec.key}
              className={cards.slot}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0, transition: { duration: 0.1 } }}
            >
              <StartCard
                spec={spec}
                phase="expanded"
                open={false}
                onPick={() => setMode(spec.key)}
                onClose={() => setMode('realm')}
              />
            </motion.div>
          ))}
        </AnimatePresence>
      </section>
    </LayoutGroup>
  )
}
