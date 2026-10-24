import * as flags from './features'
import { useSession } from './session'

/** The feature flags as the signed-in user gets them. */
export type Features = {
  makeGold: boolean
  strategyPicker: boolean
  processing: boolean
  vendorRuns: boolean
  whatIHold: boolean
}

/** An admin sees every part of the site, whatever the flags say; anyone else, what they switch on. Read at the call,
 * not at load, so a test's mocked flags hold. */
export const featuresFor = (admin: boolean): Features =>
  admin
    ? { makeGold: true, strategyPicker: true, processing: true, vendorRuns: true, whatIHold: true }
    : {
        makeGold: flags.MAKE_GOLD,
        strategyPicker: flags.STRATEGY_PICKER,
        processing: flags.PROCESSING,
        vendorRuns: flags.VENDOR_RUNS,
        whatIHold: flags.WHAT_I_HOLD,
      }

/** The feature flags for whoever is signed in. */
export const useFeatures = (): Features => featuresFor(useSession().admin)
