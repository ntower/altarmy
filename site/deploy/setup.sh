#!/usr/bin/env bash
# One-time Google Cloud setup for the hosted app, one section at a time (each creates billable or
# visible resources, so run them deliberately):
#
#   deploy/setup.sh apis         enable the APIs
#   deploy/setup.sh registry     Artifact Registry repo, keeping the last 5 images
#   deploy/setup.sh accounts     service accounts and their roles
#   deploy/setup.sh sql          Cloud SQL instance (Postgres 16, db-f1-micro, 10 GB SSD)
#   deploy/setup.sh database ENV   a database, its user (random password) and the DATABASE_URL secret
#   deploy/setup.sh staging-auth staging's runtime service account (after `database staging` and the
#                                alt-army-staging Firebase project exist; README, "Firebase projects")
#   deploy/setup.sh firestore    Firestore for price signals in prod's and staging's Firebase projects (after
#                                `accounts` and `staging-auth`), and who may write signals and deploy rules
#   deploy/setup.sh wif          Workload Identity Federation for GitHub Actions
#   deploy/setup.sh wif-repo     point the existing federation at GITHUB_REPO (after the repo was renamed;
#                                the old repo's name loses access)
#   deploy/setup.sh scheduler ENV  Cloud Scheduler jobs for prod or staging (after a deploy of ENV made its
#                                jobs; existing ones are kept)
#   deploy/setup.sh job-runner ENV  let ENV's service start its ingest jobs (the Admin page's Run now; after
#                                a deploy of ENV made them)
#   deploy/setup.sh discord [IMAGE]  alerts to a Discord channel (after a prod deploy; asks for the webhook
#                                URL): the relay service (IMAGE, else prod's), its password and the webhook
#                                notification channel (existing ones are kept)
#   deploy/setup.sh alerts       the alert policies, notifying the Discord channel (after `discord`;
#                                existing policies are kept and pointed at it alone)
#   deploy/setup.sh archive ENV  the bucket ENV's prune job archives prices to (`archive.py`), writable by
#                                ENV's runtime account alone (before the deploy that points the job at it)
#
# Then: BUILDER=cloudbuild deploy/build.sh, deploy/deploy.sh prod|staging IMAGE (README, "Deploy").
set -euo pipefail
cd "$(dirname "$0")/.."
source deploy/config.sh
G=("${GCLOUD_FLAGS[@]}")

apis() {
  gcloud services enable run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com \
    artifactregistry.googleapis.com cloudscheduler.googleapis.com cloudbuild.googleapis.com \
    iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com "${G[@]}"
}

registry() {
  gcloud artifacts repositories create "$REPO" --repository-format docker --location "$REGION" \
    --description "Alt Army website images" "${G[@]}"
  gcloud artifacts repositories set-cleanup-policies "$REPO" --location "$REGION" \
    --policy deploy/ar-cleanup.json --no-dry-run "${G[@]}"
}

project_role() { # project_role MEMBER ROLE
  gcloud projects add-iam-policy-binding "$PROJECT" --member "$1" --role "$2" --condition None \
    "${G[@]}" >/dev/null
  echo "  $2 -> $1"
}

accounts() {
  gcloud iam service-accounts create altarmy-run --display-name "Alt Army website service and jobs" "${G[@]}"
  gcloud iam service-accounts create altarmy-scheduler --display-name "Alt Army website scheduler" "${G[@]}"
  gcloud iam service-accounts create altarmy-deploy --display-name "Alt Army website CI deploys" "${G[@]}"

  # runtime: Cloud SQL, its secrets (granted per secret in `database`), deleting Firebase Auth users
  project_role "serviceAccount:$PROD_RUN_SA" roles/cloudsql.client
  project_role "serviceAccount:$PROD_RUN_SA" roles/firebaseauth.admin
  # scheduler: start Cloud Run jobs
  project_role "serviceAccount:$SCHEDULER_SA" roles/run.invoker
  # CI: deploy services and jobs as altarmy-run, push images, deploy Hosting; Cloud Build as itself
  for role in roles/run.admin roles/artifactregistry.writer roles/firebasehosting.admin \
    roles/serviceusage.serviceUsageConsumer roles/logging.logWriter roles/storage.objectViewer; do
    project_role "serviceAccount:$DEPLOY_SA" "$role"
  done
  gcloud iam service-accounts add-iam-policy-binding "$PROD_RUN_SA" --member "serviceAccount:$DEPLOY_SA" \
    --role roles/iam.serviceAccountUser "${G[@]}" >/dev/null
}

