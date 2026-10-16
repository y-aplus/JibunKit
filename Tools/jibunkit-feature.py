#!/usr/bin/env python3
"""Create Feature packages under Modules/ and connect them to the host.

  new --name Notes   Create Modules/Notes from Tuist/Templates/feature, the same
                     files `tuist scaffold feature --name Notes` creates, then sync.
  sync               Read Modules/*/JibunKitFeature.json and write
                     Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift.
                     Stops when two owners put the same Swift file name or
                     file-scope name into the host app or widget target.
  sync --check       Fail if that file is not up to date.
  check [PATH ...]   Report standalone-app code that affects other Features
                     inside JibunKit (default: every Feature under Modules/).
                     Mark an intended use with `// jibunkit: allow <rule>`.
  add URL [--ref REF] [--path DIR] [--name Notes]
                     Copy a Feature from another Git repository into
                     Modules/<Name>, record the repository and commit in
                     JibunKitImports.json, sync, and report what it brings.
  update Notes [--ref REF] [--path DIR]
                     Move an imported Feature to a new commit, keeping your
                     own changes to it (three-way merge), and report changes.
  remove Notes       Delete an imported Feature and its record, or a draft, then sync.
  migrate URL --name Notes [--ref REF] [--path DIR] [--target App] [--id notes]
                     Move an ordinary iOS app (an Xcode app target or a Swift
                     Playgrounds app) into Modules/<Name> as a draft Feature,
                     making the mechanical changes `inspect` lists, and write
                     what changed and what is left to MIGRATION.md.
  connect Notes      Connect a draft once `check` reports nothing for it.
  inspect URL [--ref REF] [--path DIR]
                     Report how far the code in another repository, such as
                     an ordinary iOS app, is from a JibunKit Feature: what can
                     be moved as it is, by a mechanical rewrite, by hand, or
                     not at all. Writes nothing.

The commands need only Python (and Git for add/update/inspect), so they also
work on Windows and Linux. add, update and inspect never run code from the
repository. The
generated helper is read by Project.swift; `tuist generate` (macOS or CI) then
adds the packages, Integration sources, registry entries, widgets and build
requirements. Hand-registered Features keep working unchanged.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile

MANIFEST = "JibunKitFeature.json"
HELPER = Path("Tuist/ProjectDescriptionHelpers/ModuleFeatures.swift")
TEMPLATE = Path("Tuist/Templates/feature")
ID_PATTERN = re.compile(r"[a-z][a-z0-9._-]*")
NAME_PATTERN = re.compile(r"[A-Z][A-Za-z0-9]*")
PRODUCT_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
EXPRESSION_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*(\(\))?")
TOP_KEYS = {"schema", "id", "products", "sources", "definitions", "app", "widget", "appShortcuts", "draft"}
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
    require(isinstance(data.get("draft", False), bool), f"{where} draft must be true or false")
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


def is_draft(module):
    """A draft (`"draft": true`) is a Feature still being moved in, for example by
    `migrate`: sync, check and CI leave it out until `connect` removes the flag."""
    try:
        data = json.loads((module / MANIFEST).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return isinstance(data, dict) and data.get("draft") is True


def drafts(root):
    base = root / "Modules"
    return sorted(path.parent for path in base.glob(f"*/{MANIFEST}") if is_draft(path.parent)) if base.is_dir() else []


def modules(root):
    base = root / "Modules"
    found = sorted(path.parent for path in base.glob(f"*/{MANIFEST}")
                   if not is_draft(path.parent)) if base.is_dir() else []
    features = []
    seen = {}
    for module in found:
        data = load(module)
        require(data["id"] not in seen,
                f"Feature ID {data['id']!r} is used by both {seen.get(data['id'])} and {module.relative_to(root).as_posix()}")
        seen[data["id"]] = module.relative_to(root).as_posix()
        features.append((module.relative_to(root).as_posix(), data))
    return features


# The host's own sources in the targets that also compile Feature sources.
# Keep in sync with the `sources:` globs of the app and widget targets in
# Project.swift; the generated files are written by `tuist generate`.
HOST_TARGET_SOURCES = {
    "app": (["Sources/JibunKit/**"], ["GeneratedFeatureSources/JibunKitShortcuts.swift",
                                      "GeneratedFeatureSources/ModuleFeatureRegistry.swift"]),
    "widget": (["Sources/JibunKitWidget/**"], ["GeneratedWidgetSources/ModuleWidgets.swift"]),
}
DECLARATION_MODIFIERS = r"(?:(?:@\w+(?:\([^)]*\))?|public|package|internal|open|final|nonisolated|indirect|private|fileprivate)\s+)*"
TOP_LEVEL_DECLARATION = re.compile(
    r"^(" + DECLARATION_MODIFIERS + r")(struct|class|enum|actor|protocol|typealias|let|var)\s+([A-Za-z_]\w*)")


def swift_files(base, globs):
    files = set()
    for glob in globs:
        for match in base.glob(glob):
            if match.is_dir():
                files.update(match.rglob("*.swift"))
            elif match.suffix == ".swift":
                files.add(match)
    return sorted(files)


def top_level_names(file):
    """Names a file declares at file scope that other files of the target can see."""
    names = {}
    for number, line in enumerate(file.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        match = TOP_LEVEL_DECLARATION.match(line)
        if match and not re.search(r"\b(private|fileprivate)\b", match.group(1)):
            names.setdefault(match.group(3), number)
    return names


def source_conflicts(root, features):
    """Swift file names and file-scope names that two owners put into one host target.

    Integration sources of every Feature compile into the host app (widget
    sources into the widget) as one Swift module, so a shared file name or
    type name stops the build there, often minutes later and on macOS only.
    """
    problems = []
    for target, (host_globs, generated) in HOST_TARGET_SOURCES.items():
        owned = [("host", path) for path in swift_files(root, host_globs)]
        owned += [("generated", root / path) for path in generated]
        for path, data in features:
            globs = data.get("sources", []) if target == "app" else (data.get("widget") or {}).get("sources", [])
            owned += [(data["id"], file) for file in swift_files(root / path, globs)]
        by_name = {}
        for owner, file in owned:
            by_name.setdefault(file.name, []).append((owner, file))
        for name, entries in sorted(by_name.items()):
            if len(entries) > 1:
                where = ", ".join(f"{file.relative_to(root).as_posix()} ({owner})" for owner, file in entries)
                problems.append(f"The {target} target compiles two files named {name}: {where}. Rename one; "
                                "Swift needs unique file names within a target.")
        declared = {}
        for owner, file in owned:
            if owner == "generated" or not file.is_file():
                continue
            for name, number in top_level_names(file).items():
                declared.setdefault(name, []).append((owner, f"{file.relative_to(root).as_posix()}:{number}"))
        for name, entries in sorted(declared.items()):
            if len({owner for owner, _ in entries}) > 1:
                where = ", ".join(f"{location} ({owner})" for owner, location in entries)
                problems.append(f"{name} is declared at file scope by more than one owner in the {target} target: "
                                f"{where}. Rename one or make it private; these sources compile into one module.")
    return problems


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
    features = modules(root)
    for name in load_imports(root):
        require((root / "Modules" / name / MANIFEST).is_file(),
                f"{IMPORTS} records {name}, but Modules/{name}/{MANIFEST} is missing; "
                f"restore it or run `python3 Tools/jibunkit-feature.py remove {name}`")
    problems = source_conflicts(root, features)
    require(not problems, "\n".join(problems))
    text = render(features)
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


# Features copied from other repositories. The copy under Modules/<Name> is
# what gets built; this file records where it came from so that an update is
# an explicit move from one commit to another.
IMPORTS = Path("JibunKitImports.json")
IMPORT_KEYS = {"repository", "ref", "commit", "path"}
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")
# `OWNER/REPO` means a GitHub repository, as in the Build mini app.
GITHUB_SHORTHAND = re.compile(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+")


def load_imports(root):
    path = root / IMPORTS
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise FeatureError(f"{IMPORTS} is not valid JSON: {error}") from None
    require(isinstance(data, dict) and data.get("schema") == 1 and isinstance(data.get("features"), dict),
            f'{IMPORTS} needs "schema": 1 and a "features" object')
    for name, entry in data["features"].items():
        where = f"{IMPORTS} {name}"
        require(NAME_PATTERN.fullmatch(name), f"{where}: not a Feature directory name")
        require(isinstance(entry, dict) and set(entry) == IMPORT_KEYS
                and all(isinstance(entry[key], str) for key in IMPORT_KEYS),
                f"{where} needs the strings {', '.join(sorted(IMPORT_KEYS))}")
        require(COMMIT_PATTERN.fullmatch(entry["commit"]), f"{where}: commit must be a full commit hash")
    return data["features"]


def save_imports(root, features):
    path = root / IMPORTS
    if not features:
        if path.exists():
            path.unlink()
        return
    text = json.dumps({"schema": 1, "features": dict(sorted(features.items()))}, indent=2, ensure_ascii=False)
    path.write_bytes((text + "\n").encode("utf-8"))


def git(arguments, cwd=None, data=None, env=None):
    result = subprocess.run(["git", "-c", "protocol.ext.allow=never", *arguments], cwd=cwd, input=data,
                            capture_output=True, env=env)
    if result.returncode:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise FeatureError(f"git {' '.join(arguments)} failed: {message}")
    return result.stdout


def source_path(value):
    path = value.strip("/")
    require("\\" not in path and ".." not in Path(path).parts and not Path(path).is_absolute(),
            f"--path must be a directory inside the repository: {value!r}")
    return path


# A token that can read other repositories on GitHub, for private ones. The
# workflows pass the repository secret of the same name; on a computer, Git's
# own credentials are used instead.
READ_TOKEN = "JIBUNKIT_READ_TOKEN"
NOT_READABLE = ("could not read Username", "Authentication failed", "Repository not found",
                "terminal prompts disabled", "Invalid username or password")


def fetch_environment(repository, environ=None):
    """The environment for fetching `repository`: never prompt, and send READ_TOKEN to github.com.
    The token goes in an HTTP header set through GIT_CONFIG_*, so it is not on the command line."""
    environ = dict(os.environ if environ is None else environ)
    environ["GIT_TERMINAL_PROMPT"] = "0"
    token = environ.pop(READ_TOKEN, "").strip()
    if token and repository.startswith("https://github.com/"):
        index = int(environ.get("GIT_CONFIG_COUNT") or 0)
        basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        environ.update({"GIT_CONFIG_COUNT": str(index + 1),
                        f"GIT_CONFIG_KEY_{index}": "http.https://github.com/.extraheader",
                        f"GIT_CONFIG_VALUE_{index}": f"AUTHORIZATION: basic {basic}"})
    return environ


def fetch(work, repository, ref):
    """Fetch one commit into the scratch repository `work` and return its hash."""
    for value, what in ((repository, "repository"), (ref, "ref")):
        require(value and not value.startswith("-") and not any(c in value for c in "\r\n\0"),
                f"Unsupported {what}: {value!r}")
    if not (work / ".git").exists():
        git(["init", "-q", str(work)])
    environment = fetch_environment(repository)
    try:
        git(["fetch", "-q", "--depth", "1", "--no-tags", "--", repository, ref], cwd=work, env=environment)
    except FeatureError as error:
        if any(text in str(error) for text in NOT_READABLE):
            if environment.get("GIT_CONFIG_COUNT") and READ_TOKEN in os.environ:
                hint = (f"The {READ_TOKEN} token could not read it: give the token read access to its "
                        "contents, or check the repository URL.")
            else:
                hint = ("The repository is private or does not exist. To read a private repository on GitHub, "
                        f"add a token that can read it as the repository secret {READ_TOKEN} "
                        "(see docs/mini-apps.md); on a computer, sign in to Git.")
            raise FeatureError(f"Could not read {repository}.\n{hint}") from None
        raise FeatureError(f"{error}\nCheck the repository URL, and use a branch, a tag or a full 40-character "
                           "commit hash for --ref.") from None
    return git(["rev-parse", "FETCH_HEAD^{commit}"], cwd=work).decode().strip()


def list_tree(work, commit, path):
    """(relative path, mode, kind, object) for each entry of a directory at a commit."""
    spec = f"{commit}:{path}" if path else commit
    try:
        listing = git(["ls-tree", "-r", "-z", spec], cwd=work)
    except FeatureError:
        raise FeatureError(f"The repository has no directory {path!r} at {commit[:12]}") from None
    entries = []
    for record in filter(None, listing.split(b"\0")):
        meta, name = record.split(b"\t", 1)
        mode, kind, sha = meta.decode().split()
        entries.append((name.decode("utf-8"), mode, kind, sha))
    return entries


def read_blobs(work, objects):
    """The contents of Git blobs, in the order given."""
    if not objects:
        return []
    output = git(["cat-file", "--batch"], cwd=work, data="".join(f"{sha}\n" for sha in objects).encode())
    contents, offset = [], 0
    for _ in objects:
        header_end = output.index(b"\n", offset)
        size = int(output[offset:header_end].split()[2])
        contents.append(output[header_end + 1:header_end + 1 + size])
        offset = header_end + 1 + size + 1
    return contents


def read_tree(work, commit, path):
    """{relative path: (bytes, executable)} of a directory at a commit, read from Git's objects."""
    entries = list_tree(work, commit, path)
    for name, mode, kind, _ in entries:
        require(mode != "120000", f"{name} is a symbolic link; JibunKit imports files only")
        require(kind == "blob", f"{name} is a Git submodule; JibunKit imports files only")
    contents = read_blobs(work, [sha for _, _, _, sha in entries])
    return {name: (data, mode == "100755") for (name, mode, _, _), data in zip(entries, contents)}


def write_file(module, name, data, executable=False):
    target = module / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    if executable and os.name == "posix":
        target.chmod(target.stat().st_mode | 0o111)


