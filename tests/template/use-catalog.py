"""Gives the package.json files of an existing repository the versions of the template's catalog.

A case's folder pins versions of its own, which Renovate leaves alone in tests/: this keeps them
on the catalog's, which Renovate keeps current, as the rendered managed files are, such as the
Playwright version ci.yml names.

Usage: python tests/template/use-catalog.py <the catalog's package.json> <project>
"""

import json
import sys
from pathlib import Path

catalog = json.loads(Path(sys.argv[1]).read_text())
versions = catalog["devDependencies"]

for path in Path(sys.argv[2]).rglob("package.json"):
    if "node_modules" in path.parts:
        continue
    manifest = json.loads(path.read_text())
    for field in ("dependencies", "devDependencies", "peerDependencies"):
        for name in manifest.get(field, {}):
            if name in versions:
                manifest[field][name] = versions[name]
    if "packageManager" in manifest:
        manifest["packageManager"] = catalog["packageManager"]
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
