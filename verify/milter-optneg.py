#!/usr/bin/env python3
# Speaks just enough of the milter wire protocol to prove rspamd_proxy's
# milter mode is alive: send SMFIC_OPTNEG (option negotiation, the first
# packet every milter client sends) and check the server replies in kind.
# See README's "Milter mode" section for why this worker matters here.

import socket
import struct
import sys

HOST, PORT = "127.0.0.1", 11332
SMFIC_OPTNEG = b"O"


def send_packet(sock, cmd, payload=b""):
    sock.sendall(struct.pack("!I", len(payload) + 1) + cmd + payload)


def read_packet(sock):
    header = b""
    while len(header) < 4:
        chunk = sock.recv(4 - len(header))
        if not chunk:
            sys.exit("connection closed while reading length")
        header += chunk
    (length,) = struct.unpack("!I", header)
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            sys.exit("connection closed while reading body")
        body += chunk
    return body[0:1], body[1:]


with socket.create_connection((HOST, PORT), timeout=10) as sock:
    # version=6, request every action/protocol bit; the server negotiates
    # down to what it actually supports.
    send_packet(sock, SMFIC_OPTNEG, struct.pack("!III", 6, 0xFFFFFFFF, 0xFFFFFFFF))
    cmd, body = read_packet(sock)
    if cmd != SMFIC_OPTNEG:
        sys.exit(f"expected SMFIC_OPTNEG ('O') reply, got {cmd!r}")
    version, actions, protocol = struct.unpack("!III", body[:12])
    print(f"milter negotiated: version={version} actions={actions:#x} protocol={protocol:#x}")