def local_files(module):
    """Files of an imported Feature on disk, without build output Git ignores."""
    try:
        listing = git(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "."], cwd=module)
        names = [name for name in listing.decode("utf-8").split("\0") if name]
    except FeatureError:
        names = [path.relative_to(module).as_posix() for path in module.rglob("*") if path.is_file()]
    return {name: (module / name).read_bytes() for name in names if (module / name).is_file()}


def require_clean(module):
    try:
        status = git(["status", "--porcelain", "--", "."], cwd=module)
    except FeatureError:
        return  # Not in a Git checkout; nothing to compare with.
    require(not status.strip(), f"{module.name} has uncommitted changes; commit them first so an update cannot lose them")


def same_text(data):
    """Compare text without line-ending differences an editor may have added."""
    return data.replace(b"\r\n", b"\n") if data is not None and b"\0" not in data else data


def merge_file(ours, base, theirs, labels):
    with tempfile.TemporaryDirectory() as temporary:
        paths = []
        for label, data in zip(("ours", "base", "theirs"), (ours, base, theirs)):
            path = Path(temporary) / label
            path.write_bytes(data)
            paths.append(str(path))
        result = subprocess.run(["git", "merge-file", "-p", "-L", labels[0], "-L", labels[1], "-L", labels[2], *paths],
                                capture_output=True)
        # Exit status: the number of conflicts (at most 127), or 255 on error.
        require(result.returncode < 128, f"git merge-file failed: {result.stderr.decode('utf-8', 'replace')}")
        return result.stdout, result.returncode == 0


def merge_tree(module, base, ours, theirs, labels):
    """Apply the upstream change base -> theirs to the files on disk (ours)."""
    changed, conflicts = [], []
    for name in sorted(set(base) | set(ours) | set(theirs)):
        base_data = base[name][0] if name in base else None
        their_data = theirs[name][0] if name in theirs else None
        our_data = ours.get(name)
        b, o, t = same_text(base_data), same_text(our_data), same_text(their_data)
        if o == t or t == b:
            continue  # Already the same, or only changed here: keep the local file.
        if o == b:
            if their_data is None:
                (module / name).unlink()
            else:
                write_file(module, name, their_data, theirs[name][1])
            changed.append(name)
        elif None in (b, o, t) or any(b"\0" in data for data in (b, o, t)):
            # Changed on both sides and not mergeable as text: keep the local
            # file and put the upstream one next to it.
            if their_data is not None:
                write_file(module, name + ".upstream", their_data, theirs[name][1])
            conflicts.append(name)
        else:
            merged, clean = merge_file(o, b, t, labels)
            write_file(module, name, merged)
            changed.append(name)
            if not clean:
                conflicts.append(name)
    for directory in sorted((path for path in module.rglob("*") if path.is_dir()), reverse=True):
        if not any(directory.iterdir()):
            directory.rmdir()
    return changed, conflicts


def balanced_calls(text, function):
    """The argument text of each `.function(...)` call, skipping parentheses inside string literals."""
    calls = []
    for match in re.finditer(r"\.%s\(" % re.escape(function), text):
        depth, index, in_string = 1, match.end(), False
        while index < len(text) and depth:
            character = text[index]
            if in_string:
                if character == "\\":
                    index += 1
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            index += 1
        calls.append(text[match.end():index - 1])
    return calls


UNPINNED = "Packages without an exact version (they can change between builds)"
OUTSIDE = "Local packages outside the Feature (missing after the copy)"
BINARY = "Precompiled code (no source in the repository)"
BUILD_CODE = "Code that runs during the build (plugins and macros)"
REQUIREMENTS = "Build requirements (Info.plist, entitlements)"
FINDINGS = "check findings (CI stops on these)"


def describe(root, module):
    """What a Feature brings into the host, read from its files without running them."""
    report = {}

    def add(category, item):
        report.setdefault(category, set()).add(item)

    describe_package(module, add)
    data = json.loads((module / MANIFEST).read_text(encoding="utf-8"))
    for category, items in describe_requirements(data).items():
        for item in items:
            add(category, item)
    for file, number, rule, _, _ in check([module]):
        add(FINDINGS, f"{file.relative_to(root).as_posix()}:{number} [{rule}]")
    return {category: sorted(items) for category, items in report.items()}


def describe_package(module, add):
    """The dependencies and build-time code that module/Package.swift declares."""
    package = (module / "Package.swift").read_text(encoding="utf-8", errors="replace")
    package = re.sub(r"(?m)^\s*//.*$", "", package)
    for arguments in balanced_calls(package, "package"):
        url = re.search(r'\b(?:url|id):\s*"([^"]+)"', arguments)
        local = re.search(r'\bpath:\s*"([^"]+)"', arguments)
        if url:
            requirement = " ".join(arguments[url.end():].strip(" ,\n").split())
            add("Swift packages", f"{url.group(1)} {requirement}".strip())
            if not re.search(r"\b(exact|revision):|\.exact\(", arguments):
                add(UNPINNED, url.group(1))
        elif local:
            add("Swift packages", f"local {local.group(1)}")
            target = (module / local.group(1)).resolve()
            if target != module.resolve() and module.resolve() not in target.parents:
                add(OUTSIDE, local.group(1))
    for function, category in (("binaryTarget", BINARY), ("plugin", BUILD_CODE), ("macro", BUILD_CODE)):
        for arguments in balanced_calls(package, function):
            name = re.search(r'\bname:\s*"([^"]+)"', arguments)
            add(category, f".{function} {name.group(1) if name else arguments.strip()}")


def print_report(report):
    if not report:
        print("No packages, precompiled code, build-time code, build requirements or check findings.")
    for category, items in report.items():
        print(f"{category}:")
        for item in items:
            print(f"  {item}")


def print_changes(before, after):
    changes = False
    for category in list(dict.fromkeys([*before, *after])):
        old, new = set(before.get(category, [])), set(after.get(category, []))
        if old != new:
            changes = True
            print(f"{category}:")
            for item in sorted(new - old):
                print(f"  + {item}")
            for item in sorted(old - new):
                print(f"  - {item}")
    if not changes:
        print("No change in packages, precompiled code, build-time code, build requirements or check findings.")


# Compatibility check (`inspect`): how far the code in a repository, such as an
# ordinary iOS app, is from a JibunKit Feature. Like add, it reads files with
# Git and never runs them, and it writes nothing to this repository. It reads
# text, so "can be moved" does not mean the moved code compiles.
UNSUPPORTED, MANUAL, MECHANICAL = "unsupported", "manual", "mechanical"
FREE_SIGNING, BRINGS, NOT_READ = "free signing", "brings", "not read"
SECTION_TITLES = {
    UNSUPPORTED: "Not supported (these parts cannot come into JibunKit)",
    MANUAL: "Manual changes",
    MECHANICAL: "Mechanical changes (the same rewrite every time)",
    FREE_SIGNING: "May not work with free signing (usually needs a paid Apple Developer Program membership)",
    BRINGS: "What it brings",
    NOT_READ: "Not read",
}
HOST_IOS = (26, 0)
# Directories that hold tests, examples, other people's code or build output.
NOT_APP_CODE = {"Tests", "UITests", "Example", "Examples", "Pods", "Carthage", ".build", ".swiftpm",
                "DerivedData", "build", "node_modules", "fastlane", "vendor", "Tuist"}
INSPECTED_SUFFIXES = {".swift", ".pbxproj", ".plist", ".entitlements", ".xcconfig"}
INSPECTED_NAMES = {MANIFEST, "Podfile", "Cartfile", "project.yml", ".gitattributes"}
# The first line of a file that Git LFS keeps outside the repository.
LFS_POINTER = b"version https://git-lfs.github.com/spec/v1"
MANIFEST_FILE = re.compile(r"Package(@swift-[0-9.]+)?\.swift|Project\.swift|Tuist\.swift|Workspace\.swift")
SHOWN_LOCATIONS = 5

# Code that has to change when it moves from an app target into a package, in
# addition to `check`. (rule, pattern, exempt, section, message, guide): when
# the pattern ends with "(", a call whose arguments match `exempt` is fine.
MOVE_CHECKS = [
    ("asset-lookup", r'\b(?:Image|Color)\((?=\s*")|\bUI(?:Image|Color)\((?=\s*named:)', r"\b(?:bundle|in):",
     MECHANICAL, "Images and colors from an asset catalog: add `bundle: .module`; in a package they are otherwise "
     "looked up in JibunKit's own bundle.", "docs/mini-apps.md#6-validate-the-integration"),
    ("localized-string", r"\bNSLocalizedString\(|\bString\((?=\s*localized:)", r"\bbundle:", MECHANICAL,
     "Localized strings: add `bundle: .module` so the Feature's translations are used.",
     "docs/mini-apps.md#6-validate-the-integration"),
    ("main-bundle", r"\bBundle\.main\b", None, MANUAL,
     "Bundle.main is JibunKit's bundle, not the Feature's; use Bundle.module for the Feature's resources.",
     "docs/updating.md"),
    ("app-delegate", r"@UIApplicationDelegateAdaptor|@UIApplicationMain|\bUIApplicationDelegate\b", None, MANUAL,
     "App delegate: JibunKit owns it; move each job to the MiniAppDefinition (onHostLaunch) or the guide for "
     "that system event.", "docs/mini-apps.md#moving-an-existing-app"),
    ("scene-delegate", r"\bUIWindowSceneDelegate\b", None, MANUAL,
     "Scene delegate: JibunKit owns the windows and scenes.", "docs/guides/window-scene-ownership.md"),
    ("core-data-model", r"\bNSPersistent(?:CloudKit)?Container\((?=\s*name:)", r"\bmanagedObjectModel:", MANUAL,
     "Core Data looks for the model in JibunKit's bundle and stores in an app-wide place: load the model from "
     "Bundle.module and put the store in the Feature's files.", "docs/guides/database-files.md"),
    ("swiftdata-default-store", r"\.modelContainer\((?=\s*for:)|\bModelContainer\((?=\s*for:)",
     r"\bconfigurations?:|\binMemory:\s*true", MANUAL,
     "SwiftData's default store is one file for the whole app: give it the Feature's own file with "
     "ModelConfiguration(url:).", "docs/guides/database-files.md"),
]
# Only when the repository has Localizable strings: Text("key") looks the key up.
LOCALIZED_TEXT = ("localized-text", r'\bText\((?=\s*")', r"\bbundle:", MECHANICAL,
                  "Text(\"...\") looks its key up in JibunKit's bundle: add `bundle: .module`.",
                  "docs/mini-apps.md#6-validate-the-integration")
APP_ENTRY = re.compile(r"@main\s+(?:(?:public|final)\s+)*(?:struct|class|enum)\s+\w+\s*:\s*([\w.]+)")

PRODUCT_TYPES = {
    "com.apple.product-type.application.watchapp": "Apple Watch app",
    "com.apple.product-type.application.watchapp2": "Apple Watch app",
    "com.apple.product-type.application.watchapp2-container": "Apple Watch app",
    "com.apple.product-type.watchkit-extension": "Apple Watch app",
    "com.apple.product-type.watchkit2-extension": "Apple Watch app",
    "com.apple.product-type.application.on-demand-install-capable": "App Clip",
    "com.apple.product-type.application.messages": "iMessage app",
    "com.apple.product-type.app-extension.messages": "iMessage app",
    "com.apple.product-type.app-extension.messages-sticker-pack": "iMessage sticker pack",
}
LIBRARY_TYPES = {"com.apple.product-type.framework", "com.apple.product-type.framework.static",
                 "com.apple.product-type.library.static", "com.apple.product-type.library.dynamic"}
EXTENSION_TYPES = {"com.apple.product-type.app-extension", "com.apple.product-type.extensionkit-extension"}
IGNORED_TYPES = {"com.apple.product-type.bundle.unit-test", "com.apple.product-type.bundle.ui-testing",
                 "com.apple.product-type.tool", "com.apple.product-type.bundle"}
# Extensions whose job JibunKit's own extensions do for every Feature.
HOST_EXTENSIONS = {
    "com.apple.widgetkit-extension": (
        "Widget extension (widgets, Live Activities, controls): JibunKit has one widget extension; declare the "
        "widgets under `widget` in JibunKitFeature.json.", "docs/guides/package-static-widgets.md"),
    "com.apple.share-services": (
        "Share extension: JibunKit's share extension saves shared items and hands them to the chosen Feature.",
        "docs/guides/feature-incoming.md"),
    "com.apple.ui-services": (
        "Action extension: JibunKit's optional action extension hands items to the chosen Feature.",
        "docs/guides/action-extension.md"),
    "com.apple.services": (
        "Action extension: JibunKit's optional action extension hands items to the chosen Feature.",
        "docs/guides/action-extension.md"),
    "com.apple.usernotifications.service": (
        "Notification service extension: JibunKit's optional one calls the Feature's handler (it uses another "
        "App ID).", "docs/guides/app-wide-surfaces.md#notification-service-and-content-extensions"),
    "com.apple.usernotifications.content-extension": (
        "Notification content extension: JibunKit's optional one shows the Feature's view (it uses another App ID).",
        "docs/guides/app-wide-surfaces.md#notification-service-and-content-extensions"),
    "com.apple.intents-service": (
        "SiriKit Intents extension: write the actions as App Intents in the Feature's package.",
        "docs/guides/package-app-intents.md"),
    "com.apple.intents-ui-service": (
        "SiriKit Intents UI extension: write the actions as App Intents in the Feature's package.",
        "docs/guides/package-app-intents.md"),
    "com.apple.appintents-extension": (
        "App Intents extension: declare the intents in the Feature's package.", "docs/guides/package-app-intents.md"),
}
EXTENSION_NAMES = {
    "com.apple.keyboard-service": "Custom keyboard",
    "com.apple.Safari.web-extension": "Safari extension",
    "com.apple.Safari.content-blocker": "Safari content blocker",
    "com.apple.fileprovider-nonui": "File Provider",
    "com.apple.fileprovider-actionsui": "File Provider",
    "com.apple.photo-editing": "Photo editing",
    "com.apple.broadcast-services-upload": "Screen broadcast",
    "com.apple.broadcast-services-setupui": "Screen broadcast",
    "com.apple.callkit.call-directory": "Call directory",
    "com.apple.identitylookup.message-filter": "Message filter",
    "com.apple.authentication-services-credential-provider-ui": "Password AutoFill",
    "com.apple.deviceactivity.monitor-extension": "Screen Time",
    "com.apple.spotlight.import": "Spotlight import",
}
# Info.plist keys the host app sets for itself; a Feature's copy is dropped.
HOST_PLIST_KEYS = {
    "CFBundleDevelopmentRegion", "CFBundleDisplayName", "CFBundleExecutable", "CFBundleIdentifier",
    "CFBundleInfoDictionaryVersion", "CFBundleName", "CFBundlePackageType", "CFBundleShortVersionString",
    "CFBundleVersion", "CFBundleSignature", "CFBundleIconName", "CFBundleIconFile", "CFBundleIconFiles",
    "CFBundleAllowMixedLocalizations", "CFBundleLocalizations", "LSRequiresIPhoneOS", "LSApplicationCategoryType",
    "UIApplicationSceneManifest", "UIApplicationSupportsIndirectInputEvents", "UIApplicationSupportsMultipleScenes",
    "UIRequiredDeviceCapabilities", "UIRequiresFullScreen", "UIViewControllerBasedStatusBarAppearance",
    "ITSAppUsesNonExemptEncryption", "NSHumanReadableCopyright", "MinimumOSVersion", "UIDeviceFamily",
    "NSPrincipalClass", "UIPrerenderedIcon",
}
HOST_PLIST_PREFIXES = ("UISupportedInterfaceOrientations", "CFBundleIcons", "UIStatusBar", "UILaunch", "DT",
                       "BuildMachine")
