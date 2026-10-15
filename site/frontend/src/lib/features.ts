/** Feature flags: parts of the site built but not offered yet. */

/** Make gold on the Profit page: off, its aim card is disabled with "Coming soon" and `/profit/gold` goes back to the
 * start. */
export const MAKE_GOLD = false

/** Make gold as a choice of strategies: `/profit/gold` asks how (`StrategyPicker`), each answer its own page
 * (`/profit/gold/<strategy>`). Off: `/profit/gold` is the one gold list, and the strategy paths go back to it. */
export const STRATEGY_PICKER = false

/** The Process trade goods strategy (a card and a page once it is built). */
export const PROCESSING = true

/** The Vendor runs strategy: what the auction house lists under what a vendor pays, and what vendors sell for less
 * than it pays. */
export const VENDOR_RUNS = true

/** The What I hold strategy: what the characters' bags and bank hold, and what to do with it. */
export const WHAT_I_HOLD = true
