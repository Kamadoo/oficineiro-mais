import { assert, assertEquals } from 'jsr:@std/assert@1';
import { carregar, json, pedidos, pedir, responder, rpc } from './apoio.ts';

const atender = await carregar('../acesso/index.ts');

const CONTA = { user_id: 'u1', email: 'pessoa@exemplo.test', ativo: true, primeiro_acesso: true };

function padrao(opcoes: { limite?: boolean; conta?: unknown; senhaCerta?: boolean } = {}) {
  responder((p) => {
    const nome = rpc(p);
    if (nome === 'fsm_tentativa') return json(opcoes.limite !== false);
    if (nome === 'fsm_conta_por_cpf' || nome === 'fsm_conta_por_usuario') {
      return json(opcoes.conta ? [opcoes.conta] : []);
    }
    if (nome) return json(null);
    if (p.caminho === '/auth/v1/otp') return json({});
    if (p.caminho === '/auth/v1/token') {
      return opcoes.senhaCerta
        ? json({ access_token: 'a.b.c', refresh_token: 'r', expires_in: 3600, expires_at: 1 })
        : json({ error: 'invalid_grant' }, 400);
    }
    return undefined;
  });
}

const chamadas = (nome: string) => pedidos.filter((p) => rpc(p) === nome || p.caminho === nome);

Deno.test('recusa origem estranha, responde OPTIONS e só aceita POST', async () => {
  padrao();
  assertEquals((await atender(pedir({}, { origem: 'https://outro.exemplo.test' }))).status, 403);
  const opcoes = await atender(pedir(null, { metodo: 'OPTIONS' }));
  assertEquals(opcoes.status, 204);
  assert(opcoes.headers.get('Access-Control-Allow-Origin'));
  assertEquals((await atender(pedir(null, { metodo: 'GET' }))).status, 405);
  assertEquals(pedidos.length, 0);
});

Deno.test('toda resposta leva pelo menos 1,2 s', async () => {
  padrao();
  const inicio = Date.now();
  const r = await atender(pedir('x', { tipo: 'text/plain' }));
  assertEquals(r.status, 415);
  assert(Date.now() - inicio >= 1150);
});

Deno.test('limite de tentativas por IP', async () => {
  padrao({ limite: false });
  const r = await atender(pedir({ acao: 'codigo', cpf: '52998224725' }));
  assertEquals(r.status, 429);
  assertEquals(chamadas('fsm_conta_por_cpf').length, 0);
});

Deno.test('pedido de código não revela se o documento existe', async () => {
  padrao({ conta: CONTA });
  const comConta = await (await atender(pedir({ acao: 'codigo', cpf: '529.982.247-25' }))).json();
  assertEquals(chamadas('/auth/v1/otp').length, 1);
  padrao();
  const semConta = await (await atender(pedir({ acao: 'codigo', cpf: '111.444.777-35' }))).json();
  assertEquals(chamadas('/auth/v1/otp').length, 0);
  assertEquals(comConta, semConta);
  padrao({ conta: { ...CONTA, primeiro_acesso: false } });
  await atender(pedir({ acao: 'codigo', cpf: '529.982.247-25' }));
  assertEquals(chamadas('/auth/v1/otp').length, 0);
});

Deno.test('documento incompleto é recusado sem consultar contas', async () => {
  padrao({ conta: CONTA });
  const r = await atender(pedir({ acao: 'codigo', cpf: '123' }));
  assertEquals(r.status, 400);
  assertEquals(chamadas('fsm_conta_por_cpf').length, 0);
});

Deno.test('entrar: usuário inexistente e senha errada têm a mesma resposta', async () => {
  padrao();
  const semConta = await atender(pedir({ acao: 'entrar', usuario: 'pessoa.um', senha: 'qualquer' }));
  padrao({ conta: CONTA });
  const senhaErrada = await atender(pedir({ acao: 'entrar', usuario: 'pessoa.um', senha: 'qualquer' }));
  assertEquals(semConta.status, 400);
  assertEquals(senhaErrada.status, 400);
  assertEquals(await semConta.json(), await senhaErrada.json());
  assertEquals(chamadas('fsm_tentativa_zerar').length, 0);
});

Deno.test('entrar com sucesso devolve só os campos da sessão e zera o limite do usuário', async () => {
  padrao({ conta: CONTA, senhaCerta: true });
  const r = await atender(pedir({ acao: 'entrar', usuario: 'Pessoa.Um', senha: 'certa' }));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), {
    ok: true,
    sessao: { access_token: 'a.b.c', refresh_token: 'r', expires_in: 3600, expires_at: 1 },
  });
  assertEquals(chamadas('fsm_tentativa_zerar').length, 1);
  assertEquals(chamadas('fsm_conta_por_usuario')[0].corpo, { p_usuario: 'pessoa.um' });
});

Deno.test('login com formato inválido não consulta contas', async () => {
  padrao({ conta: CONTA });
  const r = await atender(pedir({ acao: 'entrar', usuario: "x' or 1=1", senha: 'a' }));
  assertEquals(r.status, 400);
  assertEquals(chamadas('fsm_conta_por_usuario').length, 0);
});
