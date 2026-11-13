import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  cabecalhos,
  email,
  ErroPublico,
  lerJson,
  origemPermitida,
  resposta,
  texto,
  uuid,
} from '../_shared/seguranca.ts';

const PAPEIS = ['gerente', 'coordenador', 'analista', 'direcao', 'oficineiro'] as const;
type Papel = (typeof PAPEIS)[number];
type PapelAtor = Papel | 'administrador';
const DO_COORDENADOR: string[] = ['oficineiro', 'direcao'];
const PODEM_GERIR: string[] = ['gerente', 'coordenador', 'administrador'];

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

const semSessao = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };

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
    const papelAtor = acesso.papel as PapelAtor;
    if (!PODEM_GERIR.includes(papelAtor)) throw new ErroPublico(403, 'sem permissão para gerenciar contas');

    const admin = createClient(URL_SUPABASE, CHAVE_SERVICO, semSessao);
    const corpo = await lerJson(req);
    const auditar = (acao: string, registro: string, detalhes: Record<string, unknown>) =>
      admin.rpc('registrar_acao_admin', { p_ator: atorId, p_acao: acao, p_registro: registro, p_detalhes: detalhes });

    if (corpo.acao === 'cadastrar') {
      const papel = corpo.papel as Papel;
      if (!PAPEIS.includes(papel)) throw new ErroPublico(400, 'papel inválido');
      if (papelAtor === 'coordenador' && !DO_COORDENADOR.includes(papel)) {
        throw new ErroPublico(
          403,
          'o Coordenador do núcleo cadastra apenas contas de oficineiro e de direção escolar',
        );
      }
      const nome = texto(corpo.nome, 'nome', 3, 120);
      const mail = email(corpo.email);
      const cpf = typeof corpo.cpf === 'string' ? corpo.cpf.replace(/\D/g, '') : '';
      if (cpf.length < 10 || (cpf.length > 11 && cpf.length !== 14)) throw new ErroPublico(400, 'CPF ou CNPJ inválido');
      const usuario = typeof corpo.usuario === 'string' ? corpo.usuario.trim().toLowerCase() : '';
      if (usuario && !/^[a-z][a-z0-9._-]{3,29}$/.test(usuario)) {
        throw new ErroPublico(
          400,
          'login: use de 4 a 30 caracteres (letras minúsculas, números, ponto, hífen ou sublinhado), começando por letra',
        );
      }
      if (usuario && usuario.replace(/\D/g, '').length >= 11) {
        throw new ErroPublico(400, 'o login não pode ser o CPF nem o CNPJ');
      }
      const telefone = typeof corpo.telefone === 'string' ? corpo.telefone.replace(/\D/g, '') : '';
      if (telefone && (telefone.length < 10 || telefone.length > 11)) {
        throw new ErroPublico(400, 'telefone inválido: use DDD e número');
      }

      let escola_id: number | null = null;
      let carteira_id: string | null = null;
      if (papel === 'oficineiro' || papel === 'direcao') {
        const sigla = texto(corpo.escola_sigla, 'escola_sigla', 1, 8);
        const { data: esc } = await admin
          .from('escolas')
          .select('id')
          .eq('sigla', sigla)
          .eq('ativa', true)
          .maybeSingle();
        if (!esc) throw new ErroPublico(400, 'escola não encontrada');
        escola_id = esc.id;
      } else if (papel === 'analista') {
        carteira_id = texto(corpo.carteira_id, 'carteira_id', 2, 6).toUpperCase();
        const { data: cart } = await admin.from('carteiras').select('id').eq('id', carteira_id).maybeSingle();
        if (!cart) throw new ErroPublico(400, 'carteira não encontrada');
      }

      const { data: criado, error: erroCriar } = await admin.auth.admin.createUser({
        email: mail,
        email_confirm: true,
      });
      if (erroCriar || !criado?.user) {
        if (/already|registered|exists/i.test(erroCriar?.message ?? '')) {
          throw new ErroPublico(409, 'já existe uma conta com este e-mail');
        }
        throw new Error('falha ao criar conta: ' + (erroCriar?.message ?? 'sem detalhe'));
      }
      const novoId = criado.user.id;
      const desfazer = async () => {
        await admin.auth.admin.deleteUser(novoId);
      };
      const { error: erroPerfil } = await admin.from('perfis').insert({
        id: novoId,
        nome,
        papel,
        escola_id,
        carteira_id,
        ativo: true,
        trocar_senha: true,
        usuario: usuario || null,
        telefone: telefone || null,
      });
      if (erroPerfil) {
        await desfazer();
        if (erroPerfil.code === '23505') throw new ErroPublico(409, 'este login já está em uso; escolha outro');
        throw new Error('falha ao gravar perfil: ' + erroPerfil.code + ' ' + erroPerfil.message);
      }
      const { data: mascara, error: erroCpf } = await admin.rpc('fsm_definir_cpf', { p_user: novoId, p_cpf: cpf });
      if (erroCpf) {
        await desfazer();
        if (erroCpf.code === '23505') throw new ErroPublico(409, 'este CPF ou CNPJ já tem uma conta');
        throw new ErroPublico(400, 'CPF ou CNPJ inválido');
      }
      await auditar('CADASTRAR_USUARIO', novoId, {
        papel,
        escola_id,
        carteira_id,
        cpf: mascara,
        login_definido: !!usuario,
        telefone: !!telefone,
      });
      return resposta(req, 201, { id: novoId, cpf: mascara });
    }

    if (corpo.acao === 'desativar' || corpo.acao === 'reativar') {
      const alvoId = uuid(corpo.usuario_id, 'usuario_id');
      if (alvoId === atorId) throw new ErroPublico(400, 'não é possível alterar a própria conta');
      const { data: alvo } = await admin.from('perfis').select('papel').eq('id', alvoId).maybeSingle();
      if (!alvo) throw new ErroPublico(404, 'conta não encontrada');
      if (alvo.papel === 'administrador') {
        throw new ErroPublico(403, 'contas de administrador só são alteradas pelo painel do Supabase');
      }
      if (papelAtor === 'coordenador' && !DO_COORDENADOR.includes(alvo.papel)) {
        throw new ErroPublico(403, 'o Coordenador do núcleo altera apenas contas de oficineiro e de direção escolar');
      }

      const ativo = corpo.acao === 'reativar';
      const { error: e1 } = await admin.from('perfis').update({ ativo }).eq('id', alvoId);
      if (e1) throw new Error('falha ao atualizar perfil');
      const { error: e2 } = await admin.auth.admin.updateUserById(alvoId, { ban_duration: ativo ? 'none' : '876000h' });
      if (e2) throw new Error('falha ao atualizar login');
      await auditar(ativo ? 'REATIVAR_USUARIO' : 'DESATIVAR_USUARIO', alvoId, {});
      return resposta(req, 200, { ok: true });
    }

    if (corpo.acao === 'apagar') {
      if (papelAtor !== 'administrador') throw new ErroPublico(403, 'somente o Administrador apaga contas');
      const alvoId = uuid(corpo.usuario_id, 'usuario_id');
      if (alvoId === atorId) throw new ErroPublico(400, 'não é possível apagar a própria conta');
      const motivo = texto(corpo.motivo, 'motivo', 10, 500);
      const { data: alvo } = await admin.from('perfis').select('papel').eq('id', alvoId).maybeSingle();
      if (!alvo) throw new ErroPublico(404, 'conta não encontrada');
      if (alvo.papel === 'administrador') {
        throw new ErroPublico(403, 'contas de administrador só são alteradas pelo painel do Supabase');
      }
      const { data: res, error: erroRemover } = await admin.rpc('remover_conta', {
        p_ator: atorId,
        p_id: alvoId,
        p_motivo: motivo,
      });
      if (erroRemover || !res) {
        throw new Error(`falha ao apagar conta: ${erroRemover?.code ?? ''} ${erroRemover?.message ?? ''}`);
      }
      if (res.login === 'pendente') {
        if (res.resultado === 'apagada') {
          const { error: e1 } = await admin.auth.admin.deleteUser(alvoId);
          if (e1) throw new Error(`falha ao apagar login: ${e1.message}`);
        } else {
          const { error: e2 } = await admin.auth.admin.updateUserById(alvoId, {
            email: `removida.${alvoId.replaceAll('-', '')}@conta.invalid`,
            password: crypto.randomUUID() + crypto.randomUUID(),
            user_metadata: {},
            ban_duration: '876000h',
          });
          if (e2) throw new Error(`falha ao limpar login: ${e2.message}`);
          const { data: lista } = await admin.auth.admin.mfa.listFactors({ userId: alvoId });
          for (const f of lista?.factors ?? []) await admin.auth.admin.mfa.deleteFactor({ id: f.id, userId: alvoId });
        }
      }
      await auditar('ADMIN_APAGAR_CONTA', alvoId, { papel: alvo.papel, resultado: res.resultado, motivo });
      return resposta(req, 200, { ok: true, resultado: res.resultado });
    }

    if (corpo.acao === 'ver_email' || corpo.acao === 'alterar_email') {
      if (papelAtor !== 'administrador') {
        throw new ErroPublico(403, 'somente o Administrador consulta e altera o e-mail');
      }
      const alvoId = uuid(corpo.usuario_id, 'usuario_id');
      if (alvoId === atorId) throw new ErroPublico(400, 'não é possível alterar a própria conta');
      const { data: alvo } = await admin.from('perfis').select('papel, removido_em').eq('id', alvoId).maybeSingle();
      if (!alvo || alvo.removido_em) throw new ErroPublico(404, 'conta não encontrada');
      if (alvo.papel === 'administrador') {
        throw new ErroPublico(403, 'contas de administrador só são alteradas pelo painel do Supabase');
      }
      if (corpo.acao === 'ver_email') {
        const { data: u, error: erroVer } = await admin.auth.admin.getUserById(alvoId);
        if (erroVer || !u?.user) throw new Error(`falha ao consultar o e-mail: ${erroVer?.message ?? ''}`);
        await auditar('ADMIN_VER_EMAIL', alvoId, {});
        return resposta(req, 200, { ok: true, email: u.user.email ?? '' });
      }
      const motivo = texto(corpo.motivo, 'motivo', 10, 500);
      const mail = email(corpo.email);
      const { error: erroEmail } = await admin.auth.admin.updateUserById(alvoId, { email: mail, email_confirm: true });
      if (erroEmail) {
        if (
          (erroEmail as { code?: string }).code === 'email_exists' ||
          /already|registered|exists/i.test(erroEmail.message)
        ) {
          throw new ErroPublico(409, 'este e-mail já é usado por outra conta');
        }
        throw new Error(`falha ao alterar o e-mail: ${erroEmail.message}`);
      }
      await auditar('ADMIN_ALTERAR_EMAIL', alvoId, { motivo });
      return resposta(req, 200, { ok: true, email: mail });
    }

    if (corpo.acao === 'redefinir_mfa') {
      if (papelAtor !== 'administrador') throw new ErroPublico(403, 'somente o Administrador redefine o autenticador');
      const alvoId = uuid(corpo.usuario_id, 'usuario_id');
      if (alvoId === atorId) throw new ErroPublico(400, 'não é possível alterar a própria conta');
      const motivo = texto(corpo.motivo, 'motivo', 10, 500);
      const { data: alvo } = await admin.from('perfis').select('papel').eq('id', alvoId).maybeSingle();
      if (!alvo) throw new ErroPublico(404, 'conta não encontrada');
      if (alvo.papel === 'administrador') {
        throw new ErroPublico(403, 'contas de administrador só são alteradas pelo painel do Supabase');
      }
      const { data: lista, error: erroLista } = await admin.auth.admin.mfa.listFactors({ userId: alvoId });
      if (erroLista) throw new Error('falha ao consultar o autenticador');
      const fatores = lista?.factors ?? [];
      for (const f of fatores) {
        const { error: erroApagar } = await admin.auth.admin.mfa.deleteFactor({ id: f.id, userId: alvoId });
        if (erroApagar) throw new Error('falha ao redefinir o autenticador');
      }
      await auditar('ADMIN_REDEFINIR_AUTENTICADOR', alvoId, { fatores: fatores.length, motivo });
      return resposta(req, 200, { ok: true, fatores: fatores.length });
    }

    throw new ErroPublico(400, 'ação desconhecida');
  } catch (e) {
    if (e instanceof ErroPublico) return resposta(req, e.status, { erro: e.message });
    console.error('admin-usuarios: erro interno', e instanceof Error ? e.message : 'desconhecido');
    return resposta(req, 500, { erro: 'erro interno' });
  }
});
