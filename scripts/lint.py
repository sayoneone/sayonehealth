#!/usr/bin/env python3
"""SayoneHealth repository lint (ARCHITECTURE.md §5.8, the rules marked ●).

Python 3 standard library only. Prints one line per violation:
    file:line: rule: message
and exits 1 if there is any violation, 0 otherwise. Notes about checks that were
skipped because their input does not exist yet go to stderr and never fail the run.

Usage: python3 scripts/lint.py [--root PATH] [--quiet]
       (--root, or env SAYONE_REPO_ROOT, points the lint at another tree)

How Swift is inspected
  * A small lexer blanks comments and string-literal contents (keeping offsets and
    newlines), so tokens inside comments or strings never trigger a rule. The code
    inside string interpolations stays visible.
  * `#if / #elseif / #else / #endif` nesting is tracked line by line. Each branch
    condition is evaluated with three-valued logic for platform iOS and watchOS
    (`os(X)` is known; DEBUG, canImport(...), etc. are unknown). A line is
    "iOS-guarded" when some enclosing branch can never be active on watchOS, or the
    file is under iOS/; "watch-guarded" the other way round (or under Watch/).

Rules (numbers follow §5.8)
  rule1   iOS-only symbols outside iOS-guarded code
  rule2   watchOS-only symbols outside watch-guarded code; some only under Watch/
  rule3   forbidden symbols everywhere; forbidden entitlements
  rule4   no app-only APIs in Shared/Core, Shared/Intents, Shared/WidgetUI, */Widgets
  rule5   `switch family` has default:; WidgetUI *Views.swift containerBackground + one widgetURL
  rule7   intents: static let title, no description, TypeDisplayRepresentation(name:,
          primitive defaulted @Parameters on widget/control action intents, unique query names
  rule8   App Shortcuts: count, phrase tokens, AppShortcuts.xcstrings keys/en/ru values
  rule10  SayoneCore sources import only Foundation (+ Darwin/Glibc under #if canImport)
  rule11  unique Swift file names; @main exactly once per target folder, never in Shared/
  rule12  plists/entitlements/xcstrings parse; NSExtension placement; bundle identifiers
  rule13  Localizable keys: non-empty en+ru, same %@ count, no other format specifiers
  names   §4: never declare our own Settings/Entry/Label/Link/Timeline/Image/Color/Text/Widget
"""
import argparse
import bisect
import json
import os
import plistlib
import re
import sys

# --------------------------------------------------------------------------- configuration

SKIP_DIRS = {".git", ".build", ".swiftpm", "DerivedData", "build", "node_modules", "xcuserdata"}
APP_ROOTS = ("Shared", "iOS", "Watch")
CORE_SOURCES = "Packages/SayoneCore/Sources"

IOS_ONLY = [
    (".systemSmall", r"\.systemSmall\b"),
    (".systemMedium", r"\.systemMedium\b"),
    (".systemLarge", r"\.systemLarge\b"),
    ("promptsForUserConfiguration", r"\bpromptsForUserConfiguration\b"),
    ("ShortcutsLink", r"\bShortcutsLink\b"),
    ("ControlWidget", r"\bControlWidget\w*"),
    ("ControlConfigurationIntent", r"\bControlConfigurationIntent\b"),
    ("ControlCenter", r"\bControlCenter\b"),
    ("LiveActivityIntent", r"\bLiveActivityIntent\b"),
    ("UIApplication", r"\bUIApplication\w*"),
    ("sessionDidBecomeInactive", r"\bsessionDidBecomeInactive\b"),
    ("sessionDidDeactivate", r"\bsessionDidDeactivate\b"),
    ("isWatchAppInstalled", r"\bisWatchAppInstalled\b"),
    ("isPaired", r"\bisPaired\b"),
    ("keyboardType", r"\bkeyboardType\b"),
    ("EditButton", r"\bEditButton\b"),
    ("fullScreenCover", r"\bfullScreenCover\b"),
]
WATCH_ONLY = [
    (".accessoryCorner", r"\.accessoryCorner\b"),
    ("digitalCrownRotation", r"\bdigitalCrownRotation\b"),
    ("WKInterfaceDevice", r"\bWKInterfaceDevice\b"),
    ("WKApplication", r"\bWKApplication\w*"),
    ("invalidateConfigurationRecommendations", r"\binvalidateConfigurationRecommendations\b"),
    ("func recommendations(", r"\bfunc\s+recommendations\s*\("),
]
WATCH_DIR_ONLY = [
    ("AccessoryWidgetGroup", r"\bAccessoryWidgetGroup\b"),
    ("accessoryWidgetGroupStyle", r"\baccessoryWidgetGroupStyle\b"),
    ("handGestureShortcut", r"\bhandGestureShortcut\b"),
]
FORBIDDEN = [
    ("openAppWhenRun", r"\bopenAppWhenRun\b"),
    ("supportedModes", r"\bsupportedModes\b"),
    ("ForegroundContinuableIntent", r"\bForegroundContinuableIntent\b"),
    ("allowedExecutionTargets", r"\ballowedExecutionTargets\b"),
    ("IntentExecutionTargets", r"\bIntentExecutionTargets\b"),
    ("earliestAuthorizedSampleDate", r"\bearliestAuthorizedSampleDate\b"),
    ("HKCorrelation", r"\bHKCorrelation\w*"),
    ("handleAuthorizationForExtension", r"\bhandleAuthorizationForExtension\b"),
    ("healthDataAccessRequest", r"\bhealthDataAccessRequest\b"),
    ("import HealthKitUI", r"\bimport\s+(?:\w+\s+)?HealthKitUI\b"),
    ("AppIntentsPackage", r"\bAppIntentsPackage\b"),
    ("IntentDescription(", r"\bIntentDescription\s*\("),
    ("requestConfirmation", r"\brequestConfirmation\b"),
    ("fatalError(", r"\bfatalError\s*\("),
    ("SWIFT_DEFAULT_ACTOR_ISOLATION", r"\bSWIFT_DEFAULT_ACTOR_ISOLATION\b"),
    ("AccessoryWidgetBackground", r"\bAccessoryWidgetBackground\b"),
]
FORBIDDEN_ENTITLEMENTS = [
    ("com.apple.developer.siri", re.compile(r"com\.apple\.developer\.siri", re.I)),
    ("aps-environment", re.compile(r"aps-environment", re.I)),
    ("icloud", re.compile(r"icloud", re.I)),
    ("associated-domains", re.compile(r"associated-domains", re.I)),
    ("health-records", re.compile(r"health-records", re.I)),
]
EXTENSION_FREE_DIRS = ("Shared/Core", "Shared/Intents", "Shared/WidgetUI", "iOS/Widgets", "Watch/Widgets")
EXTENSION_BANNED = [
    ("requestAuthorization(", r"\brequestAuthorization\s*\("),
    ("WCSession", r"\bWCSession\w*"),
    ("WatchConnectivity", r"\bWatchConnectivity\b"),
    ("AppModel", r"\bAppModel\b"),
    ("CatalogSync", r"\bCatalogSync\b"),
    ("SayoneShortcuts", r"\bSayoneShortcuts\b"),
]
WIDGET_DIRS = ("Shared/WidgetUI", "iOS/Widgets", "Watch/Widgets")
MAIN_DIRS = ("iOS/App", "Watch/App", "iOS/Widgets", "Watch/Widgets")
RESERVED_TYPE_NAMES = ("Settings", "Entry", "Label", "Link", "Timeline", "Image", "Color", "Text", "Widget")
PRIMITIVE_PARAM_TYPES = {"String", "Int", "Double", "Bool", "Float"}
QUERY_PROTOCOLS = r"(?:EntityQuery|EntityStringQuery|EnumerableEntityQuery|EntityPropertyQuery|UniqueAppEntityQuery)"
SHORTCUT_PLACEHOLDERS = {"applicationName", "amount", "drink"}
MAX_APP_SHORTCUTS = 10

