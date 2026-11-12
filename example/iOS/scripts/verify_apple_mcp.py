#!/usr/bin/env python3
"""Exercise the existing Apple examples over authenticated MCP HTTP.

Run on dictator after launching the matching Debug example with NSUnbufferedIO=YES.
Use apple_mcp_client.py --session-from-log to create the private --session-file.
Evidence contains tool results, never the session URL. --screenshot captures ONE image.
"""
import argparse
import base64
import json
from pathlib import Path
import time
import urllib.error
from apple_mcp_client import Client


def settle():
    time.sleep(0.45)


def wait_for(check, description):
    for _ in range(30):
        if check():
            return
        time.sleep(0.2)
    raise AssertionError("Timed out waiting for " + description)


def tree_node(client, identifier):
    return next(node for node in client.call("get_view_tree")["views"] if node.get("accessibilityId") == identifier)


def verify_mac(client):
    client.call("tap_element", {"element_id": "sidebar.row.orders"})
    assert client.call("get_state")["selectedSection"] == "orders"
    client.call("tap_text", {"text": "Settings"})
    assert client.call("get_state")["selectedSection"] == "settings"
    before = client.call("get_screen")
    client.call("navigate_back", failure=True)
    assert client.call("get_screen")["screenKey"] == before["screenKey"]
    client.call("clear_text", {"element_id": "settings.endpoint"})
    client.call("type_text", {"element_id": "settings.endpoint", "text": "https://example.test/😀"})
    assert tree_node(client, "settings.endpoint")["text"] == "https://example.test/😀"
    client.call("clear_text", {"element_id": "settings.endpoint"})
    client.call("type_text", {"element_id": "settings.endpoint", "text": "https://api.example.com"})
    assert tree_node(client, "settings.endpoint")["text"] == "https://api.example.com"
    before_toggle = tree_node(client, "settings.notifications")["state"]
    elements = client.call("get_elements")["elements"]
    toggle = next(item for item in elements if item["id"] == "settings.notifications")
    x, y, width, height = map(float, toggle["frame"].split(","))
    client.call("tap_point", {"x": x + width / 2, "y": y + height / 2})
    assert tree_node(client, "settings.notifications")["state"] != before_toggle
    client.call("tap_element", {"element_id": "settings.notifications"})
    assert tree_node(client, "settings.notifications")["state"] == before_toggle
    client.call("get_menu_bar")
    client.call("click_menu_item", {"path": "File"}, failure=True)
    client.call("click_menu_item", {"path": "Missing > Missing"}, failure=True)
    client.call("select_tab", {"index": -1}, failure=True)
    client.call("get_webviews")
    client.call("web_evaluate", {"javascript": "42"}, failure=True)
    client.call("dismiss_modal", failure=True)