sql() {
  gcloud sql instances create "$SQL_INSTANCE" --database-version POSTGRES_16 --edition ENTERPRISE \
    --tier db-f1-micro --region "$REGION" --storage-type SSD --storage-size 10 --storage-auto-increase \
    --availability-type zonal --backup-start-time 08:00 --retained-backups-count 7 \
    --assign-ip "${G[@]}"
}

database() { # database prod|staging: its database, user and DATABASE_URL secret (password never printed)
  env_config "${1:?prod or staging}"
  gcloud sql databases create "$DB_NAME" --instance "$SQL_INSTANCE" "${G[@]}"
  local password
  password="$(openssl rand -hex 24)"
  gcloud sql users create "$DB_USER" --instance "$SQL_INSTANCE" --password "$password" "${G[@]}"
  printf 'postgresql+psycopg://%s:%s@/%s?host=/cloudsql/%s' "$DB_USER" "$password" "$DB_NAME" \
    "$SQL_CONNECTION" | gcloud secrets create "$SECRET" --data-file - --replication-policy automatic "${G[@]}"
  gcloud secrets add-iam-policy-binding "$SECRET" --member "serviceAccount:$RUN_SA" \
    --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null
}

staging_auth() { # staging's own runtime account: its database secret only, and admin of staging's Auth only
  gcloud iam service-accounts create altarmy-staging-run --display-name "Alt Army website staging service and jobs" \
    "${G[@]}"
  project_role "serviceAccount:$STAGING_RUN_SA" roles/cloudsql.client
  # deleting accounts (DELETE /api/me) in the staging Firebase project; that project has no billing, so the
  # call bills (nothing) to $PROJECT
  gcloud projects add-iam-policy-binding "$STAGING_AUTH_PROJECT" --member "serviceAccount:$STAGING_RUN_SA" \
    --role roles/firebaseauth.admin --condition None --billing-project "$PROJECT" --quiet >/dev/null
  echo "  roles/firebaseauth.admin on $STAGING_AUTH_PROJECT -> $STAGING_RUN_SA"
  env_config staging
  gcloud secrets add-iam-policy-binding "$SECRET" --member "serviceAccount:$STAGING_RUN_SA" \
    --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null
  # prod's account read staging's secret while staging ran as it
  gcloud secrets remove-iam-policy-binding "$SECRET" --member "serviceAccount:$PROD_RUN_SA" \
    --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null 2>&1 || echo "  (prod had no access to $SECRET)"
  gcloud iam service-accounts add-iam-policy-binding "$STAGING_RUN_SA" --member "serviceAccount:$DEPLOY_SA" \
    --role roles/iam.serviceAccountUser "${G[@]}" >/dev/null
}

