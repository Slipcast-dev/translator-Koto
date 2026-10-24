#!/usr/bin/env python3
"""Настоящие stdio/AF_UNIX интеграции; только синтетические тексты и собственный временный каталог."""
from __future__ import annotations
import asyncio
import json
import os
from pathlib import Path
import stat
import struct
import tempfile
from typing import Any
import uuid

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = json.loads((ROOT / "BrowserExtension/identity.json").read_text())["origin"]


def frame(kind: str, payload: dict[str, str] | None = None, identity: str | None = None) -> dict[str, Any]:
    """ID не повторяется неявно; retry не переотправляет старый translate."""
    return {"v": 1, "id": identity or str(uuid.uuid4()), "type": kind, "payload": payload or {}}


def encode(value: dict[str, Any]) -> bytes:
    body = json.dumps(value, ensure_ascii=False).encode("utf-8")
    return struct.pack("<I", len(body)) + body


async def read_frame(reader: asyncio.StreamReader) -> dict[str, Any]:
    header = await asyncio.wait_for(reader.readexactly(4), 20)
    size = struct.unpack("<I", header)[0]
    if not 0 < size <= 1_048_576:
        raise AssertionError("invalid response size")
    return json.loads(await asyncio.wait_for(reader.readexactly(size), 30))


async def write_frame(writer: asyncio.StreamWriter, value: dict[str, Any], fragmented: bool = False) -> None:
    data = encode(value)
    if fragmented:
        for chunk in [data[:2], data[2:4], data[4:9], data[9:]]:
            writer.write(chunk)
            await writer.drain()
            await asyncio.sleep(0.01)
    else:
        writer.write(data)
        await writer.drain()


async def stop(process: asyncio.subprocess.Process) -> None:
    if process.returncode is not None:
        return
    process.terminate()
    try:
        await asyncio.wait_for(process.wait(), 4)
    except asyncio.TimeoutError:
        process.kill()
        await process.wait()


