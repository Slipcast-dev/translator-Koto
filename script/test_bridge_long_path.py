#!/usr/bin/env python3
"""Регрессия длинного Unicode home: реальный server + native host без Apple/cloud/model."""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
from pathlib import Path
import tempfile

from test_bridge_integration import frame, native, read_frame, start_server, stop, write_frame


async def main() -> None:
    """Оба production endpoint должны выбрать тот же короткий socket и выполнить HELLO."""
    server = host = None
    short: Path | None = None
    with tempfile.TemporaryDirectory(prefix='koto-audit-', dir='/tmp') as base:
        directory = Path(base) / ('длинное-имя-' * 10)
        directory.mkdir(mode=0o700)
        digest = hashlib.sha256(str(directory).encode()).hexdigest()[:24]
        short = Path(f'/tmp/koto-bridge-{os.getuid()}-{digest}')
        try:
            server = await start_server(directory, 'runtime-failed')
            host = await native(directory)
            assert host.stdin is not None and host.stdout is not None
            request = frame('translate', {'text': 'Synthetic fixture', 'source': 'en', 'target': 'ru',
                                          'pageOrigin': 'https://example.com'})
            await write_frame(host.stdin, request)
            response = await asyncio.wait_for(read_frame(host.stdout), 15)
            assert response['id'] == request['id']
            assert response['payload']['code'] == 'translation_failed'
            assert (short / 'bridge.sock').is_socket()
            print(json.dumps({'status': 'passed', 'tests': ['long Unicode path authenticates native host']}))
        finally:
            if host is not None:
                await stop(host)
            if server is not None:
                await stop(server)
            # Только созданные этим тестом socket и пустой fallback directory.
            if short.exists():
                (short / 'bridge.sock').unlink(missing_ok=True)
                short.rmdir()


if __name__ == '__main__':
    asyncio.run(main())