firestore() { # the price signals' database (signals.py, firestore.rules): one per Firebase project
  local project sa
  for pair in "$PROJECT:$PROD_RUN_SA" "$STAGING_AUTH_PROJECT:$STAGING_RUN_SA"; do
    project="${pair%%:*}" sa="${pair#*:}"
    # staging's project has no billing: every call bills (nothing) to $PROJECT
    gcloud services enable firestore.googleapis.com firebaserules.googleapis.com --project "$project"       --billing-project "$PROJECT" --quiet
    gcloud firestore databases create --location "$REGION" --type firestore-native --project "$project"       --billing-project "$PROJECT" --quiet
    # the service and its jobs write signals; CI deploys the rules
    gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$sa" --role roles/datastore.user       --condition None --billing-project "$PROJECT" --quiet >/dev/null
    echo "  roles/datastore.user on $project -> $sa"
    gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$DEPLOY_SA"       --role roles/firebaserules.admin --condition None --billing-project "$PROJECT" --quiet >/dev/null
    echo "  roles/firebaserules.admin on $project -> $DEPLOY_SA"
    # the Firebase CLI checks the Firestore API is enabled before deploying rules
    gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$DEPLOY_SA"       --role roles/serviceusage.serviceUsageConsumer --condition None --billing-project "$PROJECT" --quiet >/dev/null
    echo "  roles/serviceusage.serviceUsageConsumer on $project -> $DEPLOY_SA"
  done
}

wif() {
  gcloud iam workload-identity-pools create "$WIF_POOL" --location global \
    --display-name "GitHub Actions" "${G[@]}"
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" --location global \
    --workload-identity-pool "$WIF_POOL" --issuer-uri https://token.actions.githubusercontent.com \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.repository == '$GITHUB_REPO'" "${G[@]}"
  gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" --role roles/iam.workloadIdentityUser \
    --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL/attribute.repository/$GITHUB_REPO" \
    "${G[@]}" >/dev/null
  echo "GitHub repo variables:"
  echo "  GCP_WIF_PROVIDER=projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL/providers/$WIF_PROVIDER"
  echo "  GCP_DEPLOY_SA=$DEPLOY_SA"
}

wif_repo() { # the provider admits GITHUB_REPO alone, and only its workflows may act as the deploy account
  local members="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WIF_POOL/attribute.repository"
  gcloud iam workload-identity-pools providers update-oidc "$WIF_PROVIDER" --location global \
    --workload-identity-pool "$WIF_POOL" --attribute-condition "assertion.repository == '$GITHUB_REPO'" "${G[@]}"
  gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" --role roles/iam.workloadIdentityUser \
    --member "$members/$GITHUB_REPO" "${G[@]}" >/dev/null
  gcloud iam service-accounts get-iam-policy "$DEPLOY_SA" --format "value(bindings.members)" "${G[@]}" \
    | tr ';,' '\n\n' | grep "^$members/" | grep -v "/$GITHUB_REPO\$" | while read -r old; do
      gcloud iam service-accounts remove-iam-policy-binding "$DEPLOY_SA" --role roles/iam.workloadIdentityUser \
        --member "$old" "${G[@]}" >/dev/null
      echo "  removed $old"
    done
  echo "  $GITHUB_REPO may deploy"
}

schedule() { # schedule NAME CRON: run the Cloud Run job NAME on CRON (UTC); skipped if it exists
  if gcloud scheduler jobs describe "$1" --location "$REGION" "${G[@]}" >/dev/null 2>&1; then
    echo "schedule $1 exists"
    return
  fi
  gcloud scheduler jobs create http "$1" --location "$REGION" --schedule "$2" --time-zone Etc/UTC \
    --uri "https://run.googleapis.com/v2/projects/$PROJECT/locations/$REGION/jobs/$1:run" \
    --http-method POST --oauth-service-account-email "$SCHEDULER_SA" \
    --oauth-token-scope https://www.googleapis.com/auth/cloud-platform "${G[@]}"
}

scheduler() { # scheduler prod|staging: the same cadence (jobs.CADENCE); staging's a few minutes after prod's,
  # so the two never run at once on the shared Cloud SQL instance
  env_config "${1:?prod or staging}"
  local m=0
  [ "$1" = staging ] && m=5
  schedule "$JOB_PREFIX-ingest-tbc" "$((0 + m)) 9 * * *"
  schedule "$JOB_PREFIX-ingest-forever" "$((15 + m)) 9 * * *"
  schedule "$JOB_PREFIX-prune" "$((0 + m)) 10 * * *"
  schedule "$JOB_PREFIX-merge" "$((30 + m)) * * * *" # hourly: daily medians and 7-day price statistics
}

