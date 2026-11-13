const { spawnSync } = require('child_process');

const PSQL = process.env.PSQL || 'psql';
const BANCO = process.env.PGDATABASE || 'postgres';
const HOJE = process.env.FSM_HOJE || '2026-11-09';

const literal = valor => (valor == null ? 'null' : "'" + String(valor).replace(/'/g, "''") + "'");
const identificador = nome => {
  if (!/^[a-z_][a-z0-9_]*$/.test(nome)) throw new Error('identificador inválido: ' + nome);
  return '"' + nome + '"';
};

function psql(argumentos, entrada) {
  return spawnSync(PSQL, ['-X', '-q', '-A', '-t', '-d', BANCO, ...argumentos], { input: entrada, encoding: 'utf8' });
}

function consultar(texto, usuario) {
  const claims = JSON.stringify({ sub: usuario, role: 'authenticated', aal: 'aal2' });
  const corpo = [
    '\\set ON_ERROR_STOP 1',
    '\\set VERBOSITY verbose',
    'begin;',
    `do $$ begin perform set_config('request.jwt.claims', ${literal(claims)}, true); perform set_config('t.hoje', ${literal(HOJE)}, true); end $$;`,
    usuario ? 'set local role authenticated;' : '',
    texto + ';',
    'commit;'
  ].join('\n');
  const r = psql([], corpo);
  if (r.status !== 0) {
    const linha = r.stderr.match(/ERROR:\s+(?:([0-9A-Z]{5}): )?(.*)/) || [];
    return { erro: { code: linha[1] || 'XX000', message: linha[2] || r.stderr.trim(), details: null, hint: null } };
  }
  const saida = r.stdout.trim();
  return { dados: saida === '' ? null : JSON.parse(saida) };
}

const assinaturas = {};
function assinatura(funcao) {
  if (funcao in assinaturas) return assinaturas[funcao];
  const r = psql(
    [
      '-F',
      '\t',
      '-c',
      `select p.proretset, coalesce(array_to_string(p.proargnames, ','), ''),
         coalesce((select string_agg(format_type(t, null), ',' order by o) from unnest(p.proargtypes) with ordinality u(t, o)), ''),
         format_type(p.prorettype, null)
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = ${literal(funcao)}
       order by p.pronargs desc limit 1`
    ],
    ''
  );
  const linha = r.stdout.trim();
  if (!linha) return (assinaturas[funcao] = null);
  const [conjunto, nomes, tipos, retorno] = linha.split('\t');
  return (assinaturas[funcao] = {
    conjunto: conjunto === 't',
    nomes: nomes ? nomes.split(',') : [],
    tipos: tipos ? tipos.split(',') : [],
    retorno
  });
}

function argumento(valor, tipo) {
  if (valor === null || valor === undefined) return 'null::' + tipo;
  const json = literal(JSON.stringify(valor)) + '::jsonb';
  if (tipo === 'jsonb' || tipo === 'json') return json + '::' + tipo;
  if (tipo.endsWith('[]')) return `(select array_agg(e) from jsonb_array_elements_text(${json}) e)::${tipo}`;
  return `(${json} #>> '{}')::${tipo}`;
}

function responder(resultado, sucesso = 200) {
  if (resultado.erro) {
    const codigo = resultado.erro.code;
    return { status: codigo === '42501' ? 403 : codigo === 'P0002' ? 404 : 400, corpo: resultado.erro };
  }
  return { status: sucesso, corpo: resultado.dados };
}

function rpc(funcao, argumentos, usuario) {
  const a = assinatura(funcao);
  if (!a) return { status: 404, corpo: { code: 'PGRST202', message: 'função inexistente: ' + funcao } };
  const partes = Object.keys(argumentos || {}).map(nome => {
    const i = a.nomes.indexOf(nome);
    return identificador(nome) + ' => ' + argumento(argumentos[nome], i >= 0 ? a.tipos[i] : 'text');
  });
  const chamada = `public.${identificador(funcao)}(${partes.join(', ')})`;
  const consulta = a.conjunto
    ? `select coalesce(json_agg(r), '[]') from ${chamada} r`
    : a.retorno === 'void'
      ? `select ${chamada}; select 'null'::json`
      : `select to_json(${chamada})`;
  return responder(consultar(consulta, usuario));
}

const OPERADORES = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=', like: 'like', ilike: 'ilike' };

function filtros(parametros) {
  const condicoes = [];
  for (const [coluna, valor] of parametros) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'].includes(coluna)) continue;
    const m = /^(not\.)?([a-z]+)\.(.*)$/s.exec(valor);
    if (!m) throw new Error('filtro: ' + coluna + '=' + valor);
    const [, negacao, operador, alvo] = m;
    let condicao;
    if (operador === 'is')
      condicao = `${identificador(coluna)} is ${alvo === 'null' ? 'null' : alvo === 'true' ? 'true' : 'false'}`;
    else if (operador === 'in') {
      const itens = alvo
        .replace(/^\(|\)$/g, '')
        .split(',')
        .map(x => literal(x.replace(/^"|"$/g, '')));
      condicao = `${identificador(coluna)} in (${itens.join(',')})`;
    } else if (OPERADORES[operador]) {
      const texto = operador.endsWith('like') ? alvo.replace(/\*/g, '%') : alvo;
      condicao = `${identificador(coluna)} ${OPERADORES[operador]} ${literal(texto)}`;
    } else throw new Error('operador: ' + operador);
    condicoes.push(negacao ? `not (${condicao})` : condicao);
  }
  return condicoes.length ? ' where ' + condicoes.join(' and ') : '';
}

function ordem(parametro) {
  if (!parametro) return '';
  const partes = parametro.split(',').map(item => {
    const [coluna, sentido, nulos] = item.split('.');
    return (
      identificador(coluna) +
      (sentido === 'desc' ? ' desc' : sentido === 'asc' ? ' asc' : '') +
      (nulos === 'nullslast' ? ' nulls last' : nulos === 'nullsfirst' ? ' nulls first' : '')
    );
  });
  return ' order by ' + partes.join(', ');
}

function tabela(metodo, nome, parametros, corpo, usuario, representacao) {
  const t = 'public.' + identificador(nome);
  const colunas = (parametros.get('select') || '*')
    .split(',')
    .map(c => (c === '*' ? '*' : identificador(c.trim())))
    .join(', ');
  const onde = filtros(parametros);
  if (metodo === 'GET') {
    const limite =
      (parametros.get('limit') ? ' limit ' + Number(parametros.get('limit')) : '') +
      (parametros.get('offset') ? ' offset ' + Number(parametros.get('offset')) : '');
    return responder(
      consultar(
        `select coalesce(json_agg(r), '[]') from (select ${colunas} from ${t}${onde}${ordem(parametros.get('order'))}${limite}) r`,
        usuario
      )
    );
  }
  const retorno = representacao ? `coalesce(json_agg(r), '[]') from (select * from w) r` : `'null'::json`;
  if (metodo === 'POST') {
    const linhas = Array.isArray(corpo) ? corpo : [corpo];
    const campos = Object.keys(linhas[0] || {})
      .map(identificador)
      .join(', ');
    const dados = literal(JSON.stringify(linhas));
    return responder(
      consultar(
        `with w as (insert into ${t} (${campos}) select ${campos} from jsonb_populate_recordset(null::${t}, ${dados}::jsonb) returning *) select ${retorno}`,
        usuario
      ),
      201
    );
  }
  if (metodo === 'PATCH') {
    const dados = literal(JSON.stringify(corpo));
    const valores = Object.keys(corpo).map(
      k => `${identificador(k)} = (jsonb_populate_record(null::${t}, ${dados}::jsonb)).${identificador(k)}`
    );
    return responder(
      consultar(`with w as (update ${t} set ${valores.join(', ')}${onde} returning *) select ${retorno}`, usuario)
    );
  }
  if (metodo === 'DELETE')
    return responder(consultar(`with w as (delete from ${t}${onde} returning *) select ${retorno}`, usuario));
  return { status: 405, corpo: {} };
}

const base64 = objeto => Buffer.from(JSON.stringify(objeto)).toString('base64url');
const token = usuario =>
  base64({ alg: 'HS256', typ: 'JWT' }) +
  '.' +
  base64({ sub: usuario, role: 'authenticated', aal: 'aal2', exp: 4102444800, amr: [{ method: 'totp' }] }) +
  '.assinatura';
const usuarioDoToken = cabecalho => {
  try {
    const carga = String(cabecalho || '')
      .replace(/^Bearer /, '')
      .split('.')[1];
    return JSON.parse(Buffer.from(carga, 'base64url').toString()).sub || null;
  } catch {
    return null;
  }
};

function atender(metodo, endereco, cabecalhos, texto) {
  const url = new URL(endereco);
  const corpo = texto ? JSON.parse(texto) : null;
  const usuario = usuarioDoToken(cabecalhos.authorization);
  const caminho = url.pathname;
  if (caminho === '/auth/v1/token') {
    const id = String((corpo && corpo.refresh_token) || '').replace(/^rt-/, '');
    if (!/^[0-9a-f-]{36}$/.test(id)) return { status: 400, corpo: { error: 'invalid_grant' } };
    return {
      status: 200,
      corpo: {
        access_token: token(id),
        refresh_token: 'rt-' + id,
        expires_in: 36000,
        expires_at: 4102444800,
        token_type: 'bearer',
        user: { id }
      }
    };
  }
  if (caminho === '/auth/v1/logout') return { status: 204, corpo: null };
  if (caminho === '/auth/v1/user') {
    const fatores = [{ id: 'f1', factor_type: 'totp', status: 'verified' }];
    return { status: 200, corpo: { id: usuario, email: 'teste@exemplo.test', factors: fatores } };
  }
  if (caminho.startsWith('/auth/v1/') || caminho.startsWith('/functions/v1/')) return { status: 200, corpo: {} };
  const m = /^\/rest\/v1\/(rpc\/)?([a-z_]+)$/.exec(caminho);
  if (!m) return { status: 404, corpo: {} };
  try {
    if (m[1]) return rpc(m[2], corpo, usuario);
    return tabela(
      metodo,
      m[2],
      url.searchParams,
      corpo,
      usuario,
      /return=representation/.test(cabecalhos.prefer || '')
    );
  } catch (erro) {
    return { status: 400, corpo: { code: 'TESTE', message: erro.message } };
  }
}

module.exports = { atender };
