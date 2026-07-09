#!/usr/bin/env python3
import sys
import os
import threading
import urllib.request
import urllib.error
import json
import time

PORT = 19790
base_url = f"http://127.0.0.1:{PORT}"

post_url = None

def get_access_token():
    # 1. Try environment variable
    token = os.environ.get("VANISCRIPT_MCP_TOKEN")
    if token:
        return token
    # 2. Try reading settings.json from Application Support
    try:
        path = os.path.expanduser("~/Library/Application Support/VaniScript/settings.json")
        if os.path.exists(path):
            with open(path, "r") as f:
                data = json.load(f)
                return data.get("mcpAccessToken", "")
    except Exception:
        pass
    return ""

def sse_listener():
    global post_url
    while True:
        try:
            post_url = None
            token = get_access_token()
            headers = {}
            if token:
                headers["x-vaniscript-mcp-token"] = token
            
            req = urllib.request.Request(f"{base_url}/sse", headers=headers)
            with urllib.request.urlopen(req) as response:
                current_event = None
                for line_bytes in response:
                    line = line_bytes.decode('utf-8').strip()
                    if not line:
                        continue
                    if line.startswith("event:"):
                        current_event = line.split(":", 1)[1].strip()
                    elif line.startswith("data:"):
                        data_val = line.split(":", 1)[1].strip()
                        if current_event == "endpoint":
                            post_url = f"{base_url}{data_val}"
                        elif current_event == "message" or current_event is None:
                            sys.stdout.write(data_val + "\n")
                            sys.stdout.flush()
        except Exception as e:
            post_url = None
            time.sleep(2)

# Start SSE listener in a background thread
threading.Thread(target=sse_listener, daemon=True).start()

# Main thread reads from stdin and forwards via HTTP POST
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    # Wait until we have the POST endpoint
    while post_url is None:
        time.sleep(0.1)
    
    try:
        token = get_access_token()
        headers = {'Content-Type': 'application/json'}
        if token:
            headers["x-vaniscript-mcp-token"] = token
            
        req = urllib.request.Request(
            post_url,
            data=line.encode('utf-8'),
            headers=headers
        )
        with urllib.request.urlopen(req) as resp:
            resp.read() # Consume response
    except Exception as e:
        sys.stderr.write(f"Bridge error: {str(e)}\n")
        sys.stderr.flush()
