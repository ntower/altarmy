import * as flags from './features'
import { useSession } from './session'

/** The feature flags as the signed-in user gets them. */
export type Features = {
  makeGold: boolean
}

/** An admin sees every part of the site, whatever the flags say; anyone else, what they switch on. Read at the call,
 * not at load, so a test's mocked flags hold. */
export const featuresFor = (admin: boolean): Features => (admin ? { makeGold: true } : { makeGold: flags.MAKE_GOLD })

/** The feature flags for whoever is signed in. */
export const useFeatures = (): Features => featuresFor(useSession().admin)
