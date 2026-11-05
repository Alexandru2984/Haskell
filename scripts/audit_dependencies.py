#!/usr/bin/env python3
"""Compare a Cabal plan with a local checkout of Haskell's published advisories."""
import json
from pathlib import Path
import re
import sys
import tomllib

if len(sys.argv) != 3:
    raise SystemExit('Usage: audit_dependencies.py PLAN_JSON SECURITY_ADVISORIES_CHECKOUT')
plan=json.loads(Path(sys.argv[1]).read_text())
packages={p['pkg-name']:p['pkg-version'] for p in plan['install-plan']}
root=Path(sys.argv[2])/'advisories'/'published'
assert root.is_dir(), 'Published advisory directory is required'
exceptions=json.loads((Path(__file__).resolve().parents[1]/'docs/security-exceptions.json').read_text())
version=lambda value: tuple(int(part) for part in value.split('.'))
failures=[]
reviewed=[]
count=0
for path in sorted(root.rglob('*.md')):
    match=re.search(r'```toml\s*\n(.*?)```',path.read_text(),re.S)
    if not match: raise SystemExit(f'Cannot parse advisory metadata: {path.name}')
    data=tomllib.loads(match[1]); count+=1
    if data['advisory'].get('withdrawn'): continue
    for affected in data.get('affected',[]):
        package=affected.get('package')
        if package not in packages: continue
        if affected.get('os') and plan['os'] not in affected['os']: continue
        if affected.get('arch') and plan['arch'] not in affected['arch']: continue
        for bounds in affected.get('versions',[]):
            unknown=set(bounds)-{'introduced','fixed'}
            if unknown: raise SystemExit(f'Unsupported version bounds in {path.name}: {unknown}')
            current=version(packages[package])
            if current < version(bounds.get('introduced','0')): continue
            if bounds.get('fixed') and current >= version(bounds['fixed']): continue
            entry=f'{path.stem}: {package} {packages[package]}'
            exception=exceptions.get(path.stem)
            if exception and exception['package']==package:
                reviewed.append(entry+' — '+exception['reason'])
            else: failures.append(entry)
print(f'Checked {len(packages)} packages against {count} published advisories ({plan["os"]}/{plan["arch"]}).')
for item in reviewed: print('Reviewed exception:',item)
for item in failures: print('AFFECTED:',item)
if failures: raise SystemExit(1)
print('No unreviewed applicable advisory matches. This does not prove the absence of vulnerabilities.')
