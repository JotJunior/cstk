import { defineConfig } from 'vitest/config';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  // Alias '@' do app web: componentes importam '@/lib/...'; sem isto o vitest
  // (config raiz) nao resolve o caminho e a suite do componente falha ao carregar.
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './apps/web/src'),
    },
  },
  test: {
    globals: true,
    environment: 'node',
    // Suite completa: shared-types (unitarios/paridade) + server (integracao)
    include: [
      'packages/**/*.test.ts',
      'packages/**/*.spec.ts',
      'apps/server/test/**/*.test.ts',
      'apps/server/src/**/*.test.ts',
      'apps/web/src/**/*.test.ts',
    ],
    // Timeout maior para testes de integracao com DB real
    testTimeout: 15000,
    coverage: {
      reporter: ['text', 'json'],
    },
  },
});
