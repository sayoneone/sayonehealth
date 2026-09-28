#!/usr/bin/env python3
"""Generate Shared/Resources/Localizable.xcstrings from the per-lane fragments.

ARCHITECTURE.md §6.1. Merges, in this order:
    Localization/shared.json, widgets.json, ios.json, watch.json, siri.json
A missing fragment file is treated as empty (a note goes to stderr).

Fragment format (a JSON object):
    {"English key": "Русский"}
    {"key": {"en": "English display text", "ru": "Русский"}}   # when the English text differs from the key

Rules:
  * the same key with different values (ru, or en) in two fragments is an error; identical duplicates are fine
  * output: sourceLanguage "en", version "1.0"; per key extractionState "manual" and
    stringUnit {state "translated", value} for en and ru
  * json.dumps(ensure_ascii=False, indent=2, sort_keys=True) + trailing newline

Usage:
    python3 scripts/build_strings.py            # write the catalog
    python3 scripts/build_strings.py --check    # exit 1 if the committed catalog is missing or differs
    options: --root PATH (or env SAYONE_REPO_ROOT) to run against another tree
Never hand-edit the generated file; on a merge conflict, regenerate it.
"""
import argparse
import json
import os
import sys

FRAGMENTS = ("shared", "widgets", "ios", "watch", "siri")
OUTPUT = os.path.join("Shared", "Resources", "Localizable.xcstrings")


def default_root():
    return os.environ.get("SAYONE_REPO_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class FragmentError(Exception):
    pass


def load_fragment(path, shown):
    """Return {key: (en, ru)} for one fragment file; `shown` is the path used in messages."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise FragmentError("%s:%d: invalid JSON: %s" % (shown, e.lineno, e.msg))
    path = shown
    if not isinstance(data, dict):
        raise FragmentError("%s: top level must be a JSON object" % path)
    out = {}
    for key, value in data.items():
        if not isinstance(key, str) or not key.strip():
            raise FragmentError("%s: empty key" % path)
        if isinstance(value, str):
            en, ru = key, value
        elif isinstance(value, dict):
            extra = set(value) - {"en", "ru"}
            if extra:
                raise FragmentError("%s: key %r: unexpected fields %s (only \"en\" and \"ru\")"
                                    % (path, key, sorted(extra)))
            en, ru = value.get("en", key), value.get("ru")
        else:
            raise FragmentError("%s: key %r: value must be a string or {\"en\",\"ru\"} object" % (path, key))
        if not isinstance(ru, str) or not ru.strip():
            raise FragmentError("%s: key %r: missing or empty \"ru\" value" % (path, key))
        if not isinstance(en, str) or not en.strip():
            raise FragmentError("%s: key %r: empty \"en\" value" % (path, key))
        out[key] = (en, ru)
    return out


def merge(root):
    """Return (merged {key: (en, ru, source)}, missing fragment names)."""
    merged, missing, errors = {}, [], []
    for name in FRAGMENTS:
        path = os.path.join(root, "Localization", name + ".json")
        if not os.path.isfile(path):
            missing.append(name)
            continue
        for key, (en, ru) in load_fragment(path, "Localization/%s.json" % name).items():
            if key in merged:
                pen, pru, psrc = merged[key]
                if pru != ru:
                    errors.append("key %r: different ru values in %s.json (%r) and %s.json (%r)"
                                  % (key, psrc, pru, name, ru))
                if pen != en:
                    errors.append("key %r: different en values in %s.json (%r) and %s.json (%r)"
                                  % (key, psrc, pen, name, en))
                continue
            merged[key] = (en, ru, name)
    if errors:
        raise FragmentError("\n".join(errors))
    return merged, missing


def render(merged):
    def unit(value):
        return {"stringUnit": {"state": "translated", "value": value}}

    strings = {}
    for key in sorted(merged):
        en, ru, _ = merged[key]
        strings[key] = {"extractionState": "manual", "localizations": {"en": unit(en), "ru": unit(ru)}}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Merge Localization/*.json into " + OUTPUT)
    ap.add_argument("--check", action="store_true", help="exit 1 if the committed catalog differs")
    ap.add_argument("--root", default=default_root(), help="repository root (default: this script's repo)")
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root)
    try:
        merged, missing = merge(root)
    except FragmentError as e:
        print("build_strings: error: %s" % e, file=sys.stderr)
        return 1
    for name in missing:
        print("build_strings: note: Localization/%s.json not found; treated as empty" % name, file=sys.stderr)

    text = render(merged)
    out_path = os.path.join(root, OUTPUT)
    if args.check:
        try:
            with open(out_path, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            print("build_strings: %s is missing; run: python3 scripts/build_strings.py" % OUTPUT, file=sys.stderr)
            return 1
        if current != text:
            print("build_strings: %s is out of date with Localization/*.json; "
                  "run: python3 scripts/build_strings.py and commit the result" % OUTPUT, file=sys.stderr)
            return 1
        print("build_strings: %s is up to date (%d keys)" % (OUTPUT, len(merged)))
        return 0

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("build_strings: wrote %s (%d keys)" % (OUTPUT, len(merged)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
