const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const P = carregar(['presenca-ajuda.js']).FSM_PRESENCA_AJUDA;

test('reconhece o aparelho pelo navegador', () => {
  assert.equal(P.aparelho({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130' }), 'windows');
  assert.equal(P.aparelho({ userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-A15) Chrome/130 Mobile' }), 'android');
  assert.equal(P.aparelho({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)' }), 'iphone');
  assert.equal(
    P.aparelho({
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      platform: 'MacIntel',
      maxTouchPoints: 5
    }),
    'iphone'
  );
  assert.equal(P.aparelho({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64)' }), 'computador');
  assert.equal(P.aparelho({ userAgentData: { platform: 'Windows' }, userAgent: '' }), 'windows');
  assert.equal(P.aparelho(undefined), 'computador');
});

test('só celular conta como aparelho com GPS', () => {
  assert.equal(P.temGps('android'), true);
  assert.equal(P.temGps('iphone'), true);
  assert.equal(P.temGps('windows'), false);
  assert.equal(P.temGps('computador'), false);
});

test('há passo a passo curto para cada aparelho e situação', () => {
  for (const situacao of ['bloqueada', 'aproximada', 'fora'])
    for (const tipo of ['windows', 'android', 'iphone', 'computador']) {
      const passos = P.passos(tipo, situacao);
      assert.ok(passos.length >= 3 && passos.length <= 7, situacao + ' ' + tipo);
      passos.forEach(p => assert.ok(p.length <= 170, p));
      assert.ok(P.titulo(situacao));
    }
  assert.equal(P.passos('windows', 'outra').length, 0);
});

test('no Windows o passo a passo cita as três chaves, o Wi-Fi e o F5', () => {
  const bloqueada = P.passos('windows', 'bloqueada').join(' '),
    aproximada = P.passos('windows', 'aproximada').join(' ');
  assert.match(bloqueada, /Privacidade e segurança > Localização/);
  assert.match(bloqueada, /aplicativos da área de trabalho/);
  assert.match(bloqueada, /F5/);
  assert.match(aproximada, /Wi-Fi/);
  assert.match(aproximada, /Atualizar local/);
});
