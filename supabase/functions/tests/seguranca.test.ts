import { assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@1';
import { carregar, ORIGEM } from './apoio.ts';

await carregar('../acesso/index.ts');
const { cabecalhos, email, ErroPublico, lerJson, origemPermitida, texto, uuid } = await import(
  '../_shared/seguranca.ts'
);

const comOrigem = (origem: string | null) =>
  new Request('https://funcoes.exemplo.test/', { headers: origem ? { Origin: origem } : {} });

Deno.test('CORS só para a origem configurada', () => {
  const permitida = new Headers(cabecalhos(comOrigem(ORIGEM)));
  assertEquals(permitida.get('Access-Control-Allow-Origin'), ORIGEM);
  assertEquals(permitida.get('Cache-Control'), 'no-store');
  const outra = new Headers(cabecalhos(comOrigem('https://outro.exemplo.test')));
  assertEquals(outra.get('Access-Control-Allow-Origin'), null);
  assertEquals(origemPermitida(comOrigem(ORIGEM)), true);
  assertEquals(origemPermitida(comOrigem(null)), true);
  assertEquals(origemPermitida(comOrigem('https://outro.exemplo.test')), false);
});

Deno.test('texto normaliza espaços e recusa tamanho e caracteres inválidos', () => {
  assertEquals(texto('  Pessoa   Um ', 'nome', 3, 20), 'Pessoa Um');
  assertThrows(() => texto(5, 'nome', 3, 20), ErroPublico, 'obrigatório');
  assertThrows(() => texto('ab', 'nome', 3, 20), ErroPublico, 'tamanho inválido');
  assertThrows(() => texto('<b>Pessoa</b>', 'nome', 3, 20), ErroPublico, 'não permitidos');
});

Deno.test('e-mail e UUID', () => {
  assertEquals(email(' Pessoa@Exemplo.TEST '), 'pessoa@exemplo.test');
  assertThrows(() => email('pessoa@exemplo'), ErroPublico, 'e-mail inválido');
  assertEquals(uuid('00000000-0000-0000-0000-00000000A001', 'id'), '00000000-0000-0000-0000-00000000a001');
  assertThrows(() => uuid('1 or 1=1', 'id'), ErroPublico, 'inválido');
});

Deno.test('lerJson exige JSON de objeto e limita o tamanho', async () => {
  const pedido = (corpo: string, tipo = 'application/json') =>
    new Request('https://funcoes.exemplo.test/', { method: 'POST', headers: { 'Content-Type': tipo }, body: corpo });
  assertEquals(await lerJson(pedido('{"a":1}')), { a: 1 });
  await assertRejects(() => lerJson(pedido('{}', 'text/plain')), ErroPublico, 'envie JSON');
  await assertRejects(() => lerJson(pedido('[1]')), ErroPublico, 'JSON inválido');
  await assertRejects(() => lerJson(pedido('{"a":')), ErroPublico, 'JSON inválido');
  await assertRejects(() => lerJson(pedido('{"a":"' + 'x'.repeat(100) + '"}'), 50), ErroPublico, 'grande demais');
});