FREE_SIGNING_ENTITLEMENTS = {
    "aps-environment": "Push notifications",
    "com.apple.developer.aps-environment": "Push notifications",
    "com.apple.developer.icloud-container-identifiers": "iCloud",
    "com.apple.developer.icloud-container-environment": "iCloud",
    "com.apple.developer.icloud-services": "iCloud",
    "com.apple.developer.ubiquity-container-identifiers": "iCloud Documents",
    "com.apple.developer.ubiquity-kvstore-identifier": "iCloud key-value storage",
    "com.apple.developer.associated-domains": "Associated Domains (universal links, password AutoFill)",
    "com.apple.developer.applesignin": "Sign in with Apple",
    "com.apple.developer.in-app-payments": "Apple Pay",
    "com.apple.developer.pass-type-identifiers": "Wallet",
    "com.apple.developer.siri": "Siri",
    "com.apple.developer.networking.networkextension": "Network Extensions",
    "com.apple.developer.networking.vpn.api": "Personal VPN",
}
SIGNING_ENTITLEMENTS = {"application-identifier", "com.apple.developer.team-identifier", "get-task-allow",
                        "keychain-access-groups", "com.apple.security.application-groups"}


class Inspection:
    """Findings by section: {(section, message): [where, ...]}, plus what was found."""

    def __init__(self):
        self.items = {}
        self.found = []
        self.whole = None  # Why the repository as a whole cannot become a Feature.
        self.feature = False
        self.packages = set()

    def add(self, section, message, where=None):
        places = self.items.setdefault((section, message), [])
        if where and where not in places:
            places.append(where)

    def add_package(self, name, text, category="Swift package"):
        """A Swift package dependency, once even when both the project and Package.swift list it."""
        key = (category, re.sub(r"(\.git)?/?$", "", name.lower()))
        if key not in self.packages:
            self.packages.add(key)
            self.add(BRINGS, f"{category} {text}")

    def sections(self):
        return {section for section, _ in self.items}

    def verdict(self):
        sections = self.sections()
        if self.whole:
            text = f"not supported: {self.whole}"
        elif UNSUPPORTED in sections:
            text = "some parts cannot come into JibunKit (see below); the rest can, with the changes listed"
        elif MANUAL in sections:
            text = "can be moved, with manual changes"
        elif MECHANICAL in sections:
            text = "can be moved with mechanical changes only"
        elif self.feature:
            text = "a JibunKit Feature; it can be added as it is"
        else:
            text = "nothing to move was found"
        if FREE_SIGNING in sections and not self.whole:
            text += "; some capabilities may not work with free signing"
        return text


def parse_openstep(text):
    """Parse an old-style (OpenStep) property list, the format of project.pbxproj."""
    index = 0
    token = re.compile(r"[^\s{}()=;,\"<>]+")

    def skip():
        nonlocal index
        while index < len(text):
            if text[index].isspace():
                index += 1
            elif text.startswith("/*", index):
                end = text.find("*/", index + 2)
                index = len(text) if end < 0 else end + 2
            elif text.startswith("//", index):
                end = text.find("\n", index)
                index = len(text) if end < 0 else end + 1
            else:
                return

    def expect(character):
        nonlocal index
        skip()
        require(text[index:index + 1] == character, f"expected {character!r} at offset {index}")
        index += 1

    def value():
        nonlocal index
        skip()
        require(index < len(text), "unexpected end of the file")
        character = text[index]
        if character == "{":
            index += 1
            result = {}
            while True:
                skip()
                if text[index:index + 1] == "}":
                    index += 1
                    return result
                key = value()
                expect("=")
                result[key] = value()
                expect(";")
        if character == "(":
            index += 1
            result = []
            while True:
                skip()
                if text[index:index + 1] == ")":
                    index += 1
                    return result
                result.append(value())
                skip()
                if text[index:index + 1] == ",":
                    index += 1
        if character == '"':
            index += 1
            parts = []
            while True:
                require(index < len(text), "unterminated string")
                character = text[index]
                if character == '"':
                    index += 1
                    return "".join(parts)
                if character == "\\":
                    escaped = text[index + 1:index + 2]
                    parts.append({"n": "\n", "t": "\t", "r": "\r"}.get(escaped, escaped))
                    index += 2
                else:
                    parts.append(character)
                    index += 1
        if character == "<":
            end = text.find(">", index)
            require(end > 0, "unterminated data")
            data = text[index + 1:end]
            index = end + 1
            return data
        match = token.match(text, index)
        require(match, f"unexpected {character!r} at offset {index}")
        index = match.end()
        return match.group()

    result = value()
    skip()
    require(index == len(text), f"unexpected text at offset {index}")
    return result


def inside(base, path):
    try:
        path.resolve().relative_to(base.resolve())
        return True
    except ValueError:
        return False


def xcconfig_settings(base, path, seen=None):
    """Build settings from an .xcconfig file and the files it includes (iOS values only)."""
    seen = set() if seen is None else seen
    settings = {}
    if path in seen or not inside(base, path) or not path.is_file():
        return settings
    seen.add(path)
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.split("//", 1)[0].strip()
        include = re.match(r'#include\??\s+"([^"]+)"', line)
        if include:
            settings.update(xcconfig_settings(base, path.parent / include.group(1), seen))
            continue
        match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)((?:\[[^\]]*\])*)\s*=\s*(.*)", line)
        if match and (not match.group(2) or "sdk=iphone" in match.group(2)):
            settings[match.group(1)] = match.group(3).strip().rstrip(";").strip()
    return settings


def setting(values, key, target=""):
    """A build setting as text, with the references this check can resolve replaced."""
    value = values.get(key, "")
    text = " ".join(value) if isinstance(value, list) else str(value)
    text = re.sub(r"\$[({]inherited[)}]", "", text)
    text = re.sub(r"\$[({](?:SRCROOT|PROJECT_DIR|SOURCE_ROOT)[)}]/?", "", text)
    text = re.sub(r"\$[({](?:TARGET_NAME|PRODUCT_NAME)(?::[^)}]*)?[)}]", target, text)
    return text.strip().strip('"')


def version_tuple(text):
    numbers = re.findall(r"\d+", text)
    return tuple(int(number) for number in numbers[:2]) if numbers else None


def read_plist(base, path, inspection, where):
    if not path or not inside(base, path) or not path.is_file():
        return {}
    try:
        data = plistlib.loads(path.read_bytes())
    except Exception:
        inspection.add(NOT_READ, "Property lists that could not be read", where)
        return {}
    return data if isinstance(data, dict) else {}


def plist_item(key, value):
    if key == "UIBackgroundModes" and isinstance(value, list):
        return f"UIBackgroundModes ({', '.join(map(str, value))})"
    if key == "CFBundleURLTypes" and isinstance(value, list):
        schemes = [scheme for entry in value if isinstance(entry, dict)
                   for scheme in entry.get("CFBundleURLSchemes") or []]
        return f"CFBundleURLTypes ({', '.join(map(str, schemes))})"
    return key


def inspect_info_plist(plist, inspection, where):
    copied = []
    for key, value in sorted(plist.items()):
        if (key in HOST_PLIST_KEYS or key.startswith(HOST_PLIST_PREFIXES) or key.endswith("_Generation")
                or value in ("", None)):
            continue
        if key in ("UIMainStoryboardFile", "UIMainStoryboardFile~ipad", "NSMainStoryboardFile"):
            inspection.add(MANUAL, "The app starts from a storyboard: show its first screen from the Feature's root "
                           "view (UIViewControllerRepresentable). See docs/mini-apps.md#moving-an-existing-app", where)
        elif key == "UIUserInterfaceStyle":
            inspection.add(MECHANICAL, "A fixed light or dark appearance (UIUserInterfaceStyle): set "
                           "environment(\\.colorScheme, ...) on the Feature's root view. See "
                           "docs/guides/feature-appearance.md", where)
        elif key == "UIAppFonts":
            inspection.add(MANUAL, "Fonts (UIAppFonts) are registered for the whole app: register the Feature's "
                           "fonts from Bundle.module at run time (CTFontManagerRegisterFontsForURL).", where)
        elif key in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"):
            inspection.add(MANUAL, f"{key} shows the whole app's Documents folder in Files; JibunKit decides it "
                           "for all Features. Keep the Feature's files in its own location.", where)
        elif key == "CFBundleDocumentTypes":
            inspection.add(MANUAL, "Document types (files opened from other apps): they arrive through JibunKit's "
                           "incoming files. See docs/guides/feature-incoming.md", where)
        else:
            copied.append(plist_item(key, value))
    if copied:
        inspection.add(MECHANICAL, "Info.plist keys: copy them to `app.infoPlist` in JibunKitFeature.json: "
                       + ", ".join(copied) + ". See docs/guides/feature-build-requirements.md", where)


def inspect_entitlements(entitlements, inspection, where):
    copied = []
    for key, value in sorted(entitlements.items()):
        if key in FREE_SIGNING_ENTITLEMENTS:
            inspection.add(FREE_SIGNING, f"{FREE_SIGNING_ENTITLEMENTS[key]} ({key})", where)
        elif key == "com.apple.security.application-groups":
            inspection.add(MANUAL, f"App Groups ({', '.join(map(str, value or []))}) belong to the app's own "
                           "signing: use MiniAppStorage.sharedDefaults() and the Feature's files. See "
                           "docs/mini-apps.md#moving-an-existing-app", where)
        elif key == "keychain-access-groups":
            inspection.add(MANUAL, "Keychain access groups belong to the app's own signing: keep the Feature's "
                           "items with MiniAppKeychain. See docs/guides/keychain-access-control.md", where)
        elif key not in SIGNING_ENTITLEMENTS and not key.startswith("com.apple.security."):
            copied.append(key)
    if copied:
        inspection.add(MECHANICAL, "Entitlements: copy them to `app.entitlements` in JibunKitFeature.json: "
                       + ", ".join(copied) + ".", where)


class XcodeProject:
    """The parts of an .xcodeproj that inspect and migrate read."""

    def __init__(self, base, project):
        self.base, self.project = base, project
        self.srcroot = (base / project).parent
        try:
            data = parse_openstep((base / project / "project.pbxproj").read_text(encoding="utf-8", errors="replace"))
            self.objects = data["objects"]
            self.root = self.objects[data["rootObject"]]
            self.parents = {child: key for key, item in self.objects.items() if isinstance(item, dict)
                            for child in item.get("children", []) if isinstance(child, str)}
            self.project_settings = self.settings(self.root.get("buildConfigurationList"))
        except (FeatureError, KeyError, IndexError, TypeError, AttributeError):
            raise FeatureError(f"{project}: the project file could not be read") from None

    def file_path(self, identifier):
        """The path of a file or group reference, or None when it is outside the source tree."""
        parts = []
        while identifier:
            item = self.objects.get(identifier, {})
            if item.get("path"):
                parts.append(item["path"])
            tree = item.get("sourceTree", "<group>")
            if tree == "SOURCE_ROOT":
                break
            if tree != "<group>":
                return None
            identifier = self.parents.get(identifier)
        return self.srcroot.joinpath(*reversed(parts)) if parts else None

    def settings(self, identifier):
        """The Release build settings of a configuration list, with its .xcconfig file."""
        configurations = [self.objects.get(key, {})
                          for key in self.objects.get(identifier, {}).get("buildConfigurations", [])]
        chosen = next((item for item in configurations if item.get("name") == "Release"),
                      configurations[0] if configurations else {})
        values = {}
        path = None
        if chosen.get("baseConfigurationReference"):
            path = self.file_path(chosen["baseConfigurationReference"])
        elif chosen.get("baseConfigurationReferenceAnchor"):
            # Xcode 16: a file inside a folder that the project mirrors.
            folder = self.file_path(chosen["baseConfigurationReferenceAnchor"])
            path = folder / chosen.get("baseConfigurationReferenceRelativePath", "") if folder else None
        if path:
            values.update(xcconfig_settings(self.base, path))
        for key, value in chosen.get("buildSettings", {}).items():
            # A setting for one SDK only, such as KEY[sdk=iphoneos*]: keep the iOS ones.
            key, _, condition = key.partition("[")
            if not condition or "sdk=iphone" in condition:
                values[key] = value
        return values

    def targets(self):
        """(identifier, target, build settings, platforms) for each native target."""
        for identifier in self.root.get("targets", []):
            target = self.objects.get(identifier, {})
            if target.get("isa") != "PBXNativeTarget":
                continue
            values = {**self.project_settings, **self.settings(target.get("buildConfigurationList"))}
            platforms = set(setting(values, "SUPPORTED_PLATFORMS").split()) or {setting(values, "SDKROOT") or "iphoneos"}
            yield identifier, target, values, platforms

    def info_plist(self, values, name, inspection, where):
        """The target's Info.plist file merged with its INFOPLIST_KEY_ build settings."""
        path = setting(values, "INFOPLIST_FILE", name)
        plist = read_plist(self.base, self.srcroot / path if path else None, inspection, where)
        for key in values:
            if key.startswith("INFOPLIST_KEY_"):
                plist.setdefault(key[len("INFOPLIST_KEY_"):], setting(values, key, name))
        return plist


