"""deploy/deploy.sh skips the ingest jobs unless INGEST_INPUTS changed: it must name what `ingest.fingerprint`
reads, or a deploy would leave game data made by old ingest code."""

import fnmatch
import re
from pathlib import Path

from altarmy_site import gamedata, ingest, versions

SITE = Path(__file__).resolve().parents[1]


def _ingest_inputs() -> list[str]:
    script = (SITE / "deploy" / "deploy.sh").read_text()
    match = re.search(r"^INGEST_INPUTS=\((.*?)\)", script, re.MULTILINE | re.DOTALL)
    assert match, "deploy.sh defines INGEST_INPUTS"
    return [word.strip("'\"") for word in match.group(1).split()]


def _covered(path: Path, patterns: list[str]) -> bool:
    relative = path.resolve().relative_to(SITE).as_posix()
    return any(relative == p or fnmatch.fnmatchcase(relative, p) for p in patterns)


def test_deploy_skips_ingest_only_when_nothing_the_fingerprint_reads_changed() -> None:
    patterns = _ingest_inputs()
    for module in ingest.FINGERPRINTED_MODULES:
        assert _covered(module, patterns), module
    for version in versions.VERSIONS.values():
        for csv in (
            version.disenchant_csv,
            version.vendor_csv,
            version.vendor_recipes_csv,
            version.sources_csv,
            version.trainer_costs_csv,
            version.vendor_overrides_csv,
        ):
            assert _covered(SITE / csv, patterns), csv
    assert _covered(SITE / gamedata.PINS, patterns)
