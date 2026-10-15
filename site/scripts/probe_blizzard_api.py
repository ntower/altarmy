"""Check whether Blizzard's Game Data API serves auction house data for a Classic namespace, and what it looks
like: the run that settles the hourly snapshot feed (`snapshots.py`) on launch day.

Needs a Battle.net API client (https://develop.battle.net/access/clients, "Create client"; any redirect URL):
    set BLIZZARD_CLIENT_ID=...   and   set BLIZZARD_CLIENT_SECRET=...
Usage: python scripts/probe_blizzard_api.py [--region us] [--namespace dynamic-classic1x ...]
           [--realm Dreamscythe ... | --list] [--sample 5] [--save DIR]

For each namespace (each given with `--namespace`, without the region; default: the Classic ones) it lists
the connected realms, picks the named realms (`--list`: every one), and asks for their auction house index
and each house's auctions. It prints statuses, auction counts and, with `--sample N`, the fields of the first
N auctions, every time-left value seen, whether stacks carry a `buyout` or a `unit_price`, and the
Last-Modified header. `--save DIR` writes each house's body as served (for `altarmy-site feed-load` and the
test fixtures). Nothing else is stored. Record the outcome in docs/HOSTED_PLAN.md ("Phase 0 findings").
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Any

NAMESPACES = ("dynamic-classicann", "dynamic-classic1x", "dynamic-classic")  # + "-<region>"


def token(region: str, client_id: str, secret: str) -> str:
    auth = base64.b64encode(f"{client_id}:{secret}".encode()).decode()
    req = urllib.request.Request(
        f"https://{region}.battle.net/oauth/token",
        data=b"grant_type=client_credentials",
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return str(json.load(resp)["access_token"])


def fetch(url: str, tok: str) -> tuple[int, bytes, dict[str, str]]:
    """(status, body, headers); the body is empty on an error status."""
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, resp.read(), dict(resp.headers.items())
    except urllib.error.HTTPError as e:
        return e.code, b"", dict(e.headers.items())


def get(url: str, tok: str) -> tuple[int, Any]:
    status, body, _ = fetch(url, tok)
    return status, json.loads(body) if status == 200 and body else None


def _name(value: object) -> str:
    """A realm name: a string with `locale`, else (the index's links carry no locale) a map of locales."""
    if isinstance(value, dict):
        value = value.get("en_US") or next(iter(value.values()), "")
    return value if isinstance(value, str) else ""


def describe(body: Any, sample: int) -> None:
    """The first `sample` auctions' fields, the time-left values and which price field stacks carry."""
    auctions = body.get("auctions", []) if isinstance(body, dict) else []
    for a in auctions[:sample]:
        print(f"      {json.dumps(a, sort_keys=True)}")
    left = Counter(a.get("time_left") for a in auctions if isinstance(a, dict))
    priced = Counter(
        "unit_price" if "unit_price" in a else "buyout" if a.get("buyout") else "bid only"
        for a in auctions
        if isinstance(a, dict)
    )
    print(f"      time left: {dict(left)}; priced by: {dict(priced)}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--region", default="us")
    p.add_argument("--namespace", action="append", help="a namespace without the region (repeatable)")
    p.add_argument("--realm", action="append", help="realm name to look for (repeatable)")
    p.add_argument("--list", action="store_true", help="every connected realm, not only the named ones")
    p.add_argument("--sample", type=int, default=0, help="print the first N auctions of each house")
    p.add_argument("--save", type=Path, help="write each house's body as served into this folder")
    args = p.parse_args()
    realms = {r.lower() for r in (args.realm or ["Dreamscythe", "Nightslayer"])}
    client_id, secret = os.environ.get("BLIZZARD_CLIENT_ID"), os.environ.get("BLIZZARD_CLIENT_SECRET")
    if not client_id or not secret:
        sys.exit("Set BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET (see this script's docstring).")
    if args.save:
        args.save.mkdir(parents=True, exist_ok=True)
    tok = token(args.region, client_id, secret)
    api = f"https://{args.region}.api.blizzard.com"
    for base in args.namespace or NAMESPACES:
        ns = f"{base}-{args.region}"
        q = "?" + urllib.parse.urlencode({"namespace": ns, "locale": "en_US"})
        status, index = get(f"{api}/data/wow/connected-realm/index{q}", tok)
        print(f"{ns}: connected-realm index -> {status}")
        if status != 200:
            continue
        for link in index.get("connected_realms", []):
            status, cr = get(link["href"], tok)
            names = {_name(r.get("name")) for r in (cr or {}).get("realms", [])}
            if status != 200 or not (args.list or {n.lower() for n in names} & realms):
                continue
            cid = cr["id"]
            status, houses = get(f"{api}/data/wow/connected-realm/{cid}/auctions/index{q}", tok)
            print(f"  {', '.join(sorted(names))} (connected realm {cid}): auctions index -> {status}")
            for house in (houses or {}).get("auctions", []):
                hid = house.get("id")
                status, raw, headers = fetch(f"{api}/data/wow/connected-realm/{cid}/auctions/{hid}{q}", tok)
                body = json.loads(raw) if status == 200 and raw else None
                count = len((body or {}).get("auctions", []))
                modified = headers.get("Last-Modified", "-")
                print(
                    f"    auction house {hid} ({_name(house.get('name'))}): {status}, {count} auctions,"
                    f" Last-Modified {modified}"
                )
                if body is not None and args.sample:
                    describe(body, args.sample)
                if body is not None and args.save:
                    out = args.save / f"{ns}-{cid}-{hid}.json"
                    out.write_bytes(raw)
                    print(f"      saved {out}")


if __name__ == "__main__":
    main()
