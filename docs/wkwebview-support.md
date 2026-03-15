# WKWebView Support

Playwright-style DOM access for web views embedded in native iOS apps. Covers hybrid apps (Ionic, Capacitor, Cordova), in-app browsers, marketing/content web views, and any screen that renders HTML.

## Problem

`get_elements` and `get_view_tree` see WKWebView as a single opaque box. The agent knows a web view exists and its frame, but has zero visibility into what's rendered inside — no DOM nodes, no text content, no form fields, no links, no buttons. For apps that mix native and web content, the agent is blind on web screens.

## How it works

```
Agent                        AppReveal                         WKWebView
  |                              |                                 |
  |-- get_webviews ------------->|                                 |
  |<-- [{id, url, title}] ------|                                 |
  |                              |                                 |
  |-- get_dom_tree {webview_id}->|                                 |
  |                              |-- evaluateJavaScript(dump) ---->|
  |                              |<-- JSON DOM tree ---------------|
  |<-- {dom_tree} --------------|                                 |
  |                              |                                 |
  |-- query_dom {selector} ----->|                                 |
  |                              |-- evaluateJavaScript(query) --->|
  |                              |<-- matching elements -----------|
  |<-- [{tag, text, rect, ...}]-|                                 |
  |                              |                                 |
  |-- web_click {selector} ----->|                                 |
  |                              |-- evaluateJavaScript(click) --->|
  |                              |<-- result ---------------------|
  |<-- {success} ---------------|                                 |
```

All communication with the web view goes through `WKWebView.evaluateJavaScript(_:)`. This is a public API, works on all iOS versions we support, runs on the main actor, and returns results asynchronously — a perfect fit for the existing MCP tool handler pattern.

## Discovery

### Finding web views

Walk the view hierarchy (same as `get_view_tree`) and collect every `WKWebView` instance. Each gets a stable identifier based on its position in the hierarchy or its accessibility identifier if one exists.

```swift
func findWebViews() -> [(id: String, webView: WKWebView)] {
    // Walk from keyWindow, collect all WKWebView instances
    // Assign IDs: use accessibilityIdentifier if set,
    // otherwise "webview_0", "webview_1", etc.
}
```

### Web view metadata

For each discovered web view, return:

| Field | Source |
|-------|--------|
| `id` | Assigned identifier |
| `url` | `webView.url?.absoluteString` |
| `title` | `webView.title` |
| `loading` | `webView.isLoading` |
| `frame` | Screen coordinates via `convert(bounds, to: nil)` |
| `canGoBack` | `webView.canGoBack` |
| `canGoForward` | `webView.canGoForward` |

## DOM tree extraction

### Injected JavaScript

A single JS function serializes the DOM into a JSON-friendly structure. It runs via `evaluateJavaScript` and returns the result.

```javascript
(function dumpDOM(root, maxDepth) {
    function serialize(node, depth) {
        if (depth > maxDepth) return null;
        if (node.nodeType === Node.TEXT_NODE) {
            var text = node.textContent.trim();
            return text ? { type: 'text', text: text } : null;
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return null;

        var rect = node.getBoundingClientRect();
        var el = {
            type: 'element',
            tag: node.tagName.toLowerCase(),
            id: node.id || undefined,
            classes: node.className ? node.className.split(' ').filter(Boolean) : undefined,
            attributes: {},
            rect: {
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
            },
            visible: rect.width > 0 && rect.height > 0 && getComputedStyle(node).display !== 'none',
            children: []
        };

        // Capture relevant attributes
        var dominated = ['href', 'src', 'alt', 'title', 'placeholder', 'value',
                         'type', 'name', 'role', 'aria-label', 'aria-hidden',
                         'data-testid', 'data-cy', 'data-test'];
        for (var i = 0; i < dominated.length; i++) {
            var val = node.getAttribute(dominated[i]);
            if (val != null) el.attributes[dominated[i]] = val;
        }

        // Interactive state
        if (node.disabled !== undefined) el.disabled = node.disabled;
        if (node.checked !== undefined) el.checked = node.checked;
        if (node.tagName === 'INPUT' || node.tagName === 'TEXTAREA' || node.tagName === 'SELECT') {
            el.value = node.value;
        }

        for (var c = node.firstChild; c; c = c.nextSibling) {
            var child = serialize(c, depth + 1);
            if (child) el.children.push(child);
        }
        if (el.children.length === 0) delete el.children;

        return el;
    }
    return JSON.stringify(serialize(root || document.body, 0));
})(document.body, 50)
```

