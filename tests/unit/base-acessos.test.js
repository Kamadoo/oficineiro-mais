const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');
const { arquivo } = require('./zip');

const janela = carregar(['planilha.js', 'onboarding.js', 'base-acessos.js']);
const Planilha = janela.FSM_PLANILHA;
const BA = janela.FSM_BASE_ACESSOS;

const js = valor => JSON.parse(JSON.stringify(valor));
const serial = iso => Math.round((Date.parse(iso) - Date.UTC(1899, 11, 30)) / 86400000);

async function xlsx(nome, linhas) {
  return arquivo(nome, new Uint8Array(await Planilha.gerar(linhas, 'Export').arrayBuffer()));
}

const ESCOLAS = [
  { id: 1, sigla: 'Ebv', nome: 'Ebv - Cei Bem-te-vi', carteira_id: 'CS1' },
  { id: 2, sigla: 'Ejp', nome: 'Ejp - E. M. Jardim dos Ipês', carteira_id: 'CS2' },
  { id: 3, sigla: 'Nte', nome: 'Nte - Núcleo de Tecnologia', carteira_id: null }
];
const CARTEIRAS = [{ id: 'CS1' }, { id: 'CS2' }, { id: 'AT1' }];
const RODAPE = ['Filtros aplicados:\nprojeto é Teste'];

async function planilhas() {
  return [
    await xlsx('Arlequins_Criados.xlsx', [
      [
        'login',
        'nome',
        'perfil',
        'categoria',
        'local',
        'email',
        'matricula',
        'turma',
        '__UltimaDataAcesso',
        'responsavel_turma'
      ],
      [
        'ALUNO.UM',
        'Aluno Um',
        'Aluno',
        'CS1',
        'Ebv - Cei Bem-te-vi',
        'um@exemplo.test',
        '1',
        '9º A',
        serial('2026-11-20'),
        'Prof Um'
      ],
      [
        'prof.dois',
        'Professor Dois',
        'Professor',
        'CS2',
        'E. M. Jardim dos Ipês',
        'dois@exemplo.test',
        '2',
        'Em branco',
        serial('2026-09-01'),
        'Em branco'
      ],
      [
        'serv.tres',
        'Servidor Tres',
        'Em branco',
        'AT1',
        'Secretaria de Teste',
        'tres@exemplo.test',
        '3',
        'Em branco',
        '',
        'Em branco'
      ],
      [
        'serv.quatro',
        'Servidor Quatro',
        'Servidor',
        'AT1',
        'Nte - Núcleo de Tecnologia',
        'q@exemplo.test',
        '4',
        'Em branco',
        serial('2026-11-10'),
        'Em branco'
      ],
      [
        'serv.cinco',
        'Servidor Cinco',
        'Servidor',
        'AT1',
        'Em branco',
        'c@exemplo.test',
        '5',
        'Em branco',
        '',
        'Em branco'
      ],
      ['', '', '', 'CS1'],
      RODAPE
    ]),
    await xlsx('Arlequins_Implementados.xlsx', [
      [
        'des_usu_login',
        'des_usu_nomecompleto',
        'des_usu_email',
        'primeira_data_acesso',
        'perfil',
        'categoria',
        'local'
      ],
      ['aluno.um', 'Aluno Um', 'um@exemplo.test', serial('2026-03-02'), 'Aluno', 'CS1', 'Ebv - Cei Bem-te-vi'],
      ['aluno.um', 'Aluno Um', 'um@exemplo.test', serial('2026-02-10'), 'Aluno', 'CS1', 'Ebv - Cei Bem-te-vi'],
      RODAPE
    ]),
    await xlsx('Dias_de_Acesso_por_Usuarios.xlsx', [
      [
        'des_usu_login',
        'des_usu_nomecompleto',
        'perfil',
        'categoria',
        'local',
        'PrimeiraDataAcesso_perfil',
        'UltimaDataAcesso_perfil',
        'Dias de Acesso'
      ],
      ['aluno.um', 'Aluno Um', 'Aluno', 'CS1', 'Ebv - Cei Bem-te-vi', serial('2026-02-12'), serial('2026-11-20'), 40],
      [
        'prof.dois',
        'Professor Dois',
        'Professor',
        'CS2',
        'E. M. Jardim dos Ipês',
        serial('2026-01-05'),
        serial('2026-09-01'),
        90
      ],
      RODAPE
    ]),
    await xlsx('Sem_Acesso_60 (1).xlsx', [
      [
        'des_cli_dominio_ad',
        'des_usu_login',
        'des_usu_nomecompleto',
        'perfil',
        'categoria',
        'local',
        'turma',
        'primeira_data_acesso',
        'ultima_data_acesso'
      ],
      [
        'dominio',
        'prof.dois',
        'Professor Dois',
        'Professor',
        'CS2',
        'E. M. Jardim dos Ipês',
        'Em branco',
        serial('2026-01-05'),
        serial('2026-09-01')
      ],
      RODAPE
    ])
  ];
}

