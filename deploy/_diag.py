#!/usr/bin/env python3
import sys, json, base64, random, string, urllib.request, urllib.error
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = "https://powerquest.robinmatelot.codes"
auth_b64 = base64.b64encode(b"defaultkey:").decode()


def post(path, body, auth):
    req = urllib.request.Request(
        BASE + path, data=body.encode(),
        headers={"Content-Type": "application/json", "Authorization": auth}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def rpc(name, token, payload=""):
    body = json.dumps(payload) if payload != "" else '""'
    return post(f"/v2/rpc/{name}", body, f"Bearer {token}")


def reg():
    s = "".join(random.choices(string.ascii_lowercase, k=6))
    st, txt = post(
        f"/v2/account/authenticate/email?create=true&username=U{s}",
        json.dumps({"email": f"t_{s}@pq.test", "password": "TestPass123!", "username": f"U{s}"}),
        f"Basic {auth_b64}")
    return json.loads(txt)["token"], f"U{s}"


t1, u1 = reg()
print("=== join_queue (joueur 1) ===")
st, txt = rpc("join_queue", t1)
print("HTTP", st)
print("brut:", txt)
inner = json.loads(txt).get("payload")
print("payload decode:", json.loads(inner) if inner else inner)

print("\n=== queue_status (joueur 1) ===")
st, txt = rpc("queue_status", t1)
inner = json.loads(txt).get("payload")
print("HTTP", st, "| payload:", json.loads(inner) if inner else inner)

t2, u2 = reg()
print("\n=== join_queue (joueur 2) ===")
st, txt = rpc("join_queue", t2)
inner = json.loads(txt).get("payload")
print("HTTP", st, "| payload:", json.loads(inner) if inner else inner)

print("\n=== queue_status (joueur 1 apres joueur 2) ===")
st, txt = rpc("queue_status", t1)
inner = json.loads(txt).get("payload")
print("HTTP", st, "| payload:", json.loads(inner) if inner else inner)
