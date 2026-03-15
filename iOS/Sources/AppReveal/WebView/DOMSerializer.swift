// JavaScript strings for DOM operations, injected into WKWebView

import Foundation

#if DEBUG

enum DOMSerializer {

    // MARK: - DOM Tree

    static func dumpTreeJS(root: String?, maxDepth: Int, visibleOnly: Bool) -> String {
        let rootExpr = root.map { "document.querySelector('\(escapeJS($0))')" } ?? "document.body"
        return """
        (function(root, maxDepth, visibleOnly) {
            function serialize(node, depth) {
                if (depth > maxDepth) return null;
                if (node.nodeType === Node.TEXT_NODE) {
                    var text = node.textContent.trim();
                    return text ? {type:'text',text:text.substring(0,200)} : null;
                }
                if (node.nodeType !== Node.ELEMENT_NODE) return null;
                var rect = node.getBoundingClientRect();
                var isVisible = rect.width > 0 && rect.height > 0 && getComputedStyle(node).display !== 'none';
                if (visibleOnly && !isVisible) return null;
                var el = {
                    type:'element',
                    tag:node.tagName.toLowerCase(),
                    rect:{x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)},
                    visible:isVisible
                };
                if (node.id) el.id = node.id;
                if (node.className && typeof node.className === 'string') {
                    var cls = node.className.trim();
                    if (cls) el.classes = cls.split(/\\s+/);
                }
                var dominated = ['href','src','alt','title','placeholder','value','type','name','role',
                    'aria-label','aria-hidden','data-testid','data-cy','data-test','action','method'];
                var attrs = {};
                for (var i = 0; i < dominated.length; i++) {
                    var val = node.getAttribute(dominated[i]);
                    if (val != null) attrs[dominated[i]] = val;
                }
                if (Object.keys(attrs).length > 0) el.attributes = attrs;
                if (node.disabled !== undefined && node.disabled) el.disabled = true;
                if (node.checked !== undefined) el.checked = node.checked;
                if ((node.tagName === 'INPUT' || node.tagName === 'TEXTAREA' || node.tagName === 'SELECT') && node.value) {
                    el.value = node.value.substring(0, 200);
                }
                var children = [];
                for (var c = node.firstChild; c; c = c.nextSibling) {
                    var child = serialize(c, depth + 1);
                    if (child) children.push(child);
                }
                if (children.length > 0) el.children = children;
                return el;
            }
            var r = root || document.body;
            if (!r) return JSON.stringify({error:'Root element not found'});
            return JSON.stringify(serialize(r, 0));
        })(\(rootExpr), \(maxDepth), \(visibleOnly))
        """
    }

    // MARK: - Interactive elements only

    static func interactiveJS() -> String {
        return """
        (function() {
            var selectors = 'a,button,input,textarea,select,[role="button"],[role="link"],[onclick],[tabindex]';
            var nodes = document.querySelectorAll(selectors);
            var results = [];
            for (var i = 0; i < nodes.length; i++) {
                var node = nodes[i];
                var rect = node.getBoundingClientRect();
                if (rect.width === 0 && rect.height === 0) continue;
                var el = {
                    tag: node.tagName.toLowerCase(),
                    rect: {x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)},
                    selector: genSelector(node)
                };
                if (node.id) el.id = node.id;
                if (node.name) el.name = node.name;
                if (node.type) el.type = node.type;
                if (node.placeholder) el.placeholder = node.placeholder;
                if (node.value) el.value = node.value.substring(0, 200);
                var text = node.textContent.trim();
                if (text) el.text = text.substring(0, 100);
                var testId = node.getAttribute('data-testid') || node.getAttribute('data-test') || node.getAttribute('data-cy');
                if (testId) el.testId = testId;
                if (node.getAttribute('aria-label')) el.ariaLabel = node.getAttribute('aria-label');
                if (node.disabled) el.disabled = true;
                if (node.checked !== undefined) el.checked = node.checked;
                if (node.href) el.href = node.href;
                results.push(el);
            }
            function genSelector(el) {
                if (el.getAttribute('data-testid')) return '[data-testid=\"' + el.getAttribute('data-testid') + '\"]';
                if (el.id) return '#' + el.id;
                if (el.name) return el.tagName.toLowerCase() + '[name=\"' + el.name + '\"]';
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
            return JSON.stringify({elements: results, count: results.length});
        })()
        """
    }

    // MARK: - Query

