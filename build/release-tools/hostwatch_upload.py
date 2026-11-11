"""Uploads a source overlay through the local Hostwatch MCP server (same operation as the
MCP tool: execute source_upload), in chunks of at most 262144 bytes."""
import base64, hashlib, json, subprocess, sys

SERVER = ["/Users/serhiirihgt/.nvm/versions/node/v22.13.1/bin/hostwatch-mcp-node", "serve"]
NODE = "fe8b3706-3da6-47f8-875c-ce86a0cb8114"
path, upload_id = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
digest = hashlib.sha256(data).hexdigest()
proc = subprocess.Popen(SERVER, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
counter = 0
def rpc(method, params, notify=False):
    global counter
    message = {"jsonrpc": "2.0", "method": method, "params": params}
    if not notify:
        counter += 1
        message["id"] = counter
    proc.stdin.write(json.dumps(message) + "\n"); proc.stdin.flush()
    if notify: return None
    while True:
        line = proc.stdout.readline()
        if not line: raise SystemExit("server closed")
        reply = json.loads(line)
        if reply.get("id") == counter: return reply
rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "pythilo-release", "version": "1"}})
rpc("notifications/initialized", {}, notify=True)
chunk = 262144
offset = 0
while offset < len(data):
    piece = data[offset:offset + chunk]
    reply = rpc("tools/call", {"name": "execute", "arguments": {"operation": "source_upload", "nodeId": NODE, "confirm": True,
        "args": {"id": "pythilo-web", "uploadId": upload_id, "offset": offset, "totalBytes": len(data), "sha256": digest,
                 "dataBase64": base64.b64encode(piece).decode()}}})
    text = reply.get("result", {}).get("content", [{}])[0].get("text", "") if "result" in reply else json.dumps(reply.get("error"))
    print(offset, text[:300])
    if "error" in reply or reply.get("result", {}).get("isError"): raise SystemExit(1)
    offset += len(piece)
print("sha256", digest, "bytes", len(data))
proc.terminate()