async def start_server(directory: Path, mode: str = "real") -> asyncio.subprocess.Process:
    process = await asyncio.create_subprocess_exec(
        str(ROOT / "build/stage5/bridge-harness"), str(directory), mode,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    if process.stdout is None:
        raise AssertionError("missing harness stdout")
    ready = await asyncio.wait_for(process.stdout.readline(), 15)
    if json.loads(ready).get("status") != "ready":
        await stop(process)
        raise AssertionError("bridge_not_ready")
    return process


async def native(directory: Path, origin: str = ORIGIN) -> asyncio.subprocess.Process:
    env = os.environ.copy()
    env["KOTO_BRIDGE_DIRECTORY"] = str(directory)
    return await asyncio.create_subprocess_exec(
        str(ROOT / "Resources/BrowserBridge/koto-native-host"), origin, env=env,
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )


async def main() -> None:
    checks: list[str] = []
    report: dict[str, Any] = {"status": "failed"}
    server: asyncio.subprocess.Process | None = None
    host: asyncio.subprocess.Process | None = None

    def check(condition: bool, name: str) -> None:
        if not condition:
            raise AssertionError(name)
        checks.append(name)

    try:
        with tempfile.TemporaryDirectory(prefix="koto-bridge-", dir="/tmp") as temporary:
            directory = Path(temporary)
            os.chmod(directory, 0o700)
            server = await start_server(directory)
            token = (directory / "bridge.token").read_text()
            check(stat.S_IMODE((directory / "bridge.token").stat().st_mode) == 0o600, "token file is private")
            check(stat.S_IMODE((directory / "bridge.sock").stat().st_mode) == 0o600, "socket is private")

            async def connect() -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
                return await asyncio.open_unix_connection(directory / "bridge.sock")

            for kind, payload, name in [
                ("translate", {"text": "Hello", "target": "ru"}, "translation before HELLO rejected"),
                ("hello", {"token": "wrong", "origin": ORIGIN}, "wrong token rejected"),
                ("hello", {"token": token, "origin": "chrome-extension://wrong/"}, "wrong origin rejected"),
            ]:
                reader, writer = await connect()
                await write_frame(writer, frame(kind, payload))
                check(await asyncio.wait_for(reader.read(1), 2) == b"", name)
                writer.close()
                await writer.wait_closed()

            reader, writer = await connect()
            hello = frame("hello", {"token": token, "origin": ORIGIN})
            await write_frame(writer, hello, True)
            ack = await read_frame(reader)
            check(ack["type"] == "helloAck" and ack["id"] == hello["id"], "fragmented HELLO authenticated")
            ping = frame("ping")
            await write_frame(writer, ping, True)
            pong = await read_frame(reader)
            check(pong["type"] == "pong" and pong["id"] == ping["id"], "fragmented ping")
            request = frame("translate", {"text": "The cat is sleeping on the chair.", "source": "en", "target": "ru", "pageOrigin": "https://example.com"})
            await write_frame(writer, request)
            translated = await read_frame(reader)
            report["socket_response"] = translated
            check(translated["type"] == "translated" and "спит" in translated["payload"]["text"],
                  "real Apple translation over authenticated socket")
            report["socket_translation"] = translated["payload"]["text"]
            await write_frame(writer, request)
            duplicate = await read_frame(reader)
            check(duplicate["type"] == "error" and duplicate["payload"].get("code") == "duplicate_request",
                  "duplicate translation ID rejected")
            writer.close()
            await writer.wait_closed()

            host = await native(directory)
            if host.stdin is None or host.stdout is None:
                raise AssertionError("missing native pipes")
            ping = frame("ping")
            await write_frame(host.stdin, ping, True)
            pong = await read_frame(host.stdout)
            check(pong["type"] == "pong" and pong["id"] == ping["id"], "native host authenticates before forwarding")
            check("token" not in pong["payload"], "native host does not disclose desktop token")
            # Реальный простой дольше окна записи выявляет ошибку: новое сообщение
            # не должно наследовать возраст давно опустевшей stdout-очереди.
            await asyncio.sleep(17)
            idle_ping = frame("ping")
            await write_frame(host.stdin, idle_ping)
            idle_pong = await read_frame(host.stdout)
            check(idle_pong["type"] == "pong" and idle_pong["id"] == idle_ping["id"],
                  "native host responds after idle longer than stdout deadline")
            await stop(server)
            server = None
            await asyncio.sleep(0.3)
            server = await start_server(directory)
            new_token = (directory / "bridge.token").read_text()
            check(new_token != token, "desktop restart rotates token")
            ping = frame("ping")
            await write_frame(host.stdin, ping)
            pong = await read_frame(host.stdout)
            check(pong["type"] == "pong" and pong["id"] == ping["id"], "native reconnect performs fresh HELLO with rotated token")
            await stop(host)
            host = None

            bad = await native(directory, "chrome-extension://wrong/")
            await asyncio.wait_for(bad.wait(), 3)
            check(bad.returncode == 64, "native host rejects unauthorized launch origin")
            for data, name in [
                (b"\0\0\0\0", "native zero frame rejected"),
                (struct.pack("<I", 1_048_577), "native oversized frame rejected"),
                (b"\x10\x00", "native truncated header rejected"),
                (struct.pack("<I", 100) + b"{}", "native truncated JSON body rejected"),
            ]:
                bad = await native(directory)
                output, _ = await asyncio.wait_for(bad.communicate(data), 5)
                check(bad.returncode == 2 and not output, name)

            # Системные модели не удаляются: ошибка возникает на публичной границе engine.
            # Само соединение, HELLO и код ответа BrowserBridgeServer здесь настоящие.
            await stop(server)
            server = None
            for mode, expected, name in [
                ("runtime-missing", "models_missing", "runtime notInstalled has specific browser code"),
                ("readiness-missing", "models_missing", "readiness missing models has same browser code"),
                ("runtime-failed", "translation_failed", "ordinary engine failure keeps generic browser code"),
            ]:
                server = await start_server(directory, mode)
                reader, writer = await connect()
                token = (directory / "bridge.token").read_text()
                await write_frame(writer, frame("hello", {"token": token, "origin": ORIGIN}))
                await read_frame(reader)
                request = frame("translate", {"text": "Hello", "source": "en", "target": "ru", "pageOrigin": "https://example.com"})
                await write_frame(writer, request)
                response = await read_frame(reader)
                check(response["type"] == "error" and response["id"] == request["id"]
                      and response["payload"].get("code") == expected, name)
                writer.close()
                await writer.wait_closed()
                await stop(server)
                server = None

            report.update(status="passed", count=len(checks), tests=checks)
    except Exception as error:
        report.update(error=type(error).__name__ + ": " + str(error), count=len(checks), tests=checks)
    finally:
        if host is not None:
            await stop(host)
        if server is not None:
            await stop(server)
    output = ROOT / "Docs/validation/bridge-integration.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if report["status"] != "passed":
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(main())
