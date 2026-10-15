import { useState } from 'react'
import { Text } from '@mantine/core'
import { useInterval } from '@mantine/hooks'
import { age, parseUtc } from '../lib/age'
import { IconWarning } from './icons'

/** Prices older than this are called out: a scan since then would give better results. */
export const STALE_AFTER_MS = 30 * 60_000

/**
 * How fresh the selected auction house's prices are: when its newest scan was made, in a warning colour once
 * that is over half an hour ago (or there is no scan at all). The Realm card's Upload your scan button sits beside it.
 */
export function PriceFreshness({ lastScan }: { lastScan: string | null }) {
  // Re-render each minute, so the age keeps up while the page stays open.
  const [now, setNow] = useState(() => new Date())
  useInterval(() => setNow(new Date()), 60_000, { autoInvoke: true })
  const scanned = lastScan === null ? Number.NaN : parseUtc(lastScan)
  const stale = Number.isNaN(scanned) || now.getTime() - scanned > STALE_AFTER_MS
  const text =
    lastScan === null
      ? 'No data collected for this auction house'
      : stale
        ? `Auction house prices are from a scan ${age(lastScan, now)}.`
        : `Auction house prices scanned ${age(lastScan, now)}.`
  return (
    <Text
      size="sm"
      role="status"
      aria-label="Price freshness"
      fw={stale ? 500 : undefined}
      c={stale ? 'yellow' : 'dimmed'}
      title={lastScan ? `${lastScan} UTC` : undefined}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}
    >
      {stale && <IconWarning size={16} />}
      {text}
    </Text>
  )
}
