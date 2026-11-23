import { assert, assertEquals } from 'jsr:@std/assert@1';
import { carregar, json, Pedido, pedidos, pedir, responder, rpc } from './apoio.ts';
import { modeloHtml, modeloTexto } from '../convites/modelo.ts';

Deno.env.set('RESEND_API_KEY', 're_teste');
Deno.env.set('FSM_CONVITE_REMETENTE', 'Oficineiro+ <convites@exemplo.test>');
Deno.env.set('FSM_SITE_URL', 'https://app.exemplo.test');
const atender = await carregar('../convites/index.ts');

const ATOR = '00000000-0000-0000-0000-00000000c001';
const A1 = '00000000-0000-0000-0000-00000000c0f1';
const A2 = '00000000-0000-0000-0000-00000000c0f2';
const A3 = '00000000-0000-0000-0000-00000000c0f3';

type Opcoes = { acesso?: Record<string, unknown> | null; reservas?: unknown; resend?: number; erroReserva?: string };

function padrao(o: Opcoes = {}) {
  const acesso = o.acesso === undefined ? { acesso_ok: true, papel: 'administrador' } : o.acesso;
  responder((p: Pedido) => {
    if (p.caminho === '/auth/v1/user') {
      return p.cabecalhos.get('Authorization') === 'Bearer a.b.c'
        ? json({ id: ATOR })
        : json({ message: 'invalid JWT' }, 401);
    }
    if (rpc(p) === 'meu_acesso') return json(acesso);
    if (rpc(p) === 'convites_reservar') {
      if (o.erroReserva) return json({ code: o.erroReserva, message: 'envie no máximo 50 convites por vez' }, 400);
      return json(o.reservas ?? []);
    }
    if (rpc(p) === 'convites_concluir') {
      const r = p.corpo as { p_resultados: { ok: boolean }[] };
      const enviados = r.p_resultados.filter((x) => x.ok).length;
      return json({ enviados, falhas: r.p_resultados.length - enviados });
    }
    if (p.caminho === '/emails/batch') {
      return o.resend && o.resend >= 400 ? json({ message: 'erro' }, o.resend) : json({ data: [{ id: 'x' }] });
    }
    return undefined;
  });
}

const erro = async (r: Response) => [r.status, (await r.json()).erro];
const corpo = (ids: string[], reenviar = false) => ({ acao: 'enviar', ids, reenviar });

Deno.test('origem, método e login', async () => {
  padrao();
  assertEquals((await atender(pedir({}, { origem: 'https://outro.exemplo.test', token: 'a.b.c' }))).status, 403);
  assertEquals((await atender(pedir(null, { metodo: 'GET', token: 'a.b.c' }))).status, 405);
  assertEquals(await erro(await atender(pedir(corpo([A1])))), [401, 'faça login']);
  assertEquals(await erro(await atender(pedir(corpo([A1]), { token: 'x.y.z' }))), [401, 'sessão inválida ou expirada']);
});

Deno.test('somente o Administrador com MFA envia', async () => {
  padrao({ acesso: { acesso_ok: false, papel: 'administrador' } });
  assertEquals((await atender(pedir(corpo([A1]), { token: 'a.b.c' }))).status, 403);
  for (const papel of ['gerente', 'coordenador', 'analista', 'direcao', 'oficineiro']) {
    padrao({ acesso: { acesso_ok: true, papel } });
    assertEquals(await erro(await atender(pedir(corpo([A1]), { token: 'a.b.c' }))), [
      403,
      'somente o Administrador envia convites',
    ]);
    assertEquals(pedidos.filter((p) => p.caminho === '/emails/batch' || rpc(p) === 'convites_reservar').length, 0);
  }
  padrao({ acesso: null });
  assertEquals((await atender(pedir(corpo([A1]), { token: 'a.b.c' }))).status, 403);
});

Deno.test('valida o pedido', async () => {
  padrao();
  assertEquals(await erro(await atender(pedir({ acao: 'outra' }, { token: 'a.b.c' }))), [400, 'ação desconhecida']);
  assertEquals((await atender(pedir(corpo([]), { token: 'a.b.c' }))).status, 400);
  assertEquals((await atender(pedir(corpo(['x']), { token: 'a.b.c' }))).status, 400);
  const muitos = Array.from({ length: 51 }, (_, i) => `00000000-0000-0000-0000-${String(i).padStart(12, '0')}`);
  assertEquals(await erro(await atender(pedir(corpo(muitos), { token: 'a.b.c' }))), [
    400,
    'envie no máximo 50 convites por vez',
  ]);
});

