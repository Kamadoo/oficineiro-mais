const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');
const { entradas, montar, arquivo } = require('./zip');

const janela = carregar(['planilha.js', 'onboarding.js']);
const Planilha = janela.FSM_PLANILHA;
const Onb = janela.FSM_ONB;

async function xlsx(nome, linhas, aba, compactar) {
  const bytes = new Uint8Array(await Planilha.gerar(linhas, aba).arrayBuffer());
  return arquivo(nome, compactar ? montar(entradas(bytes)) : bytes);
}

const ESCOLAS = [
  { sig: 'Ebv', n: 'Ebv - Cei Bem-te-vi', cs: 'CS1' },
  { sig: 'Ejp', n: 'Ejp - E. M. Jardim dos Ipês', cs: 'CS1' },
  { sig: 'Ecl', n: 'Ecl - E. M. Colina Azul', cs: 'CS2' },
  { sig: 'NTE', n: 'NTE - Núcleo de Tecnologia', cs: 'AT1' }
];

test('reconhece a escola pela sigla', () => {
  assert.deepEqual(
    { ...Onb.matchEscola('EJP - qualquer nome', ESCOLAS) },
    {
      sig: 'Ejp',
      n: 'Ejp - E. M. Jardim dos Ipês',
      cs: 'CS1',
      conf: 'sigla'
    }
  );
});

test('reconhece a escola pelo nome, sem acentos e sem palavras comuns', () => {
  const r = Onb.matchEscola('Escola Municipal Jardim dos Ipes', ESCOLAS);
  assert.equal(r.sig, 'Ejp');
  assert.equal(r.conf, 'nome');
  assert.equal(Onb.matchEscola('Colina Azul', ESCOLAS).sig, 'Ecl');
});

test('não inventa escola quando o nome não bate', () => {
  assert.equal(Onb.matchEscola('Escola Municipal Horizonte', ESCOLAS), null);
  assert.equal(Onb.matchEscola('', ESCOLAS), null);
});

test('núcleo de tecnologia cai no NTE', () => {
  assert.equal(Onb.matchEscola('Nucleo de Tecnologia Educacional', ESCOLAS).sig, 'NTE');
});

test('lê a planilha a partir da linha de cabeçalho', async () => {
  const f = await xlsx('lote.xlsx', [
    ['Lote de contas'],
    [],
    ['Nome', 'E-mail', 'Lotação'],
    ['Pessoa Um', 'um@exemplo.test', 'Ebv - Cei Bem-te-vi'],
    [],
    ['Pessoa & Dois', 'dois@exemplo.test', '<Ejp>']
  ]);
  const r = await Onb.lerPlanilha(f);
  assert.deepEqual([...r.colunas], ['nome', 'e mail', 'lotacao']);
  assert.equal(r.linhas.length, 2);
  assert.deepEqual({ ...r.linhas[1] }, { nome: 'Pessoa & Dois', 'e mail': 'dois@exemplo.test', lotacao: '<Ejp>' });
});

test('lê planilha compactada (deflate)', async () => {
  const f = await xlsx(
    'lote.xlsx',
    [
      ['Nome', 'Cargo'],
      ['Pessoa Um', 'Professora']
    ],
    'Planilha',
    true
  );
  const r = await Onb.lerPlanilha(f);
  assert.deepEqual({ ...r.linhas[0] }, { nome: 'Pessoa Um', cargo: 'Professora' });
});

test('lê a OS: número, secretaria e colunas pelo cabeçalho', async () => {
  const f = await xlsx(
    'OS 12.xlsx',
    [
      ['Ordem de serviço Nº 0034 · SEMSA'],
      [],
      ['SEQ', 'TIPO', 'NOME DO USUÁRIO', 'E-MAIL', 'LOGIN', 'MATRÍCULA', 'LOTAÇÃO', 'CARGO'],
      ['1', 'Inclusão', 'Pessoa   Um', 'UM@Exemplo.Test', 'pum', '123', 'Ebv  -  Cei', 'Professor'],
      ['2', 'Inclusão', '', 'sem@exemplo.test', '', '', '', '']
    ],
    'Usuários ativos'
  );
  const os = await Onb.lerOS(f);
  assert.equal(os.num, '34');
  assert.equal(os.sec, 'SEMSA');
  assert.equal(os.arquivo, 'OS 12.xlsx');
  assert.equal(os.rows.length, 1);
  assert.deepEqual(
    { ...os.rows[0] },
    {
      seq: '1',
      tipo: 'Inclusão',
      nome: 'Pessoa Um',
      email: 'um@exemplo.test',
      login: 'pum',
      matricula: '123',
      lotacao: 'Ebv - Cei',
      cargo: 'Professor'
    }
  );
});

test('OS sem número no título usa o nome do arquivo e SEMED por padrão', async () => {
  const f = await xlsx('OS 007.xlsx', [['Lista'], ['NOME DO USUÁRIO', 'LOTAÇÃO'], ['Pessoa', 'Ecl']], 'Ativos');
  const os = await Onb.lerOS(f);
  assert.equal(os.num, '7');
  assert.equal(os.sec, 'SEMED');
});

test('OS sem cabeçalho é recusada', async () => {
  const f = await xlsx(
    'OS 1.xlsx',
    [
      ['Nome', 'Lotação'],
      ['Pessoa', 'Ecl']
    ],
    'Ativos'
  );
  await assert.rejects(Onb.lerOS(f), /NOME DO USUÁRIO/);
});

test('recusa arquivo que não é xlsx, grande demais ou corrompido', async () => {
  const bytes = new Uint8Array([1, 2, 3]);
  await assert.rejects(Onb.lerPlanilha(arquivo('lote.csv', bytes)), /envie a planilha em \.xlsx/);
  await assert.rejects(
    Onb.lerPlanilha({ name: 'lote.xlsx', size: 6 * 1024 * 1024, arrayBuffer: async () => bytes.buffer }),
    /5 MB/
  );
  await assert.rejects(Onb.lerPlanilha(arquivo('lote.xlsx', bytes)), /não é um \.xlsx/);
  await assert.rejects(Onb.lerPlanilha(arquivo('lote.xlsx', montar({ 'a.txt': 'x' }))), /não é uma planilha do Excel/);
});

test('recusa conteúdo descompactado grande demais', async () => {
  const enorme = '<x>' + 'a'.repeat(31 * 1024 * 1024) + '</x>';
  const f = arquivo(
    'lote.xlsx',
    montar({ 'xl/workbook.xml': enorme, 'xl/_rels/workbook.xml.rels': '<Relationships/>' })
  );
  await assert.rejects(Onb.lerPlanilha(f), /descompactado grande demais/);
});

test('planilha vazia é recusada', async () => {
  const f = await xlsx('lote.xlsx', [['só uma coluna'], ['outra']]);
  await assert.rejects(Onb.lerPlanilha(f), /vazia/);
});
