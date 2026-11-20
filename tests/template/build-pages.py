"""Builds the site of a rendered project as its Pages workflow would, and checks what it deploys.

The shared pages.yml runs the build script its caller names, then uploads the artifact path it
names. This runs that script in the project and checks that the path then holds a site, an
index.html the build wrote: the two answers name a build and where it lands.

Usage: python3 tests/template/build-pages.py <project>
"""

import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
CALLED = 'whatsaaaa/template/.github/workflows/pages.yml@'


def main(project):
    called = yaml.safe_load((ROOT / '.github' / 'workflows' / 'pages.yml').read_text())
    # PyYAML reads the key `on` as True
    inputs = called[True]['workflow_call']['inputs']
    caller = yaml.safe_load((project / '.github' / 'workflows' / 'pages.yml').read_text())
    jobs = [job for job in caller['jobs'].values() if job.get('uses', '').startswith(CALLED)]
    if len(jobs) != 1:
        print(f'::error::pages.yml has {len(jobs)} jobs that call the shared Pages workflow, not one')
        return 1
    given = jobs[0].get('with') or {}
    script = given.get('build-script', inputs['build-script']['default'])
    artifact = project / given['artifact-path']

    # Only what this build writes counts, not what an earlier script left there
    shutil.rmtree(artifact, ignore_errors=True)
    subprocess.run(['pnpm', 'run', script], cwd=project, check=True)
    if not (artifact / 'index.html').is_file():
        print(f'::error::pnpm run {script} wrote no index.html into {given["artifact-path"]}, which pages.yml deploys')
        return 1
    print(f'pnpm run {script} built the site into {given["artifact-path"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main(Path(sys.argv[1])))
