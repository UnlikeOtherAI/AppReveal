// Shared by inventory and actions so IDs and editability describe the same DOM.
({ action, target, text, x, y }) => {
  const selector = 'a[href],button,input,textarea,select,summary,[role],[tabindex],[contenteditable],[data-testid],[data-test],[aria-label]';
  const state = window.__apprevealDomState ??= { nextId: 0, ids: new WeakMap(), elements: new Map() };
  const idFor = element => {
    if (!state.ids.has(element)) {
      const id = state.nextId++;
      state.ids.set(element, id);
    }
    const id = state.ids.get(element);
    state.elements.set(id, new WeakRef(element));
    return id;
  };
  const visible = element => {
    if (!(element instanceof Element) || !element.isConnected) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.visibility !== 'collapse'
      && !element.closest('[hidden],[inert]');
  };
  const enabled = element => !element.matches(':disabled') && !element.closest('[aria-disabled="true"],[inert]');
  const normalize = value => String(value ?? '').trim().replace(/\s+/g, ' ');
  const label = element => normalize(element.getAttribute('aria-label') ||
    (element.getAttribute('aria-labelledby') || '').split(/\s+/).map(id => document.getElementById(id)?.textContent || '').join(' ').trim() ||
    Array.from(element.labels || []).map(label => label.textContent).join(' ') ||
    element.getAttribute('title') || element.getAttribute('placeholder') || element.innerText || element.textContent);
  const editable = element => !element.readOnly && enabled(element) &&
    (element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement || element.isContentEditable ||
      (element instanceof HTMLInputElement && ['text','search','url','tel','email','password','number'].includes(element.type)));
  const selectorFor = element => {
    if (element.id) return '#' + CSS.escape(element.id);
    for (const name of ['data-testid', 'data-test', 'name', 'aria-label']) {
      const value = element.getAttribute(name);
      if (value) return `[${name}="${CSS.escape(value)}"]`;
    }
    const parts = [];
    for (let current = element; current && current !== document.body; current = current.parentElement) {
      let part = current.tagName.toLowerCase();
      const siblings = Array.from(current.parentElement?.children || []).filter(child => child.tagName === current.tagName);
      if (siblings.length > 1) part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
      parts.unshift(part);
    }
    return parts.join(' > ') || element.tagName.toLowerCase();
  };
  const descriptor = element => {
    const rect = element.getBoundingClientRect();
    const tag = element.tagName.toLowerCase();
    const secret = element instanceof HTMLInputElement && element.type === 'password';
    return {
      index: idFor(element), id: element.id || element.getAttribute('data-testid') || null,
      selector: selectorFor(element),
      tag, type: element.getAttribute('type'),
      role: element.getAttribute('role') || ({button:'button',a:'link',textarea:'textbox',select:'combobox'}[tag]) ||
        (tag === 'input' ? (['checkbox','radio'].includes(element.type) ? element.type : 'textbox') : tag),
      label: label(element), text: element.innerText || element.textContent || '',
      value: secret ? null : ('value' in element ? element.value : null),
      enabled: enabled(element), visible: visible(element),
      rect: {x: rect.left, y: rect.top, width: rect.width, height: rect.height},
      actions: enabled(element) ? ['tap', ...(editable(element) ? ['type_text', 'clear_text'] : [])] : []
    };
  };
  const all = Array.from(document.querySelectorAll(selector));
  for (const [id, reference] of state.elements) if (!reference.deref()?.isConnected) state.elements.delete(id);
  if (action === 'snapshot') return {
    url: location.href, title: document.title, viewport: {width: innerWidth, height: innerHeight},
    elements: all.filter(visible).map(descriptor)
  };
  const findTarget = () => {
    if (action === 'tap_point') return document.elementFromPoint(x, y);
    if (action === 'tap_text') return all.find(element => visible(element) && label(element).toLowerCase() === normalize(target).toLowerCase());
    if (!target) return null;
    if (/^index:\d+$/.test(target)) return state.elements.get(Number(target.slice(6)))?.deref();
    const byId = document.getElementById(target) || all.find(element => element.getAttribute('data-testid') === target || element.getAttribute('data-test') === target);
    if (byId) return byId;
    try { return document.querySelector(target); } catch (_) { return null; }
  };
  let element = findTarget();
  if (action === 'tap_point') element = element?.closest(selector) || element;
  const failure = error => ({success: false, action, error});
  if (!element?.isConnected) return failure('target_not_found');
  if (!visible(element)) return failure('target_not_visible');
  if (!enabled(element)) return failure('target_disabled');
  if (action === 'type_text' || action === 'clear_text') {
    if (!editable(element)) return failure('target_not_editable');
    element.focus();
    const input = action === 'clear_text' ? '' : text;
    if (element.isContentEditable) {
      element.textContent = action === 'clear_text' ? '' : element.textContent + input;
    } else {
      const previous = element.value;
      let next = action === 'clear_text' ? '' : previous + input;
      if (element instanceof HTMLSelectElement) {
        next = input;
        if (!Array.from(element.options).some(option => option.value === next && !option.disabled)) return failure('option_not_found');
      } else if (action !== 'clear_text' && typeof element.selectionStart === 'number') {
        next = previous.slice(0, element.selectionStart) + input + previous.slice(element.selectionEnd);
      }
      // Bypass framework-installed own value setters (notably React's tracker).
      const prototype = element instanceof HTMLInputElement ? HTMLInputElement.prototype :
        element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLSelectElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(element, next);
      if (element.value !== next) return failure('value_rejected');
    }
    element.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: action === 'clear_text' ? 'deleteContentBackward' : 'insertText', data: input}));
    element.dispatchEvent(new Event('change', {bubbles: true}));
  } else {
    if (action !== 'tap_point') element.scrollIntoView({block:'center',inline:'center'});
    const rect = element.getBoundingClientRect();
    const clientX = action === 'tap_point' ? x : rect.left + rect.width / 2;
    const clientY = action === 'tap_point' ? y : rect.top + rect.height / 2;
    const hit = document.elementFromPoint(clientX, clientY);
    if (!hit || (hit !== element && !element.contains(hit))) return failure('target_obscured');
    element.focus();
    for (const type of ['pointerdown','mousedown','pointerup','mouseup','click']) {
      const EventType = type.startsWith('pointer') ? PointerEvent : MouseEvent;
      element.dispatchEvent(new EventType(type, {bubbles:true,cancelable:true,clientX,clientY,button:0,pointerId:1,pointerType:'mouse',isPrimary:true}));
    }
  }
  return {success:true,action,element:descriptor(element)};
}
