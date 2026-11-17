#!/usr/bin/env python3
"""End-to-end protocol check against a running host (DevHost or the real Windows host).

    FLUENTDECK_HOME=/tmp/fd FLUENTDECK_PAIR_CODE=123456 dotnet run --project host/FluentDeck.DevHost
    python3 host/tools/smoke_test.py --host 127.0.0.1 --code 123456 [--deck-file /tmp/fd/deck.json]

Needs: pip install websockets
"""
import argparse, asyncio, json, time, urllib.request, urllib.error
import websockets

class Client:
    def __init__(self, ws):
        self.ws, self.states, self.inbox, self.n = ws, {}, [], 0

    async def send(self, **msg):
        await self.ws.send(json.dumps(msg))

    async def recv(self, timeout=5):
        msg = json.loads(await asyncio.wait_for(self.ws.recv(), timeout))
        if msg["type"] == "state":
            self.states[msg["topic"]] = msg["data"]
        return msg

    async def until(self, pred, timeout=5, what="message"):
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise AssertionError(f"timed out waiting for {what}")
            msg = await self.recv(left)
            if pred(msg):
                return msg

    async def invoke(self, panel, action, **args):
        self.n += 1
        rid = f"r{self.n}"
        await self.send(type="invoke", id=rid, panel=panel, action=action, args=args)
        return await self.until(lambda m: m["type"] == "result" and m["id"] == rid, what=f"result of {panel}.{action}")

def check(cond, label):
    print(("  ok   " if cond else "  FAIL ") + label)
    if not cond:
        raise SystemExit(1)

