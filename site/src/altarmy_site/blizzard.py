"""Blizzard's Game Data API for WoW: Forever's auction houses: the hourly feed's fetcher (`altarmy-site
feed`).

Forever has no connected realms. A region's auction houses (`dynamic-forever-<region>`) are numbered
(110-125) and listed under every ruleset alike, the path's ruleset ignored, so each house is asked for under
`RULESET`; which realm a house is comes from `versions.BLIZZARD_HOUSES`. A house serves its listings
(`auctions/<id>`, a stack `buyout`) and its commodities (`auctions/<id>/commodities`, a `unit_price`) apart;
both change together, about once an hour, and say when in `Last-Modified`. Asked `If-Modified-Since` the
listings answer 304 while nothing changed, so a poll between refreshes downloads nothing.

A client-credentials token (`BLIZZARD_CLIENT_ID`, `BLIZZARD_CLIENT_SECRET`) is fetched once and reused until
shortly before it expires. Standard library only; the transport is injectable for tests. Every failure to
get a house is a `FeedError`.
"""

from __future__ import annotations

import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import format_datetime, parsedate_to_datetime

RULESET = 1  # any ruleset the index lists serves every house of the region
TIMEOUT = 120.0  # seconds per request: a house's listings are about 10 MB
TOKEN_SLACK = 60  # seconds before a token's expiry it is fetched again


class FeedError(Exception):
    """A house (or the token) could not be fetched: its status or what went wrong."""


@dataclass(frozen=True)
class Response:
    status: int
    body: bytes  # empty unless 200
    headers: Mapping[str, str]  # by lower-case name


Transport = Callable[[urllib.request.Request, float], Response]


def urllib_transport(request: urllib.request.Request, timeout: float) -> Response:
    """The request over urllib; an HTTP error status is a `Response`, a network failure a `FeedError`."""
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            return Response(resp.status, resp.read(), {k.lower(): v for k, v in resp.headers.items()})
    except urllib.error.HTTPError as e:
        return Response(e.code, b"", {k.lower(): v for k, v in (e.headers or {}).items()})
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise FeedError(f"{request.full_url.split('?')[0]}: {e}") from e


@dataclass(frozen=True)
class House:
    """One house as served: its listings' and commodities' bodies, and the time they stand for."""

    t: int  # Unix seconds: the listings' Last-Modified, else when they were fetched
    listings: bytes
    commodities: bytes


class Client:
    """One region's Forever auction houses."""

    def __init__(
        self,
        region: str,
        client_id: str,
        secret: str,
        *,
        transport: Transport = urllib_transport,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self.region = region
        self.namespace = f"dynamic-forever-{region}"
        self._client_id = client_id
        self._secret = secret
        self._transport = transport
        self._clock = clock
        self._token: str | None = None
        self._expires = 0.0

    def houses(self) -> list[tuple[int, str]]:
        """Every auction house of the region: (id, name as served, "Alliance Auction House")."""
        resp = self._get(f"/data/wow/ruleset/{RULESET}/auctions/", None)
        try:
            listed = json.loads(resp.body).get("auctions", [])
            return [(int(h["id"]), str(h.get("name", ""))) for h in listed]
        except (ValueError, KeyError, TypeError, AttributeError) as e:
            raise FeedError("auction houses: unreadable answer") from e

    def house(self, house_id: int, since: int | None = None) -> House | None:
        """The house's listings and commodities; None when its listings say nothing changed after `since`
        (Unix seconds: the last snapshot recorded)."""
        base = f"/data/wow/ruleset/{RULESET}/auctions/{house_id}"
        listings = self._get(base, since)
        if listings.status == 304:
            return None
        commodities = self._get(f"{base}/commodities", None)
        return House(_modified(listings, self._clock()), listings.body, commodities.body)

    def _get(self, path: str, since: int | None) -> Response:
        query = urllib.parse.urlencode({"namespace": self.namespace, "locale": "en_US"})
        url = f"https://{self.region}.api.blizzard.com{path}?{query}"
        for attempt in range(2):
            headers = {"Authorization": f"Bearer {self._bearer()}"}
            if since is not None:
                headers["If-Modified-Since"] = format_datetime(
                    datetime.fromtimestamp(since, UTC), usegmt=True
                )
            resp = self._transport(urllib.request.Request(url, headers=headers), TIMEOUT)
            if resp.status == 401 and attempt == 0:
                self._token = None  # revoked or expired early: one more try with a new one
                continue
            if resp.status in (200, 304):
                return resp
            raise FeedError(f"{path}: {resp.status}")
        raise FeedError(f"{path}: 401")

    def _bearer(self) -> str:
        if self._token is None or self._clock() >= self._expires:
            auth = base64.b64encode(f"{self._client_id}:{self._secret}".encode()).decode()
            resp = self._transport(
                urllib.request.Request(
                    f"https://{self.region}.battle.net/oauth/token",
                    data=b"grant_type=client_credentials",
                    headers={
                        "Authorization": f"Basic {auth}",
                        "Content-Type": "application/x-www-form-urlencoded",
                    },
                ),
                TIMEOUT,
            )
            if resp.status != 200:
                raise FeedError(f"token: {resp.status}")
            try:
                data = json.loads(resp.body)
                self._token = str(data["access_token"])
                self._expires = self._clock() + float(data.get("expires_in", 0)) - TOKEN_SLACK
            except (ValueError, KeyError, TypeError) as e:
                raise FeedError("token: unreadable answer") from e
        return self._token


def _modified(resp: Response, now: float) -> int:
    """The response's Last-Modified as Unix seconds, else `now`."""
    header = resp.headers.get("last-modified")
    if header:
        try:
            return int(parsedate_to_datetime(header).timestamp())
        except (TypeError, ValueError):
            pass
    return int(now)


def from_env(region: str, transport: Transport = urllib_transport) -> Client | None:
    """A client for the region from `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET`; None without them."""
    client_id, secret = os.environ.get("BLIZZARD_CLIENT_ID"), os.environ.get("BLIZZARD_CLIENT_SECRET")
    if not client_id or not secret:
        return None
    return Client(region, client_id, secret, transport=transport)