def ios_platforms(platforms):
    return bool(platforms & {"iphoneos", "iphonesimulator", "auto"})


def inspect_xcode_project(base, project, inspection):
    """Read one .xcodeproj. Returns True when it has an iOS app target."""
    try:
        xcode = XcodeProject(base, project)
    except FeatureError:
        inspection.add(NOT_READ, "Xcode projects whose project file could not be read; only their code was checked",
                       project)
        return False
    objects, srcroot = xcode.objects, xcode.srcroot

    apps, others, skipped = [], [], []
    for identifier, target, values, platforms in xcode.targets():
        name, kind = target.get("name", identifier), target.get("productType", "")
        if kind in IGNORED_TYPES:
            continue
        if not ios_platforms(platforms):
            skipped.append(f"{name} ({', '.join(sorted(platforms))})")
            continue
        where = f"{project.rsplit('/', 1)[-1]} {name}"
        plist = xcode.info_plist(values, name, inspection, where)
        if kind == "com.apple.product-type.application":
            apps.append(name)
            minimum = version_tuple(setting(values, "IPHONEOS_DEPLOYMENT_TARGET"))
            if minimum and minimum > HOST_IOS:
                inspection.add(UNSUPPORTED, f"Needs iOS {'.'.join(map(str, minimum))}; JibunKit is built for iOS "
                               f"{'.'.join(map(str, HOST_IOS))}.", where)
            inspect_info_plist(plist, inspection, where)
            path = setting(values, "CODE_SIGN_ENTITLEMENTS", name)
            inspect_entitlements(read_plist(base, srcroot / path if path else None, inspection, where),
                                 inspection, where)
            language = version_tuple(setting(values, "SWIFT_VERSION"))
            if language and language < (6, 0):
                inspection.add(MECHANICAL, "Swift 5 code: give the package target `swiftSettings: "
                               "[.swiftLanguageMode(.v5)]`. See docs/mini-apps.md#moving-an-existing-app", where)
            if setting(values, "SWIFT_OBJC_BRIDGING_HEADER"):
                inspection.add(MANUAL, "An Objective-C bridging header: packages have none; put the Objective-C code "
                               "in its own package target and import it.", where)
        elif kind in EXTENSION_TYPES:
            extension = plist.get("NSExtension") or plist.get("EXAppExtensionAttributes") or {}
            point = extension.get("NSExtensionPointIdentifier") or extension.get("EXExtensionPointIdentifier") \
                if isinstance(extension, dict) else None
            if point in HOST_EXTENSIONS:
                message, guide = HOST_EXTENSIONS[point]
                inspection.add(MANUAL, f"{message} See {guide}", where)
            elif point:
                inspection.add(UNSUPPORTED, f"{EXTENSION_NAMES.get(point, 'This')} extension ({point}): JibunKit "
                               "has no extension of this kind.", where)
            else:
                inspection.add(MANUAL, "An app extension of a kind this check could not read: see whether one of "
                               "JibunKit's extensions does its job.", where)
        elif kind in PRODUCT_TYPES:
            inspection.add(UNSUPPORTED, f"{PRODUCT_TYPES[kind]}: JibunKit builds one iPhone app.", where)
        elif kind in LIBRARY_TYPES:
            inspection.add(MANUAL, "Framework and library targets: make each one a target of the Feature's "
                           "Swift package.", where)
        else:
            inspection.add(NOT_READ, f"Targets of a type this check does not know ({kind})", where)
        others.append(name)
    packages = []
    for identifier in xcode.root.get("packageReferences", []):
        reference = objects.get(identifier, {})
        if reference.get("isa") == "XCRemoteSwiftPackageReference":
            url = reference.get("repositoryURL", "")
            requirement = reference.get("requirement", {})
            kind = requirement.get("kind", "")
            pinned = requirement.get("version") or requirement.get("revision") or requirement.get("branch") \
                or requirement.get("minimumVersion") or ""
            inspection.add_package(url, f"{url} ({kind} {pinned})".replace(" )", ")"))
            if kind not in ("exactVersion", "revision"):
                inspection.add_package(url, url, f"{UNPINNED}:")
            packages.append(url)
        elif reference.get("isa") == "XCLocalSwiftPackageReference":
            path = reference.get("relativePath", "")
            inspection.add_package(f"local {path}", f"local {path}")
            if not inside(base, srcroot / path):
                inspection.add(MANUAL, f"A local package outside the inspected directory ({path}): it is not "
                               "copied with the Feature.", project)
            packages.append(path)
    if packages:
        inspection.add(MECHANICAL, "Swift packages the Xcode project uses: declare them as dependencies in the "
                       "Feature's Package.swift.", project)
    summary = ", ".join(apps + [name for name in others if name not in apps]) or "no iOS targets"
    inspection.found.append(f"Xcode project {project} ({summary})")
    if skipped:
        inspection.found.append(f"targets for other platforms skipped: {', '.join(skipped)}")
    return bool(apps)


def inspect_package(base, directory, inspection):
    """Read a Package.swift. Returns True when it can provide a Feature's products."""
    module = base / directory
    text = re.sub(r"(?m)^\s*//.*$", "", (module / "Package.swift").read_text(encoding="utf-8", errors="replace"))
    name = re.search(r'Package\(\s*name:\s*"([^"]+)"', text)
    label = f"Swift package {name.group(1) if name else directory or '(root)'}"
    libraries = re.findall(r'\.library\(\s*name:\s*"([^"]+)"', text)
    def add(category, item):
        if category == "Swift packages":
            inspection.add_package(item if item.startswith("local ") else item.split()[0], item)
        elif category == UNPINNED:
            inspection.add_package(item, item, f"{UNPINNED}:")
        else:
            inspection.add(BRINGS, f"{category}: {item}")

    describe_package(module, add)
    where = f"{directory}/Package.swift" if directory else "Package.swift"
    if (module / MANIFEST).exists():
        inspection.feature = True
        label = f"JibunKit Feature ({label})"
        try:
            data = load(module)
        except FeatureError as error:
            inspection.add(MANUAL, f"{MANIFEST} is not valid: {error}", where)
        else:
            for item in sorted(item for items in describe_requirements(data).values() for item in items):
                inspection.add(BRINGS, f"{REQUIREMENTS}: {item}")
    elif ".iOSApplication(" in text:
        inspection.add(MECHANICAL, "A Swift Playgrounds app: make the app product a library, add "
                       f"{MANIFEST} and replace the App with a MiniAppDefinition.", where)
        capabilities = sorted(set(re.findall(r"\.(\w+)\(\s*purposeString:", text)))
        if capabilities:
            inspection.add(MECHANICAL, f"Capabilities of the Playgrounds app ({', '.join(capabilities)}): put their "
                           "usage descriptions in `app.infoPlist` in JibunKitFeature.json. See "
                           "docs/guides/feature-build-requirements.md", where)
    elif libraries:
        inspection.add(MECHANICAL, f"No {MANIFEST}: add one that lists the products ({', '.join(libraries)}) and "
                       "an Integration file that creates the MiniAppDefinition with the root view; `new --name "
                       "Example` shows both. See docs/mini-apps.md#2-connect-it-to-the-host", where)
    else:
        inspection.add(MANUAL, "The package has no library product; JibunKit links a Feature as a library.", where)
    inspection.found.append(label)
    return bool(libraries) or ".iOSApplication(" in text


def describe_requirements(data):
    """The Info.plist keys, entitlements and App Shortcuts a Feature manifest declares."""
    report = {}
    for target, section in (("app", data.get("app") or {}), ("widget", data.get("widget") or {})):
        for kind in ("infoPlist", "entitlements"):
            for key, value in (section.get(kind) or {}).items():
                if key == "CFBundleURLTypes" and isinstance(value, list):
                    for declaration in value:
                        for scheme in (declaration.get("CFBundleURLSchemes") or []) if isinstance(declaration, dict) else []:
                            report.setdefault(REQUIREMENTS, set()).add(f"{target} {kind} CFBundleURLTypes: {scheme}")
                elif isinstance(value, list) and all(isinstance(item, str) for item in value):
                    for item in value:
                        report.setdefault(REQUIREMENTS, set()).add(f"{target} {kind} {key}: {item}")
                else:
                    report.setdefault(REQUIREMENTS, set()).add(f"{target} {kind} {key}")
    if data.get("appShortcuts"):
        report.setdefault(REQUIREMENTS, set()).add("App Shortcuts")
    return report


def app_code(name):
    """Whether a file is part of the app rather than tests, examples or other people's code."""
    parts = name.split("/")
    return not any(part in NOT_APP_CODE or part.endswith(("Tests", ".xcodeproj", ".xcworkspace", ".docc"))
                   for part in parts[:-1])


def inspect_code(base, names, inspection):
    files = [base / name for name in names if name.endswith(".swift") and app_code(name)
             and not MANIFEST_FILE.fullmatch(name.rsplit("/", 1)[-1]) and (base / name).is_file()]
    for file, number, rule, message, guide in check(files):
        if rule != "app-entry":
            inspection.add(MANUAL, f"[{rule}] {message} See {guide}", f"{file.relative_to(base).as_posix()}:{number}")
    rules = MOVE_CHECKS
    if any(name.rsplit("/", 1)[-1] in ("Localizable.strings", "Localizable.xcstrings") for name in names):
        rules = rules + [LOCALIZED_TEXT]
    compiled = [(rule, re.compile(pattern), exempt and re.compile(exempt), section, message, guide)
                for rule, pattern, exempt, section, message, guide in rules]
    for file in files:
        text = file.read_text(encoding="utf-8", errors="replace")
        relative = file.relative_to(base).as_posix()
        code = "\n".join(line.split("//", 1)[0] for line in text.splitlines())
        for rule, pattern, exempt, section, message, guide in compiled:
            for match in pattern.finditer(code):
                if exempt and exempt.search(call_arguments(code, match.end())):
                    continue
                inspection.add(section, f"[{rule}] {message} See {guide}",
                               f"{relative}:{code.count(chr(10), 0, match.start()) + 1}")
        for entry in APP_ENTRY.finditer(code):
            where = f"{relative}:{code.count(chr(10), 0, entry.start()) + 1}"
            # Other @main types are widget bundles, plugins or tools; an app
            # delegate entry is reported by the app-delegate rule.
            if entry.group(1) in ("App", "SwiftUI.App"):
                inspection.add(MECHANICAL, "[app-entry] The App with @main: JibunKit owns the app entry; show its "
                               "root view from a MiniAppDefinition instead. See docs/mini-apps.md#3-write-the-integration",
                               where)
    return len(files)


def call_arguments(code, start):
    """The argument text of a call whose "(" ends at `start`, skipping parentheses in string literals."""
    depth, index, in_string = 1, start, False
    end = min(len(code), start + 4000)
    while index < end and depth:
        character = code[index]
        if in_string:
            if character == "\\":
                index += 1
            elif character in '"\n':
                in_string = False
        elif character == '"':
            in_string = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        index += 1
    return code[start:index]


def inspect_directory(base, names=None):
    """Inspect the files under base; `names` lists every file, including ones not written to disk."""
    if names is None:
        names = sorted(path.relative_to(base).as_posix() for path in base.rglob("*")
                       if path.is_file() and ".git" not in path.relative_to(base).parts)
    inspection = Inspection()
    projects = sorted({name[:-len("/project.pbxproj")] for name in names
                       if name.endswith(".xcodeproj/project.pbxproj") and app_code(name.rsplit(".xcodeproj/", 1)[0] + "/x")})
    has_app = False
    for project in projects:
        has_app = inspect_xcode_project(base, project, inspection) or has_app
    packages = [""] if "Package.swift" in names else []
    packages += sorted(name[:-len("/Package.swift")] for name in names
                       if re.fullmatch(r"[^/]+\.swiftpm/Package\.swift", name))
    has_package = False
    for directory in packages:
        has_package = inspect_package(base, directory, inspection) or has_package
    if not projects and not packages:
        for marker, tool in (("project.yml", "XcodeGen"), ("Project.swift", "Tuist")):
            if marker in names:
                inspection.add(NOT_READ, f"The {tool} project ({marker}): its targets, Info.plist keys and "
                               "entitlements were not read; only the code was checked.")
    if any(name.rsplit("/", 1)[-1] == ".gitattributes" and (base / name).is_file()
           and "filter=lfs" in (base / name).read_text(encoding="utf-8", errors="replace") for name in names):
        inspection.add(MANUAL, "Git LFS keeps some files outside the repository; migrate copies only their "
                       "pointers, so download those files yourself.", ".gitattributes")
    for manager, pattern in (("Podfile", r"""^\s*pod\s+['"]([^'"]+)"""), ("Cartfile", r'^\s*\w+\s+"([^"]+)"')):
        for name in names:
            if name.rsplit("/", 1)[-1] == manager and app_code(name) and (base / name).is_file():
                used = re.findall(pattern, (base / name).read_text(encoding="utf-8", errors="replace"), re.M)
                tool = "CocoaPods" if manager == "Podfile" else "Carthage"
                inspection.add(MANUAL, f"{tool} ({', '.join(used) or 'no libraries listed'}): JibunKit builds with "
                               "Swift packages only; use each library's Swift package.", name)
    for name in names:
        if not app_code(name):
            continue
        suffix = Path(name).suffix
        if suffix in (".m", ".mm", ".c", ".cc", ".cpp"):
            inspection.add(MANUAL, "Objective-C, C or C++ code: a package target holds one language; put it in a "
                           "target of its own.", name)
        elif suffix in (".storyboard", ".xib") and not Path(name).stem.startswith("LaunchScreen"):
            inspection.add(MANUAL, "Storyboards and xibs: load them from Bundle.module.", name)
        elif "Settings.bundle/" in name and name.endswith("Root.plist"):
            inspection.add(UNSUPPORTED, "Settings.bundle: the Settings app shows one page for JibunKit, not one per "
                           "Feature; move the settings into the Feature's screens.", name)
        elif name.rsplit("/", 1)[-1] in ("InfoPlist.strings", "InfoPlist.xcstrings") and projects:
            inspection.add(MECHANICAL, "Localized Info.plist text: move it to `app.localizedInfoPlist` in "
                           "JibunKitFeature.json. See docs/guides/feature-build-requirements.md", name)
    count = inspect_code(base, names, inspection)
    inspection.found.append(f"{count} Swift file(s) checked")
    if not count and not projects and not packages:
        inspection.whole = "no Swift code, Xcode project or Swift package was found"
    elif projects and not has_app and not has_package:
        inspection.whole = "no iOS app target was found"
    return inspection