async def main(a):
    url = f"ws://{a.host}:{a.port}/ws"
    async with websockets.connect(url, max_size=2**22) as ws:
        c = Client(ws)
        server = await c.recv()
        check(server["type"] == "server" and server["protocol"] == 1, f"server hello from {server.get('name')}")

        await c.send(type="subscribe", topics=["media"])
        m = await c.recv()
        check(m["type"] == "authError", "unauthenticated subscribe is refused")

        await c.send(type="hello", token="nope", client={"name": "smoke"})
        m = await c.recv()
        check(m["type"] == "authError" and m["needsPairing"], "bad token → needsPairing")

        await c.send(type="pair", code="000000" if a.code != "000000" else "111111", client={"name": "smoke"})
        m = await c.recv()
        check(m["type"] == "authError", "wrong pairing code is refused")

        await c.send(type="pair", code=a.code, client={"name": "smoke test"})
        paired = await c.recv()
        check(paired["type"] == "paired" and len(paired["token"]) > 20, "pairing returns a token")
        token = paired["token"]
        welcome = await c.recv()
        ids = [p["id"] for p in welcome["panels"]]
        check(welcome["type"] == "welcome" and {"deck", "media", "audio", "system", "theme", "desktops"} <= set(ids), f"welcome lists panels {ids}")

        await c.send(type="subscribe", topics=ids)
        await c.until(lambda m: set(ids) <= set(c.states), what="snapshots")
        check(True, "snapshot for every subscribed topic")

        was = c.states["media"]["status"]
        r = await c.invoke("media", "playPause")
        check(r["ok"], "media.playPause ok")
        await c.until(lambda m: m["type"] == "state" and m["topic"] == "media" and m["data"]["status"] != was, what="media state flip")
        check(True, f"media status {was} → {c.states['media']['status']}")

        r = await c.invoke("audio", "setVolume", volume=0.25)
        await c.until(lambda m: m["type"] == "state" and m["topic"] == "audio" and abs(m["data"]["output"]["volume"] - 0.25) < 1e-6, what="volume")
        check(r["ok"], "audio.setVolume → state follows")

        mic_before = c.states["audio"]["input"]["muted"]
        r = await c.invoke("deck", "press", buttonId="main/mic")
        await c.until(lambda m: m["type"] == "state" and m["topic"] == "audio" and m["data"]["input"]["muted"] != mic_before, what="mic toggle")
        check(r["ok"], "deck builtin button toggles the mic")

        r = await c.invoke("deck", "press", buttonId="main/snip")
        check(r["ok"], "deck keys button runs")
        r = await c.invoke("deck", "press", buttonId="dev/focus")
        check(r["ok"], "deck sequence button runs")
        d = c.states["desktops"]
        check(d["current"] == 1 and [x["name"] for x in d["desktops"]] == ["Desktop 1", "Omnissa"], f"desktops lists {len(d['desktops'])} desktops, on {d['current']}")
        r = await c.invoke("deck", "press", buttonId="dev/desktop-2")
        await c.until(lambda m: m["type"] == "state" and m["topic"] == "desktops" and m["data"]["current"] == 2, what="desktop switch")
        check(r["ok"], "a desktop key switches to desktop 2")
        r = await c.invoke("desktops", "previous")
        await c.until(lambda m: m["type"] == "state" and m["topic"] == "desktops" and m["data"]["current"] == 1, what="previous desktop")
        check(r["ok"], "desktops.previous goes back")
        r = await c.invoke("desktops", "switch", index=5)
        check(not r["ok"] and "doesn't exist" in r["error"], "switching to a missing desktop → friendly error")
        r = await c.invoke("deck", "press", buttonId="main/nope")
        check(not r["ok"] and "no longer exists" in r["error"], "unknown button → friendly error")
        r = await c.invoke("media", "explode")
        check(not r["ok"], "unknown action → ok:false")
        r = await c.invoke("nope", "x")
        check(not r["ok"], "unknown panel → ok:false")

        # burst of fire-and-forget slider updates should be coalesced
        start = len([1])
        count = 0
        for i in range(100):
            await c.send(type="invoke", panel="audio", action="setVolume", args={"volume": i / 100})
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            try:
                m = await c.recv(max(0.01, deadline - time.monotonic()))
                if m["type"] == "state" and m["topic"] == "audio":
                    count += 1
            except asyncio.TimeoutError:
                break
        check(abs(c.states["audio"]["output"]["volume"] - 0.99) < 1e-6 and count < 60,
              f"100 slider updates → {count} coalesced state frames, final volume correct")

        r = await c.invoke("system", "details")
        first = r["data"] if r["ok"] else {}
        check(r["ok"] and len(first["processes"]) > 0 and all(p["name"] and p["memoryMb"] >= 0 for p in first["processes"]),
              f"system.details lists {len(first.get('processes', []))} processes and {len(first.get('disks', []))} disk(s)")
        await asyncio.sleep(1.1)
        r = await c.invoke("system", "details")
        check(r["ok"] and all(0 <= p["cpu"] <= 100 for p in r["data"]["processes"]), "a second sample reports CPU shares")

        art = c.states["media"]["artwork"]
        check(isinstance(art, str) and art.startswith("/assets/"), "media artwork is an asset path")
        base = f"http://{a.host}:{a.port}"
        req = urllib.request.Request(base + art, headers={"Authorization": f"Bearer {token}"})
        body = urllib.request.urlopen(req).read()
        check(body[:4] == b"\x89PNG", f"asset fetch with token ({len(body)} bytes)")
        try:
            urllib.request.urlopen(base + art)
            check(False, "asset without token rejected")
        except urllib.error.HTTPError as e:
            check(e.code == 401, "asset without token → 401")

        if a.deck_file:
            text = open(a.deck_file, encoding="utf-8").read()
            open(a.deck_file, "w", encoding="utf-8").write(text.replace('"title": "Main"', '"title": "Main (edited)"', 1))
            await c.until(lambda m: m["type"] == "state" and m["topic"] == "deck" and m["data"]["pages"][0]["title"] == "Main (edited)", timeout=5, what="deck hot reload")
            check(True, "deck.json edit hot-reloads")
            open(a.deck_file, "w", encoding="utf-8").write("{ broken")
            await c.until(lambda m: m["type"] == "state" and m["topic"] == "deck" and m["data"]["error"], timeout=5, what="deck error")
            check(c.states["deck"]["pages"][0]["title"] == "Main (edited)", "broken deck.json keeps last good pages + reports error")
            open(a.deck_file, "w", encoding="utf-8").write(text)
            await c.until(lambda m: m["type"] == "state" and m["topic"] == "deck" and not m["data"]["error"], timeout=5, what="deck restore")
            check(True, "restored deck.json clears the error")

        # ── editing keys from the device (the DevHost allows it; a real PC must opt in) ──
        async def deck(pred, what):
            """The deck state once it satisfies pred (it may already have arrived)."""
            if "deck" in c.states and pred(c.states["deck"]):
                return c.states["deck"]
            return (await c.until(lambda m: m["type"] == "state" and m["topic"] == "deck" and pred(m["data"]), what=what))["data"]

        def labels(state, page="main"):
            return [b["label"] for p in state["pages"] if p["id"] == page for b in p["buttons"]]

        if (await deck(lambda d: True, "deck state")).get("editable"):
            r = await c.invoke("deck", "getButton", buttonId="main/snip")
            check(r["ok"] and r["data"]["button"]["action"]["keys"] == "Win+Shift+S", "getButton returns the key's action")

            r = await c.invoke("deck", "saveButton", pageId="main",
                               button={"label": "Notes", "symbol": "note.text", "action": {"type": "launch", "target": "notepad.exe"}})
            check(r["ok"] and r["data"]["buttonId"] == "main/notes", "saveButton adds a key and names it")
            await deck(lambda d: "Notes" in labels(d), "new key in state")
            r = await c.invoke("deck", "press", buttonId="main/notes")
            check(r["ok"], "the new key runs")

            r = await c.invoke("deck", "saveButton", pageId="main", buttonId="main/notes",
                               button={"label": "Notepad", "symbol": "note.text", "action": {"type": "keys", "keys": "Ctrl+Alt+N"}})
            check(r["ok"] and r["data"]["buttonId"] == "main/notes", "saveButton changes a key and keeps its id")
            state = await deck(lambda d: "Notepad" in labels(d), "edited key in state")
            check("Notes" not in labels(state), "the old label is gone")

            r = await c.invoke("deck", "saveButton", pageId="main", buttonId="main/notes",
                               button={"label": "Bad", "action": {"type": "keys", "keys": "Hyper+Q"}})
            check(not r["ok"] and "isn't valid" in r["error"], "an invalid key combination is refused")
            r = await c.invoke("deck", "saveButton", pageId="main", button={"label": "Bad", "action": {"type": "launch"}})
            check(not r["ok"], "a launch key with no target is refused")

            before = labels(c.states["deck"])
            r = await c.invoke("deck", "moveButton", buttonId="main/notes", by=-1)
            state = await deck(lambda d: labels(d) != before, "moved key in state")
            check(r["ok"] and labels(state)[-2] == "Notepad", "moveButton moves a key one place earlier")

            r = await c.invoke("deck", "listApps")
            apps = r["data"]["apps"] if r["ok"] else []
            check(len(apps) > 0 and apps[0]["name"] and apps[0]["path"] and apps[0]["icon"].startswith("/assets/"), f"listApps returns {len(apps)} apps with icons")

            png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
            r = await c.invoke("deck", "uploadIcon", data=png)
            check(r["ok"] and r["data"]["icon"].startswith("icons/") and r["data"]["icon"].endswith(".png"), "uploadIcon stores an image")
            icon = r["data"]["icon"]
            r = await c.invoke("deck", "saveButton", pageId="main", buttonId="main/notes",
                               button={"label": "Notepad", "icon": icon, "action": {"type": "launch", "target": "notepad.exe"}})
            state = await deck(lambda d: any(b["id"] == "main/notes" and b["icon"] for p in d["pages"] for b in p["buttons"]), "custom icon in state")
            asset = next(b["icon"] for p in state["pages"] for b in p["buttons"] if b["id"] == "main/notes")
            req = urllib.request.Request(base + asset, headers={"Authorization": f"Bearer {token}"})
            check(urllib.request.urlopen(req).read()[:4] == b"\x89PNG", "the custom icon is served as an asset")
            r = await c.invoke("deck", "uploadIcon", data="bm90IGFuIGltYWdl")
            check(not r["ok"], "uploadIcon refuses a file that isn't an image")

            r = await c.invoke("deck", "deleteButton", buttonId="main/notes")
            state = await deck(lambda d: "Notepad" not in labels(d), "deleted key gone from state")
            check(r["ok"], "deleteButton removes a key")

            r = await c.invoke("deck", "addPage", title="Stream")
            check(r["ok"] and r["data"]["pageId"] == "stream", "addPage adds a page")
            r = await c.invoke("deck", "renamePage", pageId="stream", title="Streaming")
            state = await deck(lambda d: any(p["title"] == "Streaming" for p in d["pages"]), "renamed page in state")
            check(r["ok"], "renamePage renames it")
            r = await c.invoke("deck", "deletePage", pageId="stream")
            state = await deck(lambda d: all(p["id"] != "stream" for p in d["pages"]), "deleted page gone from state")
            check(r["ok"] and len(state["pages"]) == 2, "deletePage removes it")

            if a.deck_file:
                saved = open(a.deck_file, encoding="utf-8").read()
                body = "\n".join(line for line in saved.splitlines() if not line.lstrip().startswith("//"))
                pages = json.loads(body)["pages"]
                check(saved.startswith("//") and [p["id"] for p in pages] == ["main", "dev"] and len(pages[0]["buttons"]) == 12,
                      "deck.json was rewritten with its header and the original keys")
                check("null" not in body and '"hidden": false' not in body, "the rewritten deck.json carries no empty fields")
        else:
            r = await c.invoke("deck", "saveButton", pageId="main", button={"label": "Nope"})
            check(not r["ok"] and "turned off" in r["error"], "editing is refused when the PC hasn't allowed it")
            r = await c.invoke("deck", "listApps")
            check(not r["ok"], "listApps is refused too")

    async with websockets.connect(url) as ws:
        c = Client(ws)
        await c.recv()
        await c.send(type="hello", token=token, client={"name": "smoke"})
        m = await c.recv()
        check(m["type"] == "welcome", "reconnect with saved token → welcome")
        await c.send(type="ping")
        m = await c.until(lambda m: m["type"] == "pong", what="pong")
        check(True, "ping/pong")

    print("\nall checks passed")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=47610)
    p.add_argument("--code", required=True)
    p.add_argument("--deck-file")
    asyncio.run(main(p.parse_args()))
