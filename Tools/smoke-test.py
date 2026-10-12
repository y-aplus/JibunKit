#!/usr/bin/env python3
"""Open every mini app of a built JibunKit app in a booted iOS Simulator.

  python3 Tools/smoke-test.py --simulator UDID --app path/to/JibunKit_App.app \\
      --output DIR [--screenshot-url URL]

installs the app (a Debug build for the Simulator), asks it for its mini apps
(`-JibunKitListMiniApps`), then for each one starts the app fresh with
`-JibunKitOpenMiniApp <id>`, waits, checks that the app is still running and
takes a screenshot. Both arguments work only in Debug builds; a
`jibunkit://` URL would first make iOS ask whether to open the app. A crash is reported with the reason and
the app's own frames from the Simulator's crash report. DIR receives the
screenshots (`home.jpg`, `<id>.jpg`) and `report.txt`; with --screenshot-url the
report links each screenshot as URL/<file>.

This is a smoke test: it proves that each mini app's first screen opens in the
Simulator, not that the app works or that it behaves the same on a device.
Run it on macOS with Xcode. It exits 1 when the app or a mini app crashed.
"""
import argparse
from datetime import datetime
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time

LIST_ARGUMENT = "-JibunKitListMiniApps"
OPEN_ARGUMENT = "-JibunKitOpenMiniApp"
LIST_PREFIX = "jibunkit-mini-app\t"
CRASH_REPORTS = Path.home() / "Library/Logs/DiagnosticReports"
FRAMES = 5
# What Swift, the Objective-C runtime and UIKit print when they stop the app.
STOP_MESSAGE = re.compile(r"Fatal error|Precondition failed|Assertion failed|Terminating app|uncaught exception"
                          r"|Thread \d+: |EXC_[A-Z_]+")


class Failure(Exception):
    pass


def simctl(*args, timeout=120, check=True):
    result = subprocess.run(["xcrun", "simctl", *args], text=True, encoding="utf-8", errors="replace",
                            capture_output=True, timeout=timeout)
    if check and result.returncode != 0:
        raise Failure(f"`simctl {' '.join(args)}` failed: {(result.stderr or result.stdout).strip()}")
    return result


def parse_mini_apps(output):
    """[(id, title)] from the app's `-JibunKitListMiniApps` output."""
    apps = []
    for line in output.splitlines():
        if line.startswith(LIST_PREFIX):
            fields = line[len(LIST_PREFIX):].rstrip("\r").split("\t")
            apps.append((fields[0], fields[1] if len(fields) > 1 else fields[0]))
    return apps


def is_running(launchctl_list, bundle_id):
    """Whether `launchctl list` (inside the Simulator) shows a live process of the app."""
    for line in launchctl_list.splitlines():
        fields = line.split("\t")
        if len(fields) == 3 and fields[2].startswith(f"UIKitApplication:{bundle_id}["):
            return fields[0].strip() not in ("-", "")
    return False


def parse_crash_report(text):
    """The header and body of an .ips crash report, or None when it is not one."""
    header, _, body = text.partition("\n")
    try:
        return json.loads(header), json.loads(body)
    except json.JSONDecodeError:
        return None


def describe_crash(body):
    """Lines that say why the app stopped and where, from an .ips body."""
    lines = []
    exception = body.get("exception") or {}
    kind = " / ".join(value for value in (exception.get("type"), exception.get("signal")) if value)
    if kind:
        lines.append(kind)
    for messages in (body.get("asi") or {}).values():
        lines += [message.strip() for message in messages if message.strip()][:3]
    termination = body.get("termination") or {}
    if termination.get("indicator") and not kind:
        lines.append(termination["indicator"])
    images = body.get("usedImages") or []
    threads = body.get("threads") or []
    faulting = body.get("faultingThread", 0)
    frames = threads[faulting].get("frames", []) if faulting < len(threads) else []

    def own(frame):
        index = frame.get("imageIndex")
        return index is not None and index < len(images) and ".app/" in (images[index].get("path") or "")

    chosen = [frame for frame in frames if own(frame)][:FRAMES] or frames[:FRAMES]
    for frame in chosen:
        symbol = frame.get("symbol") or "?"
        index = frame.get("imageIndex")
        image = images[index].get("name", "?") if index is not None and index < len(images) else "?"
        place = f" ({frame['sourceFile']}:{frame['sourceLine']})" if frame.get("sourceFile") else ""
        lines.append(f"at {symbol}{place} in {image}")
    return lines


def new_crash(bundle_id, since, seen, wait=15):
    """The description of the newest crash report of the app written after `since`, or None.
    ReportCrash writes it a few seconds after the process ends, so this waits up to `wait` seconds."""
    deadline = time.time() + wait
    while True:
        paths = sorted(CRASH_REPORTS.glob("**/*.ips"), key=lambda path: path.stat().st_mtime, reverse=True) \
            if CRASH_REPORTS.is_dir() else []
        for path in paths:
            if path in seen or path.stat().st_mtime < since:
                continue
            parsed = parse_crash_report(path.read_text(encoding="utf-8", errors="replace"))
            if parsed and parsed[0].get("bundleID") == bundle_id:
                seen.add(path)
                return describe_crash(parsed[1])
        if time.time() >= deadline:
            return None
        time.sleep(1)


