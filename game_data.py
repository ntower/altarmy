#!/usr/bin/env python3
"""Keep both halves' game data on one pin: python game_data.py status|update|release-addon

Run it from the monorepo root with the site's venv (site/.venv/Scripts/python game_data.py ...): the site's
generators import its package. The daily game-data workflow (.github/workflows/game-data.yml) runs all three.

  status         prints GitHub step output lines: each version's pinned and latest wago.tools build and
                 emulator release, `moved` (any differs), `game_patch` (a build's major.minor.patch moved:
                 the TOC's interface and the CurseForge versions then need a person) and a cache key.
  update         regenerates everything made from the game data, at the newest builds and releases
                 (`--to latest`, the default) or at the pins (`--to pinned`: a clean checkout must come out
                 unchanged), then writes the pins (site/data/game-data.json; an emulator release that
                 changed no generated file leaves its pin alone, a new build never does):
                   addon  data/recipes/<v>/*.csv (build-recipe-server-facts.py),
                          AltArmy_TBC/Data/Recipes/RecipeData_*.lua (generate-recipe-data.py),
                          AltArmy_TBC/Data/Economy/WaylaidCrates.lua (generate-waylaid-crates.py) and
                          Writs.lua (generate-writs.py), both from a throwaway SQLite ingest of Forever
                   site   data/<v>/vendor_items.csv, vendor_recipes.csv, recipe_item_sources.csv,
                          trainer_costs.csv (build_vendor_items.py), data/forever/cities/*.json (build_cities.py),
                          frontend/public/maps/ (fetch_zone_maps.py: new areas only)
                 --message FILE writes a commit message (a subject line, then what moved and changed);
                 --notes FILE the addon's release notes (one line per changed data file; empty when the
                 addon ships nothing new).
  release-addon  releases the addon (release.py addon --patch) when its shipped files changed since the
                 newest addon-v* tag and every such change is generated game data. Hand-written addon work
                 waiting on main is never released by this: then it says so and waits for a person's release.

Standard library only (gamedata.py and versions.py are loaded by their paths).
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parent
SITE = ROOT / "site"
ADDON = ROOT / "addon"
PINS = SITE / "data" / "game-data.json"
RECIPE_DATA = {
    "tbc": ADDON / "AltArmy_TBC" / "Data" / "Recipes" / "RecipeData_TBC.lua",
    "forever": ADDON / "AltArmy_TBC" / "Data" / "Recipes" / "RecipeData_Forever.lua",
}
CRATES = ADDON / "AltArmy_TBC" / "Data" / "Economy" / "WaylaidCrates.lua"
WRITS = ADDON / "AltArmy_TBC" / "Data" / "Economy" / "Writs.lua"
# What release-addon may ship unattended: the files this script generates into the addon
GENERATED = {p.relative_to(ROOT).as_posix() for p in (*RECIPE_DATA.values(), CRATES, WRITS)}
SHIPPED = "addon/AltArmy_TBC"


def load(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


gamedata = load("gamedata", SITE / "src" / "altarmy_site" / "gamedata.py")
versions = load("versions", SITE / "src" / "altarmy_site" / "versions.py")


def run(*cmd: str | Path, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print("$", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, check=True)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def targets(to: str) -> dict:  # version -> gamedata.Pin
    """Each version's pin to regenerate at: the pins themselves, or the newest build and release."""
    pins = gamedata.read_pins(PINS)
    if to == "pinned":
        return dict(pins)
    return {
        key: gamedata.Pin(
            gamedata.latest_build(versions.VERSIONS[key].wago_product),
            pin.emulator,
            gamedata.latest_release(pin.emulator)[0],
        )
        for key, pin in pins.items()
    }


def patch(build: str) -> str:
    return ".".join(build.split(".")[:3])


def cmd_status(_: argparse.Namespace) -> None:
    pins = gamedata.read_pins(PINS)
    latest = targets("latest")
    lines = []
    for key in sorted(pins):
        lines += [
            f"{key}_pinned={pins[key].build} {pins[key].release}",
            f"{key}_build={latest[key].build}",
            f"{key}_release={latest[key].release}",
        ]
    moved = any(pins[k] != latest[k] for k in pins)
    game_patch = any(patch(pins[k].build) != patch(latest[k].build) for k in pins)
    key = "-".join(f"{latest[k].build}-{latest[k].release}" for k in sorted(latest))
    lines += [
        f"moved={'true' if moved else 'false'}",
        f"game_patch={'true' if game_patch else 'false'}",
        f"cache_key=game-data-{hashlib.sha256(key.encode()).hexdigest()[:16]}",
    ]
    print("\n".join(lines))


