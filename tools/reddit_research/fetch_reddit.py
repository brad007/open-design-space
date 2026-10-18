#!/usr/bin/env python3
"""Collect r/cricut posts and comments about Design Space through Reddit's
official Data API, for product research.

You run this with your own Reddit API app credentials, set as environment
variables. Nothing is stored except the output file, and usernames are left
out of it.

    export REDDIT_CLIENT_ID=...         # under your app's name at reddit.com/prefs/apps
    export REDDIT_CLIENT_SECRET=...
    export REDDIT_USER_AGENT="open-design-space-research/0.1 by u/YOUR_USERNAME"
    python3 tools/reddit_research/fetch_reddit.py

Output: research-data/reddit-cricut.json (git-ignored).
Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

TOKEN_URL = "https://www.reddit.com/api/v1/access_token"
API = "https://oauth.reddit.com"

# Searches run inside the subreddit. Each is combined with "design space".
TOPICS = [
    "",
    "crash", "lost project", "not saving", "update", "bug", "slow", "freeze",
    "offline", "login", "sign out",
    "weld", "slice", "contour", "offset", "kerning", "font", "text", "curve",
    "upload", "svg", "image", "trace", "background remover",
    "print then cut", "calibration", "mat", "mirror", "attach",
    "subscription", "cricut access", "paywall",
    "ipad", "android", "iphone", "mac", "windows", "linux",
    "wish", "feature request", "please add", "alternative", "silhouette",
]


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


class Reddit:
    def __init__(self, client_id: str, secret: str, user_agent: str) -> None:
        self.user_agent = user_agent
        self.token = self._token(client_id, secret)

    def _token(self, client_id: str, secret: str) -> str:
        # App-only OAuth: read access to public content, no user login.
        auth = base64.b64encode(f"{client_id}:{secret}".encode()).decode()
        req = urllib.request.Request(
            TOKEN_URL,
            data=urllib.parse.urlencode({"grant_type": "client_credentials"}).encode(),
            headers={"Authorization": f"Basic {auth}", "User-Agent": self.user_agent},
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.load(r)
        if "access_token" not in body:
            raise SystemExit(f"Reddit didn't return a token: {body}")
        return body["access_token"]

    def get(self, path: str, **params: object) -> object:
        url = f"{API}{path}?{urllib.parse.urlencode({**params, 'raw_json': 1})}"
        for attempt in range(5):
            req = urllib.request.Request(
                url, headers={"Authorization": f"bearer {self.token}", "User-Agent": self.user_agent}
            )
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    self._respect_limits(r.headers)
                    return json.load(r)
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    wait = 10 * (attempt + 1)
                    log(f"  HTTP {e.code}, waiting {wait}s")
                    time.sleep(wait)
                    continue
                raise
        raise SystemExit(f"Giving up on {path}")

    @staticmethod
    def _respect_limits(headers) -> None:
        # Stay well inside Reddit's free-tier rate limit.
        try:
            remaining = float(headers.get("X-Ratelimit-Remaining", "10"))
            reset = float(headers.get("X-Ratelimit-Reset", "60"))
        except ValueError:
            remaining, reset = 10, 60
        if remaining < 5:
            log(f"  rate limit nearly used, sleeping {reset:.0f}s")
            time.sleep(reset + 1)
        else:
            time.sleep(0.7)


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")


def post_record(d: dict) -> dict:
    return {
        "id": d["id"],
        "title": d.get("title", ""),
        "text": d.get("selftext", ""),
        "flair": d.get("link_flair_text"),
        "score": d.get("score", 0),
        "num_comments": d.get("num_comments", 0),
        "date": iso(d.get("created_utc", 0)),
        "url": "https://www.reddit.com" + d.get("permalink", ""),
    }


def flatten_comments(children: list, depth: int = 0, out: list | None = None) -> list:
    out = [] if out is None else out
    for c in children:
        if c.get("kind") != "t1":
            continue
        d = c["data"]
        body = d.get("body", "")
        if body in ("[deleted]", "[removed]"):
            continue
        out.append({"text": body, "score": d.get("score", 0), "date": iso(d.get("created_utc", 0)), "depth": depth})
        replies = d.get("replies")
        if isinstance(replies, dict):
            flatten_comments(replies["data"]["children"], depth + 1, out)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--subreddit", default="cricut")
    ap.add_argument("--time", default="year", choices=["month", "year", "all"], help="how far back to search")
    ap.add_argument("--per-search", type=int, default=50, help="posts per search (max 100)")
    ap.add_argument("--comments", type=int, default=40, help="comments kept per post, highest scored first")
    ap.add_argument("--min-comments", type=int, default=3, help="skip posts with fewer comments")
    ap.add_argument("--out", default="research-data/reddit-cricut.json")
    args = ap.parse_args()

    missing = [v for v in ("REDDIT_CLIENT_ID", "REDDIT_CLIENT_SECRET", "REDDIT_USER_AGENT") if not os.environ.get(v)]
    if missing:
        raise SystemExit(f"Set {', '.join(missing)} first. See the top of this file.")

    reddit = Reddit(os.environ["REDDIT_CLIENT_ID"], os.environ["REDDIT_CLIENT_SECRET"], os.environ["REDDIT_USER_AGENT"])
    sub = args.subreddit

    posts: dict[str, dict] = {}
    for topic in TOPICS:
        q = f'"design space" {topic}'.strip()
        log(f"search: {q}")
        listing = reddit.get(f"/r/{sub}/search", q=q, restrict_sr=1, sort="relevance", t=args.time, limit=min(args.per_search, 100))
        for child in listing["data"]["children"]:
            d = child["data"]
            rec = posts.setdefault(d["id"], post_record(d))
            rec.setdefault("matched", []).append(topic or "design space")

    keep = [p for p in posts.values() if p["num_comments"] >= args.min_comments]
    log(f"{len(posts)} posts found, fetching comments for {len(keep)}")
    for i, p in enumerate(sorted(keep, key=lambda p: -p["score"]), 1):
        log(f"  [{i}/{len(keep)}] {p['title'][:70]}")
        thread = reddit.get(f"/r/{sub}/comments/{p['id']}", sort="top", limit=200, depth=4)
        comments = flatten_comments(thread[1]["data"]["children"])
        comments.sort(key=lambda c: -c["score"])
        p["comments"] = comments[: args.comments]

    result = {
        "source": f"r/{sub} via Reddit Data API",
        "collected": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "time_range": args.time,
        "note": "Usernames are omitted. For personal, non-commercial research.",
        "posts": sorted(posts.values(), key=lambda p: -p["score"]),
    }
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    n_comments = sum(len(p.get("comments", [])) for p in result["posts"])
    log(f"Wrote {len(result['posts'])} posts and {n_comments} comments to {args.out}")


if __name__ == "__main__":
    main()
