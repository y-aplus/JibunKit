#!/usr/bin/env python3
"""Create Feature packages under Modules/ and connect them to the host.

  new --name Notes   Create Modules/Notes from Tuist/Templates/feature, the same
                     files `tuist scaffold feature --name Notes` creates, then sync.
  sync               Read Modules/*/JibunKitFeature.json and write
                     Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift.
  sync --check       Fail if that file is not up to date.
  check [PATH ...]   Report standalone-app code that affects other Features
                     inside JibunKit (default: every Feature under Modules/).
                     Mark an intended use with `// jibunkit: allow <rule>`.

Both commands need only Python, so they also work on Windows and Linux. The
generated helper is read by Project.swift; `tuist generate` (macOS or CI) then
adds the packages, Integration sources, registry entries, widgets and build
requirements. Hand-registered Features keep working unchanged.
"""
import argparse
import json
from pathlib import Path
import re
import sys

MANIFEST = "JibunKitFeature.json"
HELPER = Path("Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift")
TEMPLATE = Path("Tuist/Templates/feature")
ID_PATTERN = re.compile(r"[a-z][a-z0-9._-]*")
NAME_PATTERN = re.compile(r"[A-Z][A-Za-z0-9]*")
PRODUCT_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
EXPRESSION_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*(\(\))?")
TOP_KEYS = {"schema", "id", "products", "sources", "definitions", "app", "widget", "appShortcuts"}
REQUIREMENT_KEYS = {"infoPlist", "entitlements", "localizedInfoPlist"}
WIDGET_KEYS = REQUIREMENT_KEYS | {"products", "sources", "widgets"}
HOST_IDENTITY_KEYS = {"CFBundleIdentifier", "CFBundleExecutable"}


class FeatureError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise FeatureError(message)


def string_list(value, where, pattern=None):
    require(isinstance(value, list) and all(isinstance(item, str) and item for item in value),
            f"{where} must be a list of nonempty strings")
    require(len(set(value)) == len(value), f"{where} has duplicates")
    if pattern:
        for item in value:
            require(pattern.fullmatch(item), f"{where} has an unsupported value: {item!r}")
    return value


def relative_globs(value, module, where):
    globs = string_list(value, where)
    for glob in globs:
        parts = Path(glob).parts
        require(not Path(glob).is_absolute() and "\\" not in glob and ".." not in parts,
                f"{where} must stay inside the Feature directory: {glob!r}")
        fixed = []
        for part in parts:
            if "*" in part or "?" in part:
                break
            fixed.append(part)
        require(fixed and (module / Path(*fixed)).exists(),
                f"{where} points to a missing directory or file: {glob!r}")
    return globs


def library_products(module):
    package = module / "Package.swift"
    require(package.is_file(), f"{module.as_posix()} has no Package.swift")
    return set(re.findall(r'\.library\(\s*name:\s*"([^"]+)"', package.read_text(encoding="utf-8")))