Deno.test('envia só as contas reservadas e registra o resultado', async () => {
  padrao({
    reservas: [
      { usuario_id: A1, convite_id: 11, resultado: 'reservado', nome: 'Ana <b>Teste</b>', email: 'a1@exemplo.test' },
      { usuario_id: A2, convite_id: null, resultado: 'ja_enviado', nome: 'Bia', email: null },
      { usuario_id: A3, convite_id: null, resultado: 'indisponivel', nome: null, email: null },
    ],
  });
  const r = await atender(pedir(corpo([A1, A2, A3, A1]), { token: 'a.b.c' }));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { ok: true, enviados: 1, falhas: 0, ja_enviados: 1, em_envio: 0, indisponiveis: 1 });
  const reserva = pedidos.find((p) => rpc(p) === 'convites_reservar')!;
  assertEquals(reserva.corpo, { p_ator: ATOR, p_ids: [A1, A2, A3], p_reenviar: false });
  const envio = pedidos.find((p) => p.caminho === '/emails/batch')!;
  assertEquals(envio.cabecalhos.get('Authorization'), 'Bearer re_teste');
  assert(envio.cabecalhos.get('Idempotency-Key'));
  const mensagens = envio.corpo as { to: string[]; html: string; from: string }[];
  assertEquals(mensagens.length, 1);
  assertEquals(mensagens[0].to, ['a1@exemplo.test']);
  assert(mensagens[0].html.includes('https://app.exemplo.test/'));
  assert(!mensagens[0].html.includes('<b>Teste'));
  const concluir = pedidos.find((p) => rpc(p) === 'convites_concluir')!;
  assertEquals(concluir.corpo, { p_ator: ATOR, p_resultados: [{ convite_id: 11, ok: true }] });
});

Deno.test('reenvio confirmado e falha do serviço de e-mail', async () => {
  padrao({
    resend: 422,
    reservas: [{ usuario_id: A1, convite_id: 12, resultado: 'reservado', nome: 'Ana', email: 'a1@exemplo.test' }],
  });
  const r = await atender(pedir(corpo([A1], true), { token: 'a.b.c' }));
  assertEquals((await r.json()).falhas, 1);
  assertEquals(
    (pedidos.find((p) => rpc(p) === 'convites_reservar')!.corpo as { p_reenviar: boolean }).p_reenviar,
    true,
  );
  const concluir = pedidos.find((p) => rpc(p) === 'convites_concluir')!;
  assertEquals((concluir.corpo as { p_resultados: { ok: boolean }[] }).p_resultados[0].ok, false);
});

Deno.test('nada reservado não chama o serviço de e-mail', async () => {
  padrao({ reservas: [{ usuario_id: A1, convite_id: null, resultado: 'em_envio', nome: 'Ana', email: null }] });
  const r = await atender(pedir(corpo([A1]), { token: 'a.b.c' }));
  assertEquals((await r.json()).em_envio, 1);
  assertEquals(pedidos.filter((p) => p.caminho === '/emails/batch' || rpc(p) === 'convites_concluir').length, 0);
});

Deno.test('erro de validação do banco vira mensagem pública', async () => {
  padrao({ erroReserva: '22023' });
  assertEquals(await erro(await atender(pedir(corpo([A1]), { token: 'a.b.c' }))), [
    400,
    'envie no máximo 50 convites por vez',
  ]);
});

Deno.test('sem configuração de envio não reserva nada', async () => {
  Deno.env.delete('RESEND_API_KEY');
  try {
    padrao();
    assertEquals((await atender(pedir(corpo([A1]), { token: 'a.b.c' }))).status, 503);
    assertEquals(pedidos.filter((p) => rpc(p) === 'convites_reservar').length, 0);
  } finally {
    Deno.env.set('RESEND_API_KEY', 're_teste');
  }
});

Deno.test('modelo escapa o nome e traz os passos', () => {
  const html = modeloHtml('<script>x</script> Silva', 'https://app.exemplo.test/');
  assert(!html.includes('<script>'));
  assert(html.includes('Primeiro acesso? Ative sua conta aqui'));
  assert(modeloTexto('Ana Silva', 'https://app.exemplo.test/').startsWith('Olá, Ana!'));
});
