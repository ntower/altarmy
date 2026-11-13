# Alt Army website

The **Alt Army** website (https://alt-army.com) finds profitable crafting recipes and production
chains for **WoW: Forever** and **TBC Anniversary**, the two clients the Alt Army addon runs on. Both share one
database.

- Items and recipes come from the client's DB2 tables (via [wago.tools](https://wago.tools/) CSV exports) into
  the database: Postgres on the site, a SQLite file in development.
- Auction house prices come from the full scans players take with the Alt Army addon (uploaded on the
  site, or by the watcher or Alt Army Sync), per auction house, with history. A scan holds every
  listing, so an item is priced from how many units are listed at each price.
- The engine ranks recipes by profit: reagent cost (buy from a vendor or the AH, or craft an intermediate if cheaper) vs. the best of vendor sale, AH sale (minus the 5% cut) and expected disenchant value. Each craft is costed per character: a reagent is bought by the crafter, or crafted by whichever of your characters can make it and mailed over (30c postage per stack), whichever is cheapest. Disenchanting needs an enchanter among the selected characters; if the crafter doesn't enchant, the output is mailed to the highest-skilled enchanter.

## Setup

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -e ".[dev,ui]"   # ui: the server (FastAPI, uvicorn, firebase-admin); the watcher needs neither
npm ci; cd frontend; npm ci; cd ..   # front end and dev tooling, the Firebase emulator included (needs Node.js, Java 11+)
altarmy-site ingest       # WoW: Forever's game data into data/altarmy.sqlite
npm run dev                 # the site on http://localhost:5173 (see Development)
python scripts/check.py     # Python: ruff, mypy (strict), pytest. Front end: oxlint, vitest, tsc + vite build
```

`python scripts/check.py --skip-frontend` runs only the Python steps. Individual tools: `ruff check . --fix`,
`ruff format .`, `mypy`, `pytest`, and in `frontend/`: `npm run lint`, `npm test`, `npm run build`.

Tests run on SQLite. To run them on Postgres too, point `TEST_DATABASE_URL` at a **throwaway** database
(its `public` schema is dropped), e.g. with a local PostgreSQL install:

```powershell
$env:TEST_DATABASE_URL = "postgresql+psycopg://postgres:postgres@localhost:5432/altarmy_test"; pytest
```

GitHub Actions (`.github/workflows/check.yml`) runs `check.py` and the Postgres suite on every push.

## Usage

```powershell
altarmy-site ingest                          # downloads DB2 tables into ../.cache/, loads WoW: Forever's pinned build
altarmy-site ingest --build latest           # same, for the newest WoW: Forever build on wago.tools
altarmy-site --game-version tbc ingest       # TBC Anniversary's instead
altarmy-site ingest --only-if-new            # the pinned build, unless loaded by this ingest code and CSVs (the site's job)
altarmy-site ingest --only-if-new --force    # reload the pinned build even if loaded (add --force to the job's args)
altarmy-site serve [--reload]                # the API (and the built front end) on http://127.0.0.1:8600; --reload restarts it on code changes
altarmy-site watch --server URL --key KEY    # upload the addon files to the site as WoW rewrites them
altarmy-site migrate                         # migrate the database now (each deploy runs this once)
altarmy-site prune --archive DIR             # archive settled days to DIR (or gs://...), drop what it holds
altarmy-site merge                           # recompute daily medians and 7-day price statistics (hourly job)
```

Every command takes `--game-version forever|tbc` (default `forever`) before the command name; it picks the
game's data in the database, the data files under `data/<version>/` and the wago.tools product
(`wow_classic_beta` or `wow_anniversary`).

The database is `DATABASE_URL` (a SQLAlchemy URL such as `postgresql+psycopg://user:pass@host/db`), else
`data/altarmy.sqlite`; `--db <file>` picks another SQLite file. `serve` and the CLI jobs migrate it
(Alembic); the site's instances never do, its deploy runs `migrate` once.

Prices belong to an auction house: a realm and faction. Forever's come from the Alt Army addon's own
scans alone (the **Alt Army scan** button at the auction house, or `/altarmy scan`); each scan names the
realm and faction it was taken on. TBC's come from users' Auctionator uploads. The newest scan of an
auction house wins, whoever uploaded it; older prices stay as history (see Data notes). A realm nobody
has scanned has no prices.

**Profit per hour (not shown for now).** The site's UI no longer shows play time or profit per hour, and ranks
Make gold by net profit; the model below still runs on the server and its numbers are in the API, so the UI can
come back. Every plan is also timed: casts (DB2 cast times), clicks at the auction house, vendors
and mailbox, character switches, and running between them in a city (see Data notes). A session crafts a
batch (default 10), so a run across town or a switch to an alt is shared by the batch. The search can rank
by profit per hour. What an hour of play is worth makes plans weigh time as money, so a slow vendor run or
a mail to an alt can lose to paying more at the AH. At 0 (the default) time never changes a plan, it is only
reported. Plans are timed in the chosen city, by default wherever each pays best per hour: usually the
fastest of the faction's cities, but vendors charge a character less where their reputation is Honored or
better (10%), so a city can also win by being cheaper.

The site, **Alt Army**, is a React app (`frontend/`) in front of a FastAPI JSON API. It serves WoW: Forever
only (the API serves both games). The header links **Manage** and **Get the Addon**; each is its own page (`/manage`,
`/addon`).

The main page opens with a welcome banner and three ways to start:

- **Upload your characters** pastes the Alt Army addon's export (see Upload below).
- **Auto-upload** sets up Alt Army Sync (see below): create an account, make an upload key, download
  the app. When its first upload brings your characters in, the cards fold away by themselves.
- **Skip for now** needs no characters: every recipe is ranked for one unnamed character, so nothing is
  learned, skill-gated or mailed.

Once one is done (or characters already exist) the cards fold into a one-line summary (open it to see or
remove characters) and the search asks a few questions, one at a time:

- **What are you after?** **Make gold** ranks by net profit and shows only profitable recipes your characters know. **Skill up** (needs imported
  characters) asks **Which profession?** (one someone on the selected realm has), shows only that
  profession's recipes that can still give the crafter a skill point (with those a character can
  train within 20 points), drops the minimum profit so cheap
  losing crafts show too (their numbers in red), and ranks by the cheapest expected skill point (a **Per
  skill up** column).
