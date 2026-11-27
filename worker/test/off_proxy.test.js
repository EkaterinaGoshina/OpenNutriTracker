import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { openFoodFactsTarget } from '../src/index.js';

const target = (path) =>
  openFoodFactsTarget(new URL(`https://app.example.com${path}`))?.toString() ?? null;

test('forwards the three endpoints the app uses, with their query', () => {
  assert.equal(
    target('/api/off/search.openfoodfacts.org/search?q=apple&page=1'),
    'https://search.openfoodfacts.org/search?q=apple&page=1',
  );
  assert.equal(
    target('/api/off/world.openfoodfacts.org/cgi/search.pl?search_terms=apple'),
    'https://world.openfoodfacts.org/cgi/search.pl?search_terms=apple',
  );
  assert.equal(
    target('/api/off/world.openfoodfacts.org/api/v2/product/737628064502?json=true'),
    'https://world.openfoodfacts.org/api/v2/product/737628064502?json=true',
  );
});

test('refuses anything else, so it is not an open proxy', () => {
  for (const path of [
    '/api/off/',
    '/api/off/evil.example.com/search',
    '/api/off/world.openfoodfacts.org/',
    '/api/off/world.openfoodfacts.org/cgi/product_jqm2.pl',
    '/api/off/world.openfoodfacts.org/api/v2/product/1/../../admin',
    '/api/off/search.openfoodfacts.org/search/extra',
    '/api/off/search.openfoodfacts.org@evil.example.com/search',
    '/api/off/constructor/search',
    '/api/off/__proto__/search',
  ]) {
    assert.equal(target(path), null, path);
  }
});

test('lets answers be cached and errors not', async (t) => {
  let status = 200;
  let sent;
  t.mock.method(globalThis, 'fetch', async (_target, init) => {
    sent = init;
    return new Response('{}', { status });
  });
  const ask = () =>
    worker.fetch(
      new Request('https://app.example.com/api/off/search.openfoodfacts.org/search?q=a'),
      {},
    );

  assert.equal((await ask()).headers.get('cache-control'), 'public, max-age=3600');
  assert.deepEqual(sent.cf.cacheTtlByStatus, { '200-299': 3600, '300-599': -1 });
  assert.equal(sent.cf.cacheTtl, undefined, 'cacheTtl would cache errors too');

  for (status of [404, 502, 503]) {
    const response = await ask();
    assert.equal(response.status, status);
    assert.equal(response.headers.get('cache-control'), 'no-store', `${status}`);
  }
});
