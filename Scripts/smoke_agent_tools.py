#!/usr/bin/env python3
"""Exercise the real CLI and MCP speech path using temporary output files."""
import asyncio
import json
from pathlib import Path
import subprocess
import tempfile
import time
import wave

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

COMMAND = Path(__file__).with_name('soundploeg').resolve()


def run_cli(*arguments):
    result = subprocess.run([str(COMMAND), *arguments], capture_output=True, text=True, timeout=180, check=True)
    return json.loads(result.stdout)


async def main():
    with tempfile.TemporaryDirectory(prefix='soundploeg-agent-smoke-') as directory:
        root = Path(directory)
        text = root / 'summary.txt'
        text.write_text('This is a local speech test. The recording stays on this computer. ' * 22)
        result = run_cli('speak', str(text), '--output', str(root / 'summary.wav'))
        assert result['chunks'] > 1 and result['duration'] > 1, result
        with wave.open(result['output']) as audio:
            assert audio.getframerate() == 24000 and audio.getnframes() > 24000
        print('CLI long-text narration passed', flush=True)
        episode = root / 'episode.json'
        episode.write_text(json.dumps({'speakers': {'host': 'Heart', 'guest': 'Michael'}, 'segments': [
            {'speaker': 'host', 'text': 'Welcome to our local podcast.'},
            {'speaker': 'guest', 'text': 'These voices are generated on this Mac.'}]}))
        result = run_cli('podcast', str(episode), '--output', str(root / 'episode.mp3'))
        assert len(result['voices']) == 2 and Path(result['output']).stat().st_size > 1000
        print('CLI two-voice MP3 passed', flush=True)
        episode.write_text(json.dumps({'segments': [
            {'voice': 'Heart', 'text': 'Now a short update in Dutch.'},
            {'voice': 'Dutch Female', 'text': 'Goedemiddag. Dit is een korte samenvatting.'}]}))
        result = run_cli('podcast', str(episode), '--output', str(root / 'mixed.wav'))
        with wave.open(result['output']) as audio:
            assert audio.getframerate() == 24000 and audio.getnframes() > 24000
        print('CLI mixed English/Dutch resampling passed', flush=True)
        async with stdio_client(StdioServerParameters(command=str(COMMAND), args=['mcp'])) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                listed = await session.list_tools()
                assert {t.name for t in listed.tools} == {'list_voices', 'synthesize_speech', 'render_podcast', 'get_job'}

                async def call(name, arguments):
                    response = await session.call_tool(name, arguments)
                    assert not response.isError, response
                    return json.loads(next(c.text for c in response.content if c.type == 'text'))

                job = await call('synthesize_speech', {'text': 'Your Codex agent can now create local audio.', 'output': str(root / 'mcp.wav')})
                deadline = time.monotonic() + 120
                while True:
                    status = await call('get_job', {'job_id': job['job_id']})
                    assert status['status'] != 'failed', status
                    if status['status'] == 'completed':
                        assert Path(status['result']['output']).stat().st_size > 1000
                        break
                    assert time.monotonic() < deadline, status
                    await asyncio.sleep(0.5)
                duplicate = await session.call_tool('synthesize_speech', {'text': 'Do not overwrite.', 'output': str(root / 'mcp.wav')})
                assert duplicate.isError
                print('MCP initialization, discovery, real speech job, and overwrite protection passed', flush=True)


if __name__ == '__main__':
    asyncio.run(main())
