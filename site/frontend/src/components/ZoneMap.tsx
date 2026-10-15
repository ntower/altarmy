import { useState } from 'react'
import { zoneMapUrl } from '../lib/wow'
import classes from './ZoneMap.module.css'

/** The zone's map with a dot where `name` stands; `x` and `y` are map coordinates (percent). Nothing for a zone whose
 * map isn't there (`scripts/fetch_zone_maps.py` found none: a zone only Forever has). */
export function ZoneMap({ area, x, y, name }: { area: number; x: number; y: number; name: string }) {
  const [missing, setMissing] = useState(false)
  if (missing) return null
  return (
    <div className={classes.map}>
      <img src={zoneMapUrl(area)} alt={`Map: ${name}`} className={classes.image} onError={() => setMissing(true)} />
      <span className={classes.dot} style={{ left: `${x}%`, top: `${y}%` }} data-testid="map-dot" />
    </div>
  )
}
