#!/usr/bin/env python3
"""Install pinned voice packs. Downloads are verified before publication."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import urllib.request


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(block)
    return sha.hexdigest()


def install(model, root):
    destination = root / model['id']
    marker = destination / 'installed.json'
    if marker.exists() and json.loads(marker.read_text()) == model:
        if all((destination / f['path']).is_file() and (destination / f['path']).stat().st_size == f['bytes'] and digest(destination / f['path']) == f['sha256'] for f in model['files']):
            print(f"Verified {model['name']}", flush=True)
            return
    with tempfile.TemporaryDirectory(prefix='.download-', dir=root) as staging:
        staging = Path(staging)
        for asset in model['files']:
            target = staging / asset['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            print(f"Downloading {model['name']}: {asset['path']}", flush=True)
            with urllib.request.urlopen(asset['url'], timeout=120) as response, target.open('wb') as output:
                shutil.copyfileobj(response, output)
            if target.stat().st_size != asset['bytes'] or digest(target) != asset['sha256']:
                raise RuntimeError(f"Integrity check failed: {asset['path']}")
        (staging / 'installed.json').write_text(json.dumps(model))
        backup = root / ('.backup-' + model['id'])
        if backup.exists():
            raise RuntimeError(f'Recover or remove previous backup first: {backup}')
        if destination.exists():
            destination.rename(backup)
        try:
            staging.rename(destination)
        except Exception:
            if backup.exists():
                backup.rename(destination)
            raise
        if backup.exists():
            shutil.rmtree(backup)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--catalog', type=Path, default=Path(__file__).resolve().parents[1] / 'Config/model_catalog.json')
    parser.add_argument('--remove-legacy', action='store_true', help='Remove catalogued Piper files only, after both new packs are installed')
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    for model in json.loads(args.catalog.read_text()):
        install(model, args.root)
    if args.remove_legacy:
        legacy = Path(__file__).resolve().parents[1] / 'Config/legacy_piper_files.json'
        for name in json.loads(legacy.read_text()):
            (args.root / name).unlink(missing_ok=True)


if __name__ == '__main__':
    main()