job_runner() { # job-runner prod|staging: the service may start its ingest jobs (the Admin page's Run now)
  env_config "${1:?prod or staging}"
  local job
  for job in "$JOB_PREFIX-ingest-tbc" "$JOB_PREFIX-ingest-forever"; do
    gcloud run jobs add-iam-policy-binding "$job" --region "$REGION" --member "serviceAccount:$RUN_SA" \
      --role roles/run.invoker "${G[@]}" >/dev/null
    echo "  roles/run.invoker on $job -> $RUN_SA"
  done
}

discord_channel() { # the Discord notification channel's name, "" before `discord` made it
  gcloud beta monitoring channels list \
    --filter "type=\"webhook_basicauth\" AND displayName=\"$ALERTS_CHANNEL_NAME\"" \
    --format 'value(name)' "${G[@]}" | head -n 1
}

discord() { # discord [IMAGE]: alert policies' and Error Reporting's notifications to a Discord channel
  # the Discord webhook URL: read without echo, never in argv or the shell history
  if gcloud secrets describe "$DISCORD_SECRET" "${G[@]}" >/dev/null 2>&1; then
    echo "secret $DISCORD_SECRET exists"
  else
    local webhook
    read -rsp "Discord webhook URL (channel settings > Integrations > Webhooks): " webhook
    echo
    case "$webhook" in
      https://discord.com/api/webhooks/*) ;;
      *)
        echo "not a Discord webhook URL" >&2
        return 1
        ;;
    esac
    printf '%s' "$webhook" | gcloud secrets create "$DISCORD_SECRET" --data-file - --replication-policy automatic \
      "${G[@]}"
  fi
  # the channel's basic-auth password (never printed), which the relay checks on every request
  if gcloud secrets describe "$RELAY_SECRET" "${G[@]}" >/dev/null 2>&1; then
    echo "secret $RELAY_SECRET exists"
  else
    openssl rand -hex 24 | tr -d '\n' | gcloud secrets create "$RELAY_SECRET" --data-file - \
      --replication-policy automatic "${G[@]}"
  fi

  # the relay's account: reads both secrets
  if ! gcloud iam service-accounts describe "$ALERTS_SA" "${G[@]}" >/dev/null 2>&1; then
    gcloud iam service-accounts create altarmy-alerts --display-name "Alt Army website Discord relay" "${G[@]}"
  fi
  local secret
  for secret in "$DISCORD_SECRET" "$RELAY_SECRET"; do
    gcloud secrets add-iam-policy-binding "$secret" --member "serviceAccount:$ALERTS_SA" \
      --role roles/secretmanager.secretAccessor "${G[@]}" >/dev/null
    echo "  roles/secretmanager.secretAccessor on $secret -> $ALERTS_SA"
  done
  # CI's prod deploys redeploy the relay as it
  gcloud iam service-accounts add-iam-policy-binding "$ALERTS_SA" --member "serviceAccount:$DEPLOY_SA" \
    --role roles/iam.serviceAccountUser "${G[@]}" >/dev/null
  echo "  roles/iam.serviceAccountUser on $ALERTS_SA -> $DEPLOY_SA"

  # the relay: IMAGE, else the image prod runs now (deploy.sh redeploys it with every prod image)
  local image="${1:-}" url channel file
  if [ -z "$image" ]; then
    env_config prod
    image="$(gcloud run services describe "$SERVICE" --region "$REGION" \
      --format 'value(spec.template.spec.containers[0].image)' "${G[@]}")"
  fi
  relay_deploy "${image:?deploy prod first}"
  url="$(gcloud run services describe "$ALERTS_SERVICE" --region "$REGION" --format 'value(status.url)' "${G[@]}")"

  # the webhook channel, its password from the secret through a private temporary file (never in argv)
  channel="$(discord_channel)"
  if [ -z "$channel" ]; then
    file="$(mktemp)"
    chmod 600 "$file"
    printf '{"type": "webhook_basicauth", "displayName": "%s", "labels": {"url": "%s/", "username": "altarmy", "password": "%s"}}' \
      "$ALERTS_CHANNEL_NAME" "$url" "$(gcloud secrets versions access latest --secret "$RELAY_SECRET" "${G[@]}")" \
      >"$file"
    channel="$(gcloud beta monitoring channels create --channel-content-from-file "$file" --format 'value(name)' \
      "${G[@]}")"
    rm -f "$file"
  fi
  echo "  notification channel $channel"
  echo "Next: deploy/setup.sh alerts; and in the console, Error Reporting > Configure notifications:"
  echo "  pick '$ALERTS_CHANNEL_NAME'."
}

