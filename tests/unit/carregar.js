const fs = require('fs');
const path = require('path');
const vm = require('vm');

const LIB = path.resolve(__dirname, '..', '..', 'src', 'lib');

function carregar(arquivos, extras = {}) {
  const armazenado = {};
  const localStorage = {
    getItem: chave => (chave in armazenado ? armazenado[chave] : null),
    setItem: (chave, valor) => (armazenado[chave] = String(valor)),
    removeItem: chave => delete armazenado[chave]
  };
  const window = { localStorage, ...extras };
  const contexto = vm.createContext({
    window,
    localStorage,
    console,
    Date,
    Intl,
    Blob,
    TextEncoder,
    TextDecoder,
    DecompressionStream
  });
  for (const arquivo of arquivos) {
    vm.runInContext(fs.readFileSync(path.join(LIB, arquivo), 'utf8'), contexto, { filename: arquivo });
  }
  return window;
}

module.exports = { carregar };
