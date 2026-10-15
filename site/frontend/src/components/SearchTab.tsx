import { type ReactNode, useEffect, useState } from 'react'
import { Alert, Group, Loader, Select, Stack } from '@mantine/core'
import type { Selection } from '../api/client'
import {
  useCharacters,
  useCoverage,
  useMaxSkill,
  useProfessionRanks,
  useProfessions,
  useSelectRealm,
  useStatus,
} from '../api/queries'
import { hypotheticalPath, parseProfitPath, resolveHypothetical, resolveRun, runPath } from '../lib/profitRoute'
import { fromKey, realmOptions, toKey } from '../lib/realms'
import { STRATEGY_PICKER } from '../lib/features'
import { navigate, usePath } from '../lib/router'
import { StrategyBar, StrategyPicker } from './StrategyPicker'
import { VendorRuns } from './VendorRuns'
import { useSession } from '../lib/session'
import {
  CLIMBER_NAME,
  hasEnchanter,
  hypotheticalProfessions,
  professionsOf,
  professionsToImagine,
  setupSchema,
  skillsByRealm,
  type Setup as SetupAnswers,
} from '../lib/setup'
import { rankCap } from '../lib/skill'
import { useStoredState } from '../lib/storage'
import { AimSearch } from './AimSearch'
import { ClimberCard } from './ClimberCard'
import { HypotheticalCard } from './HypotheticalCard'
import { PriceSignal } from './PriceSignal'
import { RealmCard } from './RealmCard'
import classes from './SearchTab.module.css'
import { ProfessionQuestion } from './Setup'

export { SHOW_ARCANE_SALVAGER } from './AimSearch'

const storedSetup = setupSchema.nullable()

/** Counts the moves to another path, from 0: a new count lets the search take changed filters at once. */
function usePathMoves(path: string): number {
  const [moves, setMoves] = useState({ path, n: 0 })
  if (moves.path !== path) {
    const next = { path, n: moves.n + 1 }
    setMoves(next)
    return next.n
  }
  return moves.n
}

/**
 * The search after the Profit page's start, by its path (`profitRoute.ts`): at /profit/skill which profession to skill
 * up, and who; at /profit/gold and at a skill run's path the characters (`characters`, the Profit page's strip) and the
 * realm card (realm and faction, price freshness, an upload in place) side by side, then the aim's own search
 * (`AimSearch`: its options, advanced filters and ranked recipes). A run's path names its realm: opening it selects
 * that realm. The answers given last are remembered per user, to mark them when asked again.
 */