policy() { # policy NAME CHANNEL < POLICY_JSON: create the policy, else point the existing one at CHANNEL alone
  local existing file
  existing="$(gcloud alpha monitoring policies list --filter "displayName=\"$1\"" --format 'value(name)' \
    "${G[@]}" | head -n 1)"
  if [ -n "$existing" ]; then
    cat >/dev/null
    gcloud alpha monitoring policies update "$existing" --set-notification-channels "$2" "${G[@]}" >/dev/null
    echo "policy '$1' exists: it notifies $2 alone"
    return
  fi
  file="$(mktemp)"
  cat >"$file"
  gcloud alpha monitoring policies create --policy-from-file "$file" "${G[@]}"
  rm -f "$file"
}

alerts() { # alerts: log-based alert policies, to the Discord channel (`discord`)
  local channel
  channel="$(discord_channel)"
  if [ -z "$channel" ]; then
    echo "no '$ALERTS_CHANNEL_NAME' notification channel: run deploy/setup.sh discord first" >&2
    return 1
  fi
  echo "  notification channel $channel"

  # merge.PARTITION_ALERT: price_observations is past merge.PARTITION_AT rows (prod's or staging's merge);
  # at most once a day
  policy "altarmy price_observations needs partitioning" "$channel" <<EOF
{
  "displayName": "altarmy price_observations needs partitioning",
  "documentation": {
    "mimeType": "text/markdown",
    "content": "The hourly merge job counted more rows in price_observations than merge.PARTITION_AT. Partition the table by month (pruning then drops whole partitions), or shorten prices.KEEP_DAYS. The job label says whether it is prod's or staging's."
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "merge logged partition-observations",
      "conditionMatchedLog": {
        "filter": "resource.type=\"cloud_run_job\" AND severity=WARNING AND jsonPayload.alert=\"partition-observations\"",
        "labelExtractors": {"job": "EXTRACT(resource.labels.job_name)"}
      }
    }
  ],
  "alertStrategy": {"notificationRateLimit": {"period": "86400s"}, "autoClose": "604800s"},
  "notificationChannels": ["$channel"]
}
EOF

  # any Cloud Run job's failed execution (after its retry), prod's or staging's: a traceback (also an Error
  # Reporting event) or a sys.exit with a message (the Admin page's runs say which); at most hourly
  policy "altarmy job failed" "$channel" <<EOF
{
  "displayName": "altarmy job failed",
  "documentation": {
    "mimeType": "text/markdown",
    "content": "A Cloud Run job's execution failed. The job label says which (altarmy-staging-* are staging's); its logs, or the Admin page's recent runs, say why."
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "a job execution failed",
      "conditionMatchedLog": {
        "filter": "resource.type=\"cloud_run_job\" AND logName=\"projects/$PROJECT/logs/cloudaudit.googleapis.com%2Fsystem_event\" AND protoPayload.methodName=\"/Jobs.RunJob\" AND severity>=ERROR",
        "labelExtractors": {"job": "EXTRACT(resource.labels.job_name)"}
      }
    }
  ],
  "alertStrategy": {"notificationRateLimit": {"period": "3600s"}, "autoClose": "86400s"},
  "notificationChannels": ["$channel"]
}
EOF

  # Cloud SQL memory: the RAM Postgres uses (buffer cache included) over the tier's quota. Not
  # database/memory/utilization: on db-f1-micro it reads 1.0 always (memory/usage repeats the quota). A week
  # before this (2026-11) peaked at 0.30
  policy "altarmy database memory high" "$channel" <<EOF
{
  "displayName": "altarmy database memory high",
  "documentation": {
    "mimeType": "text/markdown",
    "content": "Cloud SQL $SQL_INSTANCE has used over 85% of its memory for 15 minutes. Prod and staging share it. Queries will start reading from disk: look at what grew (Query Insights, the largest tables), or move to a larger tier (deploy/setup.sh sql's --tier)."
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "memory over 85% of quota",
      "conditionPrometheusQueryLanguage": {
        "query": "max by (database_id) (cloudsql_googleapis_com:database_memory_total_usage{monitored_resource=\"cloudsql_database\", database_id=\"$PROJECT:$SQL_INSTANCE\"} / cloudsql_googleapis_com:database_memory_quota{monitored_resource=\"cloudsql_database\", database_id=\"$PROJECT:$SQL_INSTANCE\"}) > 0.85",
        "duration": "900s",
        "evaluationInterval": "60s"
      }
    }
  ],
  "alertStrategy": {"autoClose": "86400s"},
  "notificationChannels": ["$channel"]
}
EOF

  # Cloud SQL CPU: the 15-minute average over 80% for 15 minutes (a week before this peaked at 0.28 an hour)
  policy "altarmy database CPU high" "$channel" <<EOF
{
  "displayName": "altarmy database CPU high",
  "documentation": {
    "mimeType": "text/markdown",
    "content": "Cloud SQL $SQL_INSTANCE has averaged over 80% CPU for 15 minutes. Prod and staging share it. Check the merge and ingest jobs and Query Insights for the queries behind it, or move to a larger tier (deploy/setup.sh sql's --tier)."
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "CPU 15-minute average over 80%",
      "conditionPrometheusQueryLanguage": {
        "query": "max by (database_id) (avg_over_time(cloudsql_googleapis_com:database_cpu_utilization{monitored_resource=\"cloudsql_database\", database_id=\"$PROJECT:$SQL_INSTANCE\"}[15m])) > 0.8",
        "duration": "900s",
        "evaluationInterval": "60s"
      }
    }
  ],
  "alertStrategy": {"autoClose": "86400s"},
  "notificationChannels": ["$channel"]
}
EOF
}