- **How do you want to sell?** (making gold) **Only what reliably sells** sells via vendors and
  disenchanting; **Anything that might sell** adds the auction house.

Each answer presets the filters it is about (they stay editable) and the questions fold into one row of
the answers, each opening its question again. With no enchanter on the selected realm, a notice
suggests levelling Enchanting on an alt. Under Crafts per session, **Use Arcane Salvager for disenchanting**
counts the Arcane Salvager's bonus (see below); it starts ticked when one of your characters knows the
Arcane Salvager recipe. Then:

- **Search** ranks what your characters on the chosen realm and faction can craft (every profession they
  have), and names who crafts each recipe. The realm picker also lists every other realm with prices, to
  browse it without characters. A choice adds recipes they have not learned yet: those a character is
  at most 20 skill points short of learning, or every recipe of their professions.
  Expand a
  recipe to see its plan as a flow chart or steps. Where a material could come from elsewhere (vendor,
  AH, or a craft), or the output could be sold another way, the node's ⇄ menu lists the options, best
  first. Picking one re-costs the recipe, adding or removing buy, craft and mail steps, and the row
  shows the changed numbers. **Reset** goes back to the best plan. A row's ⋯ menu can mark its output
  **Never sell on auction house**: from then on it is only vendored or disenchanted (it can still be
  bought there). Column headers sort the loaded rows (the setup decides the ranking itself). An expanded row's steps can
  spell out where each character runs (Detailed view), without times. **Crafts per session** (saved per
  user) sets how many crafts a row plans; the city is the server's pick.
- **Manage** lists the items never sold on the auction house (remove one to allow it again) and links
  Alt Army Sync (see below).

### Accounts, uploads and the watcher

Visitors are signed in with Firebase, anonymously at first, and get everything: the main page (rankings and
flow charts), Upload and Manage. Only the uploaders need an account. The header's **Sign in** opens a dialog to
sign in (with **Forgot password?**) or **Create account**: an email address and password on the same user,
so the browser's characters and settings are kept and work on other browsers. Signed in, the email's menu
has **Sign out**, which starts a new anonymous session. Each user has their own characters, selection and AH
blocks. Data comes in through uploads (below), game data through a daily job. `DELETE /api/me` deletes the
account (the UI has no link to it for now). Requests are rate-limited per client IP and per user (429). The
server needs `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY` and `FIREBASE_AUTH_DOMAIN` (see `hosted.env`; staging's in `staging.env`).

**Site admins** get an **Admin** link in the header: the scheduled jobs' runs (ingest, merge, prune;
late or failed ones flagged), every user's uploads and price snapshots per source. Admin is the Firebase custom claim `admin: true` on an email account, set from the command line
with Firebase Auth admin rights (your own `gcloud auth application-default login` on the project):

```bash
FIREBASE_PROJECT_ID=alt-army-prod altarmy-site admin grant you@example.com   # or revoke; `admin list`
# development, against the Auth emulator of `npm run dev`:
FIREBASE_PROJECT_ID=demo-altarmy FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 altarmy-site admin grant you@example.com
```

The claim shows once the browser's sign-in token is refreshed: sign out and in (or wait up to an hour).

