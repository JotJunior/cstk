const test = require('node:test');
const assert = require('node:assert');
const { list } = require('../../src/catalog/index.js');

test('catalog exports list', () => {
  assert.strictEqual(typeof list, 'function');
});
