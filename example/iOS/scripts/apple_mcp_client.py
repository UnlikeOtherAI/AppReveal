#!/usr/bin/env python3
"""Authenticated Apple example verification. Never prints or persists session tokens in evidence.

Import Client for flow assertions, or use --session-file <private file> TOOL [JSON].
--session-from-log extracts a session URL into a mode-0600 file, without printing it.
"""
import argparse
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request


class Client:
    def __init__(self, session_file):
        path = Path(session_file)
        if path.stat().st_mode & 0o077:
            raise ValueError("Session file must be owner-only (chmod 600)")
        url = urllib.parse.urlsplit(path.read_text().strip())
        self.endpoint = urllib.parse.urlunsplit((url.scheme, url.netloc, url.path or "/", "", ""))
        self.token = urllib.parse.parse_qs(url.query)["appreveal_session_token"][0]
        self.evidence = []
        self.request_id = 0

    def request(self, method, params=None, authenticated=True):
        self.request_id += 1
        payload = {"jsonrpc": "2.0", "id": self.request_id, "method": method, "params": params or {}}
        headers = {"Content-Type": "application/json"}
        if authenticated:
            headers["Authorization"] = "Bearer " + self.token
        request = urllib.request.Request(self.endpoint, data=json.dumps(payload).encode(), headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    def call(self, name, arguments=None, failure=False):
        response = self.request("tools/call", {"name": name, "arguments": arguments or {}})
        assert "error" not in response, response.get("error")
        result = response["result"]
        blocks = result["content"]
        if any(block["type"] == "image" for block in blocks):
            value = result["structuredContent"]
            self.evidence.append({"tool": name, "arguments": arguments or {}, "result": value})
            return result
        value = json.loads(blocks[0]["text"])
        failed = (isinstance(value.get("error"), str) and bool(value["error"].strip())) or value.get("success") is False
        assert failed == failure, (name, value)
        assert bool(result.get("isError")) == failed, (name, "MCP isError mismatch", value)
        self.evidence.append({"tool": name, "arguments": arguments or {}, "result": value})
        return value

    def save(self, path):
        Path(path).write_text(json.dumps(self.evidence, indent=2) + "\n")


def extract_session(log_path, destination):
    text = Path(log_path).read_text()
    matches = re.findall(r"http://127\.0\.0\.1:\d+/\?appreveal_session_token=[^\s]+", text)
    if not matches:
        raise ValueError("No session endpoint found in app log")
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(matches[-1] + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-file", required=True)
    parser.add_argument("--session-from-log")
    parser.add_argument("--expect-failure", action="store_true")
    parser.add_argument("tool", nargs="?")
    parser.add_argument("arguments", nargs="?", default="{}")
    args = parser.parse_args()
    if args.session_from_log:
        extract_session(args.session_from_log, args.session_file)
        print("Saved private session file")
    else:
        client = Client(args.session_file)
        print(json.dumps(client.call(args.tool, json.loads(args.arguments), failure=args.expect_failure), indent=2))