def plist_value(value, where):
    require(value is not None, f"{where} must not be null")
    if isinstance(value, dict):
        for key, item in value.items():
            plist_value(item, f"{where}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            plist_value(item, f"{where}[{index}]")
    else:
        require(isinstance(value, (str, bool, int, float)), f"{where} has an unsupported type")


def requirement(value, where, allowed):
    require(isinstance(value, dict), f"{where} must be an object")
    unknown = set(value) - allowed
    require(not unknown, f"{where} has unknown keys: {', '.join(sorted(unknown))}")
    for key in ("infoPlist", "entitlements"):
        section = value.get(key, {})
        require(isinstance(section, dict), f"{where}.{key} must be an object")
        plist_value(section, f"{where}.{key}")
    clash = HOST_IDENTITY_KEYS & set(value.get("infoPlist", {}))
    require(not clash, f"{where}.infoPlist must not set host identity keys: {', '.join(sorted(clash))}")
    localized = value.get("localizedInfoPlist", {})
    require(isinstance(localized, dict) and all(
        isinstance(strings, dict) and all(isinstance(text, str) for text in strings.values())
        for strings in localized.values()), f"{where}.localizedInfoPlist must map locales to string tables")
    return value


def load(module):
    path = module / MANIFEST
    where = path.as_posix()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise FeatureError(f"{where} is not valid JSON: {error}") from None
    require(isinstance(data, dict), f"{where} must contain an object")
    unknown = set(data) - TOP_KEYS
    require(not unknown, f"{where} has unknown keys: {', '.join(sorted(unknown))}")
    require(data.get("schema") == 1, f"{where} needs \"schema\": 1")
    feature_id = data.get("id")
    require(isinstance(feature_id, str) and ID_PATTERN.fullmatch(feature_id),
            f"{where} needs an \"id\" that starts with a lowercase letter and uses only a-z, 0-9, '.', '-', '_'")
    products = string_list(data.get("products", []), f"{where} products", PRODUCT_PATTERN)
    widget = data.get("widget")
    if widget is not None:
        requirement(widget, f"{where} widget", WIDGET_KEYS)
        string_list(widget.get("products", []), f"{where} widget.products", PRODUCT_PATTERN)
        relative_globs(widget.get("sources", []), module, f"{where} widget.sources")
        string_list(widget.get("widgets", []), f"{where} widget.widgets", EXPRESSION_PATTERN)
    declared = library_products(module)
    for product in products + (widget or {}).get("products", []):
        require(product in declared, f"{where} names {product!r}, which {module.as_posix()}/Package.swift does not declare as a library")
    relative_globs(data.get("sources", []), module, f"{where} sources")
    definitions = string_list(data.get("definitions", []), f"{where} definitions", EXPRESSION_PATTERN)
    require(definitions, f"{where} needs at least one definition, such as \"NotesMiniApp.definition\"")
    if "app" in data:
        requirement(data["app"], f"{where} app", REQUIREMENT_KEYS)
    shortcuts = data.get("appShortcuts")
    if shortcuts is not None:
        require(isinstance(shortcuts, dict) and set(shortcuts) <= {"source", "imports"},
                f"{where} appShortcuts must be {{\"source\": ..., \"imports\": [...]}}")
        source = shortcuts.get("source", "")
        relative_globs([source], module, f"{where} appShortcuts.source")
        require("*" not in source and (module / source).is_file(), f"{where} appShortcuts.source must name one file")
        string_list(shortcuts.get("imports", []), f"{where} appShortcuts.imports", PRODUCT_PATTERN)
    return data


def modules(root):
    base = root / "Modules"
    found = sorted(path.parent for path in base.glob(f"*/{MANIFEST}")) if base.is_dir() else []
    features = []
    seen = {}
    for module in found:
        data = load(module)
        require(data["id"] not in seen,
                f"Feature ID {data['id']!r} is used by both {seen.get(data['id'])} and {module.as_posix()}")
        seen[data["id"]] = module.as_posix()
        features.append((module.relative_to(root).as_posix(), data))
    return features


def swift_string(text):
    out = []
    for character in text:
        if character == "\\":
            out.append("\\\\")
        elif character == '"':
            out.append('\\"')
        elif character == "\n":
            out.append("\\n")
        elif character == "\r":
            out.append("\\r")
        elif character == "\t":
            out.append("\\t")
        elif ord(character) < 0x20:
            out.append("\\u{%x}" % ord(character))
        else:
            out.append(character)
    return '"' + "".join(out) + '"'


def swift_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return swift_string(value)
    if isinstance(value, list):
        return "[" + ", ".join(swift_value(item) for item in value) + "]"
    if not value:
        return "[:]"
    return "[" + ", ".join(f"{swift_string(key)}: {swift_value(item)}" for key, item in value.items()) + "]"


def swift_strings(values):
    return "[" + ", ".join(swift_string(value) for value in values) + "]"


def swift_requirement(owner, value):
    arguments = [f"owner: {swift_string(owner)}"]
    for key in ("infoPlist", "entitlements", "localizedInfoPlist"):
        if value.get(key):
            arguments.append(f"{key}: {swift_value(value[key])}")
    return "FeatureBuildRequirement(" + ", ".join(arguments) + ")"


def render(features):
    lines = [
        "// Generated by `python3 Tools/jibunkit-feature.py sync` from Modules/*/JibunKitFeature.json.",
        "// Do not edit; change the Feature's JibunKitFeature.json and run sync again.",
        "import ProjectDescription",
        "",
        "public enum ModuleFeatures {",
        "    public static let all: [ModuleFeature] = [",
    ]
    for path, data in features:
        arguments = [f"id: {swift_string(data['id'])}", f"path: {swift_string(path)}"]
        for key in ("products", "sources", "definitions"):
            if data.get(key):
                arguments.append(f"{key}: {swift_strings(data[key])}")
        widget = data.get("widget") or {}
        for key, label in (("products", "widgetProducts"), ("sources", "widgetSources"), ("widgets", "widgets")):
            if widget.get(key):
                arguments.append(f"{label}: {swift_strings(widget[key])}")
        if any(data.get("app", {}).get(key) for key in REQUIREMENT_KEYS):
            arguments.append("app: " + swift_requirement(data["id"], data["app"]))
        if any(widget.get(key) for key in REQUIREMENT_KEYS):
            arguments.append("widget: " + swift_requirement(data["id"], widget))
        shortcuts = data.get("appShortcuts")
        if shortcuts:
            arguments.append("appShortcuts: FeatureAppShortcuts(owner: {}, imports: {}, sourceFile: {})".format(
                swift_string(data["id"]), swift_strings(shortcuts.get("imports", [])),
                swift_string(f"{path}/{shortcuts['source']}")))
        lines.append("        ModuleFeature(")
        lines.extend(f"            {argument}," for argument in arguments[:-1])
        lines.append(f"            {arguments[-1]}")
        lines.append("        ),")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def sync(root, check=False):
    text = render(modules(root))
    helper = root / HELPER
    current = helper.read_bytes().decode("utf-8") if helper.exists() else None
    if current == text:
        return False
    if check:
        raise FeatureError(f"{HELPER.as_posix()} is out of date; run python3 Tools/jibunkit-feature.py sync")
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_bytes(text.encode("utf-8"))
    return True


# Code that worked in a standalone app but changes another Feature's state, or
# the host's, inside JibunKit. Each finding names the JibunKit replacement.
CHECKS = [
    ("app-entry", r"^\s*@main\b",
     "The host owns the app entry. Expose a root view and a MiniAppDefinition instead.",
     "docs/mini-apps.md#moving-an-existing-app"),
    ("standard-defaults", r"UserDefaults\.standard|@AppStorage\((?![^)]*\bstore:)",
     "Every Feature shares the app's standard defaults. Use owner-scoped keys from MiniAppContext.storageKey(_:) "
     "or MiniAppStorage.sharedDefaults().", "docs/mini-apps.md#4-use-owner-scoped-apis"),
    ("app-group-literal", r'"group\.[A-Za-z0-9.-]+"',
     "A hard-coded App Group belongs to the standalone app's signing. Use MiniAppStorage.sharedDefaults().",
     "docs/mini-apps.md#moving-an-existing-app"),
    ("documents-directory", r"\.documentDirectory|\.applicationSupportDirectory",
     "App-wide directories are shared with every Feature. Use MiniAppFiles for the Feature's own files.",
     "docs/guides/database-files.md"),
    ("open-url", r"UIApplication\.shared\.open\(",
     "Requests made right after a Spotlight or notification launch can be dropped. Use MiniAppExternalURL.open(_:).",
     "docs/guides/feature-url-routing.md#opening-another-app"),
    ("on-open-url", r"\.onOpenURL\b",
     "The host receives URLs for every Feature. Use resolveIncomingURL and appendDestination.",
     "docs/guides/feature-url-routing.md"),
    ("color-scheme", r"\.preferredColorScheme\(",
     "preferredColorScheme changes the whole presentation, including other Features. Use "
     "environment(\\.colorScheme, ...) on the Feature's subtree.", "docs/guides/feature-appearance.md"),
    ("navigation-stack", r"\bNavigationStack\b",
     "The host owns the outer NavigationStack. Keep one only in the standalone example or inside the Feature's own "
     "sheets.", "docs/mini-apps.md#5-keep-navigation-and-app-shells-separate"),
    ("tips-configure", r"\bTips\.(configure|resetDatastore)\(",
     "The host configures TipKit once for all Features.", "docs/guides/app-wide-surfaces.md#tipkit"),
    ("badge", r"(?<!context\.)\bsetBadgeCount\(|applicationIconBadgeNumber",
     "The icon badge is the sum over Features. Use MiniAppContext.setBadgeCount.",
     "docs/guides/app-wide-surfaces.md#icon-badge"),
    ("shortcut-items", r"\bshortcutItems\b",
     "Home Screen quick actions are shared. Declare them with MiniAppDefinition.quickActions.",
     "docs/guides/app-wide-surfaces.md#home-screen-quick-actions"),
    ("notification-delegate", r"UNUserNotificationCenter\.current\(\)\.delegate\s*=",
     "The host owns the notification delegate and routes each notification to its owner.",
     "docs/guides/owned-notification-observations.md"),
    ("idle-timer", r"isIdleTimerDisabled",
     "The host combines every Feature's request. Request a scene-scoped lease instead.",
     "docs/guides/scene-idle-timer.md"),
    ("audio-session", r"AVAudioSession\.sharedInstance\(\)\.(setCategory|setActive|setMode)",
     "The audio session is shared. Submit the Feature's requirement to the host's audio coordinator.",
     "docs/guides/audio.md"),
    ("spotlight-delete-all", r"deleteAllSearchableItems",
     "This deletes other Features' items too. Delete the Feature's own domain.",
     "docs/guides/spotlight-ownership.md"),
    ("web-authentication", r"ASWebAuthenticationSession\(",
     "Connect web authentication to the Feature's runtime so disabling the Feature cancels it.",
     "docs/guides/web-authentication-ownership.md"),
    ("background-task-register", r"BGTaskScheduler\.shared\.register\(",
     "Background task identifiers are registered once for the app. Use the Feature's background registration.",
     "docs/guides/background-continued-processing.md"),
]
SKIPPED_DIRECTORIES = {"Example", "UITests", "Tests", ".build", ".swiftpm"}
ALLOW_MARKER = re.compile(r"jibunkit:\s*allow\s+([a-z-]+(?:\s*,\s*[a-z-]+)*)")


def check(paths):
    """Return (path, line number, rule, message, doc) for each finding."""
    compiled = [(rule, re.compile(pattern), message, doc) for rule, pattern, message, doc in CHECKS]
    findings = []
    for base in paths:
        require(base.exists(), f"{base} does not exist")
        files = [base] if base.is_file() else sorted(base.rglob("*.swift"))
        for file in files:
            relative = file.relative_to(base).parts if file != base else ()
            if any(part in SKIPPED_DIRECTORIES for part in relative[:-1]):
                continue
            for number, line in enumerate(file.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                code = line.split("//", 1)[0]
                allowed = set()
                marker = ALLOW_MARKER.search(line)
                if marker:
                    allowed = {name.strip() for name in marker.group(1).split(",")}
                for rule, pattern, message, doc in compiled:
                    if rule not in allowed and pattern.search(code):
                        findings.append((file, number, rule, message, doc))
    return findings


def template_items(root):
    manifest = (root / TEMPLATE / "feature.swift").read_text(encoding="utf-8")
    items = re.findall(r'\.file\(path: "([^"]+)", templatePath: "([^"]+)"\)', manifest)
    require(items, f"{TEMPLATE.as_posix()}/feature.swift lists no files")
    return items


def render_template(text, name, source):
    text = text.replace("{{ name | lowercase }}", name.lower()).replace("{{ name }}", name)
    require("{{" not in text and "{%" not in text,
            f"{source} uses template syntax this tool does not support; keep templates to {{{{ name }}}} and {{{{ name | lowercase }}}}")
    return text


def new(root, name, run_sync=True):
    require(NAME_PATTERN.fullmatch(name),
            "Use a Swift type name that starts with an uppercase letter and contains only letters and digits")
    module = root / "Modules" / name
    require(not module.exists(), f"{module.relative_to(root).as_posix()} already exists")
    rendered = []
    for path, template in template_items(root):
        source = root / TEMPLATE / template
        rendered.append((root / path.replace("\\(name)", name),
                         render_template(source.read_text(encoding="utf-8"), name, source.as_posix())))
    for target, text in rendered:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text.encode("utf-8"))
    if run_sync:
        sync(root)
    return module


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="Repository root (default: the checkout containing this tool)")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("new", help="Create Modules/<Name> and connect it")
    create.add_argument("--name", required=True)
    create.add_argument("--no-sync", action="store_true", help="Create files only")
    update = commands.add_parser("sync", help="Regenerate ModuleFeatures.swift")
    update.add_argument("--check", action="store_true", help="Fail instead of writing when out of date")
    review = commands.add_parser("check", help="Report code that affects other Features")
    review.add_argument("paths", nargs="*", type=Path, help="Directories or Swift files (default: Modules/*)")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        if args.command == "new":
            module = new(root, args.name, run_sync=not args.no_sync)
            print(f"Created {module.relative_to(root).as_posix()}"
                  + ("" if args.no_sync else f" and updated {HELPER.as_posix()}"))
        elif args.command == "check":
            paths = [path.resolve() for path in args.paths] or sorted(
                path.parent for path in (root / "Modules").glob(f"*/{MANIFEST}"))
            findings = check(paths)
            for file, number, rule, message, doc in findings:
                try:
                    shown = file.relative_to(root).as_posix()
                except ValueError:
                    shown = file.as_posix()
                print(f"{shown}:{number}: [{rule}] {message} See {doc}")
            print(f"{len(findings)} finding(s) in {len(paths)} location(s)")
            return 1 if findings else 0
        else:
            changed = sync(root, check=args.check)
            print(f"{HELPER.as_posix()} {'updated' if changed else 'is up to date'}")
    except FeatureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