test('reconhece cada planilha pelo cabeçalho e ignora o rodapé de filtros', async () => {
  const lidos = await BA.ler(await planilhas());
  assert.deepEqual(js(lidos.map(l => [l.mapa.tipo, l.mapa.faixa || 0, l.total])), [
    ['criados', 0, 5],
    ['implementados', 0, 2],
    ['dias', 0, 2],
    ['semAcesso', 60, 1]
  ]);
});

test('converte datas do Excel, texto e ISO', () => {
  assert.equal(BA.dataDe(String(serial('2026-11-21') + 0.5)), '2026-11-21');
  assert.equal(BA.dataDe('21/11/2026'), '2026-11-21');
  assert.equal(BA.dataDe('2026-11-21T00:00:00'), '2026-11-21');
  assert.equal(BA.dataDe('Em branco'), null);
});

test('consolida as pessoas, cruza pelo login e prepara as unidades', async () => {
  const lidos = await BA.ler(await planilhas());
  const c = await BA.consolidar(lidos, { escolas: ESCOLAS, carteiras: CARTEIRAS, baseRef: '2026-11-21' });
  assert.equal(c.resumo.pessoas, 5);
  assert.equal(c.resumo.alunos, 1);
  assert.equal(c.resumo.comDias, 2);
  assert.equal(c.resumo.ultimoAcesso, '2026-11-20');
  assert.equal(c.depoisDaBase, 0);
  assert.deepEqual(js(c.novas.map(u => [u.nome, u.carteira])), [
    ['Secretaria de Teste', 'AT1'],
    ['Unidade não informada AT1', 'AT1']
  ]);
  assert.deepEqual(js(c.ganhamCarteira.map(u => [u.escola, u.carteira])), [[3, 'AT1']]);
  assert.ok(c.avisos.some(a => /perfil em branco/.test(a)));
  const um = c.validas.find(l => l.login === 'aluno.um').registro;
  assert.deepEqual(js(um), {
    nome: 'Aluno Um',
    tipo: 'A',
    carteira: 'CS1',
    turma: '9º A',
    ano: 9,
    responsavel: 'Prof Um',
    primeiro: '2026-02-10',
    ultimo: '2026-11-20',
    dias: 40
  });
  const sem60 = c.conferencias.find(x => x.tipo === 'semAcesso');
  assert.equal(sem60.conferem, 1);
});

test('o envio leva só o resumo do login e nada de e-mail ou matrícula', async () => {
  const lidos = await BA.ler(await planilhas());
  const c = await BA.consolidar(lidos, { escolas: ESCOLAS, carteiras: CARTEIRAS, baseRef: '2026-11-21' });
  const envio = await BA.montarEnvio(c);
  const texto = JSON.stringify(envio);
  assert.ok(!/exemplo\.test|aluno\.um|prof\.dois/i.test(texto));
  assert.equal(envio.pessoas.length, 5);
  assert.equal(envio.pessoas[0].h, await BA.resumoDoLogin(' Aluno.Um '));
  assert.match(envio.pessoas[0].h, /^[0-9a-f]{64}$/);
  assert.equal(envio.pessoas[0].escola, 1);
  assert.equal(envio.pessoas.find(p => p.unidade === 'Secretaria de Teste').tipo, 'S');
  assert.deepEqual(js(envio.unidades), [
    { nome: 'Secretaria de Teste', carteira: 'AT1' },
    { nome: 'Unidade não informada AT1', carteira: 'AT1' },
    { escola: 3, carteira: 'AT1' }
  ]);
});

test('acusa acesso depois da data da base escolhida', async () => {
  const lidos = await BA.ler(await planilhas());
  const c = await BA.consolidar(lidos, { escolas: ESCOLAS, carteiras: CARTEIRAS, baseRef: '2026-11-15' });
  assert.equal(c.depoisDaBase, 1);
});

test('recusa conjunto sem a planilha de usuários criados', async () => {
  const [, implementados] = await planilhas();
  const lidos = await BA.ler([implementados]);
  await assert.rejects(
    BA.consolidar(lidos, { escolas: ESCOLAS, carteiras: CARTEIRAS, baseRef: '2026-11-21' }),
    /usuários criados/
  );
});
