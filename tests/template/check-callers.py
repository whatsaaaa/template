"""Checks the workflows of a rendered project against the reusable workflows of this checkout.

actionlint cannot read a workflow called at whatsaaaa/template/...@v1, so for each job that calls
one, this checks what a mismatch would only show on GitHub: that every input it passes exists and
every required one is passed, that it grants every permission the called workflow's jobs ask for,
since the caller's permissions cap them, and that the CI workflow changesets-release.yml starts on
the Version Packages pull request exists and has a workflow_dispatch trigger.

Usage: python3 tests/template/check-callers.py <project>
"""

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
PREFIX = 'whatsaaaa/template/.github/workflows/'
LEVELS = {'none': 0, 'read': 1, 'write': 2}


def load(path):
    # PyYAML reads the key `on` as True
    data = yaml.safe_load(path.read_text())
    if True in data:
        data['on'] = data.pop(True)
    return data


def permissions(value):
    """A permissions value as {scope: level}; None when it is not set."""
    if value is None:
        return None
    if isinstance(value, str):
        return {'*': LEVELS[{'read-all': 'read', 'write-all': 'write'}[value]]}
    return {scope: LEVELS[level] for scope, level in value.items()}


def granted(perms, scope):
    return perms.get(scope, perms.get('*', 0))


def main(project):
    workflows = project / '.github' / 'workflows'
    errors = []
    checked = 0
    for path in sorted(workflows.glob('*.yml')):
        caller = load(path)
        for job_name, job in caller.get('jobs', {}).items():
            uses = job.get('uses', '')
            if not uses.startswith(PREFIX):
                continue
            checked += 1
            where = f'{path.name}: job {job_name}'
            called_path = ROOT / '.github' / 'workflows' / uses[len(PREFIX):].split('@')[0]
            if not called_path.is_file():
                errors.append(f'{where} calls {uses}, which this repository does not have')
                continue
            called = load(called_path)
            inputs = (called['on'].get('workflow_call') or {}).get('inputs') or {}
            given = job.get('with') or {}
            for name in given:
                if name not in inputs:
                    errors.append(f'{where} passes {name}, which {called_path.name} does not take')
            for name, spec in inputs.items():
                if spec.get('required') and name not in given:
                    errors.append(f'{where} does not pass {name}, which {called_path.name} requires')

            caller_perms = permissions(job.get('permissions'))
            if caller_perms is None:
                caller_perms = permissions(caller.get('permissions'))
            if caller_perms is None:
                continue  # the repository's default token permissions apply
            needed = {}
            for called_job in called['jobs'].values():
                for scope, level in (permissions(called_job.get('permissions')) or {}).items():
                    needed[scope] = max(needed.get(scope, 0), level)
            for scope, level in sorted(needed.items()):
                if granted(caller_perms, scope) < level:
                    want = [k for k, v in LEVELS.items() if v == level][0]
                    errors.append(f'{where} does not grant {scope}: {want}, which {called_path.name} needs')

            if 'ci-workflow' in inputs:
                ci_name = given.get('ci-workflow', inputs['ci-workflow'].get('default'))
                ci_path = workflows / ci_name
                if not ci_path.is_file():
                    errors.append(f'{where} starts {ci_name} on the Version Packages pull request, which does not exist')
                elif 'workflow_dispatch' not in (load(ci_path)['on'] or {}):
                    errors.append(f'{where} starts {ci_name}, which has no workflow_dispatch trigger')

    for error in errors:
        print(f'::error::{error}')
    if errors:
        return 1
    print(f'{checked} call(s) of the reusable workflows match them')
    return 0


if __name__ == '__main__':
    sys.exit(main(Path(sys.argv[1])))