- **Upload** takes the Alt Army addon's export: in game, `/altarmy export` shows a string starting
  with `AAX1:`. Copy it (Ctrl+C) and
  paste it in **Paste from Alt Army**. That replaces your characters like the file does, with no logout or
  `/reload`. The string says which client made it, so a TBC export is refused.
- **Upload** takes `AltArmy_TBC.lua`: it replaces your characters and records the auction house scans
  you took with Alt Army (the file keeps the last 3 per realm and faction; scans the site already has
  are passed over). Everyone's scans fill the same auction houses, and the newest wins. WoW writes the
  file on logout or `/reload`. Files are parsed on the server, never stored, and limited to 32 MB; the
  page lists your recent uploads, rejected ones included. A scan whose prices mostly differ wildly from
  the realm's recent prices is not used (shown as **not used**), and makes the uploader's next scans
  face a stricter check. **Coverage** lists every realm's last scan, stalest first, so you can see where
  a scan helps most. An `Auctionator.lua` is refused for Forever.
- **The watcher** uploads the addon files whenever WoW rewrites them, signed in to your account with
  its email and password (`signin.py`: Firebase Auth's REST API, with the site's public config from
  `/api/config`). On the computer you play on, with this package installed:

  ```powershell
  altarmy-site watch --server https://<site>   # asks for the email and password once
  ```

  Only Firebase's refresh token is kept, in `~/.altarmy/watch-auth.json` (per site), never the
  password; it gets a fresh ID token every hour. `--sign-in` asks again, `--create-account` makes a new
  account (it starts empty), and `ALTARMY_EMAIL`/`ALTARMY_PASSWORD` answer the questions when running
  unattended. A sign-in that stops working (password changed, account deleted) is forgotten and the
  watcher exits. It finds both addons' files for both games under the usual WoW folders (`--wow-root` for
  another), uploads the ones WoW rewrote every 15 seconds (`--interval`), and remembers what it sent in
  `~/.altarmy/watch-state.json`. `--once` uploads what changed and exits. It needs no database. The
  site's Firebase browser key only answers the site's origins, so these requests send the site as their
  Referer.
- **Alt Army Sync (Windows).** The same watcher without Python or a terminal: download
  `altarmy-sync.exe` from the [latest build](https://github.com/ntower/altarmy/releases/download/sync-latest/altarmy-sync.exe)
  (the Manage page links it) and run it. Windows SmartScreen warns once because it is unsigned (More info →
  Run anyway).
  - On first run it asks for your email and password, or ticks **Create a new account** (that account
    starts empty: one created on the site from your browser session keeps what that browser has). Then it
    sits in the notification area and uploads as the watcher does.
  - Its menu shows who is signed in and the latest upload, and has Upload now, Open site, Sign in… / Sign
    out, Start with Windows (a `HKCU\...\Run` entry), Show log and Quit. Its tooltip shows its version.
  - Every 6 hours (first a minute after start) it asks GitHub's API for the newest `sync-v*` release. When
    one is newer, it notifies once per version (`notified_version` in its settings) and adds **Update
    available** to the menu, which opens the release page; it never updates itself. A build without a
    version (from source, or `build_sync.py` without `--version`) never checks.
  - It uploads to the live site. `altarmy-sync.exe --staging` uploads to staging instead, and
    `--server http://127.0.0.1:8600` to a dev server (a shortcut whose Target ends in the flag does the same).
    Each has its own settings, log and Start with Windows entry (`sync-staging.json`, `sync-dev.json`, ...),
    shows its name in the tooltip ("Alt Army Sync (staging)"), and can run next to the live one; Start with
    Windows keeps the flag.
  - Settings are in `~/.altarmy/sync.json`: `email` and Firebase's `refresh_token` (plain text, never
    the password). The log is `~/.altarmy/sync.log`. A release before the email sign-in kept an API
    key and a `server` there, which are ignored: sign in again, and pick the site with the flags.
  - From source: `pip install -e ".[tray]"`, then `altarmy-sync`.
  - To build the exe: `pip install -e ".[tray,build-tray]"` and `python scripts/build_sync.py
    [--version 1.2.3]`, which writes `dist/altarmy-sync.exe`.
  - Pushing a `sync-v*` tag makes `.github/workflows/sync.yml` build it on Windows and publish a GitHub
    Release.

**Firebase projects.** Prod and staging sign in against separate Firebase projects, so a staging account
is never a prod one (and deleting it on staging never deletes a prod login). Both have the **Anonymous** and
**Email/Password** sign-in providers enabled; each one's public web config is in an env file that the deploy
sets on its Cloud Run service:

