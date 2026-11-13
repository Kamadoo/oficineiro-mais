import { createClient } from 'npm:@supabase/supabase-js@2';
import { cabecalhos, ErroPublico, lerJson, origemPermitida, resposta } from '../_shared/seguranca.ts';

function chave(nova: string, antiga: string): string {
  const json = Deno.env.get(nova);
  if (json) {
    let k: unknown = null;
    try {
      k = JSON.parse(json)?.default;
    } catch {
      k = null;
    }
    if (typeof k === 'string' && k) return k;
  }
  const v = Deno.env.get(antiga);
  if (!v) throw new Error(`chave do Supabase ausente (${nova} / ${antiga})`);
  return v;
}
const URL_SUPABASE = Deno.env.get('SUPABASE_URL')!;
const CHAVE_PUBLICA = chave('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
const CHAVE_SERVICO = chave('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
const admin = createClient(URL_SUPABASE, CHAVE_SERVICO, { auth: { persistSession: false, autoRefreshToken: false } });

const JANELA_S = 15 * 60;
const MSG_CODIGO =
  'Se este CPF ou CNPJ tiver um primeiro acesso pendente, enviamos um código para o e-mail institucional cadastrado. Ele vale por 1 hora.';
const MSG_CONFIRMAR = 'Documento ou código inválido. Confira e tente de novo.';
const MSG_ENTRAR = 'Usuário ou senha incorretos.';

function soDigitos(v: unknown): string {
  return typeof v === 'string' ? v.replace(/\D/g, '').slice(0, 14) : '';
}

function ipDe(req: Request): string {
  const ip = req.headers.get('cf-connecting-ip') ?? (req.headers.get('x-forwarded-for') ?? '').split(',')[0];
  return ip.trim().slice(0, 64) || 'desconhecido';
}

const chaveHmac = crypto.subtle.importKey(
  'raw',
  new TextEncoder().encode(CHAVE_SERVICO),
  { name: 'HMAC', hash: 'SHA-256' },
  false,
  ['sign'],
);

async function hashCurto(v: string): Promise<string> {
  const d = await crypto.subtle.sign('HMAC', await chaveHmac, new TextEncoder().encode(v));
  return Array.from(new Uint8Array(d))
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function permitido(chaveLimite: string, max: number): Promise<boolean> {
  const { data, error } = await admin.rpc('fsm_tentativa', { p_chave: chaveLimite, p_max: max, p_janela_s: JANELA_S });
  if (error) throw new Error('falha no limite de tentativas');
  return data === true;
}

async function auth(
  caminho: string,
  corpo: unknown,
): Promise<{ ok: boolean; status: number; dados: Record<string, unknown> | null }> {
  const r = await fetch(`${URL_SUPABASE}/auth/v1${caminho}`, {
    method: 'POST',
    headers: { 'apikey': CHAVE_PUBLICA, 'Content-Type': 'application/json' },
    body: JSON.stringify(corpo),
  });
  let dados: Record<string, unknown> | null = null;
  try {
    dados = await r.json();
  } catch {
    dados = null;
  }
  return { ok: r.ok, status: r.status, dados };
}

function sessao(d: Record<string, unknown> | null) {
  if (!d || typeof d.access_token !== 'string' || typeof d.refresh_token !== 'string') {
    throw new Error('sessão inválida');
  }
  return {
    access_token: d.access_token,
    refresh_token: d.refresh_token,
    expires_in: d.expires_in,
    expires_at: d.expires_at,
  };
}

async function authComo(
  metodo: string,
  caminho: string,
  token: string,
  corpo?: unknown,
): Promise<{ ok: boolean; status: number; dados: Record<string, unknown> | null }> {
  const r = await fetch(`${URL_SUPABASE}${caminho}`, {
    method: metodo,
    headers: { 'apikey': CHAVE_PUBLICA, 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  let dados: Record<string, unknown> | null = null;
  try {
    dados = await r.json();
  } catch {
    dados = null;
  }
  return { ok: r.ok, status: r.status, dados };
}

function faltaNaSenha(s: string): string[] {
  const falta: string[] = [];
  if (s.length < 12) falta.push('12 caracteres');
  if (!/[a-z]/.test(s)) falta.push('uma letra minúscula');
  if (!/[A-Z]/.test(s)) falta.push('uma letra maiúscula');
  if (!/[0-9]/.test(s)) falta.push('um número');
  if (!/[^A-Za-z0-9]/.test(s)) falta.push('um símbolo');
  return falta;
}

async function registrarLogin(id: unknown) {
  if (typeof id !== 'string') return;
  try {
    const { error } = await admin.rpc('fsm_registrar_login', { p_user: id });
    if (error) console.error('acesso: registro do login falhou');
  } catch {
    console.error('acesso: registro do login falhou');
  }
}

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

const TEMPO_MINIMO_MS = 1200;

async function atender(req: Request): Promise<Response> {
  try {
    const corpo = await lerJson(req, 4096);
    const ip = await hashCurto('ip:' + ipDe(req));
    if (!(await permitido('ip:' + ip, 30))) {
      throw new ErroPublico(429, 'Muitas tentativas. Aguarde 15 minutos e tente de novo.');
    }

    if (corpo.acao === 'codigo') {
      const cpf = soDigitos(corpo.cpf);
      if (cpf.length < 10 || (cpf.length > 11 && cpf.length !== 14)) {
        throw new ErroPublico(400, 'Digite o CPF ou o CNPJ completo.');
      }
      if (!(await permitido('cpf:' + (await hashCurto('cpf:' + cpf)), 5))) {
        throw new ErroPublico(429, 'Muitas tentativas para este documento. Aguarde 15 minutos.');
      }
      const { data } = await admin.rpc('fsm_conta_por_cpf', { p_cpf: cpf });
      const conta = Array.isArray(data) ? data[0] : null;
      if (conta && conta.ativo && conta.primeiro_acesso && conta.email) {
        const envio = auth('/otp', { email: conta.email, create_user: false })
          .then((r) => {
            if (!r.ok) console.error('acesso/codigo: envio falhou', r.status);
          })
          .catch(() => console.error('acesso/codigo: envio falhou'));
        const runtime = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
        if (runtime) runtime.waitUntil(envio);
        else await envio;
      }
      return resposta(req, 200, { ok: true, mensagem: MSG_CODIGO });
    }

    if (corpo.acao === 'confirmar') {
      const cpf = soDigitos(corpo.cpf);
      const codigo = soDigitos(corpo.codigo);
      if (cpf.length < 10 || (cpf.length > 11 && cpf.length !== 14) || codigo.length < 6 || codigo.length > 10) {
        throw new ErroPublico(400, MSG_CONFIRMAR);
      }
      if (!(await permitido('cpfc:' + (await hashCurto('cpf:' + cpf)), 5))) {
        throw new ErroPublico(429, 'Muitas tentativas para este documento. Aguarde 15 minutos.');
      }
      const { data } = await admin.rpc('fsm_conta_por_cpf', { p_cpf: cpf });
      const conta = Array.isArray(data) ? data[0] : null;
      if (!conta || !conta.ativo || !conta.primeiro_acesso || !conta.email) throw new ErroPublico(400, MSG_CONFIRMAR);
      const r = await auth('/verify', { type: 'email', email: conta.email, token: codigo });
      if (!r.ok) {
        if (r.status !== 400 && r.status !== 403) console.error('acesso/confirmar: falhou', r.status);
        throw new ErroPublico(400, MSG_CONFIRMAR);
      }
      await registrarLogin(conta.user_id);
      return resposta(req, 200, { ok: true, sessao: sessao(r.dados) });
    }

    if (corpo.acao === 'entrar') {
      const usuario = typeof corpo.usuario === 'string' ? corpo.usuario.trim().toLowerCase().slice(0, 30) : '';
      const senha = typeof corpo.senha === 'string' ? corpo.senha.slice(0, 128) : '';
      if (!/^[a-z][a-z0-9._-]{3,29}$/.test(usuario) || !senha) throw new ErroPublico(400, MSG_ENTRAR);
      const chaveUsuario = 'usr:' + (await hashCurto('usr:' + usuario));
      if (!(await permitido(chaveUsuario, 5))) {
        throw new ErroPublico(429, 'Muitas tentativas para este usuário. Aguarde 15 minutos.');
      }
      const { data } = await admin.rpc('fsm_conta_por_usuario', { p_usuario: usuario });
      const conta = Array.isArray(data) ? data[0] : null;
      if (!conta || !conta.email) throw new ErroPublico(400, MSG_ENTRAR);
      const r = await auth('/token?grant_type=password', { email: conta.email, password: senha });
      if (!r.ok) {
        if (r.status === 429) {
          throw new ErroPublico(503, 'Não foi possível entrar agora. Aguarde alguns minutos e tente de novo.');
        }
        if (r.status !== 400) console.error('acesso/entrar: falhou', r.status);
        throw new ErroPublico(400, MSG_ENTRAR);
      }
      await admin.rpc('fsm_tentativa_zerar', { p_chave: chaveUsuario });
      await registrarLogin(conta.user_id);
      return resposta(req, 200, { ok: true, sessao: sessao(r.dados) });
    }

    if (corpo.acao === 'trocar_senha') {
      const autorizacao = req.headers.get('Authorization') ?? '';
      const tokenUsuario = autorizacao.startsWith('Bearer ') ? autorizacao.slice(7).trim() : '';
      if (tokenUsuario.split('.').length !== 3) throw new ErroPublico(401, 'Sessão expirada. Entre de novo.');
      const eu = await authComo('GET', '/auth/v1/user', tokenUsuario);
      const id = eu.dados && typeof eu.dados.id === 'string' ? eu.dados.id : '';
      const mail = eu.dados && typeof eu.dados.email === 'string' ? eu.dados.email : '';
      if (!eu.ok || !id || !mail) throw new ErroPublico(401, 'Sessão expirada. Entre de novo.');
      const acesso = await authComo('POST', '/rest/v1/rpc/meu_acesso', tokenUsuario, {});
      if (!acesso.ok || !acesso.dados || acesso.dados.acesso_ok !== true) {
        throw new ErroPublico(403, 'Confirme o login com o código do autenticador antes de trocar a senha.');
      }
      const chaveTroca = 'trs:' + (await hashCurto('uid:' + id));
      if (!(await permitido(chaveTroca, 5))) {
        throw new ErroPublico(429, 'Muitas tentativas de troca de senha. Aguarde 15 minutos.');
      }

      const atual = typeof corpo.senha_atual === 'string' ? corpo.senha_atual.slice(0, 128) : '';
      const nova = typeof corpo.senha_nova === 'string' ? corpo.senha_nova : '';
      const confirma = typeof corpo.senha_confirma === 'string' ? corpo.senha_confirma : '';
      if (!atual) throw new ErroPublico(400, 'Digite a senha atual.');
      if (nova.length > 128) throw new ErroPublico(400, 'A senha nova pode ter no máximo 128 caracteres.');
      const falta = faltaNaSenha(nova);
      if (falta.length) throw new ErroPublico(400, 'A senha nova precisa ter: ' + falta.join(', ') + '.');
      if (nova !== confirma) throw new ErroPublico(400, 'As duas senhas novas não são iguais.');
      if (nova === atual) throw new ErroPublico(400, 'A senha nova precisa ser diferente da atual.');

      const conferida = await auth('/token?grant_type=password', { email: mail, password: atual });
      if (!conferida.ok) {
        if (conferida.status === 429) {
          throw new ErroPublico(503, 'Não foi possível conferir a senha agora. Aguarde alguns minutos.');
        }
        if (conferida.status !== 400) console.error('acesso/trocar_senha: conferência falhou', conferida.status);
        throw new ErroPublico(400, 'Senha atual incorreta.');
      }
      const tokenConferencia = conferida.dados && typeof conferida.dados.access_token === 'string'
        ? conferida.dados.access_token
        : '';
      if (tokenConferencia) await authComo('POST', '/auth/v1/logout?scope=local', tokenConferencia).catch(() => null);

      const troca = await authComo('PUT', '/auth/v1/user', tokenUsuario, { password: nova });
      if (!troca.ok) {
        const codigo = String((troca.dados && (troca.dados.error_code || troca.dados.code)) || '');
        const msg = String((troca.dados && (troca.dados.msg || troca.dados.message)) || '');
        if (codigo === 'weak_password' || /weak|pwned|leaked/i.test(msg)) {
          throw new ErroPublico(400, 'Senha fraca ou já vazada na internet. Escolha outra.');
        }
        if (codigo === 'same_password') throw new ErroPublico(400, 'A senha nova precisa ser diferente da atual.');
        if (codigo === 'reauthentication_needed') {
          throw new ErroPublico(400, 'Por segurança, saia e entre de novo antes de trocar a senha.');
        }
        console.error('acesso/trocar_senha: troca falhou', troca.status);
        throw new Error('troca falhou');
      }
      const outras = await authComo('POST', '/auth/v1/logout?scope=others', tokenUsuario).catch(() => null);
      if (!outras || !outras.ok) console.error('acesso/trocar_senha: saída dos outros aparelhos falhou');
      const { error: erroAud } = await admin.rpc('registrar_acao_admin', {
        p_ator: id,
        p_acao: 'TROCAR_SENHA',
        p_registro: id,
        p_detalhes: {},
      });
      if (erroAud) console.error('acesso/trocar_senha: auditoria falhou');
      return resposta(req, 200, { ok: true });
    }

    throw new ErroPublico(400, 'ação desconhecida');
  } catch (e) {
    if (e instanceof ErroPublico) return resposta(req, e.status, { erro: e.message });
    console.error('acesso: erro interno', e instanceof Error ? e.message : 'desconhecido');
    return resposta(req, 500, { erro: 'Não foi possível concluir agora. Tente de novo.' });
  }
}

Deno.serve(async (req) => {
  if (!origemPermitida(req)) return resposta(req, 403, { erro: 'origem não permitida' });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cabecalhos(req) });
  if (req.method !== 'POST') return resposta(req, 405, { erro: 'método não permitido' });
  const inicio = Date.now();
  const r = await atender(req);
  await esperar(Math.max(0, TEMPO_MINIMO_MS - (Date.now() - inicio)));
  return r;
});
