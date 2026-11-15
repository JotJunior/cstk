const test = require('node:test');
const assert = require('node:assert');
const { format } = require('../../src/notifications/index.js');

test('notifications exports format', () => {
  assert.strictEqual(typeof format, 'function');
});
