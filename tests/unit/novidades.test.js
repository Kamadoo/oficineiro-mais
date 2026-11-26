const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const N = carregar(['novidades.js']).FSM_NOVIDADES;
const PERFIS = ['administrador', 'gerente', 'coordenador', 'analista', 'direcao', 'oficineiro'];

test('cada novidade tem número único, data, perfis conhecidos e texto curto', () => {
  const ids = N.lista.map(n => n.id);
  assert.equal(new Set(ids).size, ids.length);
  ids.forEach((id, i) => assert.ok(i === 0 || id > ids[i - 1], 'números em ordem crescente'));
  for (const n of N.lista) {
    assert.match(n.data, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(n.perfis.length > 0);
    n.perfis.forEach(p => assert.ok(PERFIS.includes(p), p));
    assert.ok(n.texto.length > 10 && n.texto.length <= 200, n.texto);
  }
  assert.equal(N.ultima(), Math.max(...ids));
});

test('cada perfil começa com pelo menos cinco novidades próprias', () => {
  for (const p of PERFIS) {
    const proprias = N.paraPerfil(p, 0).filter(n => !n.para);
    assert.ok(proprias.length >= 5, p + ': ' + proprias.length);
  }
});

test('cargo acima recebe as novidades dele e as dos cargos abaixo', () => {
  const ids = p => N.paraPerfil(p, 0).map(n => n.id);
  const contem = (maior, menor) => ids(menor).every(id => ids(maior).includes(id));
  assert.ok(contem('gerente', 'coordenador'));
  assert.ok(contem('coordenador', 'analista'));
  assert.ok(contem('coordenador', 'direcao'));
  assert.ok(contem('analista', 'oficineiro'));
  assert.equal(ids('administrador').length, N.lista.length);
  const soAdmin = N.lista.filter(n => n.perfis.length === 1 && n.perfis[0] === 'administrador').map(n => n.id);
  assert.ok(soAdmin.length > 0);
  soAdmin.forEach(id => assert.ok(!ids('gerente').includes(id)));
  assert.ok(!contem('analista', 'direcao'));
  assert.ok(!contem('direcao', 'oficineiro'));
});

test('novidade de perfil abaixo indica a quem se refere', () => {
  const ger = N.paraPerfil('gerente', 0);
  const doOficineiro = ger.find(n => N.lista.find(x => x.id === n.id).perfis.join() === 'oficineiro');
  assert.equal(doOficineiro.para, 'Oficineiro');
  const propria = ger.find(n => N.lista.find(x => x.id === n.id).perfis.includes('gerente'));
  assert.equal(propria.para, '');
});

test('mostra só o que veio depois da última vista, da mais nova para a mais antiga', () => {
  const todas = N.paraPerfil('oficineiro', 0);
  assert.ok(todas[0].id > todas[todas.length - 1].id);
  assert.match(todas[0].data, /^\d{2}\/\d{2}\/\d{4}$/);
  assert.equal(N.paraPerfil('oficineiro', N.ultima()).length, 0);
  const meio = todas[2].id;
  assert.ok(N.paraPerfil('oficineiro', meio).every(n => n.id > meio));
  assert.equal(N.paraPerfil('visitante', 0).length, 0);
});