def inspect_repository(repository, ref="HEAD", path=""):
    """Fetch one commit and inspect a directory of it. Returns (repository, commit, Inspection)."""
    repository = repository_url(repository)
    path = source_path(path)
    with tempfile.TemporaryDirectory() as temporary:
        work, base = Path(temporary) / "git", Path(temporary) / "files"
        work.mkdir()
        base.mkdir()
        commit = fetch(work, repository, ref)
        names, wanted, links, submodules = [], [], [], []
        for name, mode, kind, sha in list_tree(work, commit, path):
            if kind == "commit":
                submodules.append(name)
            elif mode == "120000":
                links.append(name)
            else:
                names.append(name)
                if Path(name).suffix in INSPECTED_SUFFIXES or Path(name).name in INSPECTED_NAMES:
                    wanted.append((name, sha))
        unwritten = []
        for (name, _), data in zip(wanted, read_blobs(work, [sha for _, sha in wanted])):
            try:
                write_file(base, name, data)
            except OSError:
                unwritten.append(name)
        inspection = inspect_directory(base, names)
    for name in submodules:
        inspection.add(MANUAL, "Git submodules: their code is in another repository and is not copied; copy it in "
                       "or depend on its Swift package.", name)
    for name in links:
        inspection.add(NOT_READ, "Symbolic links (not followed)", name)
    for name in unwritten:
        inspection.add(NOT_READ, "Files whose names this computer cannot store", name)
    return repository, commit, inspection


def print_inspection(inspection):
    print("Found: " + "; ".join(inspection.found) + ".")
    print(f"Verdict: {inspection.verdict()}.")
    for section, title in SECTION_TITLES.items():
        entries = [(message, places) for (kind, message), places in inspection.items.items() if kind == section]
        if not entries:
            continue
        print(f"\n{title}:")
        for message, places in sorted(entries):
            print(f"  {message}")
            if places:
                shown = ", ".join(places[:SHOWN_LOCATIONS])
                more = f" (+{len(places) - SHOWN_LOCATIONS} more)" if len(places) > SHOWN_LOCATIONS else ""
                print(f"    {shown}{more}")


# Moving an app in (`migrate`): copy an app target's code and resources into a
# new Feature package and make the mechanical changes that `inspect` lists.
# The result is a draft; `connect` connects it once it compiles and `check`
# reports nothing. Like add, it never runs code from the repository.
OTHER_LANGUAGES = {".m", ".mm", ".c", ".cc", ".cpp", ".h", ".hpp"}
NOT_RESOURCES = {".entitlements", ".xcconfig", ".md", ".xctestplan", ".pch", ".modulemap"}
# Resources that are directories to Xcode; a package declares the directory.
RESOURCE_DIRECTORIES = (".xcassets", ".xcdatamodeld", ".xcmappingmodel", ".lproj", ".bundle", ".scnassets",
                        ".xcstickers", ".rcproject", ".reality", ".mlpackage")
COPIED_RESOURCES = (".bundle",)
# Scene modifiers that have no View counterpart.
SCENE_ONLY_MODIFIERS = {"commands", "commandsRemoved", "commandsReplaced", "windowResizability", "defaultSize",
                        "defaultPosition", "windowStyle", "windowToolbarStyle", "handlesExternalEvents",
                        "backgroundTask", "defaultLaunchBehavior", "restorationBehavior", "windowLevel",
                        "windowManagerRole", "windowIdealSize", "defaultWindowPlacement", "windowBackgroundDragBehavior"}
# Info.plist keys that `inspect` sends to manual work: migrate does not copy them.
MANUAL_PLIST_KEYS = {"UIMainStoryboardFile", "UIMainStoryboardFile~ipad", "NSMainStoryboardFile", "UIAppFonts",
                     "UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace", "CFBundleDocumentTypes",
                     "UIUserInterfaceStyle", "NSExtension"}
# Swift Playgrounds capabilities and the usage descriptions they stand for.
PLAYGROUNDS_CAPABILITIES = {
    "camera": "NSCameraUsageDescription", "microphone": "NSMicrophoneUsageDescription",
    "photoLibrary": "NSPhotoLibraryUsageDescription", "photoLibraryAdd": "NSPhotoLibraryAddUsageDescription",
    "locationWhenInUse": "NSLocationWhenInUseUsageDescription",
    "locationAlwaysAndWhenInUse": "NSLocationAlwaysAndWhenInUseUsageDescription",
    "contacts": "NSContactsUsageDescription", "calendars": "NSCalendarsFullAccessUsageDescription",
    "reminders": "NSRemindersFullAccessUsageDescription", "bluetoothAlways": "NSBluetoothAlwaysUsageDescription",
    "motion": "NSMotionUsageDescription", "speechRecognition": "NSSpeechRecognitionUsageDescription",
    "faceID": "NSFaceIDUsageDescription", "mediaLibrary": "NSAppleMusicUsageDescription",
    "homeKit": "NSHomeKitUsageDescription", "localNetwork": "NSLocalNetworkUsageDescription",
    "nearbyInteraction": "NSNearbyInteractionUsageDescription",
}
# (pattern, labels the bundle argument follows, inserted text, only for a single argument)
BUNDLE_REWRITES = [
    ("asset-lookup", r'\b(?:Image|Color)\((?=\s*")', (), ", bundle: .module", False),
    ("asset-lookup", r"\bUIImage\((?=\s*named:)", (), ", in: .module, with: nil", True),
    ("asset-lookup", r"\bUIColor\((?=\s*named:)", (), ", in: .module, compatibleWith: nil", True),
    ("localized-string", r"\bNSLocalizedString\(", ("tableName",), ", bundle: .module", False),
    ("localized-string", r"\bString\((?=\s*localized:)", ("defaultValue", "table"), ", bundle: .module", False),
]
LOCALIZED_TEXT_REWRITE = ("localized-text", r'\bText\((?=\s*")', ("tableName",), ", bundle: .module", False)


def mask_code(text):
    """text with comments blanked and string contents replaced by "_", at the
    same positions, so that patterns and brackets only see code."""
    out = list(text)
    index, length = 0, len(text)

    def blank(start, end, filler):
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = filler

    def string_end(start):
        """The index after the string literal starting at `start`."""
        opening = re.match(r'(#*)("""|")', text[start:])
        hashes, quote = opening.group(1), opening.group(2)
        closing = quote + hashes
        position = start + len(opening.group(0))
        content_start = position
        while position < length:
            if text.startswith("\\" + hashes, position):
                after = position + 1 + len(hashes)
                if text[after:after + 1] == "(":
                    depth, position = 1, after + 1
                    while position < length and depth:
                        character = text[position]
                        if character == '"':
                            position = string_end(position)
                            continue
                        depth += {"(": 1, ")": -1}.get(character, 0)
                        position += 1
                else:
                    position = after + 1
            elif text.startswith(closing, position):
                blank(content_start, position, "_")
                return position + len(closing)
            elif text[position] == "\n" and quote == '"':
                blank(content_start, position, "_")
                return position
            else:
                position += 1
        blank(content_start, length, "_")
        return length

    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            blank(index, end, " ")
            index = end
        elif text.startswith("/*", index):
            depth, end = 1, index + 2
            while end < length and depth:
                if text.startswith("/*", end):
                    depth, end = depth + 1, end + 2
                elif text.startswith("*/", end):
                    depth, end = depth - 1, end + 2
                else:
                    end += 1
            blank(index, end, " ")
            index = end
        elif re.match(r'#*"', text[index:index + 8]) and (text[index] == '"' or not re.match(r"\w", text[index - 1:index] or " ")):
            index = string_end(index)
        else:
            index += 1
    return "".join(out)


def closing_bracket(masked, opening):
    """The index of the bracket that closes the one at `opening`, or -1."""
    depth = 0
    for position in range(opening, len(masked)):
        character = masked[position]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                return position
    return -1


def argument_spans(masked, start, end):
    """(start, end) of each top-level argument between start and end."""
    spans, depth, begin = [], 0, start
    for position in range(start, end):
        character = masked[position]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            spans.append((begin, position))
            begin = position + 1
    if masked[begin:end].strip():
        spans.append((begin, end))
    return spans


def add_module_bundles(text, localized):
    """Add `bundle: .module` (or `in: .module`) to resource lookups. Returns the
    new text, the changed lines and the lines of calls left as they were."""
    masked = mask_code(text)
    rules = BUNDLE_REWRITES + ([LOCALIZED_TEXT_REWRITE] if localized else [])
    edits, changed, left = [], set(), set()
    for rule, pattern, after, insertion, single in rules:
        for match in re.finditer(pattern, masked):
            opening = match.end() - 1
            closing = closing_bracket(masked, opening)
            if closing < 0:
                continue
            spans = argument_spans(masked, opening + 1, closing)
            labels = [re.match(r"\s*(\w+)\s*:(?!:)", masked[a:b]) for a, b in spans]
            labels = [label.group(1) if label else None for label in labels]
            line = masked.count("\n", 0, match.start()) + 1
            if {"bundle", "in"} & set(labels) or not spans:
                continue
            if single and len(spans) != 1:
                left.add((rule, line))
                continue
            index = max([0] + [number for number, label in enumerate(labels) if label in after])
            position = spans[index][0] + len(masked[spans[index][0]:spans[index][1]].rstrip())
            edits.append((position, insertion))
            changed.add((rule, line))
    for position, insertion in sorted(edits, reverse=True):
        text = text[:position] + insertion + text[position:]
    return text, sorted(changed), sorted(left)


def app_to_root_view(text, root_name, color_scheme=None):
    """Turn the `@main` SwiftUI App in text into `public struct <root_name>: View`
    that shows its WindowGroup's content. Returns (text, notes), or (None, reason)."""
    masked = mask_code(text)
    entry = re.search(r"@main\s+((?:(?:public|final|internal)\s+)*)struct\s+(\w+)\s*:\s*([^{]*)\{", masked)
    if not entry or not {"App", "SwiftUI.App"} & {part.strip() for part in entry.group(3).split(",")}:
        return None, "no SwiftUI App struct with @main"
    opening = entry.end() - 1
    closing = closing_bracket(masked, opening)
    body = re.compile(r"\bvar\s+body\s*:\s*some\s+(?:SwiftUI\.)?Scene\s*\{").search(masked, opening, closing)
    if closing < 0 or not body:
        return None, "the App has no `var body: some Scene`"
    body_close = closing_bracket(masked, body.end() - 1)
    group = re.compile(r"\s*WindowGroup\b\s*").match(masked, body.end())
    if not group:
        return None, "the App's body does not start with a WindowGroup"
    position = group.end()
    if masked[position:position + 1] == "(":
        position = re.compile(r"\s*").match(masked, closing_bracket(masked, position) + 1).end()
    if masked[position:position + 1] != "{":
        return None, "the WindowGroup has no content closure"
    content_close = closing_bracket(masked, position)
    content = text[position + 1:content_close]
    notes, modifiers, cursor = [], [], content_close + 1
    modifier = re.compile(r"\s*\.\s*([A-Za-z_]\w*)")
    while True:
        condition = re.compile(r"\s*#if\b").match(masked, cursor, body_close)
        if condition:
            # Conditional modifiers are valid in a view's chain too; keep them as written.
            depth, end = 0, condition.end()
            for directive in re.compile(r"#(if|endif)\b").finditer(masked, condition.end() - 3, body_close):
                depth += 1 if directive.group(1) == "if" else -1
                if depth == 0:
                    end = directive.end()
                    break
            if depth:
                break
            modifiers.append(text[condition.start():end].strip())
            cursor = end
            continue
        found = modifier.match(masked, cursor, body_close)
        if not found:
            break
        end = found.end()
        for bracket in ("(", "{"):
            following = re.compile(r"\s*\%s" % bracket).match(masked, end, body_close)
            if following:
                end = closing_bracket(masked, following.end() - 1) + 1
        if found.group(1) in SCENE_ONLY_MODIFIERS:
            notes.append(f"dropped the scene modifier .{found.group(1)}, which a view does not have")
        else:
            modifiers.append(text[found.start():end].strip())
        cursor = end
    if masked[cursor:body_close].strip():
        return None, "the App's body has more than one scene"
    # Keep modifiers such as `public` written before `var body` out of the members.
    body_start = masked.rfind("\n", 0, body.start()) + 1
    if not re.fullmatch(r"\s*(?:(?:public|internal|@\w+)\s+)*", masked[body_start:body.start()]):
        body_start = body.start()
    members = text[opening + 1:body_start] + text[body_close + 1:closing]
    kept, removed = [], []
    lines = members.split("\n")
    skip_next = False
    for number, line in enumerate(lines):
        if skip_next:
            skip_next = False
            removed.append(line)
            continue
        if "@UIApplicationDelegateAdaptor" in line:
            removed.append(line)
            skip_next = not re.search(r"\bvar\b", line)
            continue
        kept.append(line)
    members = "\n".join(kept)
    for delegate in re.findall(r"\bvar\s+(\w+)", "\n".join(removed)):
        uses = re.search(r"\b%s\b" % delegate, mask_code(content + members + "".join(modifiers)))
        notes.append(f"removed the @UIApplicationDelegateAdaptor property `{delegate}`"
                     + (f"; the root view still uses `{delegate}`, so create what the app delegate provided in "
                        "the view or the MiniAppDefinition" if uses else "; move the app delegate's work"))
    initializer = re.compile(r"(?m)^(\s*)(?:(?:private|fileprivate|internal|public)\s+)?init\s*\(\s*\)")
    if initializer.search(mask_code(members)):
        members = initializer.sub(r"\1public init()", members, count=1)
        initializer_line = ""
    else:
        initializer_line = "    public init() {}\n"
    view = [f"public struct {root_name}: View {{" + members.rstrip() + "\n"]
    view.append("\n" + initializer_line + "\n    public var body: some View {\n        Group {")
    view.append(content.rstrip() + "\n        }")
    for item in modifiers:
        view.append("\n        " + item)
    if color_scheme:
        view.append(f"\n        .environment(\\.colorScheme, .{color_scheme})")
    view.append("\n    }\n}")
    result = text[:entry.start()] + "".join(view) + text[closing + 1:]
    if not re.search(r"(?m)^\s*import\s+SwiftUI\b", result):
        result = "import SwiftUI\n" + result
    return result, notes


