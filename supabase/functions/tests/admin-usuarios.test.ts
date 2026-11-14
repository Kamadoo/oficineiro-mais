import { assertEquals } from 'jsr:@std/assert@1';
import { carregar, json, Pedido, pedidos, pedir, responder, rpc } from './apoio.ts';

const atender = await carregar('../admin-usuarios/index.ts');

const ATOR = '00000000-0000-0000-0000-00000000a001';
const ALVO = '00000000-0000-0000-0000-00000000a006';

function padrao(acesso: Record<string, unknown> | null, alvo: Record<string, unknown> | null = null) {
  responder((p: Pedido) => {
    if (p.caminho === '/auth/v1/user') {
      return p.cabecalhos.get('Authorization') === 'Bearer a.b.c'
        ? json({ id: ATOR })
        : json({ message: 'invalid JWT' }, 401);
    }
    if (rpc(p) === 'meu_acesso') return json(acesso);
    if (p.caminho === '/rest/v1/perfis' && p.metodo === 'GET') {
      const objeto = (p.cabecalhos.get('Accept') ?? '').includes('vnd.pgrst.object');
      return objeto ? json(alvo) : json(alvo ? [alvo] : []);
    }
    return undefined;
  });
}

const erro = async (r: Response) => [r.status, (await r.json()).erro];
const gravacoes = () => pedidos.filter((p) => p.metodo !== 'GET' && !['meu_acesso'].includes(rpc(p) ?? ''));

Deno.test('origem, método e login', async () => {
  padrao({ acesso_ok: true, papel: 'gerente' });
  assertEquals((await atender(pedir({}, { origem: 'https://outro.exemplo.test', token: 'a.b.c' }))).status, 403);
  assertEquals((await atender(pedir(null, { metodo: 'GET', token: 'a.b.c' }))).status, 405);
  assertEquals(await erro(await atender(pedir({ acao: 'cadastrar' }))), [401, 'faça login']);
  assertEquals(await erro(await atender(pedir({ acao: 'cadastrar' }, { token: 'x.y.z' }))), [
    401,
    'sessão inválida ou expirada',
  ]);
});

Deno.test('exige MFA e papel que gerencia contas', async () => {
  padrao({ acesso_ok: false, papel: 'gerente' });
  assertEquals((await atender(pedir({ acao: 'cadastrar' }, { token: 'a.b.c' }))).status, 403);
  for (const papel of ['oficineiro', 'direcao', 'analista']) {
    padrao({ acesso_ok: true, papel });
    assertEquals(await erro(await atender(pedir({ acao: 'cadastrar' }, { token: 'a.b.c' }))), [
      403,
      'sem permissão para gerenciar contas',
    ]);
  }
  padrao(null);
  assertEquals((await atender(pedir({ acao: 'cadastrar' }, { token: 'a.b.c' }))).status, 403);
  assertEquals(gravacoes().length, 0);
});

Deno.test('coordenador só cadastra oficineiro e direção', async () => {
  padrao({ acesso_ok: true, papel: 'coordenador' });
  const r = await atender(
    pedir(
      { acao: 'cadastrar', papel: 'analista', nome: 'Pessoa', email: 'p@exemplo.test', cpf: '52998224725' },
      { token: 'a.b.c' },
    ),
  );
  assertEquals(r.status, 403);
  assertEquals(gravacoes().length, 0);
});

Deno.test('cadastro valida papel, e-mail, documento, login e telefone antes de gravar', async () => {
  padrao({ acesso_ok: true, papel: 'gerente' });
  const base = {
    acao: 'cadastrar',
    papel: 'oficineiro',
    nome: 'Pessoa Um',
    email: 'p@exemplo.test',
    cpf: '52998224725',
  };
  const casos: [Record<string, unknown>, string][] = [
    [{ papel: 'administrador' }, 'papel inválido'],
    [{ email: 'sem-arroba' }, 'e-mail inválido'],
    [{ nome: '<script>' }, 'campo nome com caracteres não permitidos'],
    [{ cpf: '123' }, 'CPF ou CNPJ inválido'],
    [{ usuario: '1abc' }, 'login: use de 4 a 30 caracteres'],
    [{ usuario: 'a52998224725' }, 'o login não pode ser o CPF nem o CNPJ'],
    [{ telefone: '123' }, 'telefone inválido: use DDD e número'],
  ];
  for (const [troca, mensagem] of casos) {
    const [status, texto] = await erro(await atender(pedir({ ...base, ...troca }, { token: 'a.b.c' })));
    assertEquals(status, 400);
    assertEquals(String(texto).startsWith(mensagem), true, String(texto));
  }
  assertEquals(gravacoes().length, 0);
});

Deno.test('ninguém altera a própria conta e só o Administrador apaga', async () => {
  padrao({ acesso_ok: true, papel: 'gerente' });
  assertEquals(await erro(await atender(pedir({ acao: 'desativar', usuario_id: ATOR }, { token: 'a.b.c' }))), [
    400,
    'não é possível alterar a própria conta',
  ]);
  assertEquals(await erro(await atender(pedir({ acao: 'apagar', usuario_id: ALVO }, { token: 'a.b.c' }))), [
    403,
    'somente o Administrador apaga contas',
  ]);
  assertEquals(await erro(await atender(pedir({ acao: 'ver_email', usuario_id: ALVO }, { token: 'a.b.c' }))), [
    403,
    'somente o Administrador consulta e altera o e-mail',
  ]);
  assertEquals(await erro(await atender(pedir({ acao: 'outra' }, { token: 'a.b.c' }))), [400, 'ação desconhecida']);
  assertEquals(gravacoes().length, 0);
});

Deno.test('contas de administrador não são alteradas pela função', async () => {
  padrao({ acesso_ok: true, papel: 'gerente' }, { id: ALVO, papel: 'administrador', ativo: true });
  const r = await atender(pedir({ acao: 'desativar', usuario_id: ALVO }, { token: 'a.b.c' }));
  assertEquals(r.status, 403);
  assertEquals(gravacoes().length, 0);
});
