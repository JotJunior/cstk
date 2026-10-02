#!/usr/bin/env python3
"""Build a self-contained local pilot package without modifying installations."""

import argparse
import json
from pathlib import Path
import shutil


EXCLUDED = shutil.ignore_patterns("node_modules", "dist", "__pycache__", "*.pyc", ".DS_Store")


def build(source, output):
    source = Path(source).resolve(strict=True)
    output = Path(output).resolve()
    if output.exists():
        raise ValueError("output already exists; choose a new directory")
    for tree in ("plugins/cstk", "cli", "adapters/codex", "docs/specs/codex-feature-00c"):
        if output.is_relative_to(source / tree):
            raise ValueError("output must not be inside a copied source tree")
    # Validate inputs before creating output. copytree refuses overwrite.
    adapter = source / "adapters/codex"
    if not (adapter / ".codex-plugin/plugin.json").is_file():
        raise ValueError("missing adapter manifest")
    shutil.copytree(adapter, output, ignore=EXCLUDED)
    shutil.copytree(source / "plugins/cstk", output / "plugins/cstk", ignore=EXCLUDED)
    shutil.copytree(source / "cli", output / "cli", ignore=EXCLUDED)
    shutil.copytree(source / "docs/specs/codex-feature-00c", output / "docs/specs/codex-feature-00c",
                    ignore=EXCLUDED)
    readme = output / "README.md"
    readme.write_text(readme.read_text().replace("../../docs/specs/codex-feature-00c/",
                                               "docs/specs/codex-feature-00c/"))
    marketplace_dir = output / ".agents/plugins"
    marketplace_dir.mkdir(parents=True)
    (marketplace_dir / "marketplace.json").write_text(json.dumps({
        "name": "cstk-codex-pilot-local",
        "interface": {"displayName": "cstk Codex pilot (experimental)"},
        "plugins": [{"name": "cstk-codex-pilot",
                     "source": {"source": "local", "path": "./"},
                     "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
                     "category": "Productivity"}]
    }, indent=2) + "\n")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    try:
        print(build(Path(__file__).resolve().parents[1], args.out))
    except (OSError, ValueError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    main()