def strings_table(data):
    """{key: value} from a .strings file."""
    for encoding in ("utf-8-sig", "utf-16"):
        try:
            text = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        return {}
    pairs = re.findall(r'(?m)(?:"((?:[^"\\]|\\.)*)"|([A-Za-z_][\w.-]*))\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text)
    unescape = lambda value: re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), value)
    return {unescape(quoted or plain): unescape(value) for quoted, plain, value in pairs}


def localized_info_plist(base, names):
    """{locale: {key: text}} from InfoPlist.strings and InfoPlist.xcstrings files."""
    tables = {}
    for name in names:
        file = base / name
        if not file.is_file():
            continue
        if name.endswith(".lproj/InfoPlist.strings"):
            locale = name.rsplit("/", 2)[-2][:-len(".lproj")]
            tables.setdefault(locale, {}).update(strings_table(file.read_bytes()))
        elif name.rsplit("/", 1)[-1] == "InfoPlist.xcstrings":
            try:
                catalog = json.loads(file.read_text(encoding="utf-8"))
            except ValueError:
                continue
            for key, entry in (catalog.get("strings") or {}).items():
                for locale, localization in ((entry or {}).get("localizations") or {}).items():
                    value = ((localization or {}).get("stringUnit") or {}).get("value")
                    if isinstance(value, str):
                        tables.setdefault(locale, {})[key] = value
    return {locale: {key: value for key, value in table.items()
                     if key not in HOST_PLIST_KEYS and not key.startswith(HOST_PLIST_PREFIXES)}
            for locale, table in tables.items()}


def plist_copy(value):
    """value when JibunKitFeature.json can hold it, else None."""
    if isinstance(value, bool) or isinstance(value, (int, float, str)):
        return value
    if isinstance(value, list):
        items = [plist_copy(item) for item in value]
        return None if any(item is None for item in items) else items
    if isinstance(value, dict):
        items = {str(key): plist_copy(item) for key, item in value.items()}
        return None if any(item is None for item in items.values()) else items
    return None


def package_requirement(requirement):
    """A SwiftPM requirement for an Xcode package reference's requirement."""
    kind = requirement.get("kind", "")
    version = requirement.get("version") or requirement.get("minimumVersion") or ""
    if kind == "exactVersion":
        return f"exact: {swift_string(version)}"
    if kind == "upToNextMinorVersion":
        return f".upToNextMinor(from: {swift_string(version)})"
    if kind == "versionRange":
        return f"{swift_string(version)}..<{swift_string(requirement.get('maximumVersion', ''))}"
    if kind == "branch":
        return f"branch: {swift_string(requirement.get('branch', ''))}"
    if kind == "revision":
        return f"revision: {swift_string(requirement.get('revision', ''))}"
    return f"from: {swift_string(version)}"


def package_identity(location):
    return re.sub(r"\.git$", "", location.rstrip("/").replace("\\", "/").split("/")[-1].split(":")[-1])


class AppSource:
    """What migrate takes from an app: its files and how it was built."""

    def __init__(self, label):
        self.label = label
        self.files = []          # paths relative to the inspected directory
        self.plist = {}
        self.entitlements = {}
        self.dependencies = []   # Package.swift dependency expressions
        self.products = []       # target dependency expressions
        self.local_packages = {} # directory under Packages/ -> path relative to the inspected directory
        self.swift5 = False
        self.region = "en"
        self.title = None
        self.notes = []          # (section, message)


def members_of(names, paths):
    """Files in names that are one of paths or inside one of them."""
    chosen = []
    for name in names:
        if any(name == path or name.startswith(path + "/") for path in paths):
            chosen.append(name)
    return chosen


def local_libraries(base, names, cache={}):
    """{library product: package directory} for the Swift packages in the repository."""
    key = (str(base), len(names))
    if key not in cache:
        found = {}
        for name in names:
            if name.rsplit("/", 1)[-1] == "Package.swift" and "/" in name and app_code(name):
                text = (base / name).read_text(encoding="utf-8", errors="replace")
                for product in re.findall(r'\.library\(\s*name:\s*"([^"]+)"', text):
                    found.setdefault(product, name.rsplit("/", 1)[0])
        cache[key] = found
    return cache[key]


def xcode_app_source(base, names, xcode, identifier, target, values):
    name = target.get("name", identifier)
    source = AppSource(f"Xcode project {xcode.project}, target {name}")
    relative = lambda path: path.resolve().relative_to(base.resolve()).as_posix() if path and inside(base, path) else None
    paths, excluded = [], set()
    for phase in target.get("buildPhases", []):
        phase = xcode.objects.get(phase, {})
        if phase.get("isa") not in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase"):
            continue
        for build_file in phase.get("files", []):
            reference_id = xcode.objects.get(build_file, {}).get("fileRef")
            reference = xcode.objects.get(reference_id, {})
            children = reference.get("children", []) if reference.get("isa") == "PBXVariantGroup" else [reference_id]
            paths += [relative(xcode.file_path(child)) for child in children]
    members = set(target.get("fileSystemSynchronizedGroups", []))
    for group, item in xcode.objects.items():
        if not isinstance(item, dict) or item.get("isa") != "PBXFileSystemSynchronizedRootGroup":
            continue
        folder = relative(xcode.file_path(group))
        if not folder:
            continue
        if group in members:
            paths.append(folder)
        for exception in item.get("exceptions", []):
            exception = xcode.objects.get(exception, {})
            if exception.get("isa") == "PBXFileSystemSynchronizedBuildFileExceptionSet" \
                    and exception.get("target") == identifier:
                # Exceptions leave files out of a folder the target includes,
                # and add files of a folder it does not include.
                listed = {f"{folder}/{name}" for name in exception.get("membershipExceptions", [])}
                if group in members:
                    excluded |= listed
                else:
                    paths += sorted(listed)
    info = setting(values, "INFOPLIST_FILE", name)
    entitlements = setting(values, "CODE_SIGN_ENTITLEMENTS", name)
    for path in (info, entitlements):
        if path:
            excluded.add(relative(xcode.srcroot / path))
    source.files = [file for file in members_of(names, [path for path in paths if path])
                    if file not in excluded and not any(file.startswith(item + "/") for item in excluded if item)]
    scratch = Inspection()
    source.plist = xcode.info_plist(values, name, scratch, name)
    # Build settings write booleans as YES and NO.
    from_settings = {key[len("INFOPLIST_KEY_"):] for key in values if key.startswith("INFOPLIST_KEY_")}
    for key, value in list(source.plist.items()):
        if key in from_settings and value in ("YES", "NO"):
            source.plist[key] = value == "YES"
    source.entitlements = read_plist(base, xcode.srcroot / entitlements if entitlements else None, scratch, name)
    language = version_tuple(setting(values, "SWIFT_VERSION"))
    source.swift5 = not language or language < (6, 0)
    source.region = xcode.root.get("developmentRegion") or "en"
    source.title = source.plist.get("CFBundleDisplayName") or source.plist.get("CFBundleName") or name
    if not isinstance(source.title, str) or "$(" in source.title:
        source.title = name
    minimum = version_tuple(setting(values, "IPHONEOS_DEPLOYMENT_TARGET"))
    require(not minimum or minimum <= HOST_IOS,
            f"{name} needs iOS {'.'.join(map(str, minimum or ()))}; JibunKit is built for iOS {'.'.join(map(str, HOST_IOS))}")
    for dependency in target.get("packageProductDependencies", []):
        dependency = xcode.objects.get(dependency, {})
        product = dependency.get("productName", "")
        reference = xcode.objects.get(dependency.get("package"), {})
        if product.startswith("plugin:"):
            source.notes.append((MANUAL, f"The build tool plugin {product[len('plugin:'):]} of the Xcode target: add it "
                                         "to the package target's `plugins:` if the code needs it."))
            continue
        if reference.get("isa") == "XCRemoteSwiftPackageReference":
            url = reference.get("repositoryURL", "")
            declaration = f".package(url: {swift_string(url)}, {package_requirement(reference.get('requirement', {}))})"
            identity = package_identity(url)
        elif reference.get("isa") == "XCLocalSwiftPackageReference":
            path = relative(xcode.srcroot / reference.get("relativePath", ""))
            if not path:
                source.notes.append((MANUAL, f"The local package {reference.get('relativePath')} is outside the "
                                             f"repository directory; {product} is not connected."))
                continue
            identity = package_identity(path)
            source.local_packages[identity] = path
            declaration = f".package(path: {swift_string('Packages/' + identity)})"
        elif product in local_libraries(base, names):
            path = local_libraries(base, names)[product]
            identity = package_identity(path)
            source.local_packages[identity] = path
            declaration = f".package(path: {swift_string('Packages/' + identity)})"
        else:
            source.notes.append((MANUAL, f"The product {product} comes from a package the project file does not "
                                         "name; add it to Package.swift."))
            continue
        if declaration not in source.dependencies:
            source.dependencies.append(declaration)
        source.products.append(f".product(name: {swift_string(product)}, package: {swift_string(identity)})")
    return source


def playgrounds_app_source(base, names, directory):
    module = base / directory if directory else base
    text = re.sub(r"(?m)^\s*//(?!\s*swift-tools-version).*$", "",
                  (module / "Package.swift").read_text(encoding="utf-8", errors="replace"))
    source = AppSource(f"Swift Playgrounds app {directory or '(root)'}")
    prefix = directory + "/" if directory else ""
    source.files = [name for name in names if name.startswith(prefix)
                    and not re.fullmatch(r"Package(@swift-[0-9.]+)?\.(swift|resolved)", name[len(prefix):])
                    and not name[len(prefix):].startswith(".swiftpm/") and app_code(name[len(prefix):])]
    tools = version_tuple((re.search(r"swift-tools-version:\s*([0-9.]+)", text) or [None, "5"])[1])
    source.swift5 = tools < (6, 0)
    region = re.search(r'defaultLocalization:\s*"([^"]+)"', text)
    source.region = region.group(1) if region else "en"
    title = re.search(r'displayName:\s*"([^"]+)"', text)
    package_name = re.search(r'Package\(\s*name:\s*"([^"]+)"', text)
    source.title = (title.group(1) if title else package_name.group(1) if package_name
                    else (directory or "App").removesuffix(".swiftpm"))
    for arguments in balanced_calls(text, "package"):
        if re.search(r"\b(url|path|id):", arguments):
            local = re.search(r'\bpath:\s*"([^"]+)"', arguments)
            if local:
                path = f"{prefix}{local.group(1)}".strip("/")
                identity = package_identity(path)
                source.local_packages[identity] = path
                source.dependencies.append(f".package(path: {swift_string('Packages/' + identity)})")
            else:
                source.dependencies.append(f".package({' '.join(arguments.split())})")
    source.products = [f".product({' '.join(arguments.split())})" for arguments in balanced_calls(text, "product")]
    for capability, purpose in re.findall(r'\.(\w+)\(\s*purposeString:\s*"((?:[^"\\]|\\.)*)"', text):
        if capability in PLAYGROUNDS_CAPABILITIES:
            source.plist[PLAYGROUNDS_CAPABILITIES[capability]] = purpose
        else:
            source.notes.append((MANUAL, f"The Playgrounds capability .{capability}: add what it needs to "
                                         "`app` in JibunKitFeature.json."))
    return source