export function SearchTab({
  characters: charactersPanel,
  charactersOpen = false,
  onUploadCharacters,
}: {
  /** the Profit page's characters: its strip, or its start cards while one is open */
  characters?: ReactNode
  /** whether the start cards are open: on a run's page they take the climber's card's place meanwhile */
  charactersOpen?: boolean
  /** open the start cards' upload (the climber's card's Upload again) */
  onUploadCharacters?: () => void
}) {
  const { uid } = useSession()
  const path = usePath()
  const view = parseProfitPath(path)
  const status = useStatus()
  const characters = useCharacters()
  const coverage = useCoverage()
  const select = useSelectRealm()
  const professionsQuery = useProfessions()
  const professionNames = professionsQuery.data
  const [lastSetup, setLastSetup] = useStoredState<SetupAnswers | null>(`altarmy.setup.${uid}`, storedSetup, null)
  const groups = characters.data?.groups ?? []
  // Show the realm being switched to while the server imports its prices.
  const selection = select.isPending ? select.variables : status.data?.selection
  const selected = groups.find((g) => selection && toKey(g) === toKey(selection))
  const run = view?.kind === 'run' && characters.data ? resolveRun(view, groups, professionNames) : null
  // A climb of a character nobody uploaded: its path names a priced realm and a profession with recipes.
  const houses = coverage.data?.filter((c) => c.prices > 0)
  const hypothetical =
    view?.kind === 'hypothetical' && houses && professionNames ? resolveHypothetical(view, houses, professionNames) : null
  const ranks = useProfessionRanks()
  const maxSkill = useMaxSkill()
  const flush = usePathMoves(path)
  // Asks from the search to upload a scan (making gold's no-scan notice), each opening the realm card's upload.

  // A run's path needs its character, with that profession, on that realm; a hypothetical climb's a priced realm and
  // a profession to skill up. Either failing, the profession is asked again.
  const redirect =
    view?.kind === 'run' && characters.data && !professionsQuery.isPending && run === null
      ? '/profit/skill'
      : view?.kind === 'hypothetical' && !coverage.isPending && !professionsQuery.isPending && hypothetical === null
        ? '/profit/skill'
        : null
  useEffect(() => {
    if (redirect) navigate(redirect, { replace: true })
  }, [redirect])

  // A run's (or hypothetical climb's) path selects its realm, once: a switch that failed is not tried again and
  // again, and the search then shows for whatever is selected.
  const runRealm = run ? toKey(run.group) : hypothetical ? toKey(hypothetical.realm) : null
  const selectedKey = status.data?.selection ? toKey(status.data.selection) : null
  const { mutate: selectRealm, isPending: selecting, isIdle } = select
  // Whether the switch to the run's realm was made (or is being made): a success sets the status's selection.
  const tried = !isIdle && select.variables !== undefined && toKey(select.variables) === runRealm
  useEffect(() => {
    if (runRealm !== null && runRealm !== selectedKey && !tried) selectRealm(fromKey(runRealm))
  }, [runRealm, selectedKey, tried, selectRealm])

  // The answers the path gives, remembered to mark them when asked again (the last pick of who skills up what, or
  // from what skill).
  const runProfession = run?.choice.name ?? hypothetical?.profession
  const runCharacter = run?.holder.name
  const runSkill = hypothetical?.skill
  useEffect(() => {
    if (!runProfession) return
    if (runCharacter) {
      setLastSetup((prev) => ({ ...prev, aim: 'skill', profession: runProfession, characters: [runCharacter] }))
    } else if (runSkill !== undefined) {
      setLastSetup((prev) => ({ ...prev, aim: 'skill', profession: runProfession, climberSkill: runSkill }))
    }
  }, [runProfession, runCharacter, runSkill, setLastSetup])

  if (status.isPending || characters.isPending) return <Loader />
  if (status.isError) return <Alert color="red">{status.error.message}</Alert>
  if (status.data.recipes === 0) {
    return (
      <Alert color="red">
        No game data has been loaded yet. If you run this site, run `altarmy-site ingest`.
      </Alert>
    )
  }
  if (view === null || view.kind === 'start' || redirect) return null
  if (view.kind === 'run' && run === null) return <Loader /> // the professions are still loading
  if (view.kind === 'hypothetical' && hypothetical === null) return <Loader /> // the realms or professions are
  // Nobody uploaded on the selected realm: the profession question offers every profession, for a character nobody
  // uploaded, once the professions are known.
  const imagining = selected === undefined
  if (view.kind === 'skill' && imagining && professionNames === undefined) return <Loader />

  const options = realmOptions(groups, coverage.data ?? [])
  // The characters' realms come first, without a heading; the other priced realms under Browse a realm.
  const item = ({ value, label }: { value: string; label: string }) => ({ value, label })
  const browse = options.filter((o) => o.section === 'Browse a realm').map(item)
  if (selection && !options.some((o) => o.value === toKey(selection))) {
    // e.g. a realm whose scan is still being merged: still show what is selected
    browse.push({ value: toKey(selection), label: selection.realm })
  }
  const realmData = [
    ...options.filter((o) => o.section === 'Your characters').map(item),
    ...(browse.length > 0 ? [{ group: 'Browse a realm', items: browse }] : []),
  ]
  /** Another realm: a run's character is on the one it names, so the question of who skills up what is asked again. */
  const switchRealm = (to: Selection) => {
    if (view.kind === 'run') navigate('/profit/skill')
    select.mutate(to)
  }
  // In the realm card the picker has no visible label (it sits beside the upload buttons), only its accessible name.
  const realmSelect = (inCard = false) => (
    <Select
      label={inCard ? undefined : 'Realm'}
      aria-label={inCard ? 'Realm' : undefined}
      placeholder="No realm has prices yet"
      data={realmData}
      value={selection ? toKey(selection) : null}
      onChange={(key) => key && switchRealm(fromKey(key))}
      allowDeselect={false}
      size={inCard ? 'sm' : undefined}
      w={inCard ? 300 : undefined}
      maw={inCard ? '100%' : 420}
    />
  )

  if (view.kind === 'skill') {
    const professions = imagining ? professionsToImagine(professionNames ?? []) : professionsOf(selected, professionNames)
    return (
      <Stack>
        {charactersPanel}
        <ProfessionQuestion
          last={lastSetup}
          professions={professions}
          onPick={(profession, picked, skill) => {
            if (imagining) {
              if (selection) navigate(hypotheticalPath(selection, profession, skill ?? 1))
              return
            }
            const choice = professions.find((p) => p.name === profession)
            const name = picked?.[0] ?? choice?.holders[0]?.name
            if (!selected || !name) return
            navigate(runPath(selected, name, profession))
          }}
        >
          {/* Which professions there are depends on the realm: it can be changed right there. */}
          {realmSelect()}
        </ProfessionQuestion>
      </Stack>
    )
  }

  // The realm the search is for: a run's own (being switched to), else the one selected.
  const group = run ? run.group : selected
  // Until the server has selected a run's realm (unless that failed), nothing is ranked for the realm before.
  const switching = runRealm !== null && runRealm !== selectedKey && (selecting || !tried)
  const professions = run
    ? run.professions
    : hypothetical
      ? // taken to have trained to the cap of the rank their skill is in, so the reminders to train the next come
        hypotheticalProfessions(hypothetical.profession, hypothetical.skill, rankCap(ranks, hypothetical.skill, maxSkill))
      : professionsOf(selected, professionNames)
  const setup: SetupAnswers = run
    ? { aim: 'skill', profession: run.choice.name, characters: [run.holder.name] }
    : hypothetical
      ? { aim: 'skill', profession: hypothetical.profession, characters: [CLIMBER_NAME], climberSkill: hypothetical.skill }
      : { aim: 'gold' }
  // Without characters on the selected realm, every recipe is ranked for one unnamed crafter (making gold), or for
  // the character nobody uploaded (a hypothetical climb).
  const browsing = group === undefined && hypothetical === null
  // A way to make gold with its own page (`STRATEGY_PICKER`): the strategy bar over its search.
  const strategy = STRATEGY_PICKER && view?.kind === 'gold' ? view.strategy : undefined
  const noEnchanter = !!selection && group !== undefined && !hasEnchanter(group)
  // The selection's auction house and its newest scan; undefined while the coverage is still loading.
  const house = coverage.data?.find((c) => c.auction_house_id === status.data.auction_house_id)
  const lastScan = coverage.data && status.data.auction_house_id !== null ? (house?.last_scan ?? null) : undefined

  return (
    <Stack>
      <PriceSignal />
      {(run || hypothetical) && !charactersOpen ? (
        // The climber's card beside the auction house's.
        <div className={classes.run}>
          <div className={classes.climberCell}>
            {run ? (
              <ClimberCard
                realm={run.group}
                climber={run.holder}
                profession={run.choice.name}
                realms={skillsByRealm(groups, professionNames)}
                importedAt={characters.data?.imported_at}
                // in place of the current entry: the back button leaves the climb, not each switch; another realm's
                // character switches the search to that realm (above)
                onSwitch={(realm, profession, character) =>
                  navigate(runPath(realm, character, profession), { replace: true })
                }
                onUploadAgain={() => onUploadCharacters?.()}
              />
            ) : (
              hypothetical && (
                <HypotheticalCard
                  profession={hypothetical.profession}
                  skill={hypothetical.skill}
                  professions={professionsToImagine(professionNames ?? []).map((p) => p.name)}
                  // in place of the current entry, as the climber's card switches
                  onChange={(profession, skill) =>
                    navigate(hypotheticalPath(hypothetical.realm, profession, skill), { replace: true })
                  }
                  onUpload={() => onUploadCharacters?.()}
                />
              )
            )}
          </div>
          {/* A run's realm is its climber's: no picker, only how old the prices are. */}
          <div className={classes.houseCell}>
            <RealmCard lastScan={selection ? lastScan : undefined} />
          </div>
        </div>
      ) : (
        <>
          <div className={classes.panels}>
            {charactersPanel}
            <RealmCard
              select={run || hypothetical ? undefined : realmSelect(true)}
              lastScan={selection ? lastScan : undefined}
            />
          </div>
        </>
      )}
      {switching ? (
        <Group justify="center" py="xl">
          <Loader aria-label="Switching realm" />
        </Group>
      ) : selection && setup.aim === 'gold' && STRATEGY_PICKER && view?.kind === 'gold' && !view.strategy ? (
        <StrategyPicker />
      ) : selection ? (
        <>
        {strategy && <StrategyBar current={strategy} />}
        {strategy === 'vendor' ? (
          <VendorRuns />
        ) : (
        <AimSearch
          key={`${setup.aim}-${strategy ?? ''}`}
          strategy={strategy}
          setup={setup}
          professions={professions}
          browsing={browsing}
          noEnchanter={noEnchanter}
          noPrices={status.data.prices === 0}
          salvagerDefault={characters.data?.arcane_salvager ?? false}
          flush={characters.data ? flush : -1}
          lastScan={lastScan}
        />
        )}
        </>
      ) : (
        status.data.prices === 0 && <Alert color="yellow">No data collected for this auction house</Alert>
      )}
    </Stack>
  )
}