### Output structure

```json
{
    "type": "element",
    "tag": "div",
    "id": "app",
    "classes": ["container"],
    "rect": {"x": 0, "y": 0, "width": 390, "height": 844},
    "visible": true,
    "children": [
        {
            "type": "element",
            "tag": "input",
            "attributes": {
                "type": "email",
                "placeholder": "Email",
                "name": "email",
                "data-testid": "login-email"
            },
            "value": "",
            "rect": {"x": 20, "y": 100, "width": 350, "height": 44},
            "visible": true
        },
        {
            "type": "element",
            "tag": "button",
            "classes": ["btn", "primary"],
            "rect": {"x": 20, "y": 160, "width": 350, "height": 50},
            "visible": true,
            "children": [
                {"type": "text", "text": "Log In"}
            ]
        }
    ]
}
```

### Size management

Full DOM trees can be large. Strategies to keep responses practical:

1. **Depth limit** — `max_depth` parameter (default 50)
2. **Subtree queries** — Pass a CSS selector as `root` to dump only a section: `get_dom_tree {root: "#main-content"}`
3. **Visible only** — `visible_only: true` skips elements with zero rect or `display: none`
4. **Summary mode** — Returns only interactive elements (inputs, buttons, links, selects) instead of the full tree

## Querying

### CSS selector queries

```javascript
(function queryDOM(selector, options) {
    var nodes = document.querySelectorAll(selector);
    var results = [];
    for (var i = 0; i < nodes.length && i < (options.limit || 100); i++) {
        var node = nodes[i];
        var rect = node.getBoundingClientRect();
        results.push({
            index: i,
            tag: node.tagName.toLowerCase(),
            id: node.id || undefined,
            text: node.textContent.trim().substring(0, 200),
            attributes: {/* relevant attrs */},
            rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height},
            visible: rect.width > 0 && rect.height > 0
        });
    }
    return JSON.stringify({matches: results, total: document.querySelectorAll(selector).length});
})('button.primary', {limit: 50})
```

### Text content search

Find elements containing specific text — useful when the agent doesn't know the DOM structure:

```javascript
(function findByText(searchText, tag) {
    var candidates = document.querySelectorAll(tag || '*');
    var results = [];
    for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (el.children.length === 0 || el.tagName === 'BUTTON' || el.tagName === 'A') {
            if (el.textContent.trim().toLowerCase().includes(searchText.toLowerCase())) {
                var rect = el.getBoundingClientRect();
                results.push({
                    tag: el.tagName.toLowerCase(),
                    text: el.textContent.trim().substring(0, 200),
                    selector: generateSelector(el),
                    rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}
                });
            }
        }
    }
    return JSON.stringify(results);
})('Log In', null)
```

### Unique selector generation

To enable the agent to target a found element for interaction, generate a unique CSS selector:

```javascript
function generateSelector(el) {
    // Prefer data-testid, then id, then build a path
    if (el.dataset.testid) return '[data-testid="' + el.dataset.testid + '"]';
    if (el.id) return '#' + el.id;

    var path = [];
    while (el && el !== document.body) {
        var tag = el.tagName.toLowerCase();
        var parent = el.parentElement;
        if (parent) {
            var siblings = parent.querySelectorAll(':scope > ' + tag);
            if (siblings.length > 1) {
                var idx = Array.from(siblings).indexOf(el) + 1;
                tag += ':nth-of-type(' + idx + ')';
            }
        }
        path.unshift(tag);
        el = parent;
    }
    return path.join(' > ');
}
```

