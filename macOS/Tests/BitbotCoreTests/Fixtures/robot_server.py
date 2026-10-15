# Copyright (c) 2026 Siyuan Wang.
# Licensed under the GNU General Public License v3. See LICENSE.

"""Local protocol fixture: HTTP metadata plus RFC 6455 ping/text/binary frames."""
import argparse
import base64
import hashlib
import http.server
import json
import socket
import struct
import threading

parser = argparse.ArgumentParser()
parser.add_argument("--ready-file", required=True)
parser.add_argument("--mode", default="normal")
args = parser.parse_args()
events = []
event_lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == "/console":
            self.websocket()
            return
        values = {
            "/monitor/stateslist": {"states": [{"id": 1, "name": "kernel_idle"}]},
            "/setting/control/get": [{"event": "walk", "kb_key": "w"}, {"event": "axis", "kb_key": "GAMEPAD_JOYSTICK_LX"}],
            "/monitor/headers": {"kernel": ["state", "counter"], "bus": {"devices": [{"name": "motor", "type": "motor", "headers": ["position"]}]}, "extra": ["temp"]},
            "/testing/events": events,
        }
        if self.path not in values:
            self.send_error(404)
            return
        payload = json.dumps(values[self.path]).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def exact(self, n):
        data = b""
        while len(data) < n:
            part = self.rfile.read(n - len(data))
            if not part:
                raise ConnectionError()
            data += part
        return data

    def frame(self, opcode, payload):
        head = bytes([0x80 | opcode])
        length = len(payload)
        if length < 126:
            head += bytes([length])
        elif length < 65536:
            head += bytes([126]) + struct.pack("!H", length)
        else:
            head += bytes([127]) + struct.pack("!Q", length)
        self.wfile.write(head + payload)
        self.wfile.flush()

    def websocket(self):
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.connection.settimeout(10)
        try:
            while True:
                first, second = self.exact(2)
                opcode, length = first & 15, second & 127
                if length == 126:
                    length = struct.unpack("!H", self.exact(2))[0]
                elif length == 127:
                    length = struct.unpack("!Q", self.exact(8))[0]
                mask = self.exact(4) if second & 128 else None
                payload = self.exact(length)
                if mask:
                    payload = bytes(v ^ mask[i % 4] for i, v in enumerate(payload))
                if opcode == 8:
                    self.frame(8, payload)
                    return
                if opcode == 9:
                    if args.mode != "stall":
                        self.frame(10, payload)
                elif opcode == 1:
                    assert json.loads(payload)["type"] == "request_data"
                    data = [1, 12, 1.5, 30] if args.mode != "mismatch" else [1]
                    self.frame(1, json.dumps({"type": "monitor_data", "data": json.dumps({"data": data})}).encode())
                elif opcode == 2:
                    message = json.loads(payload)
                    assert message["type"] == "events"
                    with event_lock:
                        events.extend(json.loads(message["data"])["events"])
        except (OSError, ConnectionError):
            pass
        finally:
            self.close_connection = True


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
with open(args.ready_file, "w") as f:
    f.write(str(server.server_port))
server.serve_forever()
