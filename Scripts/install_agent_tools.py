#!/usr/bin/env python3
"""Install the user CLI/skill and optionally register the local Codex MCP server."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

from soundploeg_cli import speech_python, support_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mcp', action='store_true', help='Install isolated MCP dependencies and register with Codex')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    launcher = repo / 'Scripts/soundploeg'
    command = Path.home() / '.local/bin/soundploeg'
    skill = Path(os.environ.get('CODEX_HOME', Path.home() / '.codex')) / 'skills/soundploeg'
    template = repo / 'Skills/soundploeg/SKILL.md'
    marker = skill / '.soundploeg-source'
    if not Path(speech_python()).is_file():
        raise SystemExit('Run Scripts/bootstrap_tts.sh before installing agent tools.')
    if (command.exists() or command.is_symlink()) and command.resolve() != launcher:
        raise SystemExit(f'Refusing to replace unrelated command: {command}')
    if skill.exists() and (not marker.exists() or marker.read_text().strip() != str(repo)):
        raise SystemExit(f'Refusing to replace an existing skill from another source: {skill}')
    if args.mcp:
        if not shutil.which('codex'):
            raise SystemExit('codex CLI is required for --mcp registration.')
        # Do not replace a pre-existing server with a different command.
        existing = subprocess.run(['codex', 'mcp', 'get', 'soundploeg', '--json'], capture_output=True, text=True)
        if existing.returncode == 0:
            import json
            transport = json.loads(existing.stdout).get('transport', {})
            if transport.get('command') != str(command) or transport.get('args') != ['mcp']:
                raise SystemExit('An unrelated soundploeg MCP server is already registered.')
        runtime = support_root() / 'mcp-venv'
        if not (runtime / 'bin/python').exists():
            subprocess.run([speech_python(), '-m', 'venv', str(runtime)], check=True)
        subprocess.run([str(runtime / 'bin/python'), '-m', 'pip', 'install', '-r', str(repo / 'Scripts/mcp-requirements.txt')], check=True)
    launcher.chmod(launcher.stat().st_mode | 0o111)
    command.parent.mkdir(parents=True, exist_ok=True)
    if not command.is_symlink():
        command.symlink_to(launcher)
    skill.mkdir(parents=True, exist_ok=True)
    (skill / 'SKILL.md').write_text(template.read_text().replace('@SOUNDPLOEG_COMMAND@', str(command)))
    marker.write_text(str(repo) + '\n')
    if args.mcp:
        subprocess.run(['codex', 'mcp', 'add', 'soundploeg', '--', str(command), 'mcp'], check=True)
    print(f'Command: {command}\nSkill: {skill}\nKeep this checkout at {repo}.')
    print('Start a new Codex task or restart Codex if the new skill/tools do not appear.')


if __name__ == '__main__':
    main()