## Interaction

### Click

```javascript
(function webClick(selector) {
    var el = document.querySelector(selector);
    if (!el) return JSON.stringify({error: 'Element not found: ' + selector});
    el.click();
    return JSON.stringify({success: true, tag: el.tagName.toLowerCase(), text: el.textContent.trim().substring(0, 100)});
})('[data-testid="login-submit"]')
```

### Type text

```javascript
(function webType(selector, text, clear) {
    var el = document.querySelector(selector);
    if (!el) return JSON.stringify({error: 'Element not found: ' + selector});
    el.focus();
    if (clear) {
        el.value = '';
    }
    // Use InputEvent for framework compatibility (React, Vue, Angular)
    var nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype, 'value'
    ).set;
    nativeInputValueSetter.call(el, (clear ? '' : el.value) + text);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
    return JSON.stringify({success: true, value: el.value});
})('[name="email"]', 'user@test.com', true)
```

The `nativeInputValueSetter` trick is critical — React and other frameworks override the `value` setter, so direct assignment doesn't trigger their change handlers. This is the same approach Playwright and Cypress use.

### Select option

```javascript
(function webSelect(selector, value) {
    var el = document.querySelector(selector);
    if (!el || el.tagName !== 'SELECT') return JSON.stringify({error: 'Select not found'});
    el.value = value;
    el.dispatchEvent(new Event('change', {bubbles: true}));
    return JSON.stringify({success: true, value: el.value});
})('select[name="country"]', 'US')
```

### Scroll to element

```javascript
(function webScrollTo(selector) {
    var el = document.querySelector(selector);
    if (!el) return JSON.stringify({error: 'Element not found'});
    el.scrollIntoView({behavior: 'smooth', block: 'center'});
    var rect = el.getBoundingClientRect();
    return JSON.stringify({success: true, rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}});
})('#footer')
```

### Check/uncheck

```javascript
(function webToggle(selector, checked) {
    var el = document.querySelector(selector);
    if (!el) return JSON.stringify({error: 'Element not found'});
    if (el.checked !== checked) el.click();
    return JSON.stringify({success: true, checked: el.checked});
})('[name="remember"]', true)
```

## MCP tools

| Tool | Arguments | Description |
|------|-----------|-------------|
| `get_webviews` | — | List all WKWebView instances with URL, title, loading state, frame |
| `get_dom_tree` | `webview_id?`, `root?`, `max_depth?`, `visible_only?` | Full or partial DOM tree as JSON |
| `get_dom_interactive` | `webview_id?` | Summary: only inputs, buttons, links, selects, textareas with their attributes and rects |
| `query_dom` | `selector`, `webview_id?`, `limit?` | CSS selector query, returns matching elements |
| `find_dom_text` | `text`, `tag?`, `webview_id?` | Find elements containing text |
| `web_click` | `selector`, `webview_id?` | Click a DOM element |
| `web_type` | `selector`, `text`, `clear?`, `webview_id?` | Type into an input/textarea |
| `web_select` | `selector`, `value`, `webview_id?` | Select an option in a dropdown |
| `web_toggle` | `selector`, `checked`, `webview_id?` | Check/uncheck a checkbox or radio |
| `web_scroll_to` | `selector`, `webview_id?` | Scroll until element is visible |
| `web_evaluate` | `javascript`, `webview_id?` | Run arbitrary JS, return result |
| `web_navigate` | `url`, `webview_id?` | Navigate the web view to a URL |
| `web_back` | `webview_id?` | Go back in web view history |
| `web_forward` | `webview_id?` | Go forward in web view history |

When `webview_id` is omitted, the first (or only) web view on screen is used.

## Coordinate mapping

DOM `getBoundingClientRect()` returns coordinates relative to the web view's viewport. To map to screen coordinates (matching native element frames), add the web view's own screen origin:

