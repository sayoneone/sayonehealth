#!/usr/bin/env python3
"""App Intents metadata gate for CI (ARCHITECTURE.md §8.2, risk R11/R18).

Usage: python3 scripts/check_appintents.py <derivedDataPath> <build.log> [<build.log> ...]

Hard failures (exit 1):
  * any log line matching  appintentsmetadataprocessor.*(error|warning)
    or  No AppIntents metadata have been exported
  * missing Build/Products/Debug-iphonesimulator/SayoneHealth.app/Metadata.appintents/
  * missing SayoneHealth.app/Watch/SayoneHealthWatch.app/Metadata.appintents/

Content assertions (print ::warning:: by default, ::error:: + exit 1 when STRICT_APPINTENTS=1):
  * each app's metadata mentions LogWaterIntent, LogDrinkIntent, TodayTotalIntent, UndoLastIntent,
    has autoShortcuts, and has at most 10 of them when the JSON parses
  * the widget extension metadata (PlugIns/SayoneHealthWidgets.appex, and the watch widget appex
    when present) mentions QuickLogIntent and has no non-empty autoShortcuts

The metadata file name (extract.actionsdata) and format are medium-confidence, so the content
checks are substring-based and stay warnings until the first green run.
"""
import json
import os
import re
import sys

LOG_RE = re.compile(r"appintentsmetadataprocessor.*(error|warning)|No AppIntents metadata have been exported")
APP_INTENTS = ("LogWaterIntent", "LogDrinkIntent", "TodayTotalIntent", "UndoLastIntent")
MAX_SHORTCUTS = 10
PRODUCTS = os.path.join("Build", "Products", "Debug-iphonesimulator")
IOS_APP = "SayoneHealth.app"
WATCH_APP = os.path.join(IOS_APP, "Watch", "SayoneHealthWatch.app")
IOS_WIDGETS = os.path.join(IOS_APP, "PlugIns", "SayoneHealthWidgets.appex")
WATCH_WIDGETS = os.path.join(WATCH_APP, "PlugIns", "SayoneHealthWatchWidgets.appex")
META = "Metadata.appintents"

STRICT = os.environ.get("STRICT_APPINTENTS") == "1"


class Result:
    def __init__(self):
        self.failed = False

    def error(self, msg):
        print("::error::%s" % msg)
        self.failed = True

    def assertion(self, msg):
        if STRICT:
            self.error(msg)
        else:
            print("::warning::%s" % msg)


def read_metadata(folder):
    """Return (combined text, [parsed JSON objects]) for every file under a Metadata.appintents folder."""
    texts, docs = [], []
    for dirpath, _dirs, files in os.walk(folder):
        for name in sorted(files):
            with open(os.path.join(dirpath, name), "rb") as f:
                raw = f.read()
            text = raw.decode("utf-8", errors="replace")
            texts.append(text)
            try:
                docs.append(json.loads(text))
            except ValueError:
                pass
    return "\n".join(texts), docs


def auto_shortcut_counts(docs):
    return [len(d["autoShortcuts"]) for d in docs
            if isinstance(d, dict) and isinstance(d.get("autoShortcuts"), list)]


def check_logs(logs, res):
    for log in logs:
        if not os.path.isfile(log):
            print("::warning::build log not found: %s" % log)
            continue
        with open(log, encoding="utf-8", errors="replace") as f:
            for n, line in enumerate(f, 1):
                if LOG_RE.search(line):
                    res.error("%s:%d: %s" % (os.path.basename(log), n, line.strip()[:400]))


def check_app(label, folder, res):
    text, docs = read_metadata(folder)
    missing = [name for name in APP_INTENTS if name not in text]
    if missing:
        res.assertion("%s metadata does not mention %s" % (label, ", ".join(missing)))
    if "autoShortcuts" not in text:
        res.assertion("%s metadata has no autoShortcuts (App Shortcuts not extracted)" % label)
    for count in auto_shortcut_counts(docs):
        if count > MAX_SHORTCUTS:
            res.error("%s metadata has %d autoShortcuts; at most %d are allowed" % (label, count, MAX_SHORTCUTS))
        elif count == 0:
            res.assertion("%s metadata has an empty autoShortcuts list" % label)
    print("%s: %s checked (%d file(s) parsed as JSON)" % (label, folder, len(docs)))


def check_widget(label, folder, res):
    text, docs = read_metadata(folder)
    if "QuickLogIntent" not in text:
        res.assertion("%s metadata does not mention QuickLogIntent" % label)
    non_empty = [c for c in auto_shortcut_counts(docs) if c > 0]
    if non_empty or (not docs and re.search(r'"autoShortcuts"\s*:\s*\[\s*[^\]\s]', text)):
        res.assertion("%s metadata has autoShortcuts; App Shortcuts belong only in the apps" % label)
    print("%s: %s checked" % (label, folder))


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    derived, logs = argv[1], argv[2:]
    res = Result()
    check_logs(logs, res)

    products = os.path.join(derived, PRODUCTS)
    apps = (("iOS app", os.path.join(products, IOS_APP, META)),
            ("watch app", os.path.join(products, WATCH_APP, META)))
    for label, folder in apps:
        if not os.path.isdir(folder):
            res.error("missing %s (App Intents metadata was not extracted for the %s)" % (folder, label))
        else:
            check_app(label, folder, res)

    for label, appex, required in (("iOS widgets", IOS_WIDGETS, True), ("watch widgets", WATCH_WIDGETS, False)):
        folder = os.path.join(products, appex, META)
        if os.path.isdir(folder):
            check_widget(label, folder, res)
        elif required:
            res.assertion("missing %s" % folder)

    mode = "strict" if STRICT else "warnings for content checks"
    if res.failed:
        print("check_appintents: FAILED (%s)" % mode)
        return 1
    print("check_appintents: OK (%s)" % mode)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
