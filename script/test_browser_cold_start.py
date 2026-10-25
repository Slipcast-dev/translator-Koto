#!/usr/bin/env python3
"""Проверить первый запрос к app через настоящий host без ручного перевода."""
from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time
from typing import Any
import uuid

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = json.loads(
    (ROOT / "BrowserExtension/identity.json").read_text()
)["origin"]


def running_app(executable: Path) -> list[int]:
    """Сопоставлять полный путь, чтобы не завершить другую копию Koto."""
    rows = subprocess.check_output(
        ["ps", "-axo", "pid=,comm="], text=True
    ).splitlines()
    result: list[int] = []
    for row in rows:
        pid, _, command = row.strip().partition(" ")
        if command.strip() == str(executable):
            result.append(int(pid))
    return result


def encoded(kind: str, identity: str, payload: dict[str, str]) -> bytes:
    """Chrome Native Messaging: little-endian длина и UTF-8 JSON."""
    body = json.dumps({
        "v": 1, "id": identity, "type": kind, "payload": payload
    }, ensure_ascii=False).encode("utf-8")
    return struct.pack("<I", len(body)) + body


async def read_frame(reader: asyncio.StreamReader) -> dict[str, Any]:
    """Ограничивать размер до выделения памяти; токен host не выводится."""
    header = await reader.readexactly(4)
    size = struct.unpack("<I", header)[0]
    if not 0 < size <= 1_048_576:
        raise ValueError("Invalid native frame size")
    return json.loads(await reader.readexactly(size))


async def probe(app: Path, language: str, timeout: float) -> dict[str, Any]:
    """Новая app-сессия; ping во время ожидания отличает мост от движка."""
    executable = app / "Contents/MacOS/Koto"
    if running_app(executable):
        raise RuntimeError("This app is already running; refusing to stop it")
    host: asyncio.subprocess.Process | None = None
    result: dict[str, Any] = {"language": language, "timeout_seconds": timeout}
    request_id, ping_id = str(uuid.uuid4()), str(uuid.uuid4())
    try:
        # Аргументы действуют в этом процессе, не меняя личные настройки.
        # Apple выбран явно; данные не отправляются облачному провайдеру.
        subprocess.run([
            "/usr/bin/open", "-g", "-n", str(app), "--args",
            "-AppleLanguages", f"({language})",
            "-translation.engine", "apple", "-browserBridge.enabled", "YES",
        ], check=True)
        directory = (
            Path.home() / "Library/Application Support/dev.slipcast.koto"
        )
        socket_path = directory / "BrowserBridge/bridge.sock"
        # Не читаем auth token. Host сам проходит штатную аутентификацию.
        for _ in range(100):
            if running_app(executable) and socket_path.exists():
                break
            await asyncio.sleep(0.1)
        host = await asyncio.create_subprocess_exec(
            str(app / "Contents/Resources/BrowserBridge/koto-native-host"),
            ORIGIN, stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        if host.stdin is None or host.stdout is None:
            raise RuntimeError("Missing native pipes")
        started = time.monotonic()
        host.stdin.write(encoded("translate", request_id, {
            "text": "The cat is sleeping on the chair.",
            "source": "en", "target": "ru",
            "pageOrigin": "http://127.0.0.1:18763",
        }))
        await host.stdin.drain()
        pending_read = asyncio.create_task(read_frame(host.stdout))
        sent_ping = False
        while time.monotonic() - started < timeout:
            elapsed = time.monotonic() - started
            if elapsed >= 2 and not sent_ping:
                host.stdin.write(encoded("ping", ping_id, {}))
                await host.stdin.drain()
                sent_ping = True
            done, _ = await asyncio.wait({pending_read}, timeout=0.1)
            if not done:
                continue
            frame = pending_read.result()
            if frame.get("id") == ping_id:
                result["ping_seconds"] = round(time.monotonic() - started, 3)
            if frame.get("id") == request_id:
                result["response_type"] = frame.get("type")
                result["elapsed_seconds"] = round(
                    time.monotonic() - started, 3
                )
                payload = frame.get("payload", {})
                result["status"] = (
                    "passed" if frame.get("type") == "translated"
                    and payload.get("text", "").strip() else "failed"
                )
                if "code" in payload:
                    result["error_code"] = payload["code"]
                # В отчёте сохраняется только ответ на фиксированную фикстуру.
                if "text" in payload:
                    result["fixture_translation"] = payload["text"]
                return result
            pending_read = asyncio.create_task(read_frame(host.stdout))
        pending_read.cancel()
        await asyncio.gather(pending_read, return_exceptions=True)
        host.stdin.write(encoded("cancel", str(uuid.uuid4()), {
            "requestID": request_id
        }))
        await host.stdin.drain()
        result.update(status="timeout", elapsed_seconds=round(
            time.monotonic() - started, 3
        ))
        return result
    finally:
        if host and host.returncode is None:
            host.terminate()
            await host.wait()
        # Завершаем только сессию app, созданную этой проверкой.
        for pid in running_app(executable):
            os.kill(pid, signal.SIGTERM)
        for _ in range(50):
            if not running_app(executable):
                break
            await asyncio.sleep(0.1)


def main() -> None:
    """Один запуск даёт сигнал pass/fail; на timeout exit=1."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--language", choices=("en", "ru"), default="en")
    parser.add_argument("--timeout", type=float, default=12)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not 3 <= args.timeout <= 60:
        parser.error("timeout must be between 3 and 60 seconds")
    result = asyncio.run(probe(
        args.app.resolve(), args.language, args.timeout
    ))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(
            result, ensure_ascii=False, indent=2
        ) + "\n")
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if result["status"] == "passed" else 1)


if __name__ == "__main__":
    main()