| Env file | Project | Used by |
|----------|---------|---------|
| `hosted.env` | `alt-army-prod` | the live site |
| `staging.env` | `alt-army-staging` (Spark plan, no billing account: it holds only Auth and the price signals' Firestore) | the staging service, `npm run dev:staging-auth` |

Everything else of staging's (Hosting's `staging` channel, the `altarmy-staging` service, its database)
stays in `alt-army-prod`: Hosting only rewrites `/api` to Cloud Run in its own project. So the staging
channel's domain is added by hand to `alt-army-staging`'s Auth authorized domains (Firebase adds only its
own project's channels). Staging runs as its own service account, `altarmy-staging-run`
(`deploy/setup.sh staging-auth`), which can read only staging's database secret and administer only
staging's Auth (and, after `deploy/setup.sh firestore`, write its price signals).

Each browser API key only calls the Identity Toolkit and Token Service APIs (sign-in and token refresh) and
Firestore (the price signals the page listens to), from
`http://localhost:5173`, `http://localhost:8600` and the same two on `127.0.0.1` (Google's referrer patterns
take no port wildcard), plus its own site's origins: prod's `alt-army-prod.firebaseapp.com` and
`alt-army-prod.web.app`, and its custom domain `alt-army.com` and `www.alt-army.com`; staging's
`alt-army-staging.firebaseapp.com`, `alt-army-staging.web.app` and the staging channel
`alt-army-prod--staging-hn1s06um.web.app`. To serve the front end from another origin, pass
the full list again, since the update replaces it; a custom domain needs adding to Auth's authorized domains
too.

```powershell
# prod
gcloud services api-keys update 9856a0a7-d9e2-4b98-ad97-543f83f7bb5b --project alt-army-prod `
  --billing-project alt-army-prod `
  --api-target=service=identitytoolkit.googleapis.com --api-target=service=securetoken.googleapis.com `
  --api-target=service=firestore.googleapis.com `
  --allowed-referrers="http://localhost:5173/*,http://localhost:8600/*,http://127.0.0.1:5173/*,http://127.0.0.1:8600/*,https://alt-army-prod.firebaseapp.com/*,https://alt-army-prod.web.app/*,https://alt-army.com/*,https://www.alt-army.com/*"
# staging (its key id: gcloud services api-keys list --project alt-army-staging --billing-project alt-army-prod)
gcloud services api-keys update <staging key id> --project alt-army-staging `
  --billing-project alt-army-prod `
  --api-target=service=identitytoolkit.googleapis.com --api-target=service=securetoken.googleapis.com `
  --api-target=service=firestore.googleapis.com `
  --allowed-referrers="http://localhost:5173/*,http://localhost:8600/*,http://127.0.0.1:5173/*,http://127.0.0.1:8600/*,https://alt-army-staging.firebaseapp.com/*,https://alt-army-staging.web.app/*,https://alt-army-prod--staging-hn1s06um.web.app/*"
```

### Deploy

The site runs on Google Cloud in `alt-army-prod` (us-central1). The config is in the repo:
`Dockerfile`, `firebase.json` / `firebase.staging.json` (Hosting) and `deploy/`.

| Piece | What |
|-------|------|
| Firebase Hosting | serves `frontend/dist`; `/api/**` rewrites to Cloud Run. Prod is the live site; staging is the `staging` preview channel (https://alt-army-prod--staging-hn1s06um.web.app, expires 30 days after its last deploy) |
| Cloud Run services | `altarmy` (min 0, max 2) and `altarmy-staging` (max 1): the API, 1 vCPU, 1 GiB. Instances never migrate |
| Cloud Run jobs | the same image running the CLI: `altarmy-migrate` (each deploy, before the service), `altarmy-ingest-tbc` / `-forever` (`ingest --only-if-new`: daily, and at the end of each deploy), `altarmy-prune`, `altarmy-merge`. Staging has the same, prefixed `altarmy-staging-` |
| Cloud Scheduler | ingest tbc 09:00 UTC, ingest forever 09:15, prune 10:00, merge hourly at :30 (`deploy/setup.sh scheduler prod`); staging's the same 5 minutes later (`scheduler staging`); run as `altarmy-scheduler` |
| Cloud SQL | `altarmy-pg`: Postgres 16, db-f1-micro, databases `altarmy` and `altarmy_staging` |
| Secret Manager | `database-url`, `database-url-staging`: each database's `DATABASE_URL` (Cloud Run's Cloud SQL socket) |
| Service accounts | `altarmy-run` (prod's service and jobs), `altarmy-staging-run` (staging's), `altarmy-scheduler`, `altarmy-deploy` (CI) |
| Firebase Auth | prod: `alt-army-prod`; staging: `alt-army-staging`, a free Spark project (see "Firebase projects") |
| Firestore | price signals only (`priceSignals/<auction house id>`: the price version, never prices), in each environment's Firebase project; the API and jobs write them, signed-in browsers read them (`firestore.rules`, deployed with Hosting). Within the free tier |
| Alerts | Cloud Monitoring's alert policies (a job failed; `price_observations` needs partitioning) and Error Reporting notify the basic-auth webhook channel "altarmy Discord", which calls `altarmy-alerts` (a public Cloud Run service on prod's image, `altarmy-site alert-relay`, refusing requests without the channel's password, secret `alerts-relay-password`), which posts them to a Discord channel's webhook (secret `discord-webhook`). On Cloud Run the service and jobs log JSON lines (`cloudlog.py`), so every exception is an Error Reporting event |

About $9 to 11 a month, nearly all of it Cloud SQL; Cloud Run stays in its free tier at hobby traffic.
Staging adds little: its database shares the Cloud SQL instance, its Auth project has no billing, and its
five Cloud Scheduler jobs are about $0.50 a month (3 per billing account are free, $0.10 each after).

Deploys come from GitHub Actions (`.github/workflows/deploy.yml`). After `check` passes on a push to main,
it deploys prod; **Run workflow** deploys staging (or prod). It signs in through Workload Identity
Federation and needs two repository variables (Settings → Secrets and variables → Actions → Variables):

- `GCP_WIF_PROVIDER` = `projects/516573536063/locations/global/workloadIdentityPools/github/providers/github-actions`
- `GCP_DEPLOY_SA` = `altarmy-deploy@alt-army-prod.iam.gserviceaccount.com`

By hand (Git Bash, with gcloud and the Firebase CLI signed in; no Docker needed):

```bash
IMAGE=$(BUILDER=cloudbuild deploy/build.sh)   # build on Cloud Build, push to Artifact Registry
deploy/deploy.sh staging "$IMAGE"             # jobs, migrate*, service, front end to the staging channel, ingest* (*: if changed)
deploy/deploy.sh prod "$IMAGE"
```

Each deploy ends by running both ingest jobs side by side: they reload the game data when the build, the
ingest code (`ingest.py`, `itemstats.py`, `spelltext.py`) or the version's hand-maintained CSVs changed
(`ingest.fingerprint`, kept in `game_versions.ingest_fingerprint`), and otherwise stop at once. A Cloud Run
job takes minutes to start, so the deploy runs the ingest jobs only when one of those files (or
`data/game-data.json`) changed since the commit the service runs (its image's tag), and the migrate job only
when something under `migrations/` did; an image tag that isn't a commit in the checkout, or `DEPLOY_ALL=1`,
runs both. A new
database gets its game data the same way, or by hand: `gcloud run jobs execute altarmy-ingest-tbc --wait`
(prod) or `altarmy-staging-ingest-tbc` (staging)
(add `--region us-central1 --project alt-army-prod --billing-project alt-army-prod` to both).

`deploy/setup.sh` holds the one-time setup, one section per run: APIs, registry, service accounts and
roles, Cloud SQL, each database's user and secret, Firestore for the price signals (both Firebase projects;
before the first deploy that ships `firestore.rules`), Workload Identity Federation, the schedules, the
long-term price archive's bucket (`deploy/setup.sh archive prod|staging`, before the first deploy whose prune
job writes to it), and alerts to Discord (below). Every
command passes `--project alt-army-prod --billing-project alt-army-prod`, so gcloud's defaults don't matter.

