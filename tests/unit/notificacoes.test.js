const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const N = carregar(['base.js', 'notificacoes.js']).FSM_NOTIF;

test('chave estável e diferente por aviso', () => {
  const aviso = { tit: 'Presença', txt: 'Sem encerramento' };
  assert.equal(N.chave(aviso), N.chave({ ...aviso }));
  assert.notEqual(N.chave(aviso), N.chave({ ...aviso, txt: 'Outro' }));
  assert.match(N.chave(aviso), /^[0-9a-z]{2,16}$/);
});

test('notificações lidas ficam guardadas por usuário', () => {
  N.gravar('u1', ['abc']);
  assert.deepEqual([...N.ler('u1')], ['abc']);
  assert.deepEqual([...N.ler('u2')], []);
});

test('sino marca notificações como lidas', () => {
  let aberturas = 0;
  const componente = { forceUpdate() {} };
  const avisos = [
    { tit: 'A', txt: '1' },
    { tit: 'B', txt: '2' }
  ];
  const abrir = () => aberturas++;
  let sino = N.sino(componente, 'analista', avisos, abrir);
  assert.equal(sino.notifN, '2');
  assert.equal(sino.temVariasNotif, true);
  sino.notifs[0].marcarLida();
  sino = N.sino(componente, 'analista', avisos, abrir);
  assert.equal(sino.notifN, '1');
  sino.lerTodasNotif();
  sino = N.sino(componente, 'analista', avisos, abrir);
  assert.equal(sino.semNotif, true);
  assert.equal(sino.notifAria, 'Notificações: nenhuma nova');
  sino.abrirNotif();
  assert.equal(aberturas, 1);
});
