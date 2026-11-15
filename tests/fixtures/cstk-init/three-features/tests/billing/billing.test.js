const test = require('node:test');
const assert = require('node:assert');
const { total } = require('../../src/billing/index.js');

test('billing exports total', () => {
  assert.strictEqual(typeof total, 'function');
});
