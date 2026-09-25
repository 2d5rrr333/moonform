// Headless browser verification for web/self-test.html and
// web/wizard-self-test.html. Serves web/ statically, runs Edge headless
// with --dump-dom per page, waits for the #test-summary marker, asserts
// each harness output.
// Usage: node headless-verify.cjs
const path = require('node:path');
const {
  serveStatic,
  runChromium,
} = require('./headless.cjs');

const ROOT = path.join(__dirname, '..', 'web');
const PROFILE_ROOT = path.join(__dirname, '..', '.edge-profile');
const PORT = 8941;

async function dumpPage(site, page) {
  return runChromium({
    args: ['--dump-dom', site.url + page],
    profileRoot: PROFILE_ROOT,
    waitMarker: 'test-summary',
    timeoutMs: 60000,
  });
}

function parseSummary(dom) {
  const m = dom.match(/<pre id="test-summary">([\s\S]*?)<\/pre>/);
  if (!m) {
    return null;
  }
  const text = m[1]
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
  console.log(text);
  const kv = {};
  for (const l of text.split('\n').map((l) => l.trim()).filter(Boolean)) {
    const eq = l.indexOf('=');
    if (eq > 0) kv[l.slice(0, eq)] = l.slice(eq + 1);
  }
  return kv;
}

function report(checks) {
  let failed = 0;
  for (const [name, ok] of checks) {
    console.log((ok ? 'PASS ' : 'FAIL ') + name);
    if (!ok) failed++;
  }
  return failed;
}

(async () => {
  const site = await serveStatic(ROOT, PORT);
  let totalFailed = 0;
  try {
    // -- login demo --------------------------------------------------------
    const loginKv = parseSummary(await dumpPage(site, 'self-test.html'));
    if (!loginKv) {
      console.error('FAIL: no login test summary in DOM');
      totalFailed++;
    } else {
      totalFailed += report([
        ['login: form rendered', loginKv['H2'] === 'Sign in'],
        ['login: invalid input shows errors', Number(loginKv['INVALID_COUNT']) > 0],
        ['login: errors mention email format', /email/i.test(loginKv['INVALID_ERRS'] || '')],
        ['login: valid input clears errors', loginKv['VALID_ERRS'] === '[]'],
        ['login: submit success message', /^Welcome, user@example\.com!$/.test(loginKv['OK'] || '')],
      ]);
    }

    // -- wizard demo -------------------------------------------------------
    const wizKv = parseSummary(await dumpPage(site, 'wizard-self-test.html'));
    if (!wizKv) {
      console.error('FAIL: no wizard test summary in DOM');
      totalFailed++;
    } else {
      totalFailed += report([
        ['wizard: step 1 rendered', wizKv['STEP1'] === 'Create your account'],
        ['wizard: schema errors distribute to fields', Number(wizKv['S1_INVALID_COUNT']) >= 2],
        ['wizard: Next blocked while group invalid', wizKv['AFTER_NEXT_INVALID'] === 'Create your account'],
        ['wizard: fixed values clear errors', wizKv['S1_VALID_ERRS'] === '[]'],
        ['wizard: Next advances to step 2', wizKv['STEP2'] === 'Your profile'],
        ['wizard: empty nickname gives group error', (wizKv['S2_GROUP_ERRS'] || '').includes('Nickname is required')],
        ['wizard: Finish blocked by group error', wizKv['S2_STILL'] === 'Your profile'],
        ['wizard: short nickname gives field error', (wizKv['S2_FIELD_ERRS'] || '').includes('3+ characters')],
        ['wizard: Finish submits the whole form', /^Done, moon!$/.test(wizKv['OK'] || '')],
      ]);
    }

    console.log(
      totalFailed === 0
        ? 'ALL 14 BROWSER CHECKS PASSED'
        : `${totalFailed} CHECKS FAILED`
    );
    process.exit(totalFailed === 0 ? 0 : 1);
  } finally {
    site.close();
  }
})().catch((e) => {
  console.error('FAIL', e);
  process.exit(1);
});
