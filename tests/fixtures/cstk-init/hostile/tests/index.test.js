const test = require('node:test');
const assert = require('node:assert');
const { add } = require('../src/index.js');

test('add sums two numbers', () => {
  assert.strictEqual(add(1, 2), 3);
});
