"""Local stdio MCP tools. Long recordings run as bounded, pollable jobs."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import threading
import uuid

from mcp.server.fastmcp import FastMCP
from soundploeg_cli import prepare_episode, render, voices

server = FastMCP('SoundPloeg', instructions='Offline speech using installed Kokoro English and Supertonic Dutch voices. Rendering returns a job ID; poll get_job until completed, then link to the output audio. The agent writes the podcast script before calling render_podcast.')
executor = ThreadPoolExecutor(max_workers=1)
jobs = {}
lock = threading.Lock()


def start_job(episode, output):
    if not Path(output).is_absolute():
        raise ValueError('output must be an absolute .wav or .mp3 path')
    if Path(output).exists():
        raise ValueError('Output already exists. Choose a new filename.')
    if Path(output).suffix.lower() not in ('.wav', '.mp3'):
        raise ValueError('Output must end in .wav or .mp3')
    parts = prepare_episode(episode)
    with lock:
        if sum(j['status'] in ('queued', 'running') for j in jobs.values()) >= 4:
            raise ValueError('Four jobs are already pending. Wait for one to finish.')
        # Retain a bounded amount of job metadata for this server session.
        for key in list(jobs):
            if len(jobs) < 100:
                break
            if jobs[key]['status'] in ('completed', 'failed'):
                del jobs[key]
        job_id = str(uuid.uuid4())
        jobs[job_id] = dict(job_id=job_id, status='queued', completed_chunks=0, total_chunks=len(parts), output=output)

    def update(**values):
        with lock:
            jobs[job_id].update(values)

    def run():
        update(status='running')
        try:
            result = render(episode, output, progress=lambda done, total: update(completed_chunks=done, total_chunks=total))
            update(status='completed', result=result)
        except Exception as exc:
            update(status='failed', error=str(exc))

    executor.submit(run)
    return dict(job_id=job_id, output=output, next_step='Call get_job with this job_id until status is completed or failed.')


@server.tool()
def list_voices() -> list[dict]:
    """List installed local speech voices, IDs, languages, and engines."""
    return voices()


@server.tool()
def synthesize_speech(text: str, output: str, voice: str = 'Heart', rate: float = 1.0) -> dict:
    """Start local narration, automatically chunking long text. output is an absolute WAV/MP3 filename. Returns a job ID; call get_job to obtain completion and audio path."""
    return start_job({'segments': [dict(text=text, voice=voice, rate=rate, pause_after=0)]}, output)


@server.tool()
def render_podcast(episode: dict, output: str) -> dict:
    """Start a podcast from a prepared script. episode has speakers mapping names to installed voice IDs/names, and segments containing speaker, text, optional rate (0.5-2), and pause_after (0-10 seconds). Example: {"speakers":{"host":"Heart","guest":"Michael"},"segments":[{"speaker":"host","text":"Welcome."},{"speaker":"guest","text":"Thank you."}]}. output is an absolute WAV/MP3 path. Returns a job ID; poll get_job."""
    return start_job(episode, output)


@server.tool()
def get_job(job_id: str) -> dict:
    """Read rendering status, chunk progress, and final audio path or error. Poll every few seconds until completed or failed. Jobs belong to this MCP server session."""
    with lock:
        if job_id not in jobs:
            raise ValueError('Unknown job ID. Jobs are retained only for this server session.')
        return dict(jobs[job_id])


if __name__ == '__main__':
    try:
        server.run(transport='stdio')
    finally:
        executor.shutdown(wait=True, cancel_futures=True)