def head_rows(path: Path) -> int | None:
    """Data rows of a CSV as committed at HEAD, None when it isn't."""
    try:
        text = git("show", f"HEAD:{path.relative_to(ROOT).as_posix()}")
    except subprocess.CalledProcessError:
        return None
    return max(0, len(text.splitlines()) - 1)


def rows(path: Path) -> int:
    with open(path, encoding="utf-8") as f:
        return max(0, sum(1 for _ in f) - 1)


# Where update writes: what it reports on (and all a game-data commit should touch)
OUTPUTS = (
    "site/data",
    "site/frontend/public/maps",
    "addon/data/recipes",
    "addon/AltArmy_TBC/Data/Recipes",
    "addon/AltArmy_TBC/Data/Economy",
)


def changed_files() -> list[str]:
    """Generated paths (from the root) whose content differs from HEAD, or that are new. Content, not
    timestamps or line endings: a Windows checkout's CRLF files are unchanged when regenerated with LF."""
    edited = git("diff", "--name-only", "HEAD", "--", *OUTPUTS).splitlines()
    new = git("ls-files", "--others", "--exclude-standard", "--", *OUTPUTS).splitlines()
    return sorted({*edited, *new} - {""})


RECIPE_COUNTS = re.compile(r"\*\*(\d+) added\*\*, \*\*(\d+) removed\*\*, \*\*(\d+) changed\*\*")


def cmd_update(args: argparse.Namespace) -> None:
    old = gamedata.read_pins(PINS)
    new = targets(args.to)
    py = sys.executable
    cache = gamedata.REPO_CACHE
    worlds = {key: gamedata.world_db(pin.emulator, cache, pin.release) for key, pin in new.items()}
    tmp = Path(tempfile.mkdtemp(prefix="game-data-"))

    # addon: server facts, then each version's recipe data at its build
    run(
        py,
        "scripts/build-recipe-server-facts.py",
        "--cmangos",
        worlds["tbc"],
        "--vmangos",
        worlds["forever"],
        cwd=ADDON,
    )
    summaries = {}
    for key, pin in new.items():
        summaries[key] = tmp / f"{key}.md"
        run(
            py,
            "scripts/generate-recipe-data.py",
            "--version",
            key,
            "--build",
            pin.build,
            "--summary",
            summaries[key],
            cwd=ADDON,
        )

    # site: what the emulators say about vendors, recipe sources and cities, then the zone maps they show
    for key, pin in new.items():
        run(
            py,
            "scripts/build_vendor_items.py",
            "--game-version",
            key,
            "--build",
            pin.build,
            "--world-db",
            worlds[key],
            # Forever's trainer learn levels follow how far its colours moved from TBC's
            "--reference-build",
            new["tbc"].build,
            cwd=SITE,
        )
    run(
        py,
        "scripts/build_cities.py",
        "--build",
        new["forever"].build,
        "--world-db",
        worlds["forever"],
        cwd=SITE,
    )
    run(py, "scripts/fetch_zone_maps.py", cwd=SITE)

    # Waylaid Crates and Craftsman's Writs: from a throwaway ingest of Forever (its own run below, so a
    # failure fails this)
    db = tmp / "forever.sqlite"
    env = {**os.environ, "ALTARMY_ADDON_DIR": str(tmp / "no-addon")}  # the ingest's own regenerate stays out
    run(
        py,
        "-m",
        "altarmy_site.cli",
        "--db",
        db,
        "--game-version",
        "forever",
        "ingest",
        "--build",
        new["forever"].build,
        "--cache",
        cache,
        cwd=SITE,
        env=env,
    )
    run(py, "scripts/generate-waylaid-crates.py", "--db", db, cwd=ADDON)
    run(py, "scripts/generate-writs.py", "--db", db, "--build", new["forever"].build, cwd=ADDON)

    # The emulators publish a release every day or so, mostly with nothing we use changed: a release that
    # changed no generated file is no news, so the pins keep the one the committed data came from. A new
    # build still moves its pin, since the site's ingest loads it.
    pins = PINS.relative_to(ROOT).as_posix()
    if not [f for f in changed_files() if f != pins]:
        new = {key: gamedata.Pin(pin.build, pin.emulator, old[key].release) for key, pin in new.items()}
    gamedata.write_pins(new, PINS)

    changed = changed_files()
    labels = {key: versions.VERSIONS[key].label for key in new}
    moved = [key for key in sorted(new) if old[key] != new[key]]
    if moved:
        subject = "Game data: " + ", ".join(
            f"{labels[k]} {new[k].build}" if old[k].build != new[k].build else f"{labels[k]} {new[k].release}"
            for k in moved
        )
    else:
        subject = "Game data: regenerated at the pinned builds"
    body = [subject, ""]
    if moved:
        body += ["## Pins", ""]
        for key in moved:
            body.append(
                f"- {labels[key]}: build `{old[key].build}` → `{new[key].build}`, "
                f"{new[key].emulator} `{old[key].release}` → `{new[key].release}`"
            )
        body.append("")
    for key in sorted(new):
        if RECIPE_DATA[key].relative_to(ROOT).as_posix() in changed:
            body.append(summaries[key].read_text(encoding="utf-8").rstrip())
            body.append("")
    csvs = [f for f in changed if f.endswith(".csv")]
    if csvs:
        body += ["## Data files", ""]
        for f in csvs:
            before = head_rows(ROOT / f)
            body.append(f"- `{f}`: {'new' if before is None else before} → {rows(ROOT / f)} rows")
        body.append("")
    skip = GENERATED | {PINS.relative_to(ROOT).as_posix()}
    others = [f for f in changed if not f.endswith(".csv") and f not in skip]
    for generated in (WRITS, CRATES):  # the generated Lua worth naming, first
        if generated.relative_to(ROOT).as_posix() in changed:
            others.insert(0, generated.relative_to(ROOT).as_posix())
    if others:
        body += ["## Other files", ""] + [f"- `{f}`" for f in others] + [""]
    if not changed:
        body.append("Nothing changed.")
    if args.message:
        Path(args.message).write_text("\n".join(body).rstrip() + "\n", encoding="utf-8")

    notes = []
    for key in sorted(new):
        if RECIPE_DATA[key].relative_to(ROOT).as_posix() in changed:
            counts = RECIPE_COUNTS.search(summaries[key].read_text(encoding="utf-8"))
            detail = f": {counts[1]} added, {counts[2]} removed, {counts[3]} changed" if counts else ""
            notes.append(f"Recipe data for {labels[key]} build {new[key].build}{detail}.")
    if CRATES.relative_to(ROOT).as_posix() in changed:
        notes.append("Waylaid Crates updated from the game data.")
    if WRITS.relative_to(ROOT).as_posix() in changed:
        notes.append("Craftsman's Writs updated from the game data.")
    if args.notes:
        Path(args.notes).write_text("".join(n + "\n" for n in notes), encoding="utf-8")
    print("\n".join(body))