def verify_ios(client):
    client.call("select_tab", {"index": 0})
    settle()
    client.call("navigate_back", failure=True)
    client.call("tap_element", {"element_id": "orders.cell_0"})
    settle()
    assert client.call("get_screen")["navigationDepth"] == 2
    client.call("type_text", {"element_id": "order_detail.notes", "text": "Maintenance 😀"})
    assert "Maintenance 😀" in tree_node(client, "order_detail.notes")["text"]
    client.call("clear_text", {"element_id": "order_detail.notes"})
    assert tree_node(client, "order_detail.notes")["text"] == ""
    client.call("scroll", {"direction": "down", "container_id": "order_detail.scroll"})
    client.call("scroll", {"direction": "up", "container_id": "order_detail.scroll"})
    client.call("navigate_back")
    settle()
    assert client.call("get_screen")["navigationDepth"] == 1
    client.call("select_tab", {"index": 3})
    settle()
    def toggle_value():
        return next(e["value"] for e in client.call("get_elements")["elements"] if e["id"] == "settings.dark_mode_toggle")
    initial = toggle_value()
    client.call("tap_element", {"element_id": "settings.dark_mode_toggle"})
    assert toggle_value() != initial
    client.call("tap_element", {"element_id": "settings.dark_mode_toggle"})
    assert toggle_value() == initial
    client.call("select_tab", {"index": 4})
    settle()
    assert client.call("get_webviews")["count"] == 1
    wait_for(lambda: client.call("web_evaluate", {"javascript": "Boolean(document.querySelector('#reset-btn'))"})["result"] == "true", "local HTML")
    client.call("web_click", {"selector": "#reset-btn"})
    client.call("web_click", {"selector": "[data-testid=counter-reset]"})
    for js, expected in [("42", "42"), ("true", "true"), ("null", "null"), ("void 0", "null")]:
        assert client.call("web_evaluate", {"javascript": js})["result"] == expected
    for name in ["get_dom_tree", "get_dom_interactive", "get_dom_summary", "get_dom_links", "get_dom_forms",
                 "get_dom_headings", "get_dom_images", "get_dom_tables", "get_dom_text"]:
        client.call(name)
    client.call("query_dom", {"selector": "#name-input"})
    client.call("find_dom_text", {"text": "Contact Form"})
    client.call("type_text", {"element_id": "web.webdemo.webview.form-name", "text": "Apple '😀'"})
    assert client.call("web_evaluate", {"javascript": "document.querySelector('#name-input').value"})["result"] == "Apple '😀'"
    client.call("clear_text", {"element_id": "web.webdemo.webview.form-name"})
    assert client.call("web_evaluate", {"javascript": "document.querySelector('#name-input').value"})["result"] == ""
    client.call("web_type", {"selector": "#name-input", "text": "Verified", "clear": True})
    client.call("web_evaluate", {"javascript": "document.querySelector('#name-input').readOnly = true; 'locked'"})
    client.call("type_text", {"element_id": "web.webdemo.webview.form-name", "text": "bad"}, failure=True)
    assert client.call("web_evaluate", {"javascript": "document.querySelector('#name-input').value"})["result"] == "Verified"
    client.call("web_evaluate", {"javascript": "document.querySelector('#name-input').readOnly = false; 'unlocked'"})
    client.call("web_select", {"selector": "#category-select", "value": "support"})
    client.call("web_select", {"selector": "#category-select", "value": "missing"}, failure=True)
    assert client.call("web_evaluate", {"javascript": "document.querySelector('#category-select').value"})["result"] == "support"
    client.call("web_toggle", {"selector": "#terms-check", "checked": True})
    assert client.call("web_evaluate", {"javascript": "document.querySelector('#terms-check').checked"})["result"] == "true"
    client.call("web_evaluate", {"javascript": "document.querySelector('#submit-btn').disabled = true; 'disabled'"})
    client.call("web_click", {"selector": "#submit-btn"}, failure=True)
    client.call("web_evaluate", {"javascript": "document.querySelector('#submit-btn').disabled = false; 'enabled'"})
    client.call("web_click", {"selector": "#increment-btn"})
    assert client.call("web_evaluate", {"javascript": "document.querySelector('#counter-value').textContent"})["result"] == "1"
    client.call("web_scroll_to", {"selector": "#bottom-anchor"})
    assert float(client.call("web_evaluate", {"javascript": "window.scrollY"})["result"]) > 0
    client.call("web_evaluate", {"webview_id": "missing", "javascript": "42"}, failure=True)
    client.call("web_back", failure=True)
    client.call("web_forward", failure=True)
    client.call("web_click", {"selector": "#reset-btn"})
    client.call("web_scroll_to", {"selector": "#name-input"})
    client.call("select_tab", {"index": 0})
    settle()
    client.call("select_tab", {"index": -1}, failure=True)
    client.call("dismiss_modal", failure=True)
    client.call("open_deeplink", {"url": "appreveal://catalog"})
    settle()
    assert client.call("get_screen")["screenKey"] == "catalog"
    client.call("open_deeplink", {"url": "appreveal://orders"})
    settle()
    assert client.call("get_screen")["screenKey"] == "orders.list"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-file", required=True)
    parser.add_argument("--platform", choices=["ios", "macos"], required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--screenshot", action="store_true")
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    client = Client(args.session_file)
    try:
        try:
            client.request("initialize", authenticated=False)
            raise AssertionError("Unauthenticated request was accepted")
        except urllib.error.HTTPError as error:
            assert error.code == 401
        assert "result" in client.request("initialize")
        assert client.request("tools/list")["result"]["tools"]
        assert client.call("list_windows")["count"] > 0, "Raise the example window before verification"
        for name in ["list_windows", "get_screen", "get_elements", "get_view_tree", "get_state",
                     "get_navigation_stack", "get_feature_flags", "launch_context", "device_info"]:
            client.call(name)
        for name in ["get_logs", "get_recent_errors", "get_network_calls"]:
            client.call(name, {"limit": 0})
            client.call(name, {"limit": -1})
        client.call("get_network_call_detail", {"id": "missing"}, failure=True)
        client.call("tap_point", {"x": -100, "y": -100}, failure=True)
        client.call("tap_point", {}, failure=True)
        client.call("tap_element", {"element_id": "missing", "window_id": "missing"}, failure=True)
        client.call("type_text", {"text": "bad", "window_id": "missing"}, failure=True)
        client.call("open_deeplink", {"url": "appreveal-maintenance-invalid://unhandled"}, failure=True)
        client.call("scroll", {"direction": "sideways"}, failure=True)
        client.call("scroll_to_element", {"element_id": "missing"}, failure=True)
        batch = client.call("batch", {"stop_on_error": True, "actions": [
            {"tool": "tap_element", "arguments": {"element_id": "missing", "window_id": "missing"}},
            {"tool": "get_state"}]})
        assert batch["count"] == 1
        (verify_ios if args.platform == "ios" else verify_mac)(client)
        if args.screenshot:
            result = client.call("screenshot")
            image = next(block for block in result["content"] if block["type"] == "image")
            data = base64.b64decode(image["data"])
            assert image["mimeType"] == "image/png" and data.startswith(b"\x89PNG\r\n\x1a\n")
            assert result["structuredContent"]["width"] > 0
            (output / (args.platform + ".png")).write_bytes(data)
        print(f"PASS {args.platform}: {len(client.evidence)} authenticated tool calls, plus auth rejection and initialization")
    finally:
        client.save(output / (args.platform + "-mcp.json"))


if __name__ == "__main__":
    main()