EXPECTED_TARGETS = {
    # target: (type, PRODUCT_BUNDLE_IDENTIFIER, must have NSExtension)
    "SayoneHealth": ("application", "$(BUNDLE_ID_PREFIX)", False),
    "SayoneHealthWidgets": ("app-extension", "$(BUNDLE_ID_PREFIX).widgets", True),
    "SayoneHealthWatch": ("application", "$(BUNDLE_ID_PREFIX).watchkitapp", False),
    "SayoneHealthWatchWidgets": ("app-extension", "$(BUNDLE_ID_PREFIX).watchkitapp.widgets", True),
}
APP_PLISTS = ("iOS/App/Info.plist", "Watch/App/Info.plist")
WIDGET_PLISTS = ("iOS/Widgets/Info.plist", "Watch/Widgets/Info.plist")
LOCALIZATION_FRAGMENTS = ("shared", "widgets", "ios", "watch", "siri")
LOCALIZABLE = "Shared/Resources/Localizable.xcstrings"

# printf-style specifiers; %@ and %N$@ are the only ones allowed
SPEC_RE = re.compile(r"%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]")
OBJ_SPEC_RE = re.compile(r"^%(?:\d+\$)?@$")

# --------------------------------------------------------------------------- Swift lexer


def lex_swift(text):
    """Return (code, spans).

    code  -- `text` with comments and string-literal contents replaced by spaces
             (newlines kept, same length). Interpolated code stays; the `\\(` and `)`
             of an interpolation are blanked so brackets stay balanced.
    spans -- string literals as (start, end, depth, hashes, multiline); depth 0 is a
             top-level literal, depth > 0 a literal inside an interpolation.
    """
    n = len(text)
    out = list(text)
    spans = []

    def blank(i, j):
        for k in range(i, min(j, n)):
            if out[k] != "\n":
                out[k] = " "

    def string_start(i):
        h = 0
        while i + h < n and text[i + h] == "#":
            h += 1
        if i + h < n and text[i + h] == '"':
            return h, text.startswith('"""', i + h)
        return None

    def scan_code(i, interp, depth):
        paren = 0
        while i < n:
            c = text[i]
            if c == "/" and text.startswith("//", i):
                j = text.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
                continue
            if c == "/" and text.startswith("/*", i):
                j, nest = i + 2, 1
                while j < n and nest:
                    if text.startswith("/*", j):
                        nest, j = nest + 1, j + 2
                    elif text.startswith("*/", j):
                        nest, j = nest - 1, j + 2
                    else:
                        j += 1
                blank(i, j)
                i = j
                continue
            if c == "#" or c == '"':
                s = string_start(i)
                if s:
                    i = scan_string(i, s[0], s[1], depth)
                    continue
            if interp:
                if c == "(":
                    paren += 1
                elif c == ")":
                    if paren == 0:
                        return i
                    paren -= 1
            i += 1
        return n

    def scan_string(i, h, ml, depth):
        start = i
        i += h + (3 if ml else 1)
        close = ('"""' if ml else '"') + "#" * h
        esc = "\\" + "#" * h
        seg = i
        while i < n:
            if text.startswith(esc, i):
                j = i + len(esc)
                if j < n and text[j] == "(":
                    blank(seg, j + 1)
                    k = scan_code(j + 1, True, depth + 1)
                    blank(k, k + 1)
                    i = seg = k + 1
                    continue
                i = j + 1
                continue
            if text.startswith(close, i):
                blank(seg, i)
                end = i + len(close)
                spans.append((start, end, depth, h, ml))
                return end
            if not ml and text[i] == "\n":
                blank(seg, i)
                spans.append((start, i, depth, h, ml))
                return i
            i += 1
        blank(seg, n)
        spans.append((start, n, depth, h, ml))
        return n

    scan_code(0, False, 0)
    return "".join(out), sorted(spans)


