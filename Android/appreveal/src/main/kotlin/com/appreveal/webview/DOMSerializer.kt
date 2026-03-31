package com.appreveal.webview

/**
 * JavaScript string generators for DOM operations, injected into WebView.
 * Ported verbatim from the iOS DOMSerializer.swift — these are pure browser-standard JS.
 */
internal object DOMSerializer {
    // MARK: - DOM Tree

    fun dumpTreeJS(
        root: String?,
        maxDepth: Int,
        visibleOnly: Boolean,
    ): String {
        val rootExpr = if (root != null) "document.querySelector('${escapeJS(root)}')" else "document.body"
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
                        if (cls) el.classes = cls.split(/\s+/);
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
            })($rootExpr, $maxDepth, $visibleOnly)
            """.trimIndent()
    }

    // MARK: - Interactive elements only

    fun interactiveJS(): String =
        """
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
                if (el.getAttribute('data-testid')) return '[data-testid="' + el.getAttribute('data-testid') + '"]';
                if (el.id) return '#' + el.id;
                if (el.name) return el.tagName.toLowerCase() + '[name="' + el.name + '"]';
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
        """.trimIndent()

    // MARK: - Query

    fun queryJS(
        selector: String,
        limit: Int,
    ): String =
        """
        (function() {
            var nodes = document.querySelectorAll('${escapeJS(selector)}');
            var results = [];
            var max = Math.min(nodes.length, $limit);
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
        """.trimIndent()

    // MARK: - Find by text

    fun findTextJS(
        text: String,
        tag: String?,
    ): String {
        val tagSelector = tag ?: "*"
        return """
            (function() {
                var search = '${escapeJS(text)}'.toLowerCase();
                var candidates = document.querySelectorAll('${escapeJS(tagSelector)}');
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
                    if (el.getAttribute('data-testid')) return '[data-testid="' + el.getAttribute('data-testid') + '"]';
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
            """.trimIndent()
    }

    // MARK: - Click

    fun clickJS(selector: String): String =
        """
        (function() {
            var el = document.querySelector('${escapeJS(selector)}');
            if (!el) return JSON.stringify({error:'Element not found: ${escapeJS(selector)}'});
            el.click();
            return JSON.stringify({success:true, tag:el.tagName.toLowerCase(), text:el.textContent.trim().substring(0,100)});
        })()
        """.trimIndent()

    // MARK: - Type

    fun typeJS(
        selector: String,
        text: String,
        clear: Boolean,
    ): String {
        val baseValue = if (clear) "''" else "el.value"
        return """
            (function() {
                var el = document.querySelector('${escapeJS(selector)}');
                if (!el) return JSON.stringify({error:'Element not found: ${escapeJS(selector)}'});
                el.focus();
                var proto = el.tagName === 'TEXTAREA' ?
                    window.HTMLTextAreaElement.prototype :
                    window.HTMLInputElement.prototype;
                var setter = Object.getOwnPropertyDescriptor(proto, 'value');
                if (setter && setter.set) {
                    setter.set.call(el, $baseValue + '${escapeJS(text)}');
                } else {
                    el.value = $baseValue + '${escapeJS(text)}';
                }
                el.dispatchEvent(new Event('input', {bubbles:true}));
                el.dispatchEvent(new Event('change', {bubbles:true}));
                return JSON.stringify({success:true, value:el.value});
            })()
            """.trimIndent()
    }

    // MARK: - Select

    fun selectJS(
        selector: String,
        value: String,
    ): String =
        """
        (function() {
            var el = document.querySelector('${escapeJS(selector)}');
            if (!el || el.tagName !== 'SELECT') return JSON.stringify({error:'Select not found: ${escapeJS(selector)}'});
            el.value = '${escapeJS(value)}';
            el.dispatchEvent(new Event('change', {bubbles:true}));
            return JSON.stringify({success:true, value:el.value});
        })()
        """.trimIndent()

    // MARK: - Toggle

    fun toggleJS(
        selector: String,
        checked: Boolean,
    ): String =
        """
        (function() {
            var el = document.querySelector('${escapeJS(selector)}');
            if (!el) return JSON.stringify({error:'Element not found: ${escapeJS(selector)}'});
            if (el.checked !== $checked) el.click();
            return JSON.stringify({success:true, checked:el.checked});
        })()
        """.trimIndent()

    // MARK: - Scroll to

    fun scrollToJS(selector: String): String =
        """
        (function() {
            var el = document.querySelector('${escapeJS(selector)}');
            if (!el) return JSON.stringify({error:'Element not found: ${escapeJS(selector)}'});
            el.scrollIntoView({behavior:'smooth',block:'center'});
            var rect = el.getBoundingClientRect();
            return JSON.stringify({success:true, rect:{x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)}});
        })()
        """.trimIndent()

    // MARK: - Links only

    fun linksJS(): String =
        """
        (function() {
            var nodes = document.querySelectorAll('a[href]');
            var results = [];
            for (var i = 0; i < nodes.length; i++) {
                var a = nodes[i];
                var rect = a.getBoundingClientRect();
                if (rect.width === 0 && rect.height === 0) continue;
                var text = a.textContent.trim();
                if (!text && a.querySelector('img')) text = a.querySelector('img').alt || '[image]';
                results.push({
                    text: text.substring(0, 150),
                    href: a.href,
                    selector: a.getAttribute('data-testid') ? '[data-testid="' + a.getAttribute('data-testid') + '"]' : (a.id ? '#' + a.id : null),
                    rect: {x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)}
                });
            }
            return JSON.stringify({links: results, count: results.length});
        })()
        """.trimIndent()

    // MARK: - Text only

    fun textContentJS(selector: String?): String {
        val rootExpr = if (selector != null) "document.querySelector('${escapeJS(selector)}')" else "document.body"
        return """
            (function(root) {
                if (!root) return JSON.stringify({error:'Root not found'});
                var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
                var blocks = [];
                var current = '';
                var lastParent = null;
                while (walker.nextNode()) {
                    var node = walker.currentNode;
                    var parent = node.parentElement;
                    if (!parent) continue;
                    var tag = parent.tagName;
                    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') continue;
                    var style = getComputedStyle(parent);
                    if (style.display === 'none' || style.visibility === 'hidden') continue;
                    var text = node.textContent.trim();
                    if (!text) continue;
                    var isBlock = style.display === 'block' || style.display === 'flex' ||
                        style.display === 'grid' || tag === 'P' || tag === 'DIV' ||
                        tag === 'LI' || tag === 'H1' || tag === 'H2' || tag === 'H3' ||
                        tag === 'H4' || tag === 'H5' || tag === 'H6' || tag === 'TR' || tag === 'BR';
                    if (isBlock && current) { blocks.push(current.trim()); current = ''; }
                    current += (current ? ' ' : '') + text;
                }
                if (current.trim()) blocks.push(current.trim());
                return JSON.stringify({text: blocks.join('\n'), lines: blocks.length});
            })($rootExpr)
            """.trimIndent()
    }

    // MARK: - Forms

    fun formsJS(): String =
        """
        (function() {
            var forms = document.querySelectorAll('form');
            var results = [];
            if (forms.length === 0) {
                var inputs = document.querySelectorAll('input,textarea,select');
                if (inputs.length > 0) {
                    var fields = [];
                    for (var i = 0; i < inputs.length; i++) {
                        fields.push(describeField(inputs[i]));
                    }
                    results.push({id: null, action: null, method: null, fields: fields});
                }
            } else {
                for (var f = 0; f < forms.length; f++) {
                    var form = forms[f];
                    var inputs = form.querySelectorAll('input,textarea,select');
                    var fields = [];
                    for (var i = 0; i < inputs.length; i++) {
                        fields.push(describeField(inputs[i]));
                    }
                    results.push({
                        id: form.id || null,
                        action: form.action || null,
                        method: (form.method || 'get').toUpperCase(),
                        fields: fields
                    });
                }
            }
            function describeField(el) {
                var f = {tag: el.tagName.toLowerCase()};
                if (el.name) f.name = el.name;
                if (el.id) f.id = el.id;
                if (el.type) f.type = el.type;
                if (el.placeholder) f.placeholder = el.placeholder;
                if (el.value) f.value = el.value.substring(0, 200);
                if (el.checked !== undefined) f.checked = el.checked;
                if (el.required) f.required = true;
                if (el.disabled) f.disabled = true;
                var testId = el.getAttribute('data-testid') || el.getAttribute('data-test');
                if (testId) f.testId = testId;
                f.selector = testId ? '[data-testid="' + testId + '"]' :
                    (el.id ? '#' + el.id : (el.name ? el.tagName.toLowerCase() + '[name="' + el.name + '"]' : null));
                if (el.tagName === 'SELECT') {
                    f.options = [];
                    for (var o = 0; o < el.options.length; o++) {
                        f.options.push({value: el.options[o].value, text: el.options[o].text, selected: el.options[o].selected});
                    }
                }
                return f;
            }
            return JSON.stringify({forms: results, count: results.length});
        })()
        """.trimIndent()

    // MARK: - Headings (page structure)

    fun headingsJS(): String =
        """
        (function() {
            var nodes = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
            var results = [];
            for (var i = 0; i < nodes.length; i++) {
                var h = nodes[i];
                var rect = h.getBoundingClientRect();
                results.push({
                    level: parseInt(h.tagName.substring(1)),
                    text: h.textContent.trim().substring(0, 200),
                    id: h.id || undefined,
                    rect: {x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)}
                });
            }
            return JSON.stringify({headings: results, count: results.length});
        })()
        """.trimIndent()

    // MARK: - Images

    fun imagesJS(): String =
        """
        (function() {
            var nodes = document.querySelectorAll('img');
            var results = [];
            for (var i = 0; i < nodes.length; i++) {
                var img = nodes[i];
                var rect = img.getBoundingClientRect();
                if (rect.width === 0 && rect.height === 0) continue;
                results.push({
                    src: img.src,
                    alt: img.alt || '',
                    width: Math.round(rect.width),
                    height: Math.round(rect.height),
                    id: img.id || undefined,
                    selector: img.getAttribute('data-testid') ? '[data-testid="' + img.getAttribute('data-testid') + '"]' : (img.id ? '#' + img.id : null)
                });
            }
            return JSON.stringify({images: results, count: results.length});
        })()
        """.trimIndent()

    // MARK: - Page summary (minimal tokens)

    fun summaryJS(): String =
        """
        (function() {
            var title = document.title;
            var url = location.href;
            var meta = {};
            var metas = document.querySelectorAll('meta[name],meta[property]');
            for (var i = 0; i < metas.length; i++) {
                var key = metas[i].getAttribute('name') || metas[i].getAttribute('property');
                if (key) meta[key] = metas[i].content;
            }

            var headings = [];
            document.querySelectorAll('h1,h2,h3').forEach(function(h) {
                headings.push({level: parseInt(h.tagName[1]), text: h.textContent.trim().substring(0, 100)});
            });

            var links = document.querySelectorAll('a[href]').length;
            var images = document.querySelectorAll('img').length;
            var inputs = document.querySelectorAll('input,textarea,select').length;
            var buttons = document.querySelectorAll('button,[role="button"]').length;

            var forms = [];
            document.querySelectorAll('form').forEach(function(f) {
                forms.push({
                    id: f.id || null,
                    action: f.action || null,
                    fieldCount: f.querySelectorAll('input,textarea,select').length
                });
            });
            if (forms.length === 0 && inputs > 0) {
                forms.push({id: null, action: null, fieldCount: inputs});
            }

            return JSON.stringify({
                title: title, url: url, meta: meta,
                headings: headings,
                counts: {links: links, images: images, inputs: inputs, buttons: buttons},
                forms: forms
            });
        })()
        """.trimIndent()

    // MARK: - Tables

    fun tablesJS(): String =
        """
        (function() {
            var tables = document.querySelectorAll('table');
            var results = [];
            for (var t = 0; t < tables.length; t++) {
                var table = tables[t];
                var headers = [];
                table.querySelectorAll('th').forEach(function(th) {
                    headers.push(th.textContent.trim());
                });
                var rows = [];
                table.querySelectorAll('tbody tr, tr').forEach(function(tr) {
                    if (tr.querySelector('th') && rows.length === 0) return;
                    var cells = [];
                    tr.querySelectorAll('td').forEach(function(td) {
                        cells.push(td.textContent.trim().substring(0, 200));
                    });
                    if (cells.length > 0) rows.push(cells);
                });
                results.push({
                    id: table.id || null,
                    headers: headers,
                    rows: rows,
                    rowCount: rows.length
                });
            }
            return JSON.stringify({tables: results, count: results.length});
        })()
        """.trimIndent()

    // MARK: - Helpers

    private fun escapeJS(string: String): String =
        string
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
}
