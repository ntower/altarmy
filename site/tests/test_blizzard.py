from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass, field

import pytest

from altarmy_site import blizzard

MODIFIED = "Thu, 19 Nov 2026 16:25:02 GMT"
MODIFIED_T = 1_795_105_502


@dataclass
class FakeApi:
    """Answers the token request and each path from `answers` (status, body, Last-Modified), in turn."""

    answers: dict[str, list[tuple[int, bytes, str | None]]] = field(default_factory=dict)
    token_status: int = 200
    expires_in: int = 86_399
    requests: list[urllib.request.Request] = field(default_factory=list)
    tokens: int = 0

    def __call__(self, request: urllib.request.Request, timeout: float) -> blizzard.Response:
        self.requests.append(request)
        url = request.full_url
        if url.endswith("/oauth/token"):
            self.tokens += 1
            body = json.dumps({"access_token": f"tok{self.tokens}", "expires_in": self.expires_in}).encode()
            return blizzard.Response(self.token_status, body, {})
        path = urllib.parse.urlsplit(url).path
        status, body, modified = self.answers[path].pop(0)
        return blizzard.Response(status, body, {"last-modified": modified} if modified else {})


LISTINGS = "/data/wow/ruleset/1/auctions/111"
COMMODITIES = "/data/wow/ruleset/1/auctions/111/commodities"


def client(api: FakeApi, now: float = 1_795_106_000.0) -> blizzard.Client:
    return blizzard.Client("us", "id", "secret", transport=api, clock=lambda: now)


def test_a_house_is_its_listings_and_commodities_at_their_last_modified() -> None:
    api = FakeApi({LISTINGS: [(200, b"L", MODIFIED)], COMMODITIES: [(200, b"C", MODIFIED)]})
    house = client(api).house(111)
    assert house == blizzard.House(MODIFIED_T, b"L", b"C")
    asked = api.requests[1]
    assert "namespace=dynamic-forever-us" in asked.full_url
    assert asked.get_header("Authorization") == "Bearer tok1"


def test_without_last_modified_the_fetch_time_stands_in() -> None:
    api = FakeApi({LISTINGS: [(200, b"L", None)], COMMODITIES: [(200, b"C", None)]})
    assert client(api, now=1_000.5).house(111) == blizzard.House(1_000, b"L", b"C")


def test_nothing_new_since_the_last_snapshot_is_none_and_downloads_nothing_more() -> None:
    api = FakeApi({LISTINGS: [(304, b"", MODIFIED)]})
    assert client(api).house(111, since=MODIFIED_T) is None
    assert api.requests[1].get_header("If-modified-since") == MODIFIED
    assert len(api.requests) == 2  # the token and the listings: no commodities


def test_the_token_is_reused_until_it_nearly_expires() -> None:
    api = FakeApi({LISTINGS: [(304, b"", None)] * 2})
    c = client(api)
    c.house(111, since=1)
    c.house(111, since=1)
    assert api.tokens == 1


def test_an_expired_token_is_fetched_again() -> None:
    api = FakeApi({LISTINGS: [(304, b"", None)] * 2}, expires_in=30)  # inside the slack: always stale
    c = client(api)
    c.house(111, since=1)
    c.house(111, since=1)
    assert api.tokens == 2


def test_a_401_fetches_a_new_token_once() -> None:
    api = FakeApi({LISTINGS: [(401, b"", None), (200, b"L", None)], COMMODITIES: [(200, b"C", None)]})
    assert client(api).house(111) is not None
    assert api.tokens == 2


@pytest.mark.parametrize("status", [404, 500, 503])
def test_an_error_status_is_a_feed_error(status: int) -> None:
    api = FakeApi({LISTINGS: [(status, b"", None)]})
    with pytest.raises(blizzard.FeedError, match=str(status)):
        client(api).house(111)


def test_a_refused_token_is_a_feed_error() -> None:
    with pytest.raises(blizzard.FeedError, match="token"):
        client(FakeApi(token_status=401)).house(111)


def test_from_env_needs_both_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("BLIZZARD_CLIENT_ID", "id")
    monkeypatch.delenv("BLIZZARD_CLIENT_SECRET", raising=False)
    assert blizzard.from_env("us") is None
    monkeypatch.setenv("BLIZZARD_CLIENT_SECRET", "secret")
    found = blizzard.from_env("eu")
    assert found is not None and found.namespace == "dynamic-forever-eu"
