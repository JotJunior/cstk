import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    // Integration tests use real knowledge.db (read-only, no mocks)
    include: ['test/**/*.test.ts', 'src/**/*.test.ts'],
    // Do NOT mock the SQLite DB — tests run against fixture or real DB (read-only)
    testTimeout: 10000,
  },
});
