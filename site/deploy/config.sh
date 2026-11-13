# Names shared by deploy/*.sh. Sourced, not run. Every gcloud call passes the project explicitly, so the
# caller's gcloud defaults (project, quota project) never matter.
PROJECT=alt-army-prod
PROJECT_NUMBER=516573536063
REGION=us-central1
GCLOUD_FLAGS=(--project "$PROJECT" --billing-project "$PROJECT" --quiet)

REPO=altarmy                                   # Artifact Registry (docker)
IMAGE_BASE="$REGION-docker.pkg.dev/$PROJECT/$REPO/altarmy"

SQL_INSTANCE=altarmy-pg                        # Cloud SQL Postgres 16, db-f1-micro
SQL_CONNECTION="$PROJECT:$REGION:$SQL_INSTANCE"

PROD_RUN_SA="altarmy-run@$PROJECT.iam.gserviceaccount.com"                # prod's service and jobs run as this
STAGING_RUN_SA="altarmy-staging-run@$PROJECT.iam.gserviceaccount.com"     # staging's
STAGING_AUTH_PROJECT=alt-army-staging # staging's Firebase Auth (Spark, no billing: only IAM grants go there)
SCHEDULER_SA="altarmy-scheduler@$PROJECT.iam.gserviceaccount.com" # Cloud Scheduler starts jobs as this
DEPLOY_SA="altarmy-deploy@$PROJECT.iam.gserviceaccount.com"       # CI (Workload Identity Federation)

# Alerts to Discord (setup.sh discord): Monitoring's alert policies and Error Reporting -> a basic-auth webhook
# channel -> the relay service (public, as webhooks need; it checks the password) -> Discord's webhook
ALERTS_SA="altarmy-alerts@$PROJECT.iam.gserviceaccount.com" # the relay runs as this
ALERTS_SERVICE=altarmy-alerts                                # Cloud Run service: `altarmy-site alert-relay`
ALERTS_CHANNEL_NAME="altarmy Discord"                        # the Monitoring notification channel
DISCORD_SECRET=discord-webhook                               # Secret Manager: the Discord channel's webhook URL
RELAY_SECRET=alerts-relay-password                           # Secret Manager: the channel's basic-auth password

WIF_POOL=github
WIF_PROVIDER=github-actions
GITHUB_REPO=ntower/altarmy

# Per environment: prod | staging. Sets SERVICE, DB_NAME, DB_USER, SECRET, JOB_PREFIX, MAX_INSTANCES, RUN_SA
# (the runtime service account), FIREBASE_ENV (the env file with its Firebase web config) and ARCHIVE_BUCKET
# (the long-term price archive the prune job writes: setup.sh archive ENV).
env_config() {
  case "$1" in
    prod)
      # one instance: every request shares its market and rank caches (identical rankings at once run once)
      SERVICE=altarmy DB_NAME=altarmy DB_USER=altarmy SECRET=database-url JOB_PREFIX=altarmy MAX_INSTANCES=1
      RUN_SA="$PROD_RUN_SA" FIREBASE_ENV=hosted.env ARCHIVE_BUCKET=alt-army-prod-archive
      ;;
    staging)
      SERVICE=altarmy-staging DB_NAME=altarmy_staging DB_USER=altarmy_staging SECRET=database-url-staging
      JOB_PREFIX=altarmy-staging MAX_INSTANCES=1 RUN_SA="$STAGING_RUN_SA" FIREBASE_ENV=staging.env
      ARCHIVE_BUCKET=alt-army-prod-archive-staging
      ;;
    *)
      echo "environment must be prod or staging, not '$1'" >&2
      return 1
      ;;
  esac
}

# Deploy the Discord relay (alerts.py) with IMAGE: setup.sh discord first, then every prod deploy.
relay_deploy() {
  gcloud run deploy "$ALERTS_SERVICE" --image "${1:?image}" --region "$REGION" --service-account "$ALERTS_SA" \
    --command altarmy-site --args alert-relay --allow-unauthenticated \
    --min-instances 0 --max-instances 1 --concurrency 10 --cpu 1 --memory 256Mi \
    --set-secrets "DISCORD_WEBHOOK_URL=$DISCORD_SECRET:latest,RELAY_PASSWORD=alerts-relay-password:latest" "${GCLOUD_FLAGS[@]}"
}

# The environment's Firebase web config (public) from $FIREBASE_ENV (after env_config), as Cloud Run env vars.
# Fails if a value is missing, so a deploy never starts a service that can't sign anyone in.
firebase_env() {
  local root vars
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  vars="$(grep -E '^FIREBASE_(PROJECT_ID|API_KEY|AUTH_DOMAIN)=.+' "$root/${FIREBASE_ENV:?run env_config first}" | tr -d '\r')"
  if [ "$(printf '%s\n' "$vars" | grep -c .)" -ne 3 ]; then
    echo "$FIREBASE_ENV needs FIREBASE_PROJECT_ID, FIREBASE_API_KEY and FIREBASE_AUTH_DOMAIN" >&2
    return 1
  fi
  printf '%s\n' "$vars" | paste -sd, -
}
