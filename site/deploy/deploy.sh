#!/usr/bin/env bash
# Deploy an image to an environment, in order:
#   1. define the Cloud Run jobs with the new image (migrate, merge, ingest-tbc, ingest-forever, prune);
#      `setup.sh scheduler ENV` schedules all but migrate
#   2. run the migrate job and wait: migrations run once per deploy, before any new instance starts;
#      skipped when no file under MIGRATIONS changed since the commit the service runs (below)
#   3. deploy the Cloud Run service (its instances never migrate); prod: the Discord relay too, if
#      `setup.sh discord` made it
#   4. build the front end and deploy it to Firebase Hosting (prod: the live site; staging: the
#      `staging` preview channel, whose /api rewrites to the staging service), and the Firestore rules
#      to the environment's Firebase project (price signals, firestore.rules)
#   5. run the ingest jobs side by side and wait: they reload the game data when the new image's ingest
#      code or hand-maintained CSVs changed (`ingest.fingerprint`), and otherwise find it loaded and stop;
#      skipped when none of INGEST_INPUTS changed since the commit the service runs
#
# A job takes minutes to start whatever it does, hence the skips. The commit the service runs is its image's
# tag (build.sh's); a tag that isn't a commit here (a -dirty build, a shallow clone, no service yet) skips
# nothing, and neither does DEPLOY_ALL=1.
#
#   deploy/deploy.sh prod|staging IMAGE
set -euo pipefail
cd "$(dirname "$0")/.."
source deploy/config.sh
ENV_NAME="${1:?prod or staging}"
IMAGE="${2:?image, e.g. from deploy/build.sh}"
env_config "$ENV_NAME"
FIREBASE_VARS="$(firebase_env)" # its own Firebase project: prod's from hosted.env, staging's from staging.env

# What a job's work depends on, relative to site/ (git pathspecs). INGEST_INPUTS mirrors `ingest.fingerprint`
# and the pinned builds (tests/test_deploy.py keeps it in step).
MIGRATIONS=(src/altarmy_site/migrations)
INGEST_INPUTS=(src/altarmy_site/ingest.py src/altarmy_site/itemstats.py src/altarmy_site/spelltext.py
  data/game-data.json 'data/*/*.csv')

# The commit the environment's service runs now, if this checkout has it; else nothing.
DEPLOYED="$(gcloud run services describe "$SERVICE" --region "$REGION" "${GCLOUD_FLAGS[@]}" \
  --format 'value(spec.template.spec.containers[0].image)' 2>/dev/null |
  sed -n 's/.*:\([0-9a-f]\{7,\}\)$/\1/p')" || true
if [ -n "$DEPLOYED" ] && ! git cat-file -e "$DEPLOYED^{commit}" 2>/dev/null; then DEPLOYED=""; fi
echo "== deployed: ${DEPLOYED:-unknown}"

changed() { # changed PATHSPEC...: whether the checkout (untracked files too) differs there from the deployed commit
  [ "${DEPLOY_ALL:-}" = 1 ] || [ -z "$DEPLOYED" ] || ! git diff --quiet "$DEPLOYED" -- "$@" ||
    [ -n "$(git ls-files --others --exclude-standard -- "$@")" ]
}

COMMON=(--image "$IMAGE" --region "$REGION" --service-account "$RUN_SA"
  --set-cloudsql-instances "$SQL_CONNECTION" --set-secrets "DATABASE_URL=$SECRET:latest")

job() { # job NAME ARGS...: the CLI with ARGS, as a Cloud Run job
  local name="$1"
  shift
  local args
  args="$(IFS=,; echo "$*")"
  gcloud run jobs deploy "$name" "${COMMON[@]}" --command altarmy-site --args="$args" \
    --memory 2Gi --cpu 1 --max-retries 1 --task-timeout 30m     --set-env-vars "$FIREBASE_VARS,DB_POOL_SIZE=1,DB_MAX_OVERFLOW=0" \
    "${GCLOUD_FLAGS[@]}"
}

echo "== jobs ($ENV_NAME)"
job "$JOB_PREFIX-migrate" migrate
job "$JOB_PREFIX-merge" merge
job "$JOB_PREFIX-ingest-tbc" --game-version tbc ingest --only-if-new --cache /tmp/cache
job "$JOB_PREFIX-ingest-forever" --game-version forever ingest --only-if-new --cache /tmp/cache
# archives the settled days to the bucket (setup.sh archive ENV), then drops what the archive holds
job "$JOB_PREFIX-prune" prune --archive "gs://$ARCHIVE_BUCKET/"

if changed "${MIGRATIONS[@]}"; then
  echo "== migrate"
  gcloud run jobs execute "$JOB_PREFIX-migrate" --region "$REGION" --wait "${GCLOUD_FLAGS[@]}"
else
  echo "== migrate: no migration changed since $DEPLOYED, skipped"
fi

echo "== service $SERVICE"
# the jobs the Admin page's Run now starts (launch.CloudRunJobs; setup.sh job-runner lets the service)
RUN_JOBS="CLOUD_RUN_LOCATION=projects/$PROJECT/locations/$REGION,JOB_PREFIX=$JOB_PREFIX"
gcloud run deploy "$SERVICE" "${COMMON[@]}" \
  --allow-unauthenticated --min-instances 0 --max-instances "$MAX_INSTANCES" --concurrency 40 \
  --cpu 1 --memory 1Gi --cpu-boost --timeout 300 \
  --set-env-vars "$FIREBASE_VARS,DB_POOL_SIZE=3,DB_MAX_OVERFLOW=2,$RUN_JOBS" \
  "${GCLOUD_FLAGS[@]}"

# the Discord relay (alerts.py) runs prod's image, once setup.sh discord has made it
if [ "$ENV_NAME" = prod ] &&
  gcloud run services describe "$ALERTS_SERVICE" --region "$REGION" "${GCLOUD_FLAGS[@]}" >/dev/null 2>&1; then
  echo "== $ALERTS_SERVICE"
  relay_deploy "$IMAGE"
fi

echo "== front end"
(cd frontend && npm run build)
FIREBASE=(npx --yes firebase-tools@14 --project "$PROJECT" --non-interactive)
if [ "$ENV_NAME" = prod ]; then
  "${FIREBASE[@]}" deploy --only hosting,firestore:rules
else
  "${FIREBASE[@]}" --config firebase.staging.json hosting:channel:deploy staging --expires 30d
  # staging's price signals live in its own Firebase project
  npx --yes firebase-tools@14 --project "$STAGING_AUTH_PROJECT" --non-interactive --config firebase.staging.json     deploy --only firestore:rules
fi

if changed "${INGEST_INPUTS[@]}"; then
  echo "== game data"
  pids=()
  for v in forever tbc; do
    gcloud run jobs execute "$JOB_PREFIX-ingest-$v" --region "$REGION" --wait "${GCLOUD_FLAGS[@]}" &
    pids+=("$!")
  done
  failed=0
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  exit "$failed"
else
  echo "== game data: neither the ingest code, its CSVs nor the pins changed since $DEPLOYED, skipped"
fi
