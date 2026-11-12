// Requires Playwright: npm install --no-save --package-lock=false playwright
// dart run tool/export_dom_checks.dart dom-checks.json
// node tool/verify_dom.cjs dom-checks.json
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
(async () => {
  const scripts = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  let count = 0;
  try {
    const page = await browser.newPage();
    await page.setContent(`<h1>Fixture</h1><form><input id="input" data-test="input"><input id="readonly" readonly value="keep">
      <button type="button" id="button" onclick="this.textContent='Clicked'">Submit</button><button id="disabled" disabled>Disabled</button>
      <select id="select"><option value="a">A</option><option value="b">B</option></select>
      <input type="checkbox" id="checkbox"><input type="radio" id="radio" checked></form>
      <a href="https://example.test">Link</a><table><tr><th>Heading</th></tr><tr><td>Value</td></tr></table>
      <div style="height:2000px"></div><button id="bottom">Bottom</button>`);
    async function run(name, error = false) {
      const result = JSON.parse(await page.evaluate(scripts[name]));
      assert.equal(Boolean(result.error), error, `${name}: ${JSON.stringify(result)}`);
      count++;
      return result;
    }
    for (const name of ['missingRoot', 'disabledClick', 'readonly', 'wrongType', 'missingOption', 'untoggleRadio', 'wrongToggle']) await run(name, true);
    await run('type');
    assert.equal(await page.inputValue('#input'), "linequote'\\end"); // single-line input strips newline
    await run('select'); assert.equal(await page.inputValue('#select'), 'b');
    await run('toggle'); assert.equal(await page.isChecked('#checkbox'), true);
    const forms = await run('forms');
    const input = forms.forms[0].fields.find(field => field.id === 'input');
    assert.equal(await page.locator(input.selector).count(), 1);
    for (const name of ['tree','interactive','query','text','find','links','headings','images','tables','summary']) await run(name);
    await run('click'); assert.equal(await page.textContent('#button'), 'Clicked');
    const scroll = await run('scroll');
    assert(scroll.rect.y >= 0 && scroll.rect.y < 720, 'scroll returned stale coordinates');
    console.log(JSON.stringify({ passed: true, checks: count, engine: 'Chrome', scope: 'Flutter DOM payloads; not a native WebView backend' }));
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
