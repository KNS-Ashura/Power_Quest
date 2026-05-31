#!/usr/bin/env python3
"""Test get_leaderboard + profile on VPS. Expect entries:[] or entries:[...] (not {})."""
import json
import random
import string
import urllib.request
import base64

BASE = "https://powerquest.robinmatelot.codes"
KEY = "defaultkey"
auth_b64 = base64.b64encode(f"{KEY}:".encode()).decode()


def post(path, body, token=None):
    headers = {"Content-Type": "application/json", "Accept-Encoding": "identity"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    else:
        headers["Authorization"] = f"Basic {auth_b64}"
    req = urllib.request.Request(
        BASE + path, data=body.encode(), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.status, r.read().decode()


suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
email = f"lbtest_{suffix}@pq.test"
user = f"Lb{suffix}"
pwd = "TestPass123!"
url = f"/v2/account/authenticate/email?create=true&username={user}"
st, body = post(url, json.dumps({"email": email, "password": pwd, "username": user}))
print("AUTH", st)
tok = json.loads(body)["token"]

st2, body2 = post("/v2/rpc/get_leaderboard", '""', tok)
print("LEADERBOARD (empty payload)", st2, body2)
inner = json.loads(json.loads(body2).get("payload", "{}"))
entries = inner.get("entries")
print("  entries type:", type(entries).__name__, "value:", entries)

st3, body3 = post("/v2/rpc/get_player_profile", '""', tok)
print("PROFILE", st3, body3[:200])

inner2 = json.dumps({"win": True, "duration_seconds": 30})
try:
    st4, body4 = post("/v2/rpc/submit_match_result", inner2, tok)
    print("SUBMIT WIN", st4, body4[:200])
except urllib.error.HTTPError as e:
    print("SUBMIT WIN HTTP", e.code, e.read().decode()[:200])

st5, body5 = post("/v2/rpc/get_leaderboard", json.dumps({"limit": 20}), tok)
print("LEADERBOARD AFTER WIN", st5, body5)
inner5 = json.loads(json.loads(body5).get("payload", "{}"))
print("  entries:", inner5.get("entries"))
