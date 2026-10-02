#!/usr/bin/env python3
"""Install CSTK through the native Codex plugin CLI, preserving other clients."""

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile


PLUGIN_ID = "cstk-codex-pilot@cstk-codex-pilot-local"
SKILLS = ("feature-00c", "feature-00c-resume", "feature-00c-abort",
          "agente-00c", "agente-00c-resume", "agente-00c-abort")


class InstallError(RuntimeError):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def tree_hash(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        if path.is_symlink():
            raise InstallError("symlink in managed plugin tree: " + str(path), 4)
        if path.is_file():
            digest.update(str(path.relative_to(root)).encode())
            digest.update(b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def validate_package(root):
    manifest = json.loads((root / "plugin.json").read_text())
    if manifest.get("name") != "cstk-codex-pilot":
        raise InstallError("unexpected Codex plugin identity")
    for name in SKILLS:
        if not (root / "skills" / name / "SKILL.md").is_file():
            raise InstallError("missing native workflow: " + name)
    for asset in ("mcp.json", "hooks/hooks.json", "cli/VERSION",
                  "plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh",
                  "skills/feature-00c/scripts/mcp_bridge.py"):
        if not (root / asset).is_file():
            raise InstallError("incomplete self-contained Codex package: " + asset)
    return manifest


def invoke(codex, home, *args):
    result = subprocess.run([codex, *args], env=dict(os.environ, CODEX_HOME=str(home)),
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise InstallError("Codex " + " ".join(args[:3]) + " failed: " +
                           (result.stderr.strip() or result.stdout.strip()))
    return result.stdout.strip()


def configure_hooks(home, plugin_root, receipt):
    path = home / "hooks.json"
    if path.is_symlink():
        raise InstallError("Codex hooks.json is a symlink; reconcile before installing", 4)
    document = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(document, dict) or not isinstance(document.get("hooks", {}), dict):
        raise InstallError("existing Codex hook configuration is invalid", 4)
    groups = document.setdefault("hooks", {})
    previous = (receipt or {}).get("hook_entries", {})
    entries = {}
    for event, script in (("PreToolUse", "pretooluse.py"), ("PostToolUse", "posttooluse.py")):
        old = previous.get(event)
        if old:
            matched = [group for group in groups.get(event, []) if any(
                handler.get("command") == old["hooks"][0]["command"] for handler in group.get("hooks", []))]
            if matched != [old]:
                raise InstallError("CSTK hook changed or removed locally; reconcile before reinstalling: " + event, 4)
            groups[event] = [group for group in groups[event] if group != old]
        entry = {"matcher": "*", "hooks": [{"type": "command", "command": shlex.join(
                    [shutil.which("python3"), str(plugin_root / "hooks" / script)]), "timeout": 5}]}
        groups.setdefault(event, []).append(entry)
        entries[event] = entry
    with tempfile.NamedTemporaryFile(mode="w", dir=home, delete=False) as output:
        json.dump(document, output, indent=2)
        temporary = Path(output.name)
    os.replace(temporary, path)
    return entries


@contextmanager
def installation_lock(directory):
    lock = directory / ".install-lock"
    try:
        lock.mkdir()
    except FileExistsError as exc:
        raise InstallError("another CSTK Codex installation owns " + str(lock), 3) from exc
    try:
        yield
    finally:
        lock.rmdir()


def install(source_tree=None, package=None, codex_home=None, knowledge_db=None, dry_run=False):
    home = Path(codex_home or os.environ.get("CODEX_HOME") or Path.home() / ".codex").expanduser().absolute()
    database = Path(knowledge_db or os.environ.get("CSTK_KNOWLEDGE_DB") or
                    Path.home() / ".claude/cstk/knowledge.db").expanduser().absolute()
    managed = home / "cstk"
    if database.is_relative_to(managed) or database.is_dir():
        raise InstallError("knowledge_db must be a file outside the managed installation")
    deps = {name: shutil.which(name) for name in ("codex", "python3", "jq", "sqlite3")}
    report = {"cli": "codex", "codex_home": str(home), "knowledge_db": str(database),
              "plugin_id": PLUGIN_ID, "skills": list(SKILLS), "dependencies": deps,
              "dry_run": dry_run, "hook_trust": "operator_review_required"}
    if source_tree:
        source_tree = Path(source_tree).resolve(strict=True)
        adapter = source_tree / "adapters/codex"
        validate_package_source = json.loads((adapter / "plugin.json").read_text())
        report["plugin_version"] = validate_package_source["version"]
        report["source"] = str(source_tree)
    else:
        package = Path(package).resolve(strict=True)
        report["plugin_version"] = validate_package(package)["version"]
        report["source"] = str(package)
    if dry_run:
        return report
    missing = [name for name, path in deps.items() if path is None]
    if missing:
        raise InstallError("missing Codex installation dependencies: " + ", ".join(missing))
    # Probe native capabilities before creating managed assets or changing config.
    result = subprocess.run([deps["codex"], "plugin", "add", "--help"],
                            capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise InstallError("installed Codex does not support plugin add; upgrade Codex")
    home.mkdir(parents=True, exist_ok=True)
    if managed.is_symlink():
        raise InstallError("managed installation directory is a symlink", 4)
    managed.mkdir(exist_ok=True)
    receipt_path = managed / "install.json"
    with installation_lock(managed):
        hook_path = home / "hooks.json"
        if hook_path.is_symlink():
            raise InstallError("Codex hooks.json is a symlink; reconcile before installing", 4)
        if hook_path.exists():
            hooks = json.loads(hook_path.read_text())
            if not isinstance(hooks, dict) or not isinstance(hooks.get("hooks", {}), dict) or any(
                    not isinstance(groups, list) or any(not isinstance(group, dict) or
                    not isinstance(group.get("hooks"), list) or any(not isinstance(handler, dict)
                    for handler in group["hooks"]) for group in groups)
                    for groups in hooks.get("hooks", {}).values()):
                raise InstallError("existing Codex hook configuration is invalid", 4)
        if receipt_path.is_symlink():
            raise InstallError("installation receipt is a symlink", 4)
        receipt = None
        if receipt_path.exists():
            receipt = json.loads(receipt_path.read_text())
            for prefix in ("source", "cache"):
                old_path = Path(receipt[prefix + "_path"])
                if not old_path.exists() or tree_hash(old_path) != receipt[prefix + "_sha256"]:
                    raise InstallError("local edits or missing files in managed Codex " + prefix +
                                       "; preserve/reconcile them before reinstalling: " + str(old_path), 4)
            if receipt.get("marketplace_path") and hashlib.sha256(Path(receipt["marketplace_path"]).read_bytes()).hexdigest() != receipt["marketplace_sha256"]:
                raise InstallError("managed marketplace changed locally; reconcile before reinstalling", 4)
        # Validate managed hook edits before updating the native plugin cache.
        if receipt and receipt.get("hook_entries"):
            path = home / "hooks.json"
            if path.is_symlink() or not path.exists():
                raise InstallError("managed Codex hooks changed or disappeared", 4)
            configured = json.loads(path.read_text()).get("hooks", {})
            for event, entry in receipt["hook_entries"].items():
                matched = [group for group in configured.get(event, []) if any(
                    handler.get("command") == entry["hooks"][0]["command"] for handler in group.get("hooks", []))]
                if matched != [entry]:
                    raise InstallError("CSTK hook changed locally; reconcile before reinstalling: " + event, 4)
        with tempfile.TemporaryDirectory(prefix="cstk-codex-build-") as temp:
            staged = Path(temp) / "package"
            if source_tree:
                spec = importlib.util.spec_from_file_location("cstk_codex_builder", source_tree / "scripts/build-codex-plugin.py")
                builder = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(builder)
                builder.build(source_tree, staged)
            else:
                shutil.copytree(package, staged, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            validate_package(staged)
            # User-layer hooks are discoverable in the native harness even
            # where bundled plugin hooks aren't. Use one source to avoid ticks
            # being counted twice; trust remains an operator action.
            for manifest_path in (staged / "plugin.json", staged / ".codex-plugin/plugin.json"):
                manifest = json.loads(manifest_path.read_text())
                settings = manifest.setdefault("extensions", {}).setdefault("com.openai", {}) if manifest_path.parent == staged else manifest
                settings["hooks"] = []
                manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            mcp = json.loads((staged / "mcp.json").read_text())
            # Explicit MCP env survives the host's filtered parent environment.
            mcp["mcpServers"]["cstk_pipeline"].setdefault("env", {})["CSTK_KNOWLEDGE_DB"] = str(database)
            (staged / "mcp.json").write_text(json.dumps(mcp, indent=2) + "\n")
            sha = tree_hash(staged)
            packages = managed / "packages"
            if packages.is_symlink():
                raise InstallError("managed packages directory is a symlink", 4)
            packages.mkdir(exist_ok=True)
            destination = packages / (report["plugin_version"] + "-" + sha[:16])
            if destination.exists():
                if tree_hash(destination) != sha:
                    raise InstallError("managed package changed locally: " + str(destination), 4)
            else:
                shutil.copytree(staged, destination)
        # Keep the registered marketplace root stable across package versions
        # and database changes. Native CLI refuses changing a named source.
        inventory = json.loads(invoke(deps["codex"], home, "plugin", "marketplace", "list", "--json"))
        existing = next((item for item in inventory["marketplaces"]
                         if item["name"] == "cstk-codex-pilot-local"), None)
        if existing and Path(existing["root"]).resolve() != managed.resolve():
            if not receipt or Path(existing["root"]).resolve() != Path(receipt["source_path"]).resolve():
                raise InstallError("CSTK marketplace already belongs to another source; reconcile it before installing: " + existing["root"], 4)
            invoke(deps["codex"], home, "plugin", "marketplace", "remove", "cstk-codex-pilot-local")
        marketplace_dir = managed / ".agents/plugins"
        for path in (managed / ".agents", marketplace_dir):
            if path.is_symlink():
                raise InstallError("managed marketplace directory is a symlink", 4)
        marketplace_dir.mkdir(parents=True, exist_ok=True)
        marketplace = marketplace_dir / "marketplace.json"
        if marketplace.is_symlink():
            raise InstallError("managed marketplace file is a symlink", 4)
        catalog = json.loads((destination / ".agents/plugins/marketplace.json").read_text())
        catalog["plugins"][0]["source"]["path"] = "./packages/" + destination.name
        original = marketplace.read_bytes() if marketplace.exists() else None
        marketplace.write_text(json.dumps(catalog, indent=2) + "\n")
        try:
            invoke(deps["codex"], home, "plugin", "marketplace", "add", str(managed))
            invoke(deps["codex"], home, "plugin", "add", PLUGIN_ID)
        except InstallError:
            if original is not None:
                marketplace.write_bytes(original)
            raise
        cache = home / "plugins/cache/cstk-codex-pilot-local/cstk-codex-pilot" / report["plugin_version"]
        if not cache.is_dir():
            raise InstallError("Codex reported installation but the expected native cache is missing")
        if tree_hash(cache) != sha:
            raise InstallError("native cache does not match the prepared package; retry the native plugin installation")
        hook_entries = configure_hooks(home, destination, receipt)
        receipt = {"source_path": str(destination), "source_sha256": sha,
                   "cache_path": str(cache), "cache_sha256": tree_hash(cache),
                   "plugin_id": PLUGIN_ID, "knowledge_db": str(database),
                   "marketplace_path": str(marketplace),
                   "marketplace_sha256": hashlib.sha256(marketplace.read_bytes()).hexdigest(),
                   "hook_entries": hook_entries}
        with tempfile.NamedTemporaryFile(mode="w", dir=managed, delete=False) as output:
            json.dump(receipt, output, indent=2)
            temporary = Path(output.name)
        os.replace(temporary, receipt_path)
        return report | {"installed": True, "plugin_path": str(cache), "managed_source": str(destination),
                         "next_step": "Inicie nova sessao Codex e revise os hooks em /hooks."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--source-tree")
    source.add_argument("--package")
    parser.add_argument("--codex-home")
    parser.add_argument("--knowledge-db")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(install(**vars(args)), ensure_ascii=False, indent=2))
    except (InstallError, OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(exc.code if isinstance(exc, InstallError) else 1, str(exc) + "\n")


if __name__ == "__main__":
    main()