# --------------------------------------------------------------------------- #if evaluation

_COND_TOKEN = re.compile(r"\s*(\|\||&&|!|\(|\)|[A-Za-z_]\w*\s*\([^()]*\)|[A-Za-z_]\w*|\S)")
_eval_cache = {}


def _and(values):
    if any(v is False for v in values):
        return False
    return None if any(v is None for v in values) else True


def _or(values):
    if any(v is True for v in values):
        return True
    return None if any(v is None for v in values) else False


def _not(v):
    return None if v is None else not v


def eval_condition(cond, platform):
    """Evaluate a `#if` condition for `platform` ('iOS' or 'watchOS'): True, False or None (unknown)."""
    key = (cond, platform)
    if key in _eval_cache:
        return _eval_cache[key]
    toks = [t.strip() for t in _COND_TOKEN.findall(cond) if t.strip()]
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take():
        pos[0] += 1
        return toks[pos[0] - 1]

    def p_or():
        vals = [p_and()]
        while peek() == "||":
            take()
            vals.append(p_and())
        return _or(vals)

    def p_and():
        vals = [p_unary()]
        while peek() == "&&":
            take()
            vals.append(p_unary())
        return _and(vals)

    def p_unary():
        if peek() == "!":
            take()
            return _not(p_unary())
        return p_atom()

    def p_atom():
        t = take()
        if t == "(":
            v = p_or()
            if take() != ")":
                raise ValueError("unbalanced")
            return v
        m = re.match(r"^([A-Za-z_]\w*)\s*\((.*)\)$", t)
        if m:
            if m.group(1) == "os":
                return m.group(2).strip() == platform
            return None
        if t == "true":
            return True
        if t == "false":
            return False
        if re.match(r"^[A-Za-z_]\w*$", t):
            return None
        raise ValueError("unexpected token %r" % t)

    try:
        value = p_or()
        if pos[0] != len(toks):
            value = None
    except (ValueError, IndexError):
        value = None
    _eval_cache[key] = value
    return value


def branch_value(priors, cur, platform):
    vals = [_not(eval_condition(p, platform)) for p in priors]
    if cur is not None:
        vals.append(eval_condition(cur, platform))
    return _and(vals)


# --------------------------------------------------------------------------- Swift file model

_DIRECTIVE = re.compile(r"^\s*#(if|elseif|else|endif)\b(.*)$")


class SwiftFile:
    def __init__(self, root, rel):
        self.rel = rel
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            self.raw = f.read()
        self.code, self.spans = lex_swift(self.raw)
        self.line_starts = [0] + [m.end() for m in re.finditer("\n", self.raw)]
        self.code_lines = self.code.split("\n")
        self.under_ios = rel.startswith("iOS/")
        self.under_watch = rel.startswith("Watch/")
        self._track_directives()

    def line_of(self, index):
        return bisect.bisect_right(self.line_starts, index)

    def _track_directives(self):
        frames = []
        self.directive = []
        self.frames_at = []
        for line in self.code_lines:
            m = _DIRECTIVE.match(line)
            if m:
                kind, rest = m.group(1), m.group(2).strip()
                if kind == "if":
                    frames.append(([], rest))
                elif kind == "elseif" and frames:
                    priors, cur = frames.pop()
                    frames.append((priors + ([cur] if cur is not None else []), rest))
                elif kind == "else" and frames:
                    priors, cur = frames.pop()
                    frames.append((priors + ([cur] if cur is not None else []), None))
                elif kind == "endif" and frames:
                    frames.pop()
            self.directive.append(bool(m))
            self.frames_at.append(tuple((tuple(p), c) for p, c in frames))

    def ios_guarded(self, line):
        if self.under_ios:
            return True
        return any(branch_value(p, c, "watchOS") is False for p, c in self.frames_at[line - 1])

    def watch_guarded(self, line):
        if self.under_watch:
            return True
        return any(branch_value(p, c, "iOS") is False for p, c in self.frames_at[line - 1])

    def active_on(self, line, platform):
        return all(branch_value(p, c, platform) is not False for p, c in self.frames_at[line - 1])

    def guarded_by_can_import(self, line, module):
        pat = re.compile(r"(?<!!)\bcanImport\s*\(\s*%s\s*\)" % re.escape(module))
        return any(c is not None and pat.search(c) for _, c in self.frames_at[line - 1])

    def code_line_matches(self, pattern):
        """Yield (line, match) for `pattern` on non-directive code lines."""
        rx = re.compile(pattern)
        for i, line in enumerate(self.code_lines, 1):
            if self.directive[i - 1]:
                continue
            for m in rx.finditer(line):
                yield i, m

    def literal(self, span):
        start, end, _depth, h, ml = span
        q = 3 if ml else 1
        return self.raw[start + h + q:end - q - h]