archive() { # archive prod|staging: the long-term price archive's bucket and who may write it
  env_config "${1:?prod or staging}"
  if gcloud storage buckets describe "gs://$ARCHIVE_BUCKET" "${G[@]}" >/dev/null 2>&1; then
    echo "bucket gs://$ARCHIVE_BUCKET exists"
  else
    # Standard class (a few GB a year; read now and then for one-off analyses), private, in the region
    gcloud storage buckets create "gs://$ARCHIVE_BUCKET" --location "$REGION" --default-storage-class STANDARD       --uniform-bucket-level-access --public-access-prevention "${G[@]}"
  fi
  # the prune job writes (and rewrites, when a day is archived again) objects; nobody else
  gcloud storage buckets add-iam-policy-binding "gs://$ARCHIVE_BUCKET" --member "serviceAccount:$RUN_SA"     --role roles/storage.objectUser "${G[@]}" >/dev/null
  echo "  roles/storage.objectUser on gs://$ARCHIVE_BUCKET -> $RUN_SA"
}

case "${1:-}" in
  apis | registry | accounts | sql | firestore | wif | alerts) "$1" ;;
  archive) archive "${2:-}" ;;
  wif-repo) wif_repo ;;
  discord) discord "${2:-}" ;;
  database) database "${2:-}" ;;
  scheduler) scheduler "${2:-}" ;;
  job-runner) job_runner "${2:-}" ;;
  staging-auth) staging_auth ;;
  *)
    sed -n '2,27p' "$0"
    exit 1
    ;;
esac