The long-term archive: the daily prune job first writes every settled day (32 days old: an upload may carry a
scan 30 days old) to the environment's bucket (`gs://alt-army-prod-archive/`, staging's
`gs://alt-army-prod-archive-staging/`) as gzipped JSON lines, `snapshots/`, `price_daily/` and
`price_sales_daily/` under `YYYY/MM/YYYY-MM-DD.jsonl.gz`: each snapshot with its observations and its full
scan (an Alt Army scan's every price level, a feed snapshot's every auction), never who uploaded it. Then it
drops only what the archive holds (`archive_progress`): full scans at once, snapshots after 45 days, daily
rows after 400. Nothing everyday reads further back than 30 days. To look at history, e.g. with DuckDB:
`gcloud storage cp -r gs://alt-army-prod-archive/snapshots/2026 . && duckdb -c "select realm, count(*) from
read_json_auto('2026/*/*.jsonl.gz') group by 1"`.

Alerts to Discord, once, after a prod deploy: make a webhook in the Discord channel (its settings →
Integrations → Webhooks), then `deploy/setup.sh discord` (asks for the webhook URL; makes the relay, its
password and the webhook notification channel) and `deploy/setup.sh alerts` (the policies). Then, in the
console, Error Reporting → Configure notifications → pick "altarmy Discord": Error Reporting has no gcloud
command for it, and notifies only email, Slack and webhooks (hence a webhook, not Pub/Sub). It notifies on
each new error and on a resolved one coming back. To try the path (curl asks for the password, which
`gcloud secrets versions access latest --secret alerts-relay-password` prints):
`curl -u altarmy -H 'Content-Type: application/json' -d '{"incident": {"policy_name": "test", "summary": "hello"}}' https://altarmy-alerts-516573536063.us-central1.run.app/`.