```swift
let webViewOrigin = webView.convert(CGPoint.zero, to: nil)
let screenRect = CGRect(
    x: domRect.x + webViewOrigin.x,
    y: domRect.y + webViewOrigin.y,
    width: domRect.width,
    height: domRect.height
)
```

This means `tap_point` (the native tool) can also target DOM elements when the agent has their screen coordinates.

## Framework compatibility

The JS injection approach works with all web frameworks because it operates at the DOM level:

| Framework | Notes |
|-----------|-------|
| Plain HTML | Direct — everything works as-is |
| React | Use `nativeInputValueSetter` for inputs; `click()` works for buttons |
| Vue | `input` + `change` events trigger Vue reactivity |
| Angular | `input` + `change` events trigger Angular zone updates |
| Svelte | Standard DOM events work |
| jQuery | `.click()` triggers jQuery handlers (they bind to native events) |
| Shadow DOM | `querySelectorAll` doesn't pierce shadow roots — need `shadowRoot` traversal for web components |

### Shadow DOM handling

For apps using web components with shadow DOM:

```javascript
function querySelectorDeep(selector, root) {
    var results = Array.from((root || document).querySelectorAll(selector));
    var shadows = (root || document).querySelectorAll('*');
    for (var i = 0; i < shadows.length; i++) {
        if (shadows[i].shadowRoot) {
            results = results.concat(querySelectorDeep(selector, shadows[i].shadowRoot));
        }
    }
    return results;
}
```

## Swift implementation structure

```
iOS/Sources/AppReveal/WebView/
    WebViewBridge.swift      -- WKWebView discovery and JS evaluation
    DOMSerializer.swift      -- JS injection strings for DOM operations
    WebViewTools.swift       -- MCP tool registrations
```

### WebViewBridge

```swift
@MainActor
final class WebViewBridge {
    static let shared = WebViewBridge()

    func findWebViews() -> [(id: String, webView: WKWebView)]
    func evaluate(js: String, webViewId: String?) async throws -> Any?
    func getDOMTree(webViewId: String?, root: String?, maxDepth: Int, visibleOnly: Bool) async throws -> [String: Any]
    func queryDOM(selector: String, webViewId: String?, limit: Int) async throws -> [[String: Any]]
    func click(selector: String, webViewId: String?) async throws
    func type(selector: String, text: String, clear: Bool, webViewId: String?) async throws
}
```

### DOMSerializer

Stores the JavaScript strings as Swift string literals. Each function is self-contained (IIFE pattern) so there's no global state pollution in the web view.

## Security considerations

- All JS injection is read-only or user-initiated interaction — no mutation of page content or structure
- `web_evaluate` allows arbitrary JS execution, same as browser DevTools — acceptable in `#if DEBUG`
- No cross-origin access — `evaluateJavaScript` respects the same-origin policy of the web view
- Cookie/credential access is possible via `document.cookie` in `web_evaluate` — consider redacting in default tools, allow in `web_evaluate` since it's explicitly arbitrary

## Testing plan

The example app needs a screen with an embedded WKWebView loading a local HTML page that exercises:

- Form inputs (text, email, password, checkbox, radio, select)
- Buttons and links
- Nested containers with IDs and classes
- Dynamic content (JS-rendered elements)
- Scroll content
- A `data-testid` convention for stable selectors

This lets us test every web tool end-to-end through MCP without depending on external URLs.

## Phases

### Phase 1 — Read-only discovery
- `get_webviews` — find and list web views
- `get_dom_tree` — full DOM dump
- `get_dom_interactive` — interactive elements summary
- `query_dom` — CSS selector search
- `find_dom_text` — text content search

### Phase 2 — Interaction
- `web_click`, `web_type`, `web_select`, `web_toggle`
- `web_scroll_to`
- `web_navigate`, `web_back`, `web_forward`

### Phase 3 — Advanced
- `web_evaluate` — arbitrary JS
- Shadow DOM traversal
- MutationObserver-based change detection (notify agent when DOM changes)
- Coordinate mapping for hybrid tap scenarios (native `tap_point` on DOM elements)
