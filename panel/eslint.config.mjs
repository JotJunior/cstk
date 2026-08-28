// ESLint flat config (ESLint 9) — proibe dangerouslySetInnerHTML e innerHTML
// Ref: spec.md FR-001 (read-only), plan.md §Constitution Check (Principio V)
// Verbos SQL de mutacao sao checados pelo script `lint:readonly-check` (grep),
// pois strings SQL nao sao parseadas pelo AST do ESLint de forma confiavel.
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';

export default tseslint.config(
  // Substitui o antigo ignorePatterns
  {
    ignores: ['**/dist/', '**/coverage/', '**/*.d.ts'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        ...globals.node,
        ...globals.browser,
      },
    },
    rules: {
      // Principio V — conteudo de agente e UNTRUSTED; nunca setar innerHTML
      'no-restricted-properties': [
        'error',
        {
          object: 'element',
          property: 'innerHTML',
          message:
            'Principio V: usar textContent. dangerouslySetInnerHTML/innerHTML proibido (XSS risk + UNTRUSTED content).',
        },
      ],
      // Proibir dangerouslySetInnerHTML em JSX
      'no-restricted-syntax': [
        'error',
        {
          selector: 'JSXAttribute[name.name="dangerouslySetInnerHTML"]',
          message:
            'Principio V: dangerouslySetInnerHTML proibido. Conteudo de agente e UNTRUSTED — renderizar via textContent/JSX text node.',
        },
      ],
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
    },
  },
  {
    // Arquivos de config CommonJS/JS — permitir require()
    files: ['**/*.cjs', '**/*.js'],
    rules: {
      '@typescript-eslint/no-require-imports': 'off',
    },
  },
);
