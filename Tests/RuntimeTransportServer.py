"""Одноразовый AF_UNIX fixture: подмена сервера живёт вне дерева доверенного launcher."""
from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import sys


def serve(path: str) -> None:
    """Возвращает HTTP 200, считая байты, которые клиент разрешил отправить."""
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(path)
        server.listen(1)
        server.settimeout(5)
        print('READY', flush=True)
        connection, _ = server.accept()
        with connection:
            connection.settimeout(5)
            received = b''
            # Настоящий runtime отвечает только после полного HTTP-запроса. Подмене
            # клиент должен закрыть соединение ещё до первого байта заголовков.
            while b'\r\n\r\n' not in received:
                block = connection.recv(65536)
                if not block:
                    break
                received += block
            if received:
                header, body = received.split(b'\r\n\r\n', 1)
                length = next((int(line.split(b':', 1)[1]) for line in header.split(b'\r\n')
                               if line.lower().startswith(b'content-length:')), 0)
                while len(body) < length:
                    block = connection.recv(65536)
                    if not block:
                        break
                    body += block
                    received += block
                connection.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n{}')
            print(json.dumps({'bytes': len(received),
                              'authorized': b'Authorization: Bearer ' in received}), flush=True)
    Path(path).unlink(missing_ok=True)


def main() -> None:
    """Grandchild имеет другой parent PID даже при том же UID и том же пути сокета."""
    if sys.argv[2] == 'impostor':
        child = os.fork()
        if child:
            _, status = os.waitpid(child, 0)
            sys.exit(os.waitstatus_to_exitcode(status))
    serve(sys.argv[1])


if __name__ == '__main__':
    main()