### Development

`npm run dev` in the repo root runs the same code as the site, locally:

- the Firebase Auth emulator (`firebase.json`, project `demo-altarmy`, 127.0.0.1:9099; needs Java 11+), so
  sign-in and accounts (the site's, the watcher's and Alt Army Sync's) work offline and create no real users;
- the Firestore emulator (127.0.0.1:8080), where the API and the CLI's `merge` (with
  `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` and `FIREBASE_PROJECT_ID=demo-altarmy`) write price signals, so an
  open page refetches and says "Prices updated";
- the API on :8600 (`altarmy-site serve` via the venv, `scripts/dev-api.mjs`), on the SQLite file
  `data/altarmy.sqlite` (or `DATABASE_URL`), migrated on start; once it answers, the script runs
  the merge (`altarmy-site merge`) in the background (`npm run dev:api -- --no-prices` skips it);
- once both answer, Vite on http://localhost:5173, which it opens. Vite hot-reloads the React code and
  proxies `/api` to the API; press Ctrl+C and rerun for Python changes.

A fresh database needs game data first: `altarmy-site ingest` (and `altarmy-site --game-version tbc
ingest`); `serve` says so when it is missing. Prices come in as on the site: scan with Alt Army in game, then
upload `AltArmy_TBC.lua` on the Upload page, or point the watcher or Alt Army Sync at
`http://127.0.0.1:8600`.
Uploads don't merge: run `altarmy-site merge` for the 7-day medians. Emulator accounts are forgotten when it
stops; to keep them, run `npx firebase emulators:start --only auth --project demo-altarmy --import
.firebase/auth-emulator --export-on-exit` yourself (the folder must exist).

`npm run dev:staging-auth` signs in against the real staging Firebase project (`staging.env`) instead, so
accounts made while developing never land in prod's; it sends no price signals (`PRICE_SIGNALS=off`). After changing the
API's models or routes, regenerate the TypeScript types with `python scripts/export_openapi.py` and
`npm run gen-types` (`check.py` does both). Tests never need Firebase: they pass a fake token verifier to
`create_app`.

## Data notes

- **The addon's Waylaid Crates.** After ingesting WoW: Forever into a SQLite file, `ingest` runs the Alt Army
  addon's `scripts/generate-waylaid-crates.py` against it (`src/altarmy_site/addon_crates.py`), when the addon
  is checked out next to the site (the monorepo's `../addon`, or `ALTARMY_ADDON_DIR`). A changed crate list then shows up
  as a change to commit there. The hosted jobs (Postgres, no addon) skip it, and a failure never fails the ingest.
- Pinned builds: `data/game-data.json` (each version's wago.tools build and the emulator release its CSVs
  came from), shared with the addon and moved by the monorepo's `game_data.py` (the daily game-data
  workflow, which also regenerates the CSVs and cities and commits them; the deploy then loads the new
  build). Pass `--build <version>` or `--build latest` for another. The build actually loaded is stored in
  the `game_versions` table.
- **Price history.** Every import is a snapshot (`price_snapshots`); it records observations only for
  items whose price or last-seen day moved (`price_observations`, pruned after 45 days once archived) and updates
  `price_current`, which the ranking reads. Each scan's market price (TBC: Auctionator's per-day
  high/low/available) goes to `price_daily` (pooled across uploaders: lowest low, highest high), which
  is kept indefinitely.
- **The order book.** An Alt Army scan reads every listing; per item the site keeps the units listed at
  each price, cheapest first. What a plan pays for a reagent is a walk up that ladder for the quantity
  it needs, so one cheap listing is one cheap unit. A plan needing more than is listed is flagged. An
  item missing from the newest scan is not listed: it cannot be bought on the AH. A cheap listing
  first seen in the newest scan, under half the item's usual price, is not counted on. Sellers are
  never stored.
- **Buy and sell prices.** Reagents are bought up the order book. A craft (and disenchant materials)
  sells for the lower of the market price (the price 15% of the way into the listed units) and what the
  item goes for: what it sold for over the last week, inferred from the units that left the cheap end
  of the book between scans at most 30 minutes apart, else its 7-day median (the median of its daily
  medians over its latest 7 days with data in the last 30). So a lone overpriced listing (a 2g bag
  listed at 2,700g) isn't taken for the going rate. A sale that may take over 2 days at the rate the
  item sold lately is flagged; where nothing is known of its sales, one resting on fewer than 5 listed
  units, or fewer than the plan sells. The merge (`altarmy-site merge`, hourly on the site) fills
  the medians and sale figures; prices set by hand are used as they are.
