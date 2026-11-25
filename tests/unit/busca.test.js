const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

function janela(respostas) {
  const chamadas = [];
  const fetch = (entrada, opcoes) => {
    chamadas.push([entrada, opcoes && opcoes.cache]);
    return Promise.resolve({ status: respostas.shift() });
  };
  const w = carregar(['busca.js'], {
    fetch,
    URL,
    location: { href: 'https://site.test/', origin: 'https://site.test' }
  });
  return { w, chamadas };
}

test('arquivo publicado que volta 404 é buscado de novo direto no servidor', async () => {
  const { w, chamadas } = janela([404, 200]);
  const resposta = await w.fetch('./a/coordenador.abc123.dc.html');
  assert.equal(resposta.status, 200);
  assert.deepEqual(chamadas, [
    ['./a/coordenador.abc123.dc.html', undefined],
    ['./a/coordenador.abc123.dc.html', 'reload']
  ]);
});

test('respostas normais, outros endereços e envios não são repetidos', async () => {
  const ok = janela([200]);
  assert.equal((await ok.w.fetch('./a/base.abc.js')).status, 200);
  assert.equal(ok.chamadas.length, 1);

  const fora = janela([404]);
  assert.equal((await fora.w.fetch('https://outro.test/a/x.js')).status, 404);
  assert.equal((await fora.w.fetch('/rest/v1/rpc/x')).status, undefined);
  assert.equal(fora.chamadas.length, 2);

  const envio = janela([404]);
  assert.equal((await envio.w.fetch('./a/x.js', { method: 'POST' })).status, 404);
  assert.equal(envio.chamadas.length, 1);
});
