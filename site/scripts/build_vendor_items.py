"""Regenerate data/<version>/vendor_items.csv (and Forever's vendor_recipes.csv, recipe_item_sources.csv and
trainer_costs.csv) from an open-source world database.

Forever (vanilla-based) reads vmangos' database, TBC reads cmangos' tbc-db: by default the release pinned in
data/game-data.json, from the repo's .cache/ (`gamedata.world_db`), and the zone maps of the pinned build.
Forever's trainer_costs.csv also says how far the game moved each spell's colours down from vanilla's
(`ingest.yellow_shifts`, against the reference build: by default TBC Anniversary's pinned one), since vmangos'
trainers ask for vanilla's skill.
Usage: python scripts/build_vendor_items.py [--game-version forever|tbc] [--build B] [--world-db SQLITE]
       [--reference-build B]
The monorepo's game_data.py runs this with the builds and releases it moves the pins to. Then run that
version's game data update (or `altarmy-site --game-version <v> ingest`) to load it.
"""

import argparse
import sqlite3
from pathlib import Path

from altarmy_site import cmangos, gamedata, ingest, versions, vmangos

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--game-version", choices=list(versions.VERSIONS), default=versions.DEFAULT_VERSION)
    p.add_argument("--build", help="the DB2 build whose zone maps place sources (default: the pinned build)")
    p.add_argument(
        "--world-db", type=Path, help="the emulator's world database (default: the pinned release)"
    )
    p.add_argument(
        "--reference-build",
        help="the build whose colours Forever's are compared with (default: TBC Anniversary's pinned build)",
    )
    args = p.parse_args()
    version = versions.VERSIONS[args.game_version]
    source = cmangos if args.game_version == "tbc" else vmangos
    out = ROOT / version.vendor_csv
    pins = gamedata.read_pins(ROOT / gamedata.PINS)
    pin = pins[version.key]
    build = args.build or pin.build
    world = args.world_db or source.download_world_db(gamedata.REPO_CACHE, pin.release)
    conn = sqlite3.connect(world)
    rows = source.vendor_items(conn)
    # Forever binds most recipes on pickup, so ingest needs to know which of them a vendor sells
    recipes = vmangos.vendor_recipes(conn) if source is vmangos else None
    fees = vmangos.trainer_costs(conn) if source is vmangos else None
    # where recipe items come from, placed in the client's zone maps
    sources = None
    if source is vmangos:
        ui = {t: ingest.download(t, build, gamedata.REPO_CACHE) for t in ("UiMapAssignment", "UiMap")}
        sources = vmangos.recipe_item_sources(conn, ingest.zone_boxes(ui["UiMapAssignment"], ui["UiMap"]))
    conn.close()
    out.parent.mkdir(parents=True, exist_ok=True)
    vmangos.write_csv(rows, out)
    print(f"wrote {len(rows)} vendor items to {out}")
    if recipes is not None:
        recipes_out = ROOT / version.vendor_recipes_csv
        vmangos.write_csv(recipes, recipes_out)
        print(f"wrote {len(recipes)} vendor recipes to {recipes_out}")
    if sources is not None:
        sources_out = ROOT / version.sources_csv
        vmangos.write_sources_csv(sources, sources_out)
        print(f"wrote {len(sources)} recipe item sources to {sources_out}")
    if fees is not None:
        fees_out = ROOT / version.trainer_costs_csv
        reference = args.reference_build or pins["tbc"].build
        sla = [ingest.download("SkillLineAbility", b, gamedata.REPO_CACHE) for b in (build, reference)]
        vmangos.write_trainer_costs_csv(fees, fees_out, ingest.yellow_shifts(*sla))
        print(f"wrote {len(fees)} trainer costs to {fees_out}")


if __name__ == "__main__":
    main()
