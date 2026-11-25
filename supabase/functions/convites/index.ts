import { createClient } from 'npm:@supabase/supabase-js@2';
import { cabecalhos, ErroPublico, lerJson, origemPermitida, resposta, uuid } from '../_shared/seguranca.ts';
import { ASSUNTO, modeloHtml, modeloTexto } from './modelo.ts';

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
const CHAVE_ANON = chave('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
const CHAVE_SERVICO = chave('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
const URL_RESEND = 'https://api.resend.com/emails/batch';
const MAXIMO = 50;
const PODEM_ENVIAR: string[] = ['administrador', 'gerente', 'coordenador'];

const semSessao = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };

type Reserva = {
  usuario_id: string;
  convite_id: number | null;
  resultado: string;
  nome: string | null;
  email: string | null;
};
type Resultado = { convite_id: number; ok: boolean; detalhe?: string };

async function enviar(reservas: Reserva[], remetente: string, site: string, chaveResend: string): Promise<Resultado[]> {
  const ids = reservas.map((r) => r.convite_id!);
  try {
    const r = await fetch(URL_RESEND, {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + chaveResend,
        'Content-Type': 'application/json',
        'Idempotency-Key': 'convites-' + ids.join('-').slice(0, 200),
      },
      body: JSON.stringify(
        reservas.map((c) => ({
          from: remetente,
          to: [c.email],
          subject: ASSUNTO,
          html: modeloHtml(c.nome ?? '', site),
          text: modeloTexto(c.nome ?? '', site),
        })),
      ),
    });
    if (!r.ok) {
      const detalhe = 'recusado pelo serviço de e-mail (' + r.status + ')';
      console.error('convites: envio recusado', r.status);
      return ids.map((id) => ({ convite_id: id, ok: false, detalhe }));
    }
    return ids.map((id) => ({ convite_id: id, ok: true }));
  } catch {
    console.error('convites: serviço de e-mail indisponível');
    return ids.map((id) => ({ convite_id: id, ok: false, detalhe: 'serviço de e-mail indisponível' }));
  }
}

Deno.serve(async (req) => {
  if (!origemPermitida(req)) return resposta(req, 403, { erro: 'origem não permitida' });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cabecalhos(req) });
  if (req.method !== 'POST') return resposta(req, 405, { erro: 'método não permitido' });

  try {
    const autorizacao = req.headers.get('Authorization') ?? '';
    if (!autorizacao.startsWith('Bearer ')) throw new ErroPublico(401, 'faça login');
    const comoUsuario = createClient(URL_SUPABASE, CHAVE_ANON, {
      ...semSessao,
      global: { headers: { Authorization: autorizacao } },
    });
    const { data: sessao, error: erroSessao } = await comoUsuario.auth.getUser(autorizacao.slice(7));
    if (erroSessao || !sessao?.user) throw new ErroPublico(401, 'sessão inválida ou expirada');
    const atorId = sessao.user.id;

    const { data: acesso, error: erroAcesso } = await comoUsuario.rpc('meu_acesso');
    if (erroAcesso || !acesso) throw new ErroPublico(403, 'sem permissão');
    if (!acesso.acesso_ok) throw new ErroPublico(403, 'confirme o login com o código do autenticador (MFA)');
    if (!PODEM_ENVIAR.includes(acesso.papel)) throw new ErroPublico(403, 'sem permissão para enviar convites');
    const ehAdmin = acesso.papel === 'administrador';

    const corpo = await lerJson(req);
    if (corpo.acao !== 'enviar') throw new ErroPublico(400, 'ação desconhecida');
    if (!Array.isArray(corpo.ids) || corpo.ids.length === 0) throw new ErroPublico(400, 'selecione ao menos uma conta');
    if (corpo.ids.length > MAXIMO) throw new ErroPublico(400, `envie no máximo ${MAXIMO} convites por vez`);
    const ids = [...new Set(corpo.ids.map((v) => uuid(v, 'ids')))];
    const reenviar = corpo.reenviar === true;
    if (!ehAdmin && (reenviar || ids.length !== 1)) {
      throw new ErroPublico(403, 'o reenvio e o envio em grupo são feitos pelo Administrador');
    }

    const chaveResend = Deno.env.get('RESEND_API_KEY') ?? '';
    const remetente = Deno.env.get('FSM_CONVITE_REMETENTE') ?? '';
    const site = (Deno.env.get('FSM_SITE_URL') ?? '').trim();
    if (!chaveResend || !remetente || !/^https:\/\/[^\s"'<>]+$/.test(site)) {
      throw new ErroPublico(503, 'o envio de e-mails ainda não foi configurado no Supabase');
    }

    const admin = createClient(URL_SUPABASE, CHAVE_SERVICO, semSessao);
    const { data: reservas, error: erroReserva } = await admin.rpc('convites_reservar', {
      p_ator: atorId,
      p_ids: ids,
      p_reenviar: reenviar,
    });
    if (erroReserva) {
      if (erroReserva.code === '42501') throw new ErroPublico(403, 'sem permissão para enviar este convite');
      if (erroReserva.code === '22023') throw new ErroPublico(400, erroReserva.message);
      throw new Error('falha ao reservar convites: ' + erroReserva.code);
    }
    const lista = (reservas ?? []) as Reserva[];
    const reservados = lista.filter((r) => r.resultado === 'reservado' && r.convite_id && r.email);
    const conta = (resultado: string) => lista.filter((r) => r.resultado === resultado).length;

    let enviados = 0;
    let falhas = 0;
    if (reservados.length) {
      const resultados = await enviar(reservados, remetente, site.replace(/\/+$/, '') + '/', chaveResend);
      const { data: concluido, error: erroConcluir } = await admin.rpc('convites_concluir', {
        p_ator: atorId,
        p_resultados: resultados,
      });
      if (erroConcluir) throw new Error('falha ao registrar convites: ' + erroConcluir.code);
      enviados = Number(concluido?.enviados ?? 0);
      falhas = Number(concluido?.falhas ?? 0);
    }

    return resposta(req, 200, {
      ok: true,
      enviados,
      falhas,
      ja_enviados: conta('ja_enviado'),
      em_envio: conta('em_envio'),
      indisponiveis: conta('indisponivel'),
    });
  } catch (e) {
    if (e instanceof ErroPublico) return resposta(req, e.status, { erro: e.message });
    console.error('convites: erro interno', e instanceof Error ? e.message : 'desconhecido');
    return resposta(req, 500, { erro: 'erro interno' });
  }
});
