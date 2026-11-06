import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openFoodFactsTarget } from '../src/index.js';

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
