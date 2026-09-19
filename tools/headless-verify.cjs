// Headless browser verification for web/self-test.html.
// Serves web/ statically, runs Edge headless with --dump-dom, waits for
// the #test-summary marker, asserts the harness output.
// Usage: node headless-verify.cjs
const path = require('node:path');
const {
  serveStatic,
  runChromium,
} = require('./headless.cjs');

const ROOT = path.join(__dirname, '..', 'web');
const PROFILE_ROOT = path.join(__dirname, '..', '.edge-profile');
const PORT = 8941;

(async () => {
  const site = await serveStatic(ROOT, PORT);
  try {
    const dom = await runChromium({
      args: ['--dump-dom', site.url + 'self-test.html'],
      profileRoot: PROFILE_ROOT,
      waitMarker: 'test-summary',
      timeoutMs: 60000,
    });
    const m = dom.match(/<pre id="test-summary">([\s\S]*?)<\/pre>/);
    if (!m) {
      console.error('FAIL: no test summary in DOM');
      process.exit(1);
    }
    const text = m[1]
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>');
    console.log(text);
    const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);
    const checks = [];
    const kv = {};
    for (const l of lines) {
      const eq = l.indexOf('=');
      if (eq > 0) kv[l.slice(0, eq)] = l.slice(eq + 1);
    }
    checks.push(['form rendered', kv['H2'] === 'Sign in']);
    checks.push(['invalid input shows errors', Number(kv['INVALID_COUNT']) > 0]);
    checks.push(['errors mention email format', /email/i.test(kv['INVALID_ERRS'] || '')]);
    checks.push(['valid input clears errors', kv['VALID_ERRS'] === '[]']);
    checks.push(['submit success message', /^Welcome, user@example\.com!$/.test(kv['OK'] || '')]);
    let failed = 0;
    for (const [name, ok] of checks) {
      console.log((ok ? 'PASS ' : 'FAIL ') + name);
      if (!ok) failed++;
    }
    console.log(
      failed === 0
        ? `ALL ${checks.length} BROWSER CHECKS PASSED`
        : `${failed} CHECKS FAILED`
    );
    process.exit(failed === 0 ? 0 : 1);
  } finally {
    site.close();
  }
})().catch((e) => {
  console.error('FAIL', e);
  process.exit(1);
});