def stop_messages(console):
    """The lines of the app's console output that say why it stopped, or its last lines."""
    lines = [line.strip() for line in console.splitlines() if line.strip()]
    found = [line for line in lines if STOP_MESSAGE.search(line)]
    return (found or lines[-3:])[:5]


def screenshot(simulator, path):
    """A JPEG screenshot, scaled down so it is quick to load on a phone."""
    png = path.with_suffix(".png")
    simctl("io", simulator, "screenshot", "--type=png", str(png))
    subprocess.run(["sips", "--resampleWidth", "600", "-s", "format", "jpeg", "-s", "formatOptions", "70",
                    str(png), "--out", str(path)], check=True, capture_output=True)
    png.unlink()


def launch(simulator, bundle_id, *arguments):
    return simctl("launch", "--terminate-running-process", simulator, bundle_id, *arguments, timeout=60)


def format_report(device, results, crashed_launch, screenshot_url):
    lines = [f"Opened {len(results)} mini app(s) in the iOS Simulator ({device}), Debug build:"]
    if crashed_launch is not None:
        lines = ["JibunKit stopped before it listed its mini apps:"] + [f"  {line}" for line in crashed_launch]
    for app_id, title, status, details, image in results:
        lines.append(f"{status:<8} {title} ({app_id})")
        lines += [f"         {line}" for line in details]
        if image and screenshot_url:
            lines.append(f"         screenshot: {screenshot_url}/{image}")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--simulator", required=True, help="UDID of a booted iOS Simulator")
    parser.add_argument("--app", required=True, type=Path, help="The built app (Debug, iphonesimulator)")
    parser.add_argument("--output", required=True, type=Path, help="Directory for screenshots and report.txt")
    parser.add_argument("--screenshot-url", help="Where the screenshots will be published, for the report")
    parser.add_argument("--wait", type=float, default=6, help="Seconds to wait after opening a mini app")
    args = parser.parse_args(argv)

    bundle_id = plistlib.loads((args.app / "Info.plist").read_bytes())["CFBundleIdentifier"]
    args.output.mkdir(parents=True, exist_ok=True)
    device = next((f"{item['name']}, {runtime.rsplit('.', 1)[-1]}"
                   for runtime, items in json.loads(simctl("list", "devices", "--json").stdout)["devices"].items()
                   for item in items if item["udid"] == args.simulator), args.simulator)
    simctl("install", args.simulator, str(args.app))
    # Permission prompts would cover the screens; notifications still ask.
    simctl("privacy", args.simulator, "grant", "all", bundle_id, check=False)
    simctl("status_bar", args.simulator, "override", "--time", "9:41", check=False)
    seen = set()
    start = time.time() - 1

    # With --console-pty, launch waits for the app, which prints the list and exits.
    listing = simctl("launch", "--console-pty", "--terminate-running-process", args.simulator, bundle_id,
                     LIST_ARGUMENT, timeout=90, check=False)
    apps = parse_mini_apps(listing.stdout)
    results, crashed_launch = [], None
    if not apps:
        time.sleep(3)
        crashed_launch = new_crash(bundle_id, start, seen) or [
            f"No mini apps were listed (exit status {listing.returncode}).",
            *[line for line in (listing.stdout + listing.stderr).strip().splitlines()[-10:]]]
    else:
        launch(args.simulator, bundle_id)
        time.sleep(args.wait)
        screenshot(args.simulator, args.output / "home.jpg")
        results.append(("home", "Mini app list", "OK", [], "home.jpg"))
    for app_id, title in apps:
        opened = time.time() - 1
        # With --console-pty, launch keeps running with the app and records what it prints.
        console_path = args.output / f"{app_id}.console.txt"
        with console_path.open("w", encoding="utf-8") as console:
            process = subprocess.Popen(["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process",
                                        args.simulator, bundle_id, OPEN_ARGUMENT, app_id],
                                       stdout=console, stderr=subprocess.STDOUT)
            time.sleep(args.wait)
            alive = is_running(simctl("spawn", args.simulator, "launchctl", "list").stdout, bundle_id)
            if alive:
                image = f"{app_id}.jpg"
                screenshot(args.simulator, args.output / image)
            simctl("terminate", args.simulator, bundle_id, check=False)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
        printed = console_path.read_text(encoding="utf-8", errors="replace")
        console_path.unlink()
        if alive:
            results.append((app_id, title, "OK", [], image))
        else:
            details = stop_messages(printed)
            details += new_crash(bundle_id, opened, seen) or ["No crash report was found."]
            results.append((app_id, title, "CRASHED", details, None))

    report = format_report(device, results, crashed_launch, args.screenshot_url)
    (args.output / "report.txt").write_text(report + "\n", encoding="utf-8")
    print(report)
    stamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{stamp}] {sum(1 for result in results if result[2] == 'OK')} OK, "
          f"{sum(1 for result in results if result[2] != 'OK')} crashed", file=sys.stderr)
    return 1 if crashed_launch is not None or any(result[2] != "OK" for result in results) else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Failure as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(2)
