"""Runs one Hostwatch operation through the local MCP server and prints a compact result.
Usage: hostwatch_call.py <operation> '<args json>' [confirm] [jq-like key path, dot separated]"""
import json, subprocess, sys
SERVER = ["/Users/serhiirihgt/.nvm/versions/node/v22.13.1/bin/hostwatch-mcp-node", "serve"]
NODE = "fe8b3706-3da6-47f8-875c-ce86a0cb8114"
op, args = sys.argv[1], json.loads(sys.argv[2])
confirm = len(sys.argv) > 3 and sys.argv[3] == "confirm"
keys = sys.argv[4].split(",") if len(sys.argv) > 4 else None
proc = subprocess.Popen(SERVER, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
n = 0
def rpc(method, params, notify=False):
    global n
    m = {"jsonrpc": "2.0", "method": method, "params": params}
    if not notify: n += 1; m["id"] = n
    proc.stdin.write(json.dumps(m) + "\n"); proc.stdin.flush()
    if notify: return
    while True:
        r = json.loads(proc.stdout.readline())
        if r.get("id") == n: return r
rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "pythilo-release", "version": "1"}})
rpc("notifications/initialized", {}, True)
arguments = {"operation": op, "nodeId": NODE, "args": args}
if confirm: arguments["confirm"] = True
r = rpc("tools/call", {"name": "execute", "arguments": arguments})
text = r["result"]["content"][0]["text"] if "result" in r else json.dumps(r)
try:
    data = json.loads(text)
    result = data.get("result", data)
    if keys: result = {k: result.get(k) for k in keys}
    print(json.dumps(result)[:4000])
except Exception:
    print(text[:4000])
proc.terminate()
