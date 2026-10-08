import createClient from 'openapi-fetch'
import { getIdToken } from '../lib/auth'
import type { components, paths } from './schema'

export type Status = components['schemas']['Status']
export type RankResult = components['schemas']['RankResult']
export type StrategyOut = components['schemas']['StrategyOut']
/** How far a result's AH sell price can be trusted, and the numbers behind it. */
export type PriceConfidence = components['schemas']['ConfidenceOut']
/** One recipe re-costed with the user's choices, and tooltip details for the items it now uses. */
export type Evaluation = components['schemas']['EvaluateResponse']
export type ItemInfo = components['schemas']['ItemInfo']
/** Where to learn a recipe nobody selected has learned (`RankResponse.learn`). */
export type Learn = components['schemas']['LearnOut']
/** One item in a recipe's reagent tree: bought (no inputs) or crafted from its inputs. */
export type FlowNode = components['schemas']['NodeOut']
/** One instruction of a recipe's plan; `paths` are the tree paths of the nodes it stands for. */
export type Step = components['schemas']['StepOut']
/** Tooltip details keyed by item id (JSON object keys are strings). */
export type ItemMap = Readonly<Record<string, ItemInfo>>
export type Characters = components['schemas']['Characters']
/** Which game's data a request is about: `tbc` or `forever`. */
export type GameVersion = components['schemas']['VersionOut']['key']
/** A rank a profession trainer teaches: from `train_at` skill and character `level`, up to `cap`. */
export type ProfessionRank = components['schemas']['ProfessionRankOut']
export type CharacterGroup = components['schemas']['GroupOut']
export type Selection = components['schemas']['SelectionModel']
/** Items never sold on the AH, with tooltip details. */
export type AhBlocked = components['schemas']['AhBlocked']
/** The user's favorite recipes, listed first in searches. */
export type Favorites = components['schemas']['Favorites']
export type Coverage = components['schemas']['CoverageOut']
export type Config = components['schemas']['ConfigOut']
export type Me = components['schemas']['Me']
/** What the ingestion jobs, uploads and feeds have been doing (the Admin page). */
export type Ingestion = components['schemas']['IngestionOut']
export type UploadResult = components['schemas']['UploadResult']
/** A character typed in by hand. */
/** The user's time settings: the cities they can craft in, the one plans are timed in, seconds per action. */
export type TimeSettings = components['schemas']['TimeSettings']
export type TimeConfig = components['schemas']['TimeConfigModel']
/** How long a batch of a recipe takes in a city, and what it makes per hour. */
export type Timing = components['schemas']['TimingOut']

export const client = createClient<paths>({
  baseUrl: globalThis.location?.origin ?? '',
  // Look fetch up per call (not once at import) so tests can stub it.
  fetch: (request) => globalThis.fetch(request),
})

// Every request carries the signed-in user's Firebase ID token.
client.use({
  async onRequest({ request }) {
    const token = await getIdToken()
    if (token) request.headers.set('Authorization', `Bearer ${token}`)
    return request
  },
})

export class ApiError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

function errorMessage(error: unknown, response: Response): string {
  if (error && typeof error === 'object' && 'detail' in error) {
    const { detail } = error
    return typeof detail === 'string' ? detail : JSON.stringify(detail)
  }
  return `${response.status} ${response.statusText}`
}

/** Resolve an openapi-fetch call to its data, or throw an ApiError carrying FastAPI's `detail`. */
export async function call<T>(
  request: Promise<{ data?: T; error?: unknown; response: Response }>,
): Promise<T> {
  const { data, error, response } = await request
  if (!response.ok || data === undefined) {
    throw new ApiError(errorMessage(error, response), response.status)
  }
  return data
}
