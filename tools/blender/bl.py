"""Send a Python script to the running Blender (add-on "MCP for Blender", localhost:9876) and print
what it printed.  Usage:  python tools/blender/bl.py <script.py> [NAME=value ...]
Each NAME=value is defined as a global string before the script runs."""
import json
import socket
import sys


def run(code: str, timeout: float = 600.0) -> dict:
    s = socket.create_connection(("localhost", 9876), timeout=timeout)
    s.sendall(json.dumps({"type": "execute_code", "params": {"code": code}}).encode())
    buf = b""
    while True:
        d = s.recv(1 << 20)
        if not d:
            break
        buf += d
        try:
            return json.loads(buf)
        except ValueError:
            continue
    return json.loads(buf)


if __name__ == "__main__":
    src = open(sys.argv[1], encoding="utf-8").read()
    pre = "".join("%s = %r\n" % tuple(a.split("=", 1)) for a in sys.argv[2:])
    r = run(pre + src)
    if r.get("status") != "success":
        msg = r.get("message", r)
        try:
            msg = json.loads(msg)["traceback"]
        except Exception:
            pass
        print("BLENDER ERROR:\n" + str(msg))
        sys.exit(1)
    print(r["result"].get("result", ""))
