import type { PriceConfidence } from '../api/client'

const units = (n: number) => `${n.toLocaleString()} ${n === 1 ? 'unit' : 'units'}`
const hours = (h: number) => `${h} ${h === 1 ? 'hour' : 'hours'}`
const day = (iso: string) => new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })

/** Why a sell price is trusted as much as it is, in words. */
export function confidenceWhy(c: PriceConfidence): string {
  const plan = c.units > 1 ? `; this plan sells ${c.units.toLocaleString()}` : ''
  switch (c.reason) {
    case 'hand_set':
      return 'Price set by hand'
    case 'sold':
      return `${units(c.sold)} seen selling in the last 7 days`
    case 'few_sold':
      return c.sold >= c.units
        ? `${units(c.sold)} seen selling in the last 7 days, but the auction house was watched for only ${hours(c.watched_hours)}`
        : `Only ${units(c.sold)} seen selling in the last 7 days${plan}`
    case 'one_pair':
      return `${units(c.sold)} seen selling, all between one pair of scans: maybe a single buyer`
    case 'unlisted': {
      const since = c.unlisted_since ? ` since ${day(c.unlisted_since)}` : ''
      return `None listed${since}, and none seen selling: priced from what it was listed for before`
    }
    case 'few_days':
      return c.scan_days > 0
        ? `Priced from scans on only ${c.scan_days} ${c.scan_days === 1 ? 'day' : 'days'}`
        : 'Not scanned on enough days to price it'
    case 'unsold': {
      const seen = c.sold ? `Only ${units(c.sold)}` : 'None'
      return `${seen} seen selling in ${hours(c.watched_hours)} of back-to-back scans`
    }
    case 'thin':
      return `Rests on ${units(c.listed ?? 0)} listed${plan}`
    case 'unwatched':
      return 'Sales unknown: they are seen only between snapshots of the auction house taken close together'
  }
}

/** A sell price's confidence and why, for a tooltip. */
export function confidenceTitle(c: PriceConfidence): string {
  const level = c.level === 'high' ? 'High' : c.level === 'medium' ? 'Medium' : 'Low'
  return `${level} confidence in the sell price: ${confidenceWhy(c)}`
}
