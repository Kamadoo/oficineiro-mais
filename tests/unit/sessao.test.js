const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

function montar(respostas) {
  const chamadas = [];
  const timers = [];
  const armazenado = {};
  const sessionStorage = {
    getItem: chave => (chave in armazenado ? armazenado[chave] : null),
    setItem: (chave, valor) => (armazenado[chave] = String(valor)),
    removeItem: chave => delete armazenado[chave]
  };
  const ouvintes = {};
  const fetch = async (url, init) => {
    const caminho = url.replace('https://abc.supabase.co', '');
    const token = (init.headers.Authorization || '').replace('Bearer ', '');
    chamadas.push({ caminho, token });
    const r = respostas(caminho, token, chamadas);
    if (r instanceof Error) throw r;
    return { ok: r.status < 400, status: r.status, text: async () => JSON.stringify(r.corpo || null) };
  };
  const window = carregar(
    ['auth.js'],
    {
      FSM_CONFIG: { url: 'https://abc.supabase.co', chave: 'eyJteste' },
      addEventListener: (ev, fn) => (ouvintes[ev] = fn)
    },
    {
      location: { hash: '', search: '', pathname: '/' },
      sessionStorage,
      fetch,
      setTimeout: fn => timers.push(fn),
      clearTimeout: () => {},
      URLSearchParams,
      atob,
      escape,
      document: { title: '', querySelectorAll: () => [] }
    }
  );
  return { A: window.FSM_AUTH, chamadas, timers, ouvintes };
}

const agora = () => Math.floor(Date.now() / 1000);
const login = (at, rt, venceEm) => ({
  status: 200,
  corpo: { sessao: { access_token: at, refresh_token: rt, expires_at: agora() + venceEm } }
});
const renovado = n => ({ status: 200, corpo: { access_token: 'at' + n, refresh_token: 'rt' + n, expires_in: 900 } });

test('renova antes da chamada quando o token está para vencer', async () => {
  const { A, chamadas } = montar(caminho => {
    if (caminho.startsWith('/functions/v1/acesso')) return login('at1', 'rt1', 20);
    if (caminho.startsWith('/auth/v1/token')) return renovado(2);
    return { status: 200, corpo: 'ok' };
  });
  await A.entrar('analista', 'senha', false);
  await A.gerarMeuUsuario();
  const rpc = chamadas.filter(c => c.caminho.startsWith('/rest/'));
  assert.equal(chamadas.filter(c => c.caminho.startsWith('/auth/v1/token')).length, 1);
  assert.equal(rpc.length, 1);
  assert.equal(rpc[0].token, 'at2');
});

test('depois de 401 renova e repete a chamada uma vez', async () => {
  const { A, chamadas } = montar((caminho, token) => {
    if (caminho.startsWith('/functions/v1/acesso')) return login('at1', 'rt1', 900);
    if (caminho.startsWith('/auth/v1/token')) return renovado(2);
    if (token === 'at1') return { status: 401, corpo: { code: 'PGRST301', message: 'JWT expired' } };
    return { status: 200, corpo: 'ok' };
  });
  await A.entrar('analista', 'senha', false);
  assert.equal(await A.gerarMeuUsuario(), 'ok');
  const rpc = chamadas.filter(c => c.caminho.startsWith('/rest/')).map(c => c.token);
  assert.deepEqual(rpc, ['at1', 'at2']);
});

test('falha de rede na renovação não encerra a sessão', async () => {
  let rede = false;
  const { A, timers } = montar(caminho => {
    if (caminho.startsWith('/functions/v1/acesso')) return login('at1', 'rt1', 900);
    if (caminho.startsWith('/auth/v1/token')) return rede ? new TypeError('Failed to fetch') : renovado(2);
    return { status: 200, corpo: 'ok' };
  });
  const motivos = [];
  A.aoExpirar(m => motivos.push(m));
  await A.entrar('analista', 'senha', false);
  rede = true;
  timers[0]();
  await new Promise(r => setImmediate(r));
  assert.deepEqual(motivos, []);
  assert.ok(timers.length > 2);
});

test('refresh recusado pelo servidor encerra a sessão', async () => {
  const { A, timers } = montar(caminho => {
    if (caminho.startsWith('/functions/v1/acesso')) return login('at1', 'rt1', 900);
    if (caminho.startsWith('/auth/v1/token')) return { status: 400, corpo: { error_code: 'refresh_token_not_found' } };
    return { status: 200, corpo: 'ok' };
  });
  const motivos = [];
  A.aoExpirar(m => motivos.push(m));
  await A.entrar('analista', 'senha', false);
  timers[0]();
  await new Promise(r => setImmediate(r));
  assert.deepEqual(motivos, ['expirou']);
});

test('403 de permissão não aparece como sessão expirada', async () => {
  const { A } = montar(caminho => {
    if (caminho.startsWith('/functions/v1/acesso')) return login('at1', 'rt1', 900);
    return { status: 403, corpo: { code: '42501', message: 'permission denied' } };
  });
  await A.entrar('analista', 'senha', false);
  await assert.rejects(A.gerarMeuUsuario(), /não tem permissão/);
});

test('ao voltar para a página renova o token que está para vencer', async () => {
  const { A, chamadas, ouvintes } = montar(caminho => {
    if (caminho.startsWith('/functions/v1/acesso')) return login('at1', 'rt1', 30);
    if (caminho.startsWith('/auth/v1/token')) return renovado(2);
    return { status: 200, corpo: 'ok' };
  });
  await A.entrar('analista', 'senha', false);
  ouvintes.pageshow();
  await new Promise(r => setImmediate(r));
  assert.equal(chamadas.filter(c => c.caminho.startsWith('/auth/v1/token')).length, 1);
});
