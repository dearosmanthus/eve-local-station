#!/usr/bin/env python3
"""Explicit developer-only network operation: download a pinned official SDE."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import urllib.parse
import urllib.request

BASE = "https://developers.eveonline.com/static-data/tranquility"


class OfficialRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlparse(newurl)
        if parsed.scheme != "https" or parsed.hostname != "developers.eveonline.com":
            raise ValueError("Refusing redirect outside the official HTTPS SDE host")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=int, help="Pinned build; omit to resolve official latest.jsonl")
    parser.add_argument("--output", required=True, type=Path, help="Archive destination (.zip)")
    parser.add_argument("--expected-sha256", help="Optional previously audited archive SHA256")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; choose a new path or use the local converter")
    opener = urllib.request.build_opener(OfficialRedirectHandler())
    opener.addheaders = [("User-Agent", "EveLocalStation-DataBuilder/0.1")]
    build = args.build
    if build is None:
        with opener.open(BASE + "/latest.jsonl", timeout=60) as response:
            records = [json.loads(line) for line in response if line.strip()]
        build = next(row["buildNumber"] for row in records if row["_key"] == "sde")
    if build <= 0:
        parser.error("Build must be positive")
    url = f"{BASE}/eve-online-static-data-{build}-jsonl.zip"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".part")
    digest = hashlib.sha256()
    try:
        with opener.open(url, timeout=60) as response, temporary.open("wb") as destination:
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                digest.update(chunk)
                destination.write(chunk)
        actual_hash = digest.hexdigest()
        if args.expected_sha256 and actual_hash != args.expected_sha256.lower():
            raise ValueError("Archive SHA256 mismatch")
        temporary.replace(args.output)
    finally:
        temporary.unlink(missing_ok=True)
    record = {"sourceUrl": url, "buildNumber": build, "sha256": actual_hash,
              "bytes": args.output.stat().st_size}
    args.output.with_suffix(".download.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