- **Disenchant results are not in DB2** (they are server-side loot tables). `data/<version>/disenchant.csv`
  (`item_class,quality,min_ilvl,max_ilvl,result_item_id,chance,min_count,max_count`) holds the rates.
  Forever's are Classic-era rates, derived from the brackets Auctionator uses for Classic clients, and
  cover greens ilvl 5–65, blues 11–65, epics 40–80. Counts within a row are assumed uniform.
  Forever-specific rates are not yet published — verify against Wowhead's Forever database as data comes
  in, then re-run `altarmy-site ingest`. TBC's are generated from the TBC client's Auctionator
  (one row per count) by `python scripts/build_disenchant.py`.
- **Arcane Salvager** (WoW: Forever): an Enchanting-made station (recipe spell 1263056). Near it a
  disenchant has a 10% chance of a second roll of the same table, so with the search's Arcane Salvager
  option every disenchant sale (flips included) is worth 1.1 times its expected
  materials. The 10% is the players' understanding, not yet measured in game.
- **Essence conversions** (3 Lesser Astral Essence into 1 Greater and back) come from DB2: an item whose Use
  effect consumes it (negative charges) and casts a spell creating another item, the spell's reagents (if
  any) being more of the same item, with both items disenchant results in `disenchant.csv` (so only
  enchanting materials: Magic, Astral, Mystic, Nether and Eternal essences on Forever, Planar too on TBC).
  Ingest stores each as a `recipes` row of `kind` `convert` (id 1,000,000,000 + its spell id, no
  profession, input count 1 + the spell's reagents). Anyone converts, it never skills anyone up, and it is
  ranked only when Sell via includes Disenchant and nobody is being skilled up; its output then sells on the
  AH even if Auction house is unticked, the same bet on enchanting materials' prices. Chains also use a
  conversion to get a reagent when that is cheaper; what a conversion converts is always bought.
- **Buy-and-disenchant flips**: gear on the AH listed below what its disenchant materials are expected to
  fetch. Every item that can be disenchanted (greens, blues and epics the disenchant rows cover, not flagged
  NO_DISENCHANT) and can be bought on the AH gets a flip, made by the engine for each market (`kind` `flip`,
  id 2,000,000,000 + the item id, never stored): buy it, disenchant it, sell the materials. A session buys
  the batch up the item's listings, cheapest first, but never more units than are listed (one where only a
  cheapest-listing price is known). Like conversions it needs no profession, never skills anyone up and
  ranks only when Sell via includes Disenchant (and an enchanter can disenchant it); it is only ever
  disenchanted, and it is never a way to get a reagent. Brand-new listings under half the item's 7-day
  median are not counted on (`prices.load_books`), so a stray one-off bargain doesn't show up: it is
  usually gone before anyone gets there.