def find_app(base, names, target=None):
    """The app to move: an iOS app target of an Xcode project, or a Swift Playgrounds app."""
    candidates, described = [], []
    for project in sorted({name[:-len("/project.pbxproj")] for name in names
                           if name.endswith(".xcodeproj/project.pbxproj")
                           and app_code(name.rsplit(".xcodeproj/", 1)[0] + "/x")}):
        try:
            xcode = XcodeProject(base, project)
        except FeatureError:
            continue
        for identifier, item, values, platforms in xcode.targets():
            if item.get("productType") == "com.apple.product-type.application" and ios_platforms(platforms):
                candidates.append((item.get("name", identifier), lambda x=xcode, i=identifier, t=item, v=values:
                                   xcode_app_source(base, names, x, i, t, v)))
    for directory in [""] + sorted(name[:-len("/Package.swift")] for name in names
                                   if re.fullmatch(r"[^/]+\.swiftpm/Package\.swift", name)):
        manifest = base / directory / "Package.swift" if directory else base / "Package.swift"
        if manifest.is_file() and ".iOSApplication(" in manifest.read_text(encoding="utf-8", errors="replace"):
            label = directory or "(root)"
            candidates.append((label, lambda d=directory: playgrounds_app_source(base, names, d)))
    described = [label for label, _ in candidates]
    if target:
        chosen = [make for label, make in candidates if label == target]
        require(chosen, f"No iOS app target {target!r}; found: {', '.join(described) or 'none'}")
        return chosen[0]()
    require(candidates, "migrate moves an iOS app target of an Xcode project or a Swift Playgrounds app, and found "
                        "neither. `inspect` shows what the repository has.")
    require(len(candidates) == 1, f"Several apps: {', '.join(described)}. Choose one with --target.")
    return candidates[0][1]()


def resource_entry(relative):
    """The path to declare for a resource file: the directory Xcode treats as one resource, or the file."""
    parts = relative.split("/")
    for index, part in enumerate(parts[:-1]):
        if part.endswith(RESOURCE_DIRECTORIES):
            return "/".join(parts[:index + 1])
    return relative


def package_manifest(name, source, resources, localized):
    lines = ["// swift-tools-version: 6.0", "// Written by `jibunkit-feature.py migrate`.", "import PackageDescription",
             "", "let package = Package(", f"    name: {swift_string(name)},"]
    if localized:
        lines.append(f"    defaultLocalization: {swift_string(source.region)},")
    lines += ['    platforms: [.iOS("26.0")],',
              f"    products: [.library(name: {swift_string(name + 'Feature')}, targets: [{swift_string(name + 'Feature')}])],"]
    if source.dependencies:
        lines.append("    dependencies: [")
        lines += [f"        {dependency}," for dependency in source.dependencies]
        lines.append("    ],")
    target = [f"            name: {swift_string(name + 'Feature')}"]
    if source.products:
        target.append("            dependencies: [\n" + "".join(f"                {product},\n" for product in source.products)
                      + "            ]")
    if resources:
        target.append("            resources: [\n" + "".join(
            f"                .{'copy' if entry.endswith(COPIED_RESOURCES) else 'process'}({swift_string(entry)}),\n"
            for entry in resources) + "            ]")
    if source.swift5:
        target.append("            swiftSettings: [.swiftLanguageMode(.v5)]")
    lines.append("    targets: [\n        .target(\n" + ",\n".join(target) + "\n        ),\n    ]")
    lines.append(")")
    return "\n".join(lines) + "\n"


def integration_source(name, feature_id, title):
    return f"""#if os(iOS)
import JibunKitCore
import {name}Feature

/// Connects {name} to the JibunKit host. Written by `jibunkit-feature.py migrate`;
/// JibunKitFeature.json lists this directory, so the host app compiles it.
@MainActor
enum {name}MiniApp {{
    static let definition = MiniAppDefinition(
        id: MiniAppID({swift_string(feature_id)}),
        title: {swift_string(title)},
        systemImage: "square.grid.2x2"
    ) {{ _ in
        {name}RootView()
    }}
}}
#endif
"""


def migrate_feature(root, repository, ref="HEAD", path="", name=None, target=None, feature_id=None):
    """Move an app into Modules/<name> as a draft Feature. Returns (module, commit, report text)."""
    repository = repository_url(repository)
    path = source_path(path)
    name = name or default_name(repository, path.removesuffix(".swiftpm") if path else path)
    require(NAME_PATTERN.fullmatch(name),
            "Use a Swift type name that starts with an uppercase letter and contains only letters and digits")
    feature_id = feature_id or name.lower()
    require(ID_PATTERN.fullmatch(feature_id),
            "The Feature ID must start with a lowercase letter and use only a-z, 0-9, '.', '-', '_'")
    module = root / "Modules" / name
    require(not module.exists() and name not in load_imports(root),
            f"Modules/{name} already exists; choose another --name")
    with tempfile.TemporaryDirectory() as temporary:
        work, base = Path(temporary) / "git", Path(temporary) / "files"
        work.mkdir()
        base.mkdir()
        commit = fetch(work, repository, ref)
        entries = [entry for entry in list_tree(work, commit, path) if entry[2] == "blob" and entry[1] != "120000"]
        names = []
        for (file, _, _, _), data in zip(entries, read_blobs(work, [sha for _, _, _, sha in entries])):
            try:
                write_file(base, file, data)
                names.append(file)
            except OSError:
                pass
        before = inspect_directory(base, names)
        source = find_app(base, names, target)
        report = migrate_files(root, module, name, feature_id, base, names, source)
    header = (f"# Moving {source.title} into JibunKit\n\n"
              f"Moved by `python3 Tools/jibunkit-feature.py migrate` from {repository} {path or '(root)'} at "
              f"{commit} ({ref}), {source.label}.\n\n"
              f"This Feature is a draft: `sync`, `check` and CI leave it out, so it does not affect builds. When "
              f"it compiles and `check Modules/{name}` reports nothing, run `python3 Tools/jibunkit-feature.py "
              f"connect {name}`.\n")
    left_out = []
    for (section, message), places in before.items.items():
        # Code findings are reported again on the moved files under "Still to change".
        project_level = places and all(".xcodeproj " in place or place in ("Podfile", "Cartfile") for place in places)
        if section == UNSUPPORTED or (section == MANUAL and project_level):
            left_out.append(f"- {message}" + (f" ({', '.join(places[:SHOWN_LOCATIONS])})" if places else ""))
    text = header + report
    if left_out:
        text += "\n## Not brought from the app\n\n" + "\n".join(sorted(left_out)) + "\n"
    (module / "MIGRATION.md").write_bytes(text.encode("utf-8"))
    return module, commit, text


