const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const Base = carregar(['base.js']).FSM_BASE;
const data = (ano, mes, dia) => new Date(ano, mes - 1, dia);

test('datas no formato brasileiro', () => {
  assert.equal(Base.dmIso('2026-03-09'), '09/03');
  assert.equal(Base.dmIso(''), '');
  assert.equal(Base.dmIso(null), '');
  assert.equal(Base.dmyIso('2026-03-09'), '09/03/2026');
  assert.equal(Base.dmyIso(''), '');
  assert.equal(Base.iso(data(2026, 1, 5)), '2026-01-05');
  assert.equal(Base.iso(Base.add(data(2026, 1, 31), 1)), '2026-02-01');
});

test('horas e durações', () => {
  assert.equal(Base.hm(65), '01:05');
  assert.equal(Base.dur(480), '8h00');
  assert.equal(Base.minDeHora('07:30'), 450);
  assert.equal(Base.minDeHora('10'), 600);
});

test('presença fechada só com saída e sem pausa em aberto', () => {
  assert.equal(Base.presencaFechada({ fim: null }), false);
  assert.equal(Base.presencaFechada({ fim: '2026-03-09T17:00:00Z' }), true);
  assert.equal(Base.presencaFechada({ fim: 'x', pausa_inicio: 'y', pausa_fim: null }), false);
  assert.equal(Base.presencaFechada({ fim: 'x', pausa_inicio: 'y', pausa_fim: 'z' }), true);
});

test('minutos válidos limitados ao dia de trabalho', () => {
  assert.equal(Base.MINUTOS_DO_DIA, 480);
  assert.equal(Base.minutosValidos({ fim: 'x', trabalhado_min: 300 }), 300);
  assert.equal(Base.minutosValidos({ fim: 'x', trabalhado_min: 600 }), 480);
  assert.equal(Base.minutosValidos({ fim: null, trabalhado_min: 300 }), 0);
  assert.equal(Base.minutosValidos({ fim: 'x', trabalhado_min: 300 }, 200), 200);
  assert.equal(Base.minutosValidos({ fim: 'x' }, null), 0);
});

test('ciclo mensal para CPF e do dia 21 para os demais', () => {
  assert.equal(Base.cicloDe('CPF'), 'mensal');
  assert.equal(Base.cicloDe('CPF', 'oficineiro'), 'mensal');
  assert.equal(Base.cicloDe('CPF', 'analista'), 'dia21');
  assert.equal(Base.cicloDe('CNPJ'), 'dia21');
  const marco = data(2026, 3, 1);
  assert.equal(Base.iso(Base.cicloIni(marco, 'dia21')), '2026-02-21');
  assert.equal(Base.iso(Base.cicloFim(marco, 'dia21')), '2026-03-20');
  assert.equal(Base.iso(Base.cicloIni(marco, 'mensal')), '2026-03-01');
  assert.equal(Base.iso(Base.cicloFim(marco, 'mensal')), '2026-03-31');
});

test('feriados e dias letivos', () => {
  assert.equal(Base.feriado(data(2026, 4, 21)), 'Tiradentes');
  assert.equal(Base.feriado(data(2026, 4, 22)), '');
  assert.equal(Base.letivo(data(2026, 4, 21)), false);
  assert.equal(Base.letivo(data(2026, 4, 25)), false);
  assert.equal(Base.letivo(data(2026, 4, 22)), true);
  assert.equal(Base.iso(Base.nextLetivo(data(2026, 4, 24))), '2026-04-27');
});

test('textos, números e plural', () => {
  assert.equal(Base.normTxt('Ação Educação'), 'acao educacao');
  assert.equal(Base.numero(1234), '1.234');
  assert.equal(Base.plural(1, 'conta', 'contas'), '1 conta');
  assert.equal(Base.plural(2, 'conta', 'contas'), '2 contas');
});

test('escolher copia só as chaves pedidas', () => {
  assert.deepEqual({ ...Base.escolher({ a: 1, b: 2, c: 3 }, ['a', 'c', 'd']) }, { a: 1, c: 3, d: undefined });
});