- **Vendor-sold items are not in DB2** (vendor inventories are server-side). `data/<version>/vendor_items.csv`
  (`item_id,name`) lists the items vendors sell with unlimited stock and no reputation or event condition
  (TBC: and no honor or badge cost), taken from [vmangos](https://github.com/vmangos/core)' vanilla world
  database for Forever and [cmangos](https://github.com/cmangos/tbc-db)' for TBC by
  `python scripts/build_vendor_items.py --game-version forever|tbc` (at the pinned release; `game_data.py`
  runs it). The price is DB2's `BuyPrice` per
  `VendorStackCount`, rounded up to whole copper. Reagents are bought from whichever of vendor and AH is
  cheaper. Forever may differ from vanilla; edit the CSV and re-run `altarmy-site ingest` if a vendor
  item is missing or wrong.
- **Reputation discounts.** A vendor takes 10% off for a buyer who is Honored or better with the vendor's
  faction (vanilla's rule, `GameVersion.reputation_discounts`; it adds to the Bartering talent's discount,
  an assumption until a vendor's price in Forever has been compared). Which faction a vendor belongs to
  comes from vmangos too, per vendor (`vendor_reputations` in the city presets): Ironforge and Stormwind
  have gnome vendors, Orgrimmar troll ones. The characters' standings come from the Alt Army addon, for
  the eight city factions only. The discount needs a city preset, so there is none on TBC or in the CLI's
  ranking. Vanilla's second 10% for PvP rank 3 is not counted.
- Recipe output count comes from `SpellEffect.EffectBasePointsF` (Forever) or `EffectBasePoints` plus the
  average `EffectDieSides` roll (TBC); see `ingest.output_count`. Cast time comes from `SpellMisc`'s
  `CastingTimeIndex` into `SpellCastTimes`, and the station a craft needs (anvil, cooking fire, loom, ...)
  from `SpellCastingRequirements.RequiresSpellFocus`'s `SpellFocusObject` name.
- **City presets** (`data/forever/cities/*.json`) say where the auction house (the hub every character
  starts at; nobody runs back after their last action), mailboxes, anvils, forges, cooking fires and
  vendors (with what they sell) stand,
  taken from vmangos' world database by `python scripts/build_cities.py` (patch 1.12 spawns within a
  radius of each city's teleport point; `cities.CITY_SPECS`). Running time is straight-line distance
  times a detour factor over the run speed. Measured times go in a preset's `overrides`, which
  regenerating keeps: `travel` (`{"ah|mailbox:123": 12.5}` seconds), `detour` (e.g. 1.8 for Undercity's
  levels), `hub`, `drop` (location ids) and `locations` (added or moved, e.g. `{"id": "anvil:9", "kind":
  "anvil", "name": "Anvil", "x": 1650, "y": -4410, "z": 21}`). Positions are world coordinates, not map
  percentages: standing there, `/dump UnitPosition("player")` prints them (check its order against a known
  spot, such as the preset's auction house). WoW: Forever's new stations (spinning wheel, sewing machine,
  tanning rack, loom, master forge, iron oven, ...; `timing.DEPLOYABLE`) are not in vmangos. For now they
  count as set down where the crafter stands: always there, no running. A plan still names them. Restart
  the API to load them. A plan needing a station a city lacks is flagged and never recommended there;
  a vendor item no vendor in the city sells is timed at the nearest vendor. TBC has no presets yet: its
  plans are timed "Anywhere" (actions and switches, no running).

## Layout

- `src/altarmy_site/versions.py` – the game versions (TBC Anniversary, Forever): data files,
  wago.tools product, WoW flavor folder, AH cut and postage
- `src/altarmy_site/db.py`, `schema.py`, `migrations/` – the database (SQLAlchemy Core, SQLite or
  Postgres), its tables and Alembic migrations
- `src/altarmy_site/ingest.py` – download + load DB2 CSVs; `addon_crates.py` – regenerate the Alt Army
  addon's Waylaid Crates table after a local Forever ingest
- `src/altarmy_site/engine.py` – pure profit/chain logic (no I/O), covered by `tests/`
- `src/altarmy_site/timing.py` – pure play-time model (action seconds, city maps, routes, per-hour
  rates); `cities.py` builds city presets from vmangos spawns (`scripts/build_cities.py`)
- `src/altarmy_site/prices.py` – the price store (auction houses, snapshots, current and daily prices,
  screening uploads, coverage); `book.py` reads Alt Army's auction house scans and prices from their
  ladders; `auctionator.py` parses Auctionator's SavedVariables (TBC);
  `merge.py` – daily medians and 7-day statistics
- `src/altarmy_site/altarmy.py` – characters and learned recipes from Alt Army's SavedVariables (`luasv.py` parses them)
- `src/altarmy_site/auth.py`, `users.py` – users and tiers (Firebase token verification), each user's
  settings and trust; `signin.py` – the watcher's and Alt Army Sync's email sign-in
- `src/altarmy_site/uploads.py`, `watch.py` – uploaded addon files (parse, pool, history, rate limit)
  and the CLI watcher that sends them; `paste.py` – the Alt Army addon's export string; `wowfiles.py` –
  where WoW keeps SavedVariables; `tray.py`, `tray_core.py` – Alt Army Sync, the Windows uploader
- `src/altarmy_site/store.py` – load the database into engine dataclasses
- `src/altarmy_site/service.py`, `api.py` – use-cases and the FastAPI JSON API behind the site
- `src/altarmy_site/cli.py` – command line; `ratelimit.py` – the API's per-IP and per-user limits
- `Dockerfile`, `firebase.json`, `deploy/`, `.github/workflows/deploy.yml` – the deploy (see Deploy)
- `src/altarmy_site/vmangos.py`, `cmangos.py`, `disenchant_rates.py` – sources for the hand data files
- `scripts/bench_rank.py` (ranking timings), `scripts/probe_blizzard_api.py` (Blizzard AH API check)
- `frontend/` – Vite + React + TypeScript + Mantine front end
- `docs/` – plans: `HOSTED_PLAN.md` (the move to a hosted, multi-user site), `ROADMAP_IDEAS.md` (feature ideas)

## Roadmap

1. Verify ingest against known recipes on a real build.
2. ~~Auctionator SavedVariables importer~~ (done: uploads, the watcher and Alt Army Sync).
3. ~~Web UI~~ (done: React + FastAPI). Next: filter by skill level, which needs real required-skill data.
4. Recipe availability (who learns what / trainer vs. drop), auction volume and price-history risk.
5. ~~Hosted, multi-user site~~ (done: see [docs/HOSTED_PLAN.md](docs/HOSTED_PLAN.md)).
