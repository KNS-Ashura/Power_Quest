#!/usr/bin/env python3
import json
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
    data = body.encode() if isinstance(body, str) else body
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.status, r.read().decode()

# register test user
import random, string
suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
email = f"test_{suffix}@pq.test"
user = f"Test{suffix}"
pwd = "TestPass123!"
url = f"/v2/account/authenticate/email?create=true&username={user}"
st, body = post(url, json.dumps({"email": email, "password": pwd, "username": user}))
print("AUTH", st, body[:200])
tok = json.loads(body)["token"]

st2, body2 = post("/v2/rpc/join_queue", '""', tok)
print("JOIN_QUEUE", st2, body2)
st3, body3 = post("/v2/rpc/queue_status", '""', tok)
print("QUEUE_STATUS", st3, body3)
