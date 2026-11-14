const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');
const { entradas } = require('./zip');

const Planilha = carregar(['planilha.js']).FSM_PLANILHA;

async function gerar(linhas, aba) {
  const blob = Planilha.gerar(linhas, aba);
  return entradas(new Uint8Array(await blob.arrayBuffer()));
}

test('gera um pacote xlsx com as partes obrigatórias', async () => {
  const partes = await gerar(
    [
      ['Nome', 'Total'],
      ['Escola A', 3]
    ],
    'Resumo'
  );
  assert.deepEqual(Object.keys(partes).sort(), [
    '[Content_Types].xml',
    '_rels/.rels',
    'xl/_rels/workbook.xml.rels',
    'xl/styles.xml',
    'xl/workbook.xml',
    'xl/worksheets/sheet1.xml'
  ]);
  assert.match(partes['xl/workbook.xml'], /<sheet name="Resumo" sheetId="1"/);
});

test('números viram células numéricas e textos viram texto', async () => {
  const folha = (
    await gerar([
      ['Nome', 'Total'],
      ['Escola A', 3],
      ['Escola B', '12'],
      ['Código', '007']
    ])
  )['xl/worksheets/sheet1.xml'];
  assert.match(folha, /<c r="B2" s="2"><v>3<\/v><\/c>/);
  assert.match(folha, /<c r="B3" s="3"><v>12<\/v><\/c>/);
  assert.match(folha, /<c r="B4" s="2" t="inlineStr"><is><t xml:space="preserve">007<\/t>/);
  assert.match(folha, /<c r="A1" s="1" t="inlineStr"><is><t xml:space="preserve">Nome<\/t>/);
});

test('escapa caracteres especiais e remove os de controle', async () => {
  const folha = (
    await gerar([
      ['A', 'B'],
      ['<b>"x" & y</b>', 'a\u0001b']
    ])
  )['xl/worksheets/sheet1.xml'];
  assert.match(folha, /&lt;b&gt;&quot;x&quot; &amp; y&lt;\/b&gt;/);
  assert.match(folha, />ab<\/t>/);
  assert.doesNotMatch(folha, /<b>/);
});

test('nomeia colunas além da Z', async () => {
  const linha = Array.from({ length: 28 }, (_, i) => 'c' + i);
  const folha = (await gerar([linha, linha]))['xl/worksheets/sheet1.xml'];
  assert.match(folha, /r="Z1"/);
  assert.match(folha, /r="AA1"/);
  assert.match(folha, /r="AB2"/);
});

test('título acima da tabela usa estilo de título', async () => {
  const folha = (await gerar([['Relatório de presença'], [], ['Nome', 'Dias'], ['Pessoa', 4]]))[
    'xl/worksheets/sheet1.xml'
  ];
  assert.match(folha, /<c r="A1" s="4" t="inlineStr">/);
  assert.match(folha, /<c r="A3" s="1" t="inlineStr">/);
});

test('o nome da aba é limpo e escapado', async () => {
  const partes = await gerar([['a', 'b']], 'Contas & "lote"');
  assert.match(partes['xl/workbook.xml'], /<sheet name="[^"<>]*&amp;[^"<>]*"/);
  assert.doesNotMatch(partes['xl/workbook.xml'], /name="[^"]*"lote/);
});