def migrate_files(root, module, name, feature_id, base, names, source):
    """Write Modules/<name> from source. Returns the report sections."""
    changed, notes = [], list(source.notes)
    files = [file for file in source.files if Path(file).name != ".DS_Store"]
    swift = [file for file in files if file.endswith(".swift")]
    require(swift, f"{source.label} has no Swift files")
    other_code = [file for file in files if Path(file).suffix in OTHER_LANGUAGES]
    info_strings = [file for file in files if Path(file).name in ("InfoPlist.strings", "InfoPlist.xcstrings")]
    resources = [file for file in files if file not in swift and file not in other_code and file not in info_strings
                 and Path(file).suffix not in NOT_RESOURCES and Path(file).name not in ("Info.plist",)
                 and not Path(file).name.startswith("LaunchScreen.")]
    common = posixpath.commonpath([posixpath.dirname(file) for file in swift + resources])
    inside_target = lambda file: file[len(common) + 1:] if common else file
    localized = any(Path(file).name in ("Localizable.strings", "Localizable.xcstrings") or ".lproj/" in file
                    or file.endswith(".xcstrings") for file in resources)
    new(root, name, run_sync=False)
    target = module / "Sources" / f"{name}Feature"
    template_view = target / f"{name}RootView.swift"
    template_text = template_view.read_bytes()
    template_view.unlink()
    root_view = None
    color = {"dark": "dark", "light": "light"}.get(str(source.plist.get("UIUserInterfaceStyle", "")).lower())
    clash = False
    for file in swift:
        text = (base / file).read_bytes().decode("utf-8", errors="replace")
        if re.search(r"\b(?:struct|class|enum)\s+%sRootView\b" % name, text):
            clash = True
    for file in sorted(swift):
        data = (base / file).read_bytes()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            write_file(target, inside_target(file), data)
            notes.append((MANUAL, f"{inside_target(file)} is not UTF-8 text and was copied unchanged."))
            continue
        if root_view is None and not clash and re.search(r"@main\b", mask_code(text)):
            rewritten, result = app_to_root_view(text, f"{name}RootView", color)
            if rewritten is not None:
                text, root_view = rewritten, inside_target(file)
                changed.append(f"`{root_view}`: the `@main` App is now `public struct {name}RootView: View`, which "
                               "shows the WindowGroup's content; the host opens it from the MiniAppDefinition.")
                changed += [f"`{root_view}`: {note}." for note in result]
                if color:
                    changed.append(f"`{root_view}`: UIUserInterfaceStyle became `.environment(\\.colorScheme, "
                                   f".{color})` on the root view.")
            else:
                notes.append((MANUAL, f"`{inside_target(file)}`: the App was not changed ({result}). Show its first "
                                      f"screen from `{name}RootView`."))
        text, rewrites, left = add_module_bundles(text, localized)
        for rule in sorted({rule for rule, _ in rewrites}):
            lines = [str(line) for kind, line in rewrites if kind == rule]
            changed.append(f"`{inside_target(file)}` lines {', '.join(lines)}: added `bundle: .module` "
                           f"({rule}).")
        for rule, line in left:
            notes.append((MANUAL, f"`{inside_target(file)}:{line}`: a {rule} call with several arguments; give it "
                                  "the Feature's bundle (`in: .module`)."))
        write_file(target, inside_target(file), text.encode("utf-8"))
    if root_view is None:
        template_view.write_bytes(template_text)
        notes.append((MANUAL, f"No SwiftUI App was turned into the root view; `{name}RootView.swift` shows only the "
                              "name. Make it show the app's first screen."))
    pointers = [file for file in resources if (base / file).read_bytes().startswith(LFS_POINTER)]
    # Core Image kernels need the -fcikernel compiler flag, which a package cannot set.
    kernels = [file for file in resources if file.endswith(".ci.metal")]
    resources = [file for file in resources if file not in pointers and file not in kernels]
    if kernels:
        notes.append((MANUAL, f"Core Image kernels were not copied ({', '.join(kernels[:5])}): they need the "
                              "-fcikernel Metal flag, which a Swift package cannot set. Compile them into a "
                              ".metallib on a Mac and add that file as a resource, or write the filter another way."))
    for file in resources:
        write_file(target, inside_target(file), (base / file).read_bytes())
    if pointers:
        notes.append((MANUAL, f"{len(pointers)} file(s) are stored with Git LFS, so the repository holds only a "
                              f"pointer to them and they were not copied: {', '.join(pointers[:5])}"
                              f"{' ...' if len(pointers) > 5 else ''}. Download them (`git lfs pull` in a clone) "
                              f"and put them under `Sources/{name}Feature`."))
    entries = sorted({resource_entry(inside_target(file)) for file in resources})
    if entries:
        changed.append(f"Copied {len(resources)} resource file(s); Package.swift declares them: "
                       + ", ".join(entries[:10]) + (" ..." if len(entries) > 10 else "") + ".")
    pending, copied_packages = sorted(source.local_packages.items()), {}
    while pending:
        identity, path = pending.pop(0)
        if identity in copied_packages:
            continue
        copied_packages[identity] = path
        for file in members_of(names, [path]):
            write_file(module / "Packages" / identity, file[len(path) + 1:], (base / file).read_bytes())
        changed.append(f"Copied the local package {path} to `Packages/{identity}`.")
        manifest_text = (base / path / "Package.swift").read_text(encoding="utf-8", errors="replace") \
            if (base / path / "Package.swift").is_file() else ""
        for reference in re.findall(r'\.package\(\s*(?:name:\s*"[^"]*"\s*,\s*)?path:\s*"([^"]+)"', manifest_text):
            other = posixpath.normpath(posixpath.join(path, reference))
            if posixpath.dirname(other) != posixpath.dirname(path) or other.startswith(".."):
                notes.append((MANUAL, f"`Packages/{identity}` depends on {reference}, which is not next to it; fix "
                                      "the path in its Package.swift."))
            elif package_identity(other) not in copied_packages:
                pending.append((package_identity(other), other))
    if other_code:
        notes.append((MANUAL, f"Objective-C, C or C++ files were not copied ({', '.join(other_code[:5])}"
                              f"{' ...' if len(other_code) > 5 else ''}); a Swift package target holds one language. "
                              "Put them in a target of their own, or rewrite them in Swift."))
    (module / "Package.swift").write_bytes(package_manifest(name, source, entries, localized).encode("utf-8"))
    if source.dependencies:
        changed.append(f"Package.swift depends on the app's Swift packages: {', '.join(source.dependencies)}.")
    if source.swift5:
        changed.append("Package.swift compiles the code in the Swift 5 language mode, as the app did.")
    manifest = {"schema": 1, "id": feature_id, "draft": True, "products": [f"{name}Feature"],
                "sources": ["Integration/**"], "definitions": [f"{name}MiniApp.definition"]}
    app, copied, skipped = {}, [], []
    for key, value in sorted(source.plist.items()):
        if key in HOST_PLIST_KEYS or key.startswith(HOST_PLIST_PREFIXES) or key.endswith("_Generation") \
                or value in ("", None) or key in HOST_IDENTITY_KEYS:
            continue
        if key in MANUAL_PLIST_KEYS:
            if key != "UIUserInterfaceStyle" or root_view is None:
                skipped.append(key)
            continue
        value = plist_copy(value)
        if value is None:
            skipped.append(key)
        else:
            app.setdefault("infoPlist", {})[key] = value
            copied.append(key)
    entitlements = []
    for key, value in sorted(source.entitlements.items()):
        if key in FREE_SIGNING_ENTITLEMENTS:
            notes.append((MANUAL, f"The entitlement {key} ({FREE_SIGNING_ENTITLEMENTS[key]}) was not copied: it "
                                  "usually needs a paid Apple Developer Program membership. Add it under "
                                  "`app.entitlements` if your signing supports it."))
        elif key in SIGNING_ENTITLEMENTS or key.startswith("com.apple.security."):
            continue
        elif plist_copy(value) is not None:
            app.setdefault("entitlements", {})[key] = plist_copy(value)
            entitlements.append(key)
    localized_plist = localized_info_plist(base, info_strings)
    if localized_plist:
        app["localizedInfoPlist"] = localized_plist
        changed.append(f"Localized Info.plist text ({', '.join(sorted(localized_plist))}) is under "
                       "`app.localizedInfoPlist` in JibunKitFeature.json.")
    if app:
        manifest["app"] = app
    if copied:
        changed.append(f"Info.plist keys are under `app.infoPlist` in JibunKitFeature.json: {', '.join(copied)}.")
    if entitlements:
        changed.append(f"Entitlements are under `app.entitlements` in JibunKitFeature.json: {', '.join(entitlements)}.")
    if skipped:
        notes.append((MANUAL, f"Info.plist keys that were not copied: {', '.join(skipped)}. `inspect` explains each "
                              "one; move what the Feature needs by hand."))
    (module / MANIFEST).write_bytes((json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    (module / "Integration" / f"{name}MiniApp.swift").write_bytes(
        integration_source(name, feature_id, source.title).encode("utf-8"))
    load(module)
    after = inspect_directory(module)
    remaining = []
    for (section, message), places in sorted(after.items.items()):
        if section in (MANUAL, MECHANICAL, UNSUPPORTED):
            remaining.append(f"- {message}" + (f"\n  {', '.join(places[:SHOWN_LOCATIONS])}"
                                               + (f" (+{len(places) - SHOWN_LOCATIONS} more)"
                                                  if len(places) > SHOWN_LOCATIONS else "") if places else ""))
    remaining += [f"- {message}" for section, message in notes]
    warnings = draft_collisions(root, module, feature_id)
    size = sum(file.stat().st_size for file in module.rglob("*") if file.is_file())
    text = (f"\nCopied {len(swift)} Swift file(s) and {len(resources)} resource file(s) into `Sources/{name}Feature`; "
            f"Modules/{name} has {size // 1024} KB.\n\n## Changed\n\n" + "\n".join(f"- {item}" for item in changed) + "\n")
    text += "\n## Still to change\n\n" + ("\n".join(remaining) if remaining else "Nothing that the checks find.") + "\n"
    if warnings:
        text += "\n## Collisions with connected Features\n\n" + "\n".join(f"- {item}" for item in warnings) + "\n"
    return text


def draft_collisions(root, module, feature_id):
    """What would stop sync once the draft is connected, without stopping it now."""
    warnings = []
    try:
        features = modules(root)
    except FeatureError as error:
        return [str(error)]
    for other, data in features:
        if data["id"] == feature_id:
            warnings.append(f"The Feature ID {feature_id!r} is also used by {other}; choose another with --id.")
    data = json.loads((module / MANIFEST).read_text(encoding="utf-8"))
    warnings += source_conflicts(root, features + [(module.relative_to(root).as_posix(), data)])
    return warnings


def connect_feature(root, name, ignore_check=False):
    """Remove the draft flag once the Feature passes `check`, then sync. With
    ignore_check, connect it anyway, to compile it; do not commit that."""
    module = root / "Modules" / name
    path = module / MANIFEST
    require(path.is_file(), f"Modules/{name}/{MANIFEST} does not exist")
    require(is_draft(module), f"Modules/{name} is not a draft; it is connected already")
    original = path.read_bytes()
    data = json.loads(original.decode("utf-8"))
    del data["draft"]
    path.write_bytes((json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    try:
        load(module)
        findings = [] if ignore_check else check([module])
        require(not findings, "check still reports:\n" + "\n".join(
            f"  {file.relative_to(root).as_posix()}:{number} [{rule}] {message}"
            for file, number, rule, message, _ in findings)
            + f"\nFix them, or mark an intended use with `// jibunkit: allow <rule>`; Modules/{name} stays a draft.")
        return sync(root)
    except FeatureError:
        path.write_bytes(original)
        raise


def default_name(repository, path):
    name = Path(path).name if path else re.sub(r"\.git$", "", repository.rstrip("/").replace("\\", "/").split("/")[-1].split(":")[-1])
    require(NAME_PATTERN.fullmatch(name),
            f"{name!r} cannot be a Feature directory name; choose one with --name, such as --name Notes")
    return name


def repository_url(value):
    """A local directory as an absolute path (Git runs elsewhere), `OWNER/REPO` as GitHub, else unchanged."""
    if Path(value).is_dir():
        return str(Path(value).resolve())
    if GITHUB_SHORTHAND.fullmatch(value):
        return f"https://github.com/{value}"
    return value


def add_feature(root, repository, ref="HEAD", path="", name=None):
    """Copy a Feature into Modules/<name> and record it. Returns the module and commit."""
    repository = repository_url(repository)
    path = source_path(path)
    name = name or default_name(repository, path)
    require(NAME_PATTERN.fullmatch(name),
            "Use a Swift type name that starts with an uppercase letter and contains only letters and digits")
    features = load_imports(root)
    module = root / "Modules" / name
    require(not module.exists() and name not in features, f"Modules/{name} already exists; use update or another --name")
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        commit = fetch(work, repository, ref)
        files = read_tree(work, commit, path)
    where = f"{repository} {path or '(root)'} at {commit[:12]}"
    require(MANIFEST in files and "Package.swift" in files,
            f"{where} has no {MANIFEST} and Package.swift, so it is not a JibunKit Feature")
    for file, (data, executable) in files.items():
        write_file(module, file, data, executable)
    try:
        load(module)
    except FeatureError:
        shutil.rmtree(module)
        raise
    features[name] = {"repository": repository, "ref": ref, "commit": commit, "path": path}
    save_imports(root, features)
    return module, commit


def update_feature(root, name, ref=None, path=None):
    """Move an imported Feature to a new commit. Returns (old, new, changed files, conflicts, before, after)."""
    features = load_imports(root)
    require(name in features, f"{name} is not in {IMPORTS}; only Features added with `add` can be updated")
    entry = features[name]
    module = root / "Modules" / name
    require(module.is_dir(), f"Modules/{name} is missing")
    require_clean(module)
    ref = ref or entry["ref"]
    path = entry["path"] if path is None else source_path(path)
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        commit = fetch(work, entry["repository"], ref)
        theirs = read_tree(work, commit, path)
        if (commit, path) == (entry["commit"], entry["path"]):
            base = theirs
        else:
            try:
                fetch(work, entry["repository"], entry["commit"])
            except FeatureError:
                raise FeatureError(
                    f"The recorded commit {entry['commit'][:12]} is no longer in {entry['repository']}, so your "
                    f"changes cannot be carried over. Run `remove {name}` and `add` again, then reapply them "
                    "from Git history.") from None
            base = read_tree(work, entry["commit"], entry["path"])
    require(MANIFEST in theirs and "Package.swift" in theirs,
            f"{entry['repository']} {path or '(root)'} at {commit[:12]} is no longer a JibunKit Feature")
    before = describe(root, module)
    changed, conflicts = merge_tree(module, base, local_files(module), theirs,
                                    ("yours", entry["commit"][:12], commit[:12]))
    features[name] = {**entry, "ref": ref, "commit": commit, "path": path}
    save_imports(root, features)
    return entry["commit"], commit, changed, conflicts, before, describe(root, module)


def remove_feature(root, name):
    """Delete an imported Feature and its record, or a draft that migrate wrote."""
    features = load_imports(root)
    module = root / "Modules" / name
    draft = NAME_PATTERN.fullmatch(name) and is_draft(module)
    require(name in features or draft,
            f"{name} is not in {IMPORTS} and is not a draft; delete a Feature you created yourself by hand")
    if module.exists():
        shutil.rmtree(module)
    if name in features:
        del features[name]
        save_imports(root, features)


def print_drafts(root):
    for module in drafts(root):
        print(f"Draft, not connected: {module.relative_to(root).as_posix()} (connect it with `connect {module.name}`)")


def sync_after_import(root, name):
    """Connect the imported Feature; a collision with another Feature is reported, not undone."""
    # Import Feature (import-feature.yml) commits only after success and says so itself.
    in_workflow = bool(os.environ.get("GITHUB_ACTIONS"))
    try:
        changed = sync(root)
    except FeatureError as error:
        sys.stdout.flush()
        print(f"\nsync stopped:\n{error}", file=sys.stderr)
        if not in_workflow:
            print(f"Fix this in Modules/{name} (an update keeps your changes) and run sync, "
                  f"or undo the import with `remove {name}`.", file=sys.stderr)
        return False
    print(f"\n{HELPER.as_posix()} {'updated' if changed else 'is up to date'}.")
    if not in_workflow:
        print("Review the changes, commit them, then build.")
    return True


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
    importing = commands.add_parser("add", help="Copy a Feature from another Git repository")
    importing.add_argument("repository", help="Git URL, OWNER/REPO on GitHub, or a local path")
    importing.add_argument("--ref", default="HEAD", help="Branch, tag or commit to follow (default: the default branch)")
    importing.add_argument("--path", default="", help="Directory of the Feature in the repository (default: its root)")
    importing.add_argument("--name", help="Directory under Modules/ (default: the last part of --path or the URL)")
    updating = commands.add_parser("update", help="Move an imported Feature to a new commit")
    updating.add_argument("name")
    updating.add_argument("--ref", help="Follow another branch, tag or commit from now on")
    updating.add_argument("--path", help="The Feature moved to another directory of the repository")
    removing = commands.add_parser("remove", help="Delete an imported Feature or a draft")
    removing.add_argument("name")
    migrating = commands.add_parser("migrate", help="Move an app from another repository in as a draft Feature")
    migrating.add_argument("repository", help="Git URL, OWNER/REPO on GitHub, or a local path")
    migrating.add_argument("--ref", default="HEAD", help="Branch, tag or commit (default: the default branch)")
    migrating.add_argument("--path", default="", help="Directory of the app in the repository (default: its root)")
    migrating.add_argument("--name", help="Directory under Modules/ (default: the last part of --path or the URL)")
    migrating.add_argument("--target", help="The app to move when there are several: an Xcode target name")
    migrating.add_argument("--id", help="Feature ID (default: the name in lowercase)")
    connecting = commands.add_parser("connect", help="Connect a draft Feature once check reports nothing")
    connecting.add_argument("name")
    connecting.add_argument("--ignore-check", action="store_true",
                            help="Connect even when check reports findings, to compile the draft; do not commit that")
    inspecting = commands.add_parser("inspect", help="Report how far a repository is from a JibunKit Feature")
    inspecting.add_argument("repository", help="Git URL, OWNER/REPO on GitHub, or a local path")
    inspecting.add_argument("--ref", default="HEAD", help="Branch, tag or commit (default: the default branch)")
    inspecting.add_argument("--path", default="", help="Directory to inspect (default: the repository root)")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        if args.command == "new":
            module = new(root, args.name, run_sync=not args.no_sync)
            print(f"Created {module.relative_to(root).as_posix()}"
                  + ("" if args.no_sync else f" and updated {HELPER.as_posix()}"))
        elif args.command == "check":
            paths = [path.resolve() for path in args.paths] or sorted(
                path.parent for path in (root / "Modules").glob(f"*/{MANIFEST}") if not is_draft(path.parent))
            findings = check(paths)
            for file, number, rule, message, doc in findings:
                try:
                    shown = file.relative_to(root).as_posix()
                except ValueError:
                    shown = file.as_posix()
                print(f"{shown}:{number}: [{rule}] {message} See {doc}")
            print(f"{len(findings)} finding(s) in {len(paths)} location(s)")
            return 1 if findings else 0
        elif args.command == "add":
            module, commit = add_feature(root, args.repository, args.ref, args.path, args.name)
            files = [path for path in module.rglob("*") if path.is_file()]
            print(f"Copied {load_imports(root)[module.name]['repository']} {args.path or '(root)'} at {commit} ({args.ref}) into "
                  f"Modules/{module.name}: {len(files)} files, {sum(path.stat().st_size for path in files) // 1024} KB")
            print_report(describe(root, module))
            return 0 if sync_after_import(root, module.name) else 1
        elif args.command == "update":
            old_commit, new_commit, changed, conflicts, before, after = update_feature(root, args.name, args.ref, args.path)
            if old_commit == new_commit and not changed:
                print(f"{args.name} is already at {new_commit}.")
            else:
                print(f"{args.name}: {old_commit[:12]} -> {new_commit[:12]}, {len(changed)} file(s) changed")
                print_changes(before, after)
            sys.stdout.flush()
            for name in conflicts:
                print(f"conflict: Modules/{args.name}/{name} (resolve the markers, or compare with {name}.upstream)",
                      file=sys.stderr)
            synced = sync_after_import(root, args.name)
            return 0 if synced and not conflicts else 1
        elif args.command == "remove":
            remove_feature(root, args.name)
            changed = sync(root)
            print(f"Removed Modules/{args.name}; {HELPER.as_posix()} {'updated' if changed else 'is up to date'}")
        elif args.command == "migrate":
            module, commit, text = migrate_feature(root, args.repository, args.ref, args.path, args.name,
                                                   args.target, args.id)
            print(text, end="")
            print(f"\nWrote Modules/{module.name} as a draft; the report is in Modules/{module.name}/MIGRATION.md.")
        elif args.command == "connect":
            changed = connect_feature(root, args.name, args.ignore_check)
            print(f"Connected Modules/{args.name}; {HELPER.as_posix()} {'updated' if changed else 'is up to date'}.")
        elif args.command == "inspect":
            repository, commit, inspection = inspect_repository(args.repository, args.ref, args.path)
            print(f"Inspected {repository} {args.path or '(root)'} at {commit} ({args.ref}).")
            print_inspection(inspection)
        else:
            changed = sync(root, check=args.check)
            print(f"{HELPER.as_posix()} {'updated' if changed else 'is up to date'}")
            print_drafts(root)
    except FeatureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