def match_bracket(code, open_index):
    """Index of the bracket closing code[open_index] (one of ( [ {), or -1."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    opener = code[open_index]
    closer = pairs[opener]
    depth = 0
    for i in range(open_index, len(code)):
        c = code[i]
        if c == opener:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                return i
    return -1


# --------------------------------------------------------------------------- linter


class Linter:
    def __init__(self, root, quiet=False):
        self.root = root
        self.quiet = quiet
        self.violations = []
        self.notes = []
        self.swift = {}          # rel -> SwiftFile (Shared, iOS, Watch, Packages/*/Sources)
        self.all_swift = []      # every .swift file (for rule 11 names)

    # ---- helpers
    def report(self, rel, line, rule, msg):
        self.violations.append((rel, line or 1, rule, msg))

    def note(self, msg):
        self.notes.append(msg)

    def path(self, rel):
        return os.path.join(self.root, rel)

    def exists(self, rel):
        return os.path.exists(self.path(rel))

    def walk(self, suffixes):
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = sorted(d for d in dirnames
                                 if d not in SKIP_DIRS and not d.endswith((".xcodeproj", ".xcworkspace")))
            for name in sorted(filenames):
                if name.endswith(suffixes):
                    yield os.path.relpath(os.path.join(dirpath, name), self.root).replace(os.sep, "/")

    def files_under(self, *prefixes):
        return [f for rel, f in sorted(self.swift.items()) if rel.startswith(tuple(p.rstrip("/") + "/" for p in prefixes))]

    def app_files(self):
        return self.files_under(*APP_ROOTS)

    def load(self):
        for rel in self.walk((".swift",)):
            self.all_swift.append(rel)
            if rel.startswith(tuple(r + "/" for r in APP_ROOTS)) or re.match(r"^Packages/[^/]+/Sources/", rel):
                self.swift[rel] = SwiftFile(self.root, rel)

    # ---- rules 1-4: symbol placement
    def check_symbols(self):
        for f in self.app_files():
            for name, pat in IOS_ONLY:
                for line, _ in f.code_line_matches(pat):
                    if not f.ios_guarded(line):
                        self.report(f.rel, line, "rule1", "'%s' is iOS-only; guard it with #if os(iOS) or move it under iOS/" % name)
            for name, pat in WATCH_ONLY:
                for line, _ in f.code_line_matches(pat):
                    if not f.watch_guarded(line):
                        self.report(f.rel, line, "rule2", "'%s' is watchOS-only; guard it with #if os(watchOS) or move it under Watch/" % name)
            if not f.under_watch:
                for name, pat in WATCH_DIR_ONLY:
                    for line, _ in f.code_line_matches(pat):
                        self.report(f.rel, line, "rule2", "'%s' may only be used in files under Watch/ (e.g. Watch/Widgets/WatchWidgetFeatures.swift)" % name)
            if f.rel.startswith(tuple(d + "/" for d in EXTENSION_FREE_DIRS)):
                for name, pat in EXTENSION_BANNED:
                    for line, _ in f.code_line_matches(pat):
                        self.report(f.rel, line, "rule4", "'%s' must not be used in %s (app-only API; widgets compile this folder)" % (name, "/".join(f.rel.split("/")[:2])))
        for f in self.app_files() + self.files_under(CORE_SOURCES):
            for name, pat in FORBIDDEN:
                for line, _ in f.code_line_matches(pat):
                    self.report(f.rel, line, "rule3", "'%s' is forbidden" % name)
            for line, m in f.code_line_matches(r"\b(?:struct|class|enum|actor|protocol)\s+(%s)\b" % "|".join(RESERVED_TYPE_NAMES)):
                self.report(f.rel, line, "names", "never declare a type named '%s' (collides with SwiftUI/WidgetKit)" % m.group(1))

    # ---- rule 5: widget families, container background, widgetURL
    def check_widget_views(self):
        for f in self.app_files():
            for m in re.finditer(r"\bswitch\s+(?:[A-Za-z_][\w.]*\.)?(?:family|widgetFamily)\s*\{", f.code):
                brace = m.end() - 1
                end = match_bracket(f.code, brace)
                body = f.code[brace:end if end > 0 else len(f.code)]
                if not re.search(r"\bdefault\s*:", body):
                    self.report(f.rel, f.line_of(m.start()), "rule5", "'switch %s' must have a 'default:' case" % m.group(0).split()[1])
        for f in self.files_under("Shared/WidgetUI"):
            if not f.rel.endswith("Views.swift") or not re.search(r":\s*View\b", f.code):
                continue
            if not re.search(r"\bcontainerBackground\s*\(\s*for\s*:\s*\.widget\b", f.code):
                self.report(f.rel, 1, "rule5", "widget view file must apply containerBackground(for: .widget) on its root view")
            urls = [f.line_of(m.start()) for m in re.finditer(r"\.widgetURL\s*\(", f.code)]
            for platform in ("iOS", "watchOS"):
                active = [ln for ln in urls if f.active_on(ln, platform)]
                if len(active) != 1:
                    self.report(f.rel, active[1] if len(active) > 1 else 1, "rule5",
                                "the root widget view must have exactly one .widgetURL (found %d for %s)" % (len(active), platform))

    # ---- rule 7: intents
    def check_intents(self):
        intent_decl = re.compile(r"(?::|,)\s*(?:AppIntent|WidgetConfigurationIntent|ControlConfigurationIntent)\b")
        for f in self.app_files():
            if intent_decl.search(f.code):
                for line, _ in f.code_line_matches(r"\bstatic\s+var\s+title\b"):
                    self.report(f.rel, line, "rule7", "intent metadata must be 'static let title', not 'static var title'")
                for line, _ in f.code_line_matches(r"\bstatic\s+(?:let|var)\s+description\b"):
                    self.report(f.rel, line, "rule7", "intents must not declare 'description' (§5.4)")
            for m in re.finditer(r"\bTypeDisplayRepresentation\s*\(", f.code):
                if not f.code[m.end():].lstrip().startswith("name:"):
                    self.report(f.rel, f.line_of(m.start()), "rule7", "write TypeDisplayRepresentation(name: ...)")
            for m in re.finditer(r"\bstatic\s+(?:let|var)\s+typeDisplayRepresentation\b\s*(?::\s*[\w.]+\s*)?([={])", f.code):
                rest = f.code[m.end():]
                if m.group(1) == "=":
                    ok = rest.lstrip().startswith("TypeDisplayRepresentation")
                else:
                    close = match_bracket(f.code, m.end() - 1)
                    ok = bool(re.search(r"\bTypeDisplayRepresentation\s*\(\s*name:", f.code[m.end():close]))
                if not ok:
                    self.report(f.rel, f.line_of(m.start()), "rule7",
                                "typeDisplayRepresentation must be TypeDisplayRepresentation(name: ...), never .init( or a literal")

        # widget / control action intents: primitive @Parameters with default:
        action_names = set()
        action_rx = re.compile(r"\b(?:Button|Toggle|ControlWidgetButton|ControlWidgetToggle)\s*\("
                               r"(?:[^()]|\([^()]*\))*?\b(?:intent|action)\s*:\s*([A-Z]\w*)\s*\(")
        for f in self.files_under(*WIDGET_DIRS):
            action_names.update(m.group(1) for m in action_rx.finditer(f.code))
        decl_rx = re.compile(r"\b(?:struct|class)\s+([A-Z]\w*)\s*:([^{]*)\{")
        for f in self.files_under("Shared/Intents"):
            for m in decl_rx.finditer(f.code):
                if re.search(r"\bAppIntent\b", m.group(2)):
                    action_names.add(m.group(1))
        param_rx = re.compile(r"@Parameter\b\s*(\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?\s*"
                              r"(?:(?:public|internal|private|fileprivate)\s+)?var\s+(\w+)\s*:\s*([^\s={]+)")
        for f in self.app_files():
            for m in decl_rx.finditer(f.code):
                name, inherits = m.group(1), m.group(2)
                if name not in action_names or re.search(r"\b(?:WidgetConfigurationIntent|ControlConfigurationIntent)\b", inherits):
                    continue
                if not re.search(r"\b(?:AppIntent|LiveActivityIntent)\b", inherits):
                    continue
                end = match_bracket(f.code, m.end() - 1)
                body_start = m.end()
                body = f.code[body_start:end if end > 0 else len(f.code)]
                for p in param_rx.finditer(body):
                    args, var, typ = p.group(1) or "", p.group(2), p.group(3)
                    line = f.line_of(body_start + p.start())
                    if typ not in PRIMITIVE_PARAM_TYPES:
                        self.report(f.rel, line, "rule7", "%s.%s: widget/control intents take only non-optional primitive "
                                    "@Parameters (String/Int/Double/Bool), got '%s'" % (name, var, typ))
                    if not re.search(r"\bdefault\s*:", args):
                        self.report(f.rel, line, "rule7", "%s.%s: widget/control intent @Parameter needs 'default:'" % (name, var))

        queries = {}
        for f in self.app_files():
            for m in re.finditer(r"\b(?:struct|class|enum|actor)\s+([A-Za-z_]\w*)\s*:[^{]*?\b%s\b" % QUERY_PROTOCOLS, f.code):
                queries.setdefault(m.group(1), []).append((f.rel, f.line_of(m.start())))
        for name, places in sorted(queries.items()):
            if len(places) > 1:
                for rel, line in places[1:]:
                    self.report(rel, line, "rule7", "query type name '%s' is declared more than once (first at %s:%d)" % (name, places[0][0], places[0][1]))

    # ---- rule 8: App Shortcuts
    @staticmethod
    def phrase_key(phrase):
        s = re.sub(r"\\\(\s*\.applicationName\s*\)", "${applicationName}", phrase)
        return re.sub(r"\\\(\s*\\\.\$(\w+)\s*\)", r"${\1}", s)

    def check_app_shortcuts(self):
        shortcuts = []   # (file, line, [phrases])
        total = 0
        for f in self.app_files():
            for m in re.finditer(r"\bAppShortcut\s*\(", f.code):
                total += 1
                open_i = m.end() - 1
                close_i = match_bracket(f.code, open_i)
                call = f.code[open_i:close_i if close_i > 0 else len(f.code)]
                pm = re.search(r"\bphrases\s*:\s*\[", call)
                line = f.line_of(m.start())
                if not pm:
                    self.report(f.rel, line, "rule8", "AppShortcut without a phrases: [...] array")
                    continue
                lb = open_i + pm.end() - 1
                rb = match_bracket(f.code, lb)
                phrases = []
                for span in f.spans:
                    if span[2] == 0 and lb < span[0] < rb:
                        phrases.append((f.line_of(span[0]), f.literal(span)))
                if not phrases:
                    self.report(f.rel, line, "rule8", "AppShortcut has no phrase literals")
                    continue
                for pline, ph in phrases:
                    n_app = len(re.findall(r"\\\(\s*\.applicationName\s*\)", ph))
                    n_par = len(re.findall(r"\\\(\s*\\\.\$\w+\s*\)", ph))
                    if n_app != 1:
                        self.report(f.rel, pline, "rule8", "phrase must contain \\(.applicationName) exactly once (found %d): \"%s\"" % (n_app, ph))
                    if n_par > 1:
                        self.report(f.rel, pline, "rule8", "phrase may contain at most one \\(\\.$parameter) (found %d): \"%s\"" % (n_par, ph))
                shortcuts.append((f, line, [self.phrase_key(p) for _, p in phrases]))
        if total > MAX_APP_SHORTCUTS:
            f, line, _ = shortcuts[-1] if shortcuts else (None, 1, None)
            self.report(f.rel if f else "Shared", line, "rule8",
                        "AppShortcut( appears %d times; an app may have at most %d" % (total, MAX_APP_SHORTCUTS))

        catalogs = [rel for rel in self.walk((".xcstrings",)) if os.path.basename(rel) == "AppShortcuts.xcstrings"]
        if not catalogs:
            if shortcuts:
                f, line, _ = shortcuts[0]
                self.report(f.rel, line, "rule8", "AppShortcuts are declared but Shared/AppOnly/Siri/AppShortcuts.xcstrings is missing (§7)")
            else:
                self.note("no AppShortcutsProvider and no AppShortcuts.xcstrings yet; App Shortcut checks skipped")
            return
        for rel in catalogs:
            data, raw = self.load_json(rel, "rule12")
            if data is None:
                continue
            strings = data.get("strings") if isinstance(data, dict) else None
            if not isinstance(strings, dict):
                self.report(rel, 1, "rule8", "missing top-level \"strings\" object")
                continue
            first = {phr[0]: (f, line, phr) for f, line, phr in shortcuts}
            for key, entry in strings.items():
                kline = self.json_line(raw, key)
                locs = entry.get("localizations", {}) if isinstance(entry, dict) else {}
                sets = {}
                for lang in ("en", "ru"):
                    loc = locs.get(lang)
                    if not isinstance(loc, dict):
                        self.report(rel, kline, "rule8", "key \"%s\" has no \"%s\" phrases" % (key, lang))
                        continue
                    values = (loc.get("stringSet") or {}).get("values")
                    if values is None and "stringUnit" in loc:
                        values = [loc["stringUnit"].get("value")]
                    if not isinstance(values, list) or not values:
                        self.report(rel, kline, "rule8", "key \"%s\": empty \"%s\" phrase list" % (key, lang))
                        continue
                    sets[lang] = values
                    for v in values:
                        if not isinstance(v, str):
                            self.report(rel, kline, "rule8", "key \"%s\": non-string %s phrase" % (key, lang))
                            continue
                        vline = self.json_line(raw, v, kline)
                        n_app = v.count("${applicationName}")
                        if n_app != 1:
                            self.report(rel, vline, "rule8", "%s phrase must contain ${applicationName} exactly once (found %d): \"%s\"" % (lang, n_app, v))
                        bad = sorted(set(re.findall(r"\$\{(\w*)\}", v)) - SHORTCUT_PLACEHOLDERS)
                        if bad:
                            self.report(rel, vline, "rule8", "%s phrase uses unknown placeholder(s) %s: \"%s\"" % (lang, ", ".join("${%s}" % b for b in bad), v))
                if not shortcuts:
                    continue
                if key not in first:
                    self.report(rel, kline, "rule8", "key \"%s\" is not the first Swift phrase of any AppShortcut" % key)
                elif "en" in sets and sets["en"] != first[key][2]:
                    self.report(rel, kline, "rule8", "en phrases of \"%s\" must equal the Swift phrase list %s" % (key, first[key][2]))
            for key, (f, line, _) in first.items():
                if key not in strings:
                    self.report(f.rel, line, "rule8", "no AppShortcuts.xcstrings entry for first phrase \"%s\" (%s)" % (key, rel))

    # ---- rule 10: SayoneCore imports
    def check_core_imports(self):
        rx = re.compile(r"^\s*(?:@[\w()]+\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_]\w*)")
        for f in self.files_under(CORE_SOURCES):
            for i, line in enumerate(f.code_lines, 1):
                m = rx.match(line)
                if not m:
                    continue
                mod = m.group(1)
                if mod == "Foundation":
                    continue
                if mod in ("Darwin", "Glibc") and f.guarded_by_can_import(i, mod):
                    continue
                self.report(f.rel, i, "rule10", "SayoneCore may import only Foundation (and Darwin/Glibc inside #if canImport(...)); found 'import %s'" % mod)

    # ---- rule 11: file names and @main
    def check_names_and_main(self):
        seen = {}
        for rel in self.all_swift:
            if re.match(r"^Packages/[^/]+/Tests/", rel):
                continue
            seen.setdefault(os.path.basename(rel), []).append(rel)
        for name, rels in sorted(seen.items()):
            if len(rels) > 1:
                for rel in rels[1:]:
                    self.report(rel, 1, "rule11", "Swift file name '%s' is also used by %s (Xcode: filename used twice)" % (name, rels[0]))
        for d in MAIN_DIRS:
            files = self.files_under(d)
            if not files:
                continue
            hits = [(f.rel, line) for f in files for line, _ in f.code_line_matches(r"@main\b")]
            if len(hits) != 1:
                where = ", ".join("%s:%d" % h for h in hits) or "none"
                rel, line = hits[1] if len(hits) > 1 else (files[0].rel, 1)
                self.report(rel, line, "rule11", "@main must appear exactly once in %s (found %d: %s)" % (d, len(hits), where))
        for f in self.files_under("Shared"):
            for line, _ in f.code_line_matches(r"@main\b"):
                self.report(f.rel, line, "rule11", "@main must never appear in Shared/")

    # ---- rule 12: plists, entitlements, catalogs, project.yml
    def load_json(self, rel, rule):
        try:
            with open(self.path(rel), encoding="utf-8") as fh:
                raw = fh.read()
            return json.loads(raw), raw
        except (ValueError, UnicodeDecodeError) as e:
            self.report(rel, getattr(e, "lineno", 1), rule, "does not parse as JSON: %s" % getattr(e, "msg", e))
            return None, None

    @staticmethod
    def json_line(raw, text, default=1):
        if raw is None:
            return default
        i = raw.find(json.dumps(text, ensure_ascii=False))
        if i < 0:
            i = raw.find(json.dumps(text))
        return raw.count("\n", 0, i) + 1 if i >= 0 else default

    def load_plist(self, rel):
        try:
            with open(self.path(rel), "rb") as fh:
                return plistlib.load(fh)
        except Exception as e:  # plistlib raises several exception types
            self.report(rel, 1, "rule12", "does not parse as a property list: %s" % e)
            return None

    def check_plists(self):
        plists = {}
        for rel in self.walk((".plist", ".entitlements")):
            data = self.load_plist(rel)
            if data is None:
                continue
            plists[rel] = data
            if rel.endswith(".entitlements"):
                for text in self.plist_strings(data):
                    for name, rx in FORBIDDEN_ENTITLEMENTS:
                        if rx.search(text):
                            self.report(rel, 1, "rule3", "forbidden entitlement '%s' (%s); a free Personal Team cannot sign it" % (name, text))
        for rel in self.walk((".xcstrings",)):
            self.load_json(rel, "rule12")
        for rel in self.walk((".json",)):
            if ".xcassets/" in rel:
                self.load_json(rel, "rule12")
        for rel in APP_PLISTS:
            if rel in plists and isinstance(plists[rel], dict) and "NSExtension" in plists[rel]:
                self.report(rel, 1, "rule12", "app Info.plist must not contain NSExtension (see R16)")
        for rel in WIDGET_PLISTS:
            if rel in plists and isinstance(plists[rel], dict):
                ext = plists[rel].get("NSExtension")
                if not isinstance(ext, dict) or ext.get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
                    self.report(rel, 1, "rule12", "widget Info.plist needs NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension")
        self.check_project_yml()
        for rel in list(self.walk((".xcconfig",))) + ["project.yml"]:
            if self.exists(rel):
                with open(self.path(rel), encoding="utf-8", errors="replace") as fh:
                    for i, line in enumerate(fh, 1):
                        body = line.split("//")[0] if rel.endswith(".xcconfig") else line.split("#")[0]
                        if "SWIFT_DEFAULT_ACTOR_ISOLATION" in body:
                            self.report(rel, i, "rule3", "SWIFT_DEFAULT_ACTOR_ISOLATION is forbidden (D3)")

    def plist_strings(self, obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                yield str(k)
                yield from self.plist_strings(v)
        elif isinstance(obj, (list, tuple)):
            for v in obj:
                yield from self.plist_strings(v)
        elif isinstance(obj, str):
            yield obj

    def check_project_yml(self):
        rel = "project.yml"
        if not self.exists(rel):
            self.note("project.yml not found; project checks skipped")
            return
        with open(self.path(rel), encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        ids = []
        targets = {}
        current = None
        in_targets = False
        for i, line in enumerate(lines, 1):
            body = line.split(" #")[0].rstrip()
            if not body.strip() or body.lstrip().startswith("#"):
                continue
            if re.match(r"^\S", body):
                in_targets = body.startswith("targets:")
                current = None
            elif in_targets:
                m = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", body)
                if m:
                    current = m.group(1)
                    targets[current] = {"line": i, "type": None, "id": None, "ext": False}
            m = re.search(r"\bPRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", body)
            if m:
                value = m.group(1).strip("\"'")
                ids.append((value, i))
                if current:
                    targets[current]["id"] = value
            if current:
                m = re.match(r"^    type:\s*(\S+)", body)
                if m:
                    targets[current]["type"] = m.group(1).strip("\"'")
                if re.match(r"^\s+NSExtension:", body):
                    targets[current]["ext"] = i
            for name, rx in FORBIDDEN_ENTITLEMENTS:
                if rx.search(body):
                    self.report(rel, i, "rule3", "forbidden entitlement '%s'" % name)
        expected_ids = sorted(v[1] for v in EXPECTED_TARGETS.values())
        if sorted(v for v, _ in ids) != expected_ids:
            self.report(rel, ids[0][1] if ids else 1, "rule12",
                        "PRODUCT_BUNDLE_IDENTIFIER values must be exactly %s (found %s)" % (expected_ids, [v for v, _ in ids]))
        for name, (typ, bid, needs_ext) in EXPECTED_TARGETS.items():
            t = targets.get(name)
            if t is None:
                self.report(rel, 1, "rule12", "target '%s' is missing" % name)
                continue
            if t["type"] != typ:
                self.report(rel, t["line"], "rule12", "target '%s' must have type %s (found %s)" % (name, typ, t["type"]))
            if t["id"] != bid:
                self.report(rel, t["line"], "rule12", "target '%s' must have PRODUCT_BUNDLE_IDENTIFIER %s (found %s)" % (name, bid, t["id"]))
            if needs_ext and not t["ext"]:
                self.report(rel, t["line"], "rule12", "widget target '%s' needs NSExtension in its info properties" % name)
            if not needs_ext and t["ext"]:
                self.report(rel, t["ext"], "rule12", "app target '%s' must not declare NSExtension" % name)
        for name, t in targets.items():
            if name not in EXPECTED_TARGETS:
                self.report(rel, t["line"], "rule12", "unexpected target '%s' (§2.1 lists exactly 4)" % name)

    # ---- rule 13: localization
    def check_specifiers(self, rel, line, key, en, ru):
        for lang, value in (("en", en), ("ru", ru)):
            if not isinstance(value, str) or not value.strip():
                self.report(rel, line, "rule13", "key \"%s\": empty or missing %s value" % (key, lang))
                return
        for lang, value in (("key", key), ("en", en), ("ru", ru)):
            if lang == "en" and en == key:
                continue
            for spec in SPEC_RE.findall(value.replace("%%", "")):
                if not OBJ_SPEC_RE.match(spec):
                    self.report(rel, line, "rule13", "key \"%s\": %s uses format specifier '%s'; only %%@ / %%1$@ are allowed "
                                "(format numbers with VolumeText first)" % (key, lang, spec))
        count = lambda s: len([x for x in SPEC_RE.findall(s.replace("%%", "")) if OBJ_SPEC_RE.match(x)])
        if count(en) != count(ru):
            self.report(rel, line, "rule13", "key \"%s\": en has %d %%@ specifier(s), ru has %d" % (key, count(en), count(ru)))

    def check_localization(self):
        missing = []
        for name in LOCALIZATION_FRAGMENTS:
            rel = "Localization/%s.json" % name
            if not self.exists(rel):
                missing.append(rel)
                continue
            data, raw = self.load_json(rel, "rule13")
            if data is None:
                continue
            if not isinstance(data, dict):
                self.report(rel, 1, "rule13", "fragment must be a JSON object")
                continue
            for key, value in data.items():
                line = self.json_line(raw, key)
                if isinstance(value, str):
                    en, ru = key, value
                elif isinstance(value, dict):
                    en, ru = value.get("en", key), value.get("ru")
                else:
                    self.report(rel, line, "rule13", "key \"%s\": value must be a string or {\"en\",\"ru\"}" % key)
                    continue
                self.check_specifiers(rel, line, key, en, ru)
        if missing:
            self.note("missing localization fragments (treated as empty): %s" % ", ".join(missing))
        if not self.exists(LOCALIZABLE):
            self.note("%s not generated yet; run python3 scripts/build_strings.py" % LOCALIZABLE)
            return
        data, raw = self.load_json(LOCALIZABLE, "rule12")
        if not isinstance(data, dict) or not isinstance(data.get("strings"), dict):
            if data is not None:
                self.report(LOCALIZABLE, 1, "rule13", "missing top-level \"strings\" object")
            return
        for key, entry in data["strings"].items():
            locs = entry.get("localizations", {}) if isinstance(entry, dict) else {}
            val = lambda lang: ((locs.get(lang) or {}).get("stringUnit") or {}).get("value")
            self.check_specifiers(LOCALIZABLE, self.json_line(raw, key), key, val("en"), val("ru"))

    # ---- driver
    def run(self):
        self.load()
        self.check_symbols()
        self.check_widget_views()
        self.check_intents()
        self.check_app_shortcuts()
        self.check_core_imports()
        self.check_names_and_main()
        self.check_plists()
        self.check_localization()
        seen = set()
        unique = []
        for v in sorted(self.violations, key=lambda v: (v[0], v[1], v[2], v[3])):
            if v not in seen:
                seen.add(v)
                unique.append(v)
        self.violations = unique
        return self.violations


def main(argv=None):
    ap = argparse.ArgumentParser(description="SayoneHealth repository lint (ARCHITECTURE.md §5.8)")
    ap.add_argument("--root", default=os.environ.get("SAYONE_REPO_ROOT")
                    or os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    help="repository root to lint (default: this script's repo)")
    ap.add_argument("--quiet", action="store_true", help="do not print notes about skipped checks")
    args = ap.parse_args(argv)
    linter = Linter(os.path.abspath(args.root), quiet=args.quiet)
    violations = linter.run()
    for rel, line, rule, msg in violations:
        print("%s:%d: %s: %s" % (rel, line, rule, msg))
    if not args.quiet:
        for n in linter.notes:
            print("lint: note: %s" % n, file=sys.stderr)
    if violations:
        print("lint: %d violation(s)" % len(violations), file=sys.stderr)
        return 1
    print("lint: OK (%d Swift files checked)" % len(linter.swift))
    return 0


if __name__ == "__main__":
    sys.exit(main())
