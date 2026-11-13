const js = require('@eslint/js');
const globals = require('globals');

module.exports = [
  {
    ignores: ['dist/**', 'node_modules/**', 'vendor/**', 'src/config.js', 'supabase/functions/**']
  },
  js.configs.recommended,
  {
    files: ['src/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'script',
      globals: { ...globals.browser, L: 'readonly', React: 'readonly' }
    },
    rules: {
      'no-empty': ['error', { allowEmptyCatch: true }],
      'no-unused-vars': ['error', { caughtErrors: 'none' }],
      'no-control-regex': 'off'
    }
  },
  {
    files: ['src/components/*.dc.js'],
    languageOptions: {
      globals: { DCLogic: 'readonly' }
    },
    rules: {
      'no-unused-vars': ['error', { caughtErrors: 'none', varsIgnorePattern: '^Component$' }]
    }
  },
  {
    files: ['eslint.config.js', 'scripts/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'commonjs',
      globals: globals.node
    }
  }
];
