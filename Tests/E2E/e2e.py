#!/usr/bin/env python3
"""End-to-end tests against a real, running Islet.app.

Launches build/Islet.app with isolated config/support directories and its own API port,
then drives it through isletctl, raw HTTP and the URL scheme, and checks the result through
the API and the window server.

    python3 Tests/E2E/e2e.py                    # everything except media
    ISLET_E2E_MEDIA=1 python3 Tests/E2E/e2e.py  # also the MediaRemote bridge (skipped if
                                                # anything else is playing, so your music is safe)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = os.path.join(ROOT, "build", "Islet.app")
EXE = os.path.join(APP, "Contents", "MacOS", "Islet")
CTL = os.path.join(APP, "Contents", "MacOS", "isletctl")
PORT = 47931
LAN_PORT = 47934

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    mark = "\033[32m✓\033[0m" if cond else "\033[31m✗\033[0m"
    print(f"  {mark} {name}" + (f"  — {detail}" if detail and not cond else ""))
    return cond


def skip(name, why):
    results.append((name, None, why))
    print(f"  \033[33m–\033[0m {name}  (skipped: {why})")


class Env:
    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="islet-e2e-")
        self.support = os.path.join(self.tmp, "support")
        self.xdg = os.path.join(self.tmp, "config")
        self.plugins = os.path.join(self.xdg, "islet", "plugins")
        os.makedirs(self.support)
        os.makedirs(self.plugins)
        self.env = dict(os.environ, ISLET_SUPPORT_DIR=self.support, XDG_CONFIG_HOME=self.xdg)

    @property
    def config_path(self):
        return os.path.join(self.xdg, "islet", "config.json")

    def discovery(self):
        with open(os.path.join(self.support, "api.json")) as f:
            return json.load(f)


def ctl(e, *args, stdin=None, check_rc=True):
    p = subprocess.run([CTL, *args], env=e.env, input=stdin, capture_output=True, text=True, timeout=30)
    if check_rc and p.returncode != 0:
        print("    isletctl failed:", args, p.stderr.strip())
    return p


def http(method, path, token=None, body=None, headers=None):
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            data = r.read()
            return r.status, json.loads(data) if data else None
    except urllib.error.HTTPError as err:
        data = err.read()
        try:
            return err.code, json.loads(data)
        except Exception:
            return err.code, data


def http_to(port, method, path, token=None, body=None, headers=None):
    global PORT
    saved = PORT
    PORT = port
    try:
        return http(method, path, token, body, headers)
    finally:
        PORT = saved


def activities(e):
    return {a["id"]: a for a in json.loads(ctl(e, "ls").stdout or "[]")}


def state(e):
    return json.loads(ctl(e, "state").stdout or "{}")


def wait_for(pred, timeout=8.0, step=0.1):
    end = time.time() + timeout
    while time.time() < end:
        try:
            v = pred()
            if v:
                return v
        except Exception:
            pass
        time.sleep(step)
    return None


def cpu_seconds(pid):
    out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    # [[dd-]hh:]mm:ss.cc
    parts = out.replace("-", ":").split(":")
    secs = 0.0
    for p in parts:
        secs = secs * 60 + float(p)
    return secs


def rss_mb(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) / 1024


def main():
    if not os.path.exists(EXE):
        sys.exit("build/Islet.app not found; run scripts/bundle.sh first")
    e = Env()
    # Config: dedicated port, plugins on, clipboard off.
    os.makedirs(os.path.dirname(e.config_path), exist_ok=True)
    with open(e.config_path, "w") as f:
        json.dump({"apiPort": PORT, "pluginsEnabled": True, "hoverToOpen": True,
                   "lanBridgeEnabled": True, "lanPort": LAN_PORT, "callDetection": True}, f)
    # A plugin that emits Islet JSON, and an xbar-format one.
    with open(os.path.join(e.plugins, "e2e.1m.sh"), "w") as f:
        f.write('#!/bin/sh\necho \'{"id":"plugin-e2e","title":"Plugin says hi","progress":0.5,"priority":"low"}\'\n')
    with open(os.path.join(e.plugins, "xbar.1m.sh"), "w") as f:
        f.write('#!/bin/sh\necho "Hello xbar | color=green"\necho "---"\necho "Item | href=https://example.com"\n')
    for n in ("e2e.1m.sh", "xbar.1m.sh"):
        os.chmod(os.path.join(e.plugins, n), 0o755)

    windows_bin = os.path.join(e.tmp, "windows")
    subprocess.run(["swiftc", "-O", os.path.join(ROOT, "Tests", "E2E", "windows.swift"), "-o", windows_bin],
                   check=True, capture_output=True)

    print("▸ launching Islet")
    app = subprocess.Popen([EXE], env=e.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        run_suite(e, app, windows_bin)
    finally:
        app.terminate()
        try:
            app.wait(timeout=5)
        except subprocess.TimeoutExpired:
            app.kill()
        check("api.json removed on quit", not os.path.exists(os.path.join(e.support, "api.json")))
        shutil.rmtree(e.tmp, ignore_errors=True)

    failed = [r for r in results if r[1] is False]
    passed = [r for r in results if r[1] is True]
    skipped = [r for r in results if r[1] is None]
    print(f"\n{len(passed)} passed, {len(failed)} failed, {len(skipped)} skipped")
    sys.exit(1 if failed else 0)


def run_suite(e, app, windows_bin):
    ok = wait_for(lambda: os.path.exists(os.path.join(e.support, "api.json")), timeout=15)
    if not check("app starts and writes api.json", ok):
        print(app.stderr.read1(4000).decode(errors="replace") if app.stderr else "")
        return
    d = e.discovery()
    token = d["token"]
    mode = oct(os.stat(os.path.join(e.support, "api.json")).st_mode & 0o777)
    check("api.json is private (0600)", mode == "0o600", mode)
    check("api listens on configured port", d["port"] == PORT, str(d))

    print("▸ local API security")
    check("health without token", http("GET", "/v1/health")[0] == 200)
    check("401 without token", http("GET", "/v1/activities")[0] == 401)
    check("401 with wrong token", http("GET", "/v1/activities", token="nope")[0] == 401)
    check("403 for web-page origin (CSRF)", http("POST", "/v1/notify", token, {"title": "x"}, {"Origin": "https://evil.example"})[0] == 403)
    check("403 for DNS-rebinding host", http("GET", "/v1/activities", token, headers={"Host": "evil.example"})[0] == 403)
    status, body = http("POST", "/v1/activities", token, {"id": "bad", "title": "x", "progress": 900})
    check("422 with a readable validation error", status == 422 and "progress" in str(body), str(body))

    print("▸ activities via isletctl")
    check("notify", ctl(e, "notify", "E2E hello", "--subtitle", "from the test", "--ttl", "30").returncode == 0)
    acts = activities(e)
    check("notification listed", any(a["title"] == "E2E hello" for a in acts.values()))
    check("presentation is a sneak peek", state(e).get("presentation") == "sneak", state(e).get("presentation"))

    ctl(e, "set", "build", "--title", "Build", "--progress", "30", "--icon", "sf:hammer.fill", "--tint", "orange")
    ctl(e, "set", "build", "--progress", "0.9", "--subtitle", "linking")
    b = activities(e).get("build", {})
    check("progress update merges fields", b.get("progress") == 0.9 and b.get("title") == "Build" and b.get("subtitle") == "linking", str(b))
    check("bad state rejected by CLI", ctl(e, "set", "build", "--state", "nope", check_rc=False).returncode != 0)

    ctl(e, "timer", "90s", "--title", "Tea")
    t = [a for a in activities(e).values() if a["source"] == "timer"]
    check("timer has a countdown", bool(t) and "endsAt" in t[0], str(t))

    print("▸ agent hooks")
    base = {"session_id": "e2e-session-1", "cwd": "/Users/me/code/islet"}
    for ev, extra in [("UserPromptSubmit", {"prompt": "hi"}),
                      ("PreToolUse", {"tool_name": "Bash", "tool_input": {"command": "swift test"}})]:
        ctl(e, "hook", "claude", stdin=json.dumps({**base, "hook_event_name": ev, **extra}))
    a = activities(e).get("claude-e2e-session")
    check("claude tool use shows what it's doing", a and a["subtitle"] == "Running swift test" and a["state"] == "running", str(a))
    ctl(e, "hook", "claude", stdin=json.dumps({**base, "hook_event_name": "Notification", "message": "Claude needs your permission to use Bash"}))
    a = activities(e).get("claude-e2e-session")
    check("waiting for input is high priority", a and a["state"] == "waiting" and a["priority"] == "high", str(a))
    check("waiting agent sneaks open", state(e).get("presentation") == "sneak")
    ctl(e, "hook", "claude", stdin=json.dumps({**base, "hook_event_name": "Stop"}))
    a = activities(e).get("claude-e2e-session")
    check("stop marks success", a and a["state"] == "success", str(a))
    ctl(e, "hook", "claude", stdin=json.dumps({**base, "hook_event_name": "SessionEnd"}))
    check("session end removes it", "claude-e2e-session" not in activities(e))
    ctl(e, "hook", "codex", json.dumps({"type": "agent-turn-complete", "turn-id": "t9", "last-assistant-message": "Done!"}))
    check("codex notify payload as argument", activities(e).get("codex-t9", {}).get("subtitle") == "Done!")
    t0 = time.time()
    p = subprocess.run([CTL, "hook", "claude"], input="{}", capture_output=True, text=True,
                       env=dict(e.env, ISLET_SUPPORT_DIR=os.path.join(e.tmp, "nowhere")))
    check("hook never fails the agent when Islet is down", p.returncode == 0 and time.time() - t0 < 3)

    print("▸ command wrapper")
    p = ctl(e, "run", "--title", "e2e ok", "--", "sh", "-c", "exit 0")
    ok_runs = [a for a in activities(e).values() if a["source"] == "run" and a["title"] == "e2e ok"]
    check("run success", p.returncode == 0 and ok_runs and ok_runs[0]["state"] == "success", str(ok_runs))
    p = ctl(e, "run", "--title", "e2e fail", "--", "sh", "-c", "exit 3", check_rc=False)
    bad = [a for a in activities(e).values() if a["title"] == "e2e fail"]
    check("run failure keeps exit code", p.returncode == 3 and bad and bad[0]["state"] == "failure", str(bad))

    print("▸ shell integration (zsh hook)")
    hook = os.path.join(ROOT, "integrations", "shell", "islet.zsh")
    ctl_dir = os.path.dirname(CTL)
    script = f'export PATH="{ctl_dir}:$PATH"; source "{hook}"; ISLET_MIN_SECONDS=0; ' \
             '_islet_preexec "make release"; sleep 1.2; (exit 2); _islet_precmd; sleep 0.5'
    subprocess.run(["zsh", "-c", script], env=e.env, capture_output=True, timeout=30)
    sh = [a for a in activities(e).values() if a["source"] == "shell"]
    check("long-running failed command reported by the zsh hook", sh and sh[0]["state"] == "failure"
          and "exit 2" in (sh[0].get("subtitle") or ""), str(sh))
    ctl(e, "clear", "--source", "shell")

    print("▸ ActivityKit-style fields")
    ctl(e, "set", "plan", "--title", "Agent plan", "--steps", "5", "--step", "2",
        "--url", "https://example.com/run/1", "--relevance", "80", "--stale-in", "600")
    pl = activities(e).get("plan", {})
    check("steps, url, relevance and staleAt round-trip", pl.get("steps") == 5 and pl.get("step") == 2
          and pl.get("url") == "https://example.com/run/1" and pl.get("relevance") == 80 and "staleAt" in pl, str(pl))
    check("bad --url rejected", ctl(e, "set", "plan", "--url", "not a url", check_rc=False).returncode != 0)
    ctl(e, "set", "pizza", "--title", "Pizza", "--ends-in", "1200", "--action", "Track=https://example.com/t")
    pz = activities(e).get("pizza", {})
    check("countdown and action button from the CLI", "endsAt" in pz and pz.get("actions", [{}])[0].get("title") == "Track", str(pz))
    ctl(e, "rm", "pizza")
    ctl(e, "focus", "Work", "on")
    fo = activities(e).get("focus", {})
    check("focus pill via CLI", fo.get("title") == "Work" and fo.get("trailing") == "On", str(fo))
    ctl(e, "rm", "plan")

    print("▸ iPhone bridge (LAN listener)")
    lan_ok = wait_for(lambda: http_to(LAN_PORT, "GET", "/v1/health")[0] == 200, timeout=5)
    check("LAN listener is up", lan_ok)
    status, body = http_to(LAN_PORT, "POST", "/v1/notify", token, {"title": "From iPhone", "ttl": 30}, {"Host": "my-mac.local:%d" % LAN_PORT})
    check("iPhone-style request with .local host accepted", status == 201, f"{status} {body}")
    check("LAN still requires the token", http_to(LAN_PORT, "POST", "/v1/notify", None, {"title": "x"}, {"Host": "my-mac.local"})[0] == 401)
    check("LAN refuses browser origins", http_to(LAN_PORT, "POST", "/v1/notify", token, {"title": "x"}, {"Origin": "https://evil.example"})[0] == 403)
    codes = [http_to(LAN_PORT, "GET", "/v1/health")[0] for _ in range(40)]
    check("LAN is rate limited", 429 in codes, str(sorted(set(codes))))
    check("loopback API is not rate limited", all(http("GET", "/v1/health")[0] == 200 for _ in range(40)))

    print("▸ HUD, island, removal")
    check("hud accepted", ctl(e, "hud", "volume", "0.4").returncode == 0)
    check("presentation is hud", state(e).get("presentation") == "hud")
    ctl(e, "open")
    check("island opens via API", state(e).get("presentation") == "expanded")
    ctl(e, "close")
    check("island closes via API", state(e).get("presentation") != "expanded")
    ctl(e, "rm", "build")
    check("rm removes", "build" not in activities(e))
    status, body = http("DELETE", "/v1/activities?source=run", token)
    check("clear by source", status == 200 and body.get("removed") == 2, str(body))

    print("▸ plugins")
    pa = wait_for(lambda: activities(e).get("plugin-e2e"), timeout=8)
    check("JSON plugin becomes an activity", pa and pa["title"] == "Plugin says hi", str(pa))

    print("▸ live config reload")
    with open(e.config_path) as f:
        cfg = json.load(f)
    cfg["mutedSources"] = ["noisy"]
    with open(e.config_path, "w") as f:
        json.dump(cfg, f)
    time.sleep(1.0)
    http("POST", "/v1/activities", token, {"id": "muted-1", "source": "noisy", "title": "should not show"})
    check("muted source is ignored after reload", "muted-1" not in activities(e))

    print("▸ URL scheme")
    lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if os.path.exists(lsreg):
        subprocess.run([lsreg, "-f", APP], capture_output=True)
        subprocess.run(["open", "-g", "islet://notify?title=From%20URL&ttl=30"], capture_output=True)
        got = wait_for(lambda: any(a["title"] == "From URL" for a in activities(e).values()), timeout=6)
        check("islet:// URL creates a notification", got)
        subprocess.run(["open", "-g", "islet://focus?name=Sleep&state=on"], capture_output=True)
        got = wait_for(lambda: activities(e).get("focus", {}).get("title") == "Sleep", timeout=6)
        check("islet://focus from a Shortcuts automation", got)
        # Menu bar items can only be pressed by a click in Islet, never through a URL.
        subprocess.run(["open", "-g", "islet://menubar-activity?key=id:x"], capture_output=True)
        time.sleep(0.5)
        check("islet://menubar-activity is not a command", ctl(e, "health").returncode == 0)
    else:
        skip("islet:// URL", "lsregister not found")

    print("▸ MCP server")
    msgs = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "e2e", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "show_progress", "arguments": {"id": "e2e", "title": "Refactoring", "step": 2, "steps": 5}}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "finish", "arguments": {"id": "e2e", "success": True}}},
    ]
    p = ctl(e, "mcp", stdin="".join(json.dumps(m) + "\n" for m in msgs), check_rc=False)
    replies = {r.get("id"): r for r in (json.loads(l) for l in p.stdout.splitlines() if l.strip())}
    check("MCP handshake and tool list", replies.get(1, {}).get("result", {}).get("protocolVersion") == "2025-06-18"
          and len(replies.get(2, {}).get("result", {}).get("tools", [])) >= 5, p.stdout[:300])
    got = activities(e).get("mcp-e2e", {})
    check("MCP tools drive an activity", got.get("state") == "success" and got.get("step") == 2, str(got))

    print("▸ menu bar Live Activities")
    p = ctl(e, "debug", "menubar", check_rc=False)
    try:
        items = json.loads(p.stdout or "null")
    except ValueError:
        items = None
    check("debug menubar returns the MenuBarAgent items as JSON", p.returncode == 0 and isinstance(items, list), p.stderr.strip())
    system = {"Battery", "Wi‑Fi", "Wi-Fi", "Bluetooth", "Clock", "Control Center", "Screen Mirroring", "Now Playing"}
    mirrored = [a for a in activities(e).values() if a.get("source") == "live-activity"]
    check("system menu extras are never mirrored as Live Activities",
          not any(a["title"] in system for a in mirrored), str([a["title"] for a in mirrored]))

    print("▸ window server")
    info = json.loads(subprocess.run([windows_bin, str(app.pid)], capture_output=True, text=True).stdout)
    wins = [w for w in info["windows"] if w["layer"] == 27]
    check("island panel above the menu bar (level 27)", wins, str(info["windows"]))
    if wins:
        w = wins[0]
        disp = next((dd for dd in info["displays"] if dd["builtin"]), info["displays"][0])
        centered = abs((w["x"] + w["width"] / 2) - (disp["x"] + disp["width"] / 2)) < 1
        check("panel is centred on the notched display and touches the top", centered and abs(w["y"] - disp["y"]) < 1, str(w))

    print("▸ single instance")
    second = subprocess.Popen([EXE], env=e.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        second.wait(timeout=6)
        check("second launch exits", True)
    except subprocess.TimeoutExpired:
        second.kill()
        check("second launch exits", False, "still running after 6s")

    print("▸ idle performance")
    ctl(e, "close")
    http("DELETE", "/v1/activities?source=timer", token)
    for a in activities(e):
        http("DELETE", f"/v1/activities/{a}", token)
    time.sleep(3)  # let animations and deadline timers settle
    # Two windows; judge the quieter one so unrelated system load doesn't fail the run.
    samples = []
    for _ in range(2):
        c0 = cpu_seconds(app.pid)
        time.sleep(8)
        samples.append((cpu_seconds(app.pid) - c0) / 8 * 100)
    cpu_pct = min(samples)
    mem = rss_mb(app.pid)
    print(f"    idle CPU {cpu_pct:.2f}% (windows: {', '.join(f'{x:.2f}%' for x in samples)}), RSS {mem:.0f} MB")
    check("idle CPU under 1%", cpu_pct < 1.0, f"{cpu_pct:.2f}%")
    check("memory under 150 MB", mem < 150, f"{mem:.0f} MB")

    if os.environ.get("ISLET_E2E_MEDIA") == "1":
        media_suite(e)
    else:
        skip("MediaRemote bridge", "set ISLET_E2E_MEDIA=1")


def media_suite(e):
    print("▸ media (MediaRemote bridge)")
    np = state(e).get("nowPlaying")
    if np and np.get("isPlaying"):
        skip("MediaRemote bridge", f"'{np.get('title')}' is playing; not interrupting it")
        return
    fake = os.path.join(ROOT, "build", "helpers", "FakePlayer")
    if not os.path.exists(fake):
        subprocess.run(["swiftc", "-O", os.path.join(ROOT, "Helpers", "FakePlayer", "main.swift"), "-o", fake], check=True)
    title = "Islet E2E Track"
    log = tempfile.NamedTemporaryFile(delete=False, suffix=".log")
    player = subprocess.Popen([fake, title], stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, FAKE_PLAYER_SECONDS="8"))
    try:
        got = wait_for(lambda: (state(e).get("nowPlaying") or {}).get("title") == title, timeout=8)
        check("bridge reports another app's Now Playing", got, str(state(e).get("nowPlaying")))
        if got:
            # Only send a command once we know it will reach the fake player.
            ctl(e, "media", "playpause")
            time.sleep(1.0)
            with open(log.name) as f:
                check("transport command reaches the player", "command togglePlayPause" in f.read())
    finally:
        player.terminate()
        os.unlink(log.name)


if __name__ == "__main__":
    main()
