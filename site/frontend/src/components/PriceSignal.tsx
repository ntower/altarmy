import { useEffect, useRef } from 'react'
import { notifications } from '@mantine/notifications'
import { useQueryClient } from '@tanstack/react-query'
import { useStatus } from '../api/queries'
import { GAME_VERSION } from '../lib/gameVersion'
import { realmLabel } from '../lib/realms'
import { watchPriceSignal } from '../lib/signals'

/**
 * Keeps the Profit page's prices live: listens to the selected auction house's price signal and refetches the
 * status when the server's price version passes the one shown (which refetches every price-dependent query, keyed
 * on it). Whenever the shown version moves on for the same auction house, by a signal or the status poll, it says
 * so and marks every cached ranking stale. Renders nothing.
 */
export function PriceSignal() {
  const status = useStatus().data
  const queryClient = useQueryClient()
  const ah = status?.auction_house_id ?? null
  const shown = status?.price_version ?? null

  const known = useRef(shown)
  known.current = shown
  useEffect(() => {
    if (ah === null) return
    return watchPriceSignal(ah, (version) => {
      if (known.current !== null && version > known.current) {
        void queryClient.invalidateQueries({ queryKey: ['status', GAME_VERSION] })
      }
    })
  }, [ah, queryClient])

  const last = useRef<{ ah: number | null; version: number | null } | null>(null)
  const where = status?.selection ? realmLabel(status.selection) : 'your realm'
  useEffect(() => {
    const before = last.current
    last.current = { ah, version: shown }
    if (before && before.ah === ah && before.version !== null && shown !== null && shown > before.version) {
      // Every cached ranking is stale now, but none is refetched here: the live ones are keyed on the version, and a
      // list held at its prices (the skill workspace) waits for its Refresh. A ranking asked for again is fetched anew.
      void queryClient.invalidateQueries({ queryKey: ['rank'], refetchType: 'none' })
      notifications.show({
        id: 'prices-updated', // one notice however many updates arrive
        title: 'Prices updated',
        message: `New auction house prices for ${where}: the results were refreshed.`,
      })
    }
  }, [ah, shown, where, queryClient])

  return null
}