def cmd_release_addon(args: argparse.Namespace) -> None:
    try:
        tag = git("describe", "--tags", "--match", "addon-v*", "--abbrev=0")
    except subprocess.CalledProcessError:
        sys.exit("no addon-v* tag to compare with")
    changed = set(git("diff", "--name-only", f"{tag}..HEAD", "--", SHIPPED).splitlines())
    if not changed:
        print(f"The addon has nothing new since {tag}.")
        return
    hand_written = sorted(changed - GENERATED)
    if hand_written:
        say(
            f"Not releasing the addon: besides game data, {len(hand_written)} file(s) changed since {tag} "
            f"({', '.join(hand_written[:5])}{', ...' if len(hand_written) > 5 else ''}). The game data ships "
            "with the next release made with release.py."
        )
        return
    notes = Path(args.notes) if args.notes else None
    if notes is None or not notes.is_file() or not notes.read_text(encoding="utf-8").strip():
        notes = Path(tempfile.mkdtemp(prefix="game-data-")) / "notes.txt"
        notes.write_text("Updated game data.\n", encoding="utf-8")
    run(
        sys.executable,
        "release.py",
        *(["--dry-run"] if args.dry_run else []),
        "addon",
        "--patch",
        "--notes-file",
        notes,
        "--yes",
        "--no-watch",
    )


def say(text: str) -> None:
    """Print, and add to the Actions run's summary when there is one."""
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]  # the summaries' arrows
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status", help="pinned and latest builds and releases (GitHub step output)")
    p = sub.add_parser("update", help="regenerate both halves' game data and write the pins")
    p.add_argument("--to", choices=["latest", "pinned"], default="latest")
    p.add_argument("--message", help="write a commit message here")
    p.add_argument("--notes", help="write the addon's release notes here")
    p = sub.add_parser("release-addon", help="release the addon when only its game data changed")
    p.add_argument("--notes", help="release notes (default: 'Updated game data.')")
    p.add_argument("--dry-run", action="store_true", help="show what release.py would do")
    args = parser.parse_args()
    {"status": cmd_status, "update": cmd_update, "release-addon": cmd_release_addon}[args.cmd](args)


if __name__ == "__main__":
    main()