    static func queryJS(selector: String, limit: Int) -> String {
        return """
        (function() {
            var nodes = document.querySelectorAll('\(escapeJS(selector))');
            var results = [];
            var max = Math.min(nodes.length, \(limit));
            for (var i = 0; i < max; i++) {
                var node = nodes[i];
                var rect = node.getBoundingClientRect();
                var el = {
                    index: i,
                    tag: node.tagName.toLowerCase(),
                    text: node.textContent.trim().substring(0, 200),
                    rect: {x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)},
                    visible: rect.width > 0 && rect.height > 0
                };
                if (node.id) el.id = node.id;
                if (node.value) el.value = node.value;
                var attrs = {};
                for (var a = 0; a < node.attributes.length; a++) {
                    attrs[node.attributes[a].name] = node.attributes[a].value;
                }
                el.attributes = attrs;
                results.push(el);
            }
            return JSON.stringify({matches: results, total: nodes.length});
        })()
        """
    }

    // MARK: - Find by text

    static func findTextJS(text: String, tag: String?) -> String {
        let tagSelector = tag ?? "*"
        return """
        (function() {
            var search = '\(escapeJS(text))'.toLowerCase();
            var candidates = document.querySelectorAll('\(escapeJS(tagSelector))');
            var results = [];
            for (var i = 0; i < candidates.length && results.length < 50; i++) {
                var el = candidates[i];
                var content = el.textContent.trim();
                if (content.toLowerCase().includes(search)) {
                    var isLeaf = el.children.length === 0 ||
                        el.tagName === 'BUTTON' || el.tagName === 'A' ||
                        el.tagName === 'LI' || el.tagName === 'H1' ||
                        el.tagName === 'H2' || el.tagName === 'H3';
                    if (!isLeaf) continue;
                    var rect = el.getBoundingClientRect();
                    if (rect.width === 0 && rect.height === 0) continue;
                    results.push({
                        tag: el.tagName.toLowerCase(),
                        text: content.substring(0, 200),
                        selector: genSelector(el),
                        rect: {x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)}
                    });
                }
            }
            function genSelector(el) {
                if (el.getAttribute('data-testid')) return '[data-testid=\"' + el.getAttribute('data-testid') + '\"]';
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
            return JSON.stringify({matches: results, count: results.length});
        })()
        """
    }

    // MARK: - Click

    static func clickJS(selector: String) -> String {
        return """
        (function() {
            var el = document.querySelector('\(escapeJS(selector))');
            if (!el) return JSON.stringify({error:'Element not found: \(escapeJS(selector))'});
            el.click();
            return JSON.stringify({success:true, tag:el.tagName.toLowerCase(), text:el.textContent.trim().substring(0,100)});
        })()
        """
    }

    // MARK: - Type

    static func typeJS(selector: String, text: String, clear: Bool) -> String {
        return """
        (function() {
            var el = document.querySelector('\(escapeJS(selector))');
            if (!el) return JSON.stringify({error:'Element not found: \(escapeJS(selector))'});
            el.focus();
            var proto = el.tagName === 'TEXTAREA' ?
                window.HTMLTextAreaElement.prototype :
                window.HTMLInputElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value');
            if (setter && setter.set) {
                setter.set.call(el, \(clear ? "''" : "el.value") + '\(escapeJS(text))');
            } else {
                el.value = \(clear ? "''" : "el.value") + '\(escapeJS(text))';
            }
            el.dispatchEvent(new Event('input', {bubbles:true}));
            el.dispatchEvent(new Event('change', {bubbles:true}));
            return JSON.stringify({success:true, value:el.value});
        })()
        """
    }

    // MARK: - Select

    static func selectJS(selector: String, value: String) -> String {
        return """
        (function() {
            var el = document.querySelector('\(escapeJS(selector))');
            if (!el || el.tagName !== 'SELECT') return JSON.stringify({error:'Select not found: \(escapeJS(selector))'});
            el.value = '\(escapeJS(value))';
            el.dispatchEvent(new Event('change', {bubbles:true}));
            return JSON.stringify({success:true, value:el.value});
        })()
        """
    }

    // MARK: - Toggle

    static func toggleJS(selector: String, checked: Bool) -> String {
        return """
        (function() {
            var el = document.querySelector('\(escapeJS(selector))');
            if (!el) return JSON.stringify({error:'Element not found: \(escapeJS(selector))'});
            if (el.checked !== \(checked)) el.click();
            return JSON.stringify({success:true, checked:el.checked});
        })()
        """
    }

    // MARK: - Scroll to

    static func scrollToJS(selector: String) -> String {
        return """
        (function() {
            var el = document.querySelector('\(escapeJS(selector))');
            if (!el) return JSON.stringify({error:'Element not found: \(escapeJS(selector))'});
            el.scrollIntoView({behavior:'smooth',block:'center'});
            var rect = el.getBoundingClientRect();
            return JSON.stringify({success:true, rect:{x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)}});
        })()
        """
    }

    // MARK: - Helpers

    private static func escapeJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

#endif
