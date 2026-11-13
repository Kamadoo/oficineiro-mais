const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const Contas = carregar(['base.js', 'contas.js']).FSM_CONTAS;

test('CPF válido e inválido', () => {
  assert.equal(Contas.documentoValido('529.982.247-25'), true);
  assert.equal(Contas.documentoValido('11144477735'), true);
  assert.equal(Contas.documentoValido('529.982.247-24'), false);
  assert.equal(Contas.documentoValido('111.111.111-11'), false);
  assert.equal(Contas.documentoValido('123'), false);
  assert.equal(Contas.documentoValido(''), false);
});

test('CNPJ válido e inválido', () => {
  assert.equal(Contas.documentoValido('11.222.333/0001-81'), true);
  assert.equal(Contas.documentoValido('11.222.333/0001-82'), false);
  assert.equal(Contas.documentoValido('00000000000000'), false);
});

test('documento mascarado', () => {
  assert.equal(Contas.documentoMascarado('529.982.247-25'), '***.982.247-**');
  assert.equal(Contas.documentoMascarado('11222333000181'), '**.***.333/0001-**');
  assert.equal(Contas.documentoMascarado('123'), 'inválido');
  assert.equal(Contas.documentoMascarado(''), '—');
});

test('detalhamento do lote de contas', () => {
  const nomes = { oficineiro: 'Oficineiro de Inclusão Digital' };
  const lote = {
    arquivo: 'lote.xlsx',
    linhas: [
      {
        n: 2,
        st: 'pronta',
        nome: 'Pessoa Um',
        email: 'um@exemplo.test',
        cpf: '52998224725',
        papel: 'oficineiro',
        escola: { sigla: 'Ebv' }
      },
      { n: 3, st: 'erro', erro: 'CPF inválido', nome: 'Pessoa Dois', papel: 'oficineiro' }
    ]
  };
  const detalhe = Contas.detalharLote(lote, nomes);
  assert.equal(detalhe.temArquivo, true);
  assert.equal(detalhe.resumo, 'lote.xlsx · 2 pessoas · 1 pronta · 1 com problema');
  assert.equal(detalhe.linhas[0].documento, '***.982.247-**');
  assert.equal(detalhe.linhas[0].vinculo, 'Ebv');
  assert.equal(detalhe.linhas[0].perfil, 'Oficineiro de Inclusão Digital');
  assert.equal(detalhe.linhas[1].situacao, 'CPF inválido');
  assert.equal(detalhe.botao, 'Criar 1 conta');
  assert.equal(detalhe.podeCriar, true);
  assert.equal(Contas.detalharLote(null, nomes).temArquivo, false);
});
