window.FSM_AUTH =
  window.FSM_AUTH ||
  (() => {
    function cfg() {
      return window.FSM_CONFIG || {};
    }
    function urlBase() {
      return String(cfg().url || '').replace(/\/+$/, '');
    }
    function chave() {
      return String(cfg().chave || '');
    }
    const CAMPOS_PRES =
      'id,oficineiro_id,escola_id,data,inicio,fim,pausa_inicio,pausa_fim,conferencia,distancia_inicio_m,distancia_fim_m,entrou_raio_em,distancia_entrada_m,excedente_min,excedente_status,motivo,justificativa,motivo_excedente,justificativa_excedente,conferencia_status,conferencia_obs,excedente_obs,trabalhado_min,previsto_min,compensacao_min,deficit_min,deficit_status,motivo_deficit,justificativa_deficit,compensar_em,deficit_obs,deficit_decidido_em,atraso_min,horario_status,motivo_horario,justificativa_horario,horario_obs,horario_decidido_em,conferido_em,decidido_em,ponto,falta_status,falta_motivo,falta_justificativa,falta_horarios,falta_obs,falta_decidido_em,marcacoes_informadas';
    const CHAVE_RT = 'fsm_rt';
    const CHAVE_LEMBRAR = 'fsm_lembrar';
    const CHAVE_PEDIDO = 'fsm_pedido_codigo';
    const PEDIDO_MS = 65 * 60 * 1000;
    const INATIVIDADE_MS = 30 * 60 * 1000;
    const CORTE_HORA_SP = 4;
    const CORTE_MIN_MS = 60 * 60 * 1000;
    let lembrarAte = 0;

    function proximoCorte(agora) {
      const fuso = 3 * 60 * 60 * 1000;
      const local = new Date(agora - fuso);
      let corte = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate(), CORTE_HORA_SP, 0, 0) + fuso;
      while (corte - agora < CORTE_MIN_MS) corte += 24 * 60 * 60 * 1000;
      return corte;
    }

    function lerLembrar() {
      try {
        const d = JSON.parse(localStorage.getItem(CHAVE_LEMBRAR) || 'null');
        if (d && typeof d.rt === 'string' && typeof d.ate === 'number') return d;
      } catch (e) {}
      return null;
    }

    function termos(t) {
      const guarda = [];
      return String(t == null ? '' : t)
        .replace(/aula regular/gi, m => {
          guarda.push(m);
          return '\u0000' + (guarda.length - 1) + '\u0001';
        })
        .replace(/\bAulas\b/g, 'Atividades')
        .replace(/\bAula\b/g, 'Atividade')
        .replace(/\baulas\b/g, 'atividades')
        .replace(/\baula\b/g, 'atividade')
        .replace(/\u0000(\d+)\u0001/g, (m, k) => guarda[Number(k)]);
    }

    let sessao = null;

    let doLink = (() => {
      const h = String(location.hash || '').replace(/^#/, '');
      const s = String(location.search || '').replace(/^\?/, '');
      if (!/access_token=|error=|error_description=/.test(h + '&' + s)) return null;
      try {
        history.replaceState(null, '', location.pathname);
      } catch (e) {}
      const q = new URLSearchParams(h);
      const qs = new URLSearchParams(s);
      const codigoErro = q.get('error_code') || qs.get('error_code') || q.get('error') || qs.get('error');
      if (codigoErro) return { erro: true, motivo: codigoErro };
      const at = q.get('access_token');
      const rt = q.get('refresh_token');
      if (!at || !rt || at.split('.').length !== 3) return null;
      return {
        access_token: at,
        refresh_token: rt,
        expires_in: Number(q.get('expires_in')) || 900,
        expires_at: Number(q.get('expires_at')) || 0
      };
    })();
    let timerRenova = null;
    let timerInativo = null;
    let aoExpirar = null;

    function configurado() {
      return /^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(urlBase()) && /^(sb_publishable_|eyJ)/.test(chave());
    }

    function traduz(status, corpo) {
      const c = (corpo && (corpo.error_code || corpo.code || corpo.error)) || '';
      const m = (corpo && (corpo.msg || corpo.message || corpo.error_description)) || '';
      if (status === 429 || /rate/i.test(c)) return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
      if (c === 'invalid_credentials' || /invalid login/i.test(m)) return 'Usuário ou senha incorretos.';
      if (c === 'user_banned') return 'Esta conta está desativada. Procure o gerente do projeto.';
      if (c === 'email_not_confirmed') return 'O e-mail desta conta ainda não foi confirmado.';
      if (c === 'mfa_verification_failed' || /invalid totp|invalid code/i.test(m))
        return 'Código do autenticador inválido ou vencido.';
      if (c === 'same_password' || /different from the old/i.test(m))
        return 'A senha nova precisa ser diferente da atual.';
      if (c === 'weak_password' || /weak|pwned|leaked/i.test(m))
        return 'Senha fraca ou já vazada na internet. Escolha outra.';
      if (c === 'reauthentication_needed' || /reauthenticat/i.test(m))
        return 'Por segurança, entre de novo antes de trocar a senha.';
      if (corpo && corpo.code === '22023' && m) return m.charAt(0).toUpperCase() + m.slice(1) + '.';
      if (status === 401 || status === 403) return 'Sessão expirada. Entre de novo.';
      return 'Não foi possível concluir agora. Tente de novo.';
    }

    async function chamar(caminho, opcoes) {
      if (!configurado()) throw new Error('O site ainda não foi ligado ao Supabase (arquivo fsm_config.js).');
      opcoes = opcoes || {};
      const cab = { apikey: chave(), 'Content-Type': 'application/json' };
      if (opcoes.token) cab['Authorization'] = 'Bearer ' + opcoes.token;
      if (opcoes.representacao) cab['Prefer'] = 'return=representation';
      let r;
      try {
        r = await fetch(urlBase() + caminho, {
          method: opcoes.metodo || 'GET',
          headers: cab,
          cache: 'no-store',
          credentials: 'omit',
          referrerPolicy: 'no-referrer',
          body: opcoes.corpo === undefined ? undefined : JSON.stringify(opcoes.corpo)
        });
      } catch (e) {
        throw new Error('Sem conexão com o servidor. Verifique a internet.');
      }
      const txt = await r.text();
      let corpo = null;
      try {
        corpo = txt ? JSON.parse(txt) : null;
      } catch (e) {
        corpo = null;
      }
      if (!r.ok) {
        const msg =
          caminho.indexOf('/functions/') === 0 && corpo && typeof corpo.erro === 'string'
            ? corpo.erro
            : traduz(r.status, corpo);
        const err = new Error(termos(msg));
        err.status = r.status;
        throw err;
      }
      return corpo;
    }

    const PAGINA = 1000;
    async function chamarTudo(caminho, opcoes) {
      let todos = [];
      let inicio = 0;
      for (let volta = 0; volta < 200; volta++) {
        const r = await chamar(
          caminho + (caminho.indexOf('?') >= 0 ? '&' : '?') + 'limit=' + PAGINA + '&offset=' + inicio,
          opcoes
        );
        if (!Array.isArray(r)) return r;
        todos = todos.concat(r);
        if (r.length < PAGINA) return todos;
        inicio += r.length;
      }
      throw new Error('Consulta grande demais. Escolha um período menor.');
    }

    function claims(token) {
      try {
        const p = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
        return JSON.parse(decodeURIComponent(escape(atob(p + '==='.slice((p.length + 3) % 4)))));
      } catch (e) {
        return {};
      }
    }

    function guarda(r) {
      if (!r || !r.access_token || !r.refresh_token) throw new Error('Resposta de login inválida.');
      sessao = {
        access_token: r.access_token,
        refresh_token: r.refresh_token,
        expires_at: r.expires_at || Math.floor(Date.now() / 1000) + (r.expires_in || 900)
      };
      if (lembrarAte) {
        try {
          localStorage.setItem(CHAVE_LEMBRAR, JSON.stringify({ rt: sessao.refresh_token, ate: lembrarAte }));
        } catch (e) {}
        try {
          sessionStorage.removeItem(CHAVE_RT);
        } catch (e) {}
      } else {
        try {
          sessionStorage.setItem(CHAVE_RT, sessao.refresh_token);
        } catch (e) {}
      }
      clearTimeout(timerRenova);
      const ms = Math.max(30, sessao.expires_at - Math.floor(Date.now() / 1000) - 60) * 1000;
      timerRenova = setTimeout(() => {
        renovar().catch(() => {
          encerrar('expirou');
        });
      }, ms);
      vigiaInatividade();
    }

    function limpa() {
      sessao = null;
      clearTimeout(timerRenova);
      clearTimeout(timerInativo);
      lembrarAte = 0;
      try {
        sessionStorage.removeItem(CHAVE_RT);
      } catch (e) {}
      try {
        localStorage.removeItem(CHAVE_RT);
      } catch (e) {}
      try {
        localStorage.removeItem(CHAVE_LEMBRAR);
      } catch (e) {}
    }

    let renovando = null;
    function encerrar(motivo) {
      const t = sessao && sessao.access_token;
      limpa();
      renovando = null;
      if (t) chamar('/auth/v1/logout?scope=local', { metodo: 'POST', token: t }).catch(() => {});
      if (aoExpirar) aoExpirar(motivo || 'saiu');
    }

    let ultimoUso = Date.now();
    let vigiando = false;
    function vigiaInatividade() {
      if (!vigiando) {
        vigiando = true;
        ['click', 'keydown', 'pointermove', 'scroll', 'touchstart'].forEach(ev => {
          window.addEventListener(
            ev,
            () => {
              ultimoUso = Date.now();
            },
            { passive: true, capture: true }
          );
        });
      }
      clearTimeout(timerInativo);
      (function checa() {
        timerInativo = setTimeout(() => {
          if (!sessao) return;
          if (lembrarAte) {
            if (Date.now() >= lembrarAte) encerrar('prazo');
            else checa();
          } else if (Date.now() - ultimoUso >= INATIVIDADE_MS) encerrar('inatividade');
          else checa();
        }, 60 * 1000);
      })();
    }

    function renovar() {
      if (renovando) return renovando;
      renovando = (async () => {
        let rt = sessao && sessao.refresh_token;
        if (!rt) {
          try {
            rt = sessionStorage.getItem(CHAVE_RT);
          } catch (e) {}
        }
        if (!rt) {
          const d = lerLembrar();
          if (d && Date.now() < d.ate) {
            rt = d.rt;
            lembrarAte = d.ate;
          } else if (d) {
            try {
              localStorage.removeItem(CHAVE_LEMBRAR);
            } catch (e) {}
            try {
              const v = await chamar('/auth/v1/token?grant_type=refresh_token', {
                metodo: 'POST',
                corpo: { refresh_token: d.rt }
              });
              await chamar('/auth/v1/logout?scope=local', { metodo: 'POST', token: v.access_token });
            } catch (e) {}
            throw new Error('prazo');
          }
        }
        if (!rt) throw new Error('sem sessão');
        const r = await chamar('/auth/v1/token?grant_type=refresh_token', {
          metodo: 'POST',
          corpo: { refresh_token: rt }
        });
        guarda(r);
        return r;
      })();
      renovando.then(
        () => {
          renovando = null;
        },
        () => {
          renovando = null;
        }
      );
      return renovando;
    }

    function token() {
      if (!sessao || !sessao.access_token) throw new Error('Sessão expirada. Entre de novo.');
      return sessao.access_token;
    }

    function telaAtual() {
      const hs = document.querySelectorAll('[data-fsm-tela], main h1, header h1');
      for (let i = 0; i < hs.length; i++) {
        const t = (hs[i].textContent || '').trim();
        if (t && t !== 'Oficineiro+' && hs[i].getClientRects().length) return t;
      }
      return '';
    }

    function registrar(tipo, detalhes) {
      try {
        if (!configurado() || !sessao || !sessao.access_token) return Promise.resolve();
        detalhes = Object.assign({}, detalhes || {});
        if (!detalhes.tela || detalhes.tela === 'Oficineiro+') detalhes.tela = telaAtual() || detalhes.tela || null;
        return chamar('/rest/v1/rpc/registrar_atividade', {
          metodo: 'POST',
          token: sessao.access_token,
          corpo: { p_tipo: String(tipo), p_detalhes: detalhes }
        }).catch(() => {});
      } catch (e) {
        return Promise.resolve();
      }
    }

    function comRecusa(promessa, detalhes) {
      return promessa.catch(e => {
        if (e && e.status >= 400 && e.status < 500 && e.status !== 401)
          registrar('PRESENCA_RECUSADA', Object.assign({ motivo: e.message }, detalhes));
        throw e;
      });
    }

    if (typeof window !== 'undefined' && window.addEventListener)
      window.addEventListener('beforeprint', () => {
        registrar('EXPORTACAO', { formato: 'PDF ou impressão', tela: telaAtual() || document.title || 'Página' });
      });

    return {
      configurado,
      aoExpirar(fn) {
        aoExpirar = fn;
      },
      sessaoDoLink() {
        if (!doLink) return false;
        const d = doLink;
        doLink = null;
        if (d.erro) return 'erro';
        let pedido = 0;
        try {
          pedido = Number(localStorage.getItem(CHAVE_PEDIDO)) || 0;
          localStorage.removeItem(CHAVE_PEDIDO);
        } catch (e) {}
        if (!pedido || Date.now() > pedido) {
          chamar('/auth/v1/logout?scope=local', { metodo: 'POST', token: d.access_token }).catch(() => {});
          return 'outro';
        }
        if (!d.expires_at) delete d.expires_at;
        guarda(d);
        return true;
      },
      temSessaoGuardada() {
        try {
          if (sessionStorage.getItem(CHAVE_RT)) return true;
        } catch (e) {}
        return !!lerLembrar();
      },
      retomar() {
        return renovar().catch(e => {
          if (!sessao) limpa();
          throw e;
        });
      },

      async entrar(usuario, senha, manterConectado) {
        usuario = String(usuario || '')
          .trim()
          .toLowerCase();
        if (!usuario || !senha) throw new Error('Informe usuário e senha.');
        limpa();
        if (manterConectado) lembrarAte = proximoCorte(Date.now());
        const r = await chamar('/functions/v1/acesso', {
          metodo: 'POST',
          corpo: { acao: 'entrar', usuario, senha: String(senha) }
        });
        guarda(r && r.sessao);
      },

      async pedirCodigo(cpf) {
        const d = String(cpf || '').replace(/\D/g, '');
        if (d.length !== 11 && d.length !== 14) throw new Error('Digite o CPF (11 números) ou o CNPJ (14 números).');
        const r = await chamar('/functions/v1/acesso', { metodo: 'POST', corpo: { acao: 'codigo', cpf: d } });
        try {
          localStorage.setItem(CHAVE_PEDIDO, String(Date.now() + PEDIDO_MS));
        } catch (e) {}
        return (
          (r && r.mensagem) ||
          'Se o documento tiver um primeiro acesso pendente, enviamos um código para o e-mail institucional.'
        );
      },
      async confirmarPrimeiroAcesso(cpf, codigo) {
        const d = String(cpf || '').replace(/\D/g, '');
        const c = String(codigo || '').replace(/\D/g, '');
        if (c.length < 6) throw new Error('Digite o código recebido no e-mail.');
        limpa();
        const r = await chamar('/functions/v1/acesso', {
          metodo: 'POST',
          corpo: { acao: 'confirmar', cpf: d, codigo: c }
        });
        try {
          localStorage.removeItem(CHAVE_PEDIDO);
        } catch (e) {}
        guarda(r && r.sessao);
      },

      gerarMeuUsuario() {
        return chamar('/rest/v1/rpc/gerar_meu_usuario', { metodo: 'POST', token: token(), corpo: {} });
      },

      sair() {
        encerrar('saiu');
      },

      logado() {
        return !!(sessao && sessao.access_token);
      },

      async minhaEscola() {
        const r = await chamar('/rest/v1/rpc/minha_escola', { metodo: 'POST', token: token(), corpo: {} });
        return (r && r[0]) || null;
      },
      marcarPresenca(tipo, lat, lng, precisao) {
        const rotulo = {
          entrada: 'Entrada',
          saida_almoco: 'Saída para almoço',
          retorno_almoco: 'Volta do almoço',
          saida: 'Saída'
        };
        return comRecusa(
          chamar('/rest/v1/rpc/marcar_presenca', {
            metodo: 'POST',
            token: token(),
            corpo: {
              p_tipo: tipo,
              p_lat: lat == null ? null : Number(lat),
              p_lng: lng == null ? null : Number(lng),
              p_precisao: precisao == null ? null : Math.round(precisao)
            }
          }),
          { evento: rotulo[tipo] || 'Presença' }
        );
      },
      minhaPresencaHoje() {
        return chamar('/rest/v1/rpc/minha_presenca_hoje', { metodo: 'POST', token: token(), corpo: {} });
      },
      meuEspelho(competencia) {
        if (competencia && !/^\d{4}-\d{2}-\d{2}$/.test(String(competencia)))
          return Promise.reject(new Error('Mês inválido.'));
        return chamar('/rest/v1/rpc/meu_espelho', {
          metodo: 'POST',
          token: token(),
          corpo: { p_competencia: competencia || null }
        });
      },
      assinarEspelho(competencia) {
        return chamar('/rest/v1/rpc/assinar_espelho', {
          metodo: 'POST',
          token: token(),
          corpo: { p_competencia: competencia }
        });
      },
      solicitarAjuste(d) {
        return chamar('/rest/v1/rpc/solicitar_ajuste', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_tipo: d.tipo,
            p_data: d.data,
            p_entrada: d.entrada || null,
            p_saida_almoco: d.saidaAlmoco || null,
            p_retorno_almoco: d.retornoAlmoco || null,
            p_saida: d.saida || null,
            p_motivo: d.motivo
          }
        });
      },
      decidirAjuste(id, aprovar, obs) {
        return chamar('/rest/v1/rpc/decidir_ajuste', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: id, p_aprovar: !!aprovar, p_obs: obs || null }
        });
      },
      ajustesPresenca(status) {
        return chamar('/rest/v1/rpc/ajustes_presenca', {
          metodo: 'POST',
          token: token(),
          corpo: { p_status: status || null }
        });
      },
      relatorioJustificativas(status, de, ate) {
        const iso = /^\d{4}-\d{2}-\d{2}$/;
        if ((de && !iso.test(String(de))) || (ate && !iso.test(String(ate))))
          return Promise.reject(new Error('Período inválido.'));
        return chamar('/rest/v1/rpc/relatorio_justificativas', {
          metodo: 'POST',
          token: token(),
          corpo: { p_status: status || null, p_de: de || null, p_ate: ate || null }
        });
      },
      sinalizarAjuste(id, mensagem) {
        return chamar('/rest/v1/rpc/sinalizar_ajuste', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: id, p_mensagem: String(mensagem || '').trim() }
        });
      },
      espelhoOficineiro(oficineiro, competencia) {
        if (competencia && !/^\d{4}-\d{2}-\d{2}$/.test(String(competencia)))
          return Promise.reject(new Error('Mês inválido.'));
        return chamar('/rest/v1/rpc/espelho_oficineiro', {
          metodo: 'POST',
          token: token(),
          corpo: { p_oficineiro: oficineiro, p_competencia: competencia || null }
        });
      },
      painelPresenca() {
        return chamar('/rest/v1/rpc/painel_presenca', { metodo: 'POST', token: token(), corpo: {} });
      },
      registrarAtividade(tipo, detalhes) {
        return registrar(tipo, detalhes);
      },
      gradeAulas(anoLetivo) {
        const a = Number(anoLetivo);
        if (!(a >= 2024 && a <= 2100)) return Promise.reject(new Error('Ano letivo inválido.'));
        return chamar(
          '/rest/v1/grade_aulas?select=id,ano_letivo,dia_semana,horario,inicio,fim,ano,turma,tipo,solucao,oficina,professor,espaco,observacao,componente,criado_em&order=dia_semana,inicio&ano_letivo=eq.' +
            a,
          { token: token() }
        );
      },
      async salvarAulaGrade(id, dados) {
        const campos = [
          'ano_letivo',
          'dia_semana',
          'horario',
          'inicio',
          'fim',
          'ano',
          'turma',
          'tipo',
          'solucao',
          'oficina',
          'professor',
          'espaco',
          'observacao',
          'componente'
        ];
        const corpo = {};
        campos.forEach(k => {
          if (k in dados) corpo[k] = dados[k];
        });
        if (id) delete corpo.ano_letivo;
        const r = id
          ? await chamar('/rest/v1/grade_aulas?id=eq.' + encodeURIComponent(id), {
              metodo: 'PATCH',
              token: token(),
              corpo,
              representacao: true
            })
          : await chamar('/rest/v1/grade_aulas', { metodo: 'POST', token: token(), corpo, representacao: true });
        if (!r || !r[0]) throw new Error('Não foi possível salvar a atividade.');
        return r[0];
      },
      semanasGrade(anoLetivo) {
        const a = Number(anoLetivo);
        if (!(a >= 2024 && a <= 2100)) return Promise.reject(new Error('Ano letivo inválido.'));
        return chamarTudo(
          '/rest/v1/grade_semanas?select=id,grade_aula_id,oficineiro_id,semana,tipo,solucao,componente,oficina&order=semana,id&ano_letivo=eq.' +
            a,
          { token: token() }
        );
      },
      salvarSemanaGrade(semana, itens) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(semana))) return Promise.reject(new Error('Semana inválida.'));
        const lista = (itens || []).map(i => ({
          grade_aula_id: Number(i.grade_aula_id),
          tipo: String(i.tipo),
          solucao: String(i.solucao || ''),
          componente: i.componente ? String(i.componente) : null,
          oficina: i.oficina ? String(i.oficina) : null
        }));
        return chamar('/rest/v1/rpc/salvar_semana_grade', {
          metodo: 'POST',
          token: token(),
          corpo: { p_semana: semana, p_itens: lista }
        });
      },
      copiarSemanaGrade(origem, destinos) {
        const ok = /^\d{4}-\d{2}-\d{2}$/;
        if (!ok.test(String(origem)) || !Array.isArray(destinos) || !destinos.every(d => ok.test(String(d))))
          return Promise.reject(new Error('Semana inválida.'));
        return chamar('/rest/v1/rpc/copiar_semana_grade', {
          metodo: 'POST',
          token: token(),
          corpo: { p_origem: origem, p_destinos: destinos }
        });
      },
      async excluirAulaGrade(id) {
        const r = await chamar('/rest/v1/grade_aulas?id=eq.' + encodeURIComponent(id), {
          metodo: 'DELETE',
          token: token(),
          representacao: true
        });
        if (!r || !r[0]) throw new Error('Não foi possível excluir a atividade.');
      },
      registrosDoDia(data) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(data))) return Promise.reject(new Error('Data inválida.'));
        return chamar(
          '/rest/v1/aulas_registro?select=id,grade_aula_id,data,horario,inicio,fim,tipo,oficina,situacao,motivo,presentes,matriculados,conteudo,solucao,professor_aula,mudanca,componente,atividade,objetivo,engajamento,proxima_aula,check_direcao,check_motivo,check_em,revisao_status,revisao_obs&data=eq.' +
            data,
          { token: token() }
        );
      },
      async salvarRegistroAula(id, dados) {
        const novos = ['grade_aula_id', 'data', 'inicio', 'fim', 'turma', 'tipo'];
        const campos = [
          'solucao',
          'oficina',
          'presentes',
          'matriculados',
          'situacao',
          'motivo',
          'conteudo',
          'professor_aula',
          'mudanca',
          'componente',
          'atividade',
          'objetivo',
          'engajamento',
          'proxima_aula'
        ];
        const corpo = {};
        (id ? campos : novos.concat(campos)).forEach(k => {
          if (k in dados) corpo[k] = dados[k];
        });
        const r = id
          ? await chamar('/rest/v1/aulas_registro?id=eq.' + encodeURIComponent(id), {
              metodo: 'PATCH',
              token: token(),
              corpo,
              representacao: true
            })
          : await chamar('/rest/v1/aulas_registro', {
              metodo: 'POST',
              token: token(),
              corpo,
              representacao: true
            });
        if (!r || !r[0])
          throw new Error('Não foi possível salvar o registro. Confira se ele ainda está dentro do prazo.');
        return r[0];
      },
      presencasPeriodo(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamar(
          '/rest/v1/presencas?select=id,data,inicio,fim,pausa_inicio,pausa_fim,conferencia,excedente_min,excedente_status,motivo,justificativa,motivo_excedente,conferencia_status,conferencia_obs,excedente_obs,trabalhado_min,ponto,falta_status,falta_motivo,falta_horarios,falta_obs,marcacoes_informadas&order=data&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      registrosPeriodo(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamar(
          '/rest/v1/aulas_registro?select=id,grade_aula_id,data,horario,inicio,fim,turma,tipo,solucao,oficina,situacao,motivo,presentes,matriculados,conteudo,professor_aula,mudanca,componente,atividade,objetivo,engajamento,proxima_aula,check_direcao,check_motivo,check_em,revisao_status,revisao_obs,revisado_em&order=data,inicio&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      async relatorioDoMes(competencia) {
        if (!/^\d{4}-\d{2}-01$/.test(String(competencia))) throw new Error('Mês inválido.');
        const r = await chamar(
          '/rest/v1/relatorios_mensais?select=id,competencia,status,fechado_em,direcao_em,coordenacao_em,motivo_devolucao,devolvido_papel&competencia=eq.' +
            competencia,
          { token: token() }
        );
        return (r && r[0]) || null;
      },
      fecharRelatorio(competencia) {
        return chamar('/rest/v1/rpc/fechar_relatorio', {
          metodo: 'POST',
          token: token(),
          corpo: { p_competencia: competencia }
        });
      },
      relatoriosEscola(competencia) {
        if (!/^\d{4}-\d{2}-01$/.test(String(competencia))) return Promise.reject(new Error('Mês inválido.'));
        return chamar('/rest/v1/rpc/relatorios_escola', {
          metodo: 'POST',
          token: token(),
          corpo: { p_competencia: competencia }
        });
      },
      aprovarRelatorio(id) {
        return chamar('/rest/v1/rpc/aprovar_relatorio', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id) }
        });
      },
      devolverRelatorio(id, motivo) {
        return chamar('/rest/v1/rpc/devolver_relatorio', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_motivo: String(motivo || '') }
        });
      },
      conferirAula(id, confirmar, motivo) {
        return chamar('/rest/v1/rpc/conferir_aula', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_confirmar: !!confirmar, p_motivo: confirmar ? null : String(motivo || '') }
        });
      },
      conferirAulas(ids) {
        return chamar('/rest/v1/rpc/conferir_aulas', {
          metodo: 'POST',
          token: token(),
          corpo: { p_ids: (ids || []).map(Number) }
        });
      },
      historicoCheck(desde) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(desde))) return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/check_historico?select=id,aula_id,evento,texto,por,em&order=em,id&em=gte.' +
            desde +
            'T00:00:00-03:00',
          { token: token() }
        );
      },
      visitasPeriodo(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/visitas?select=id,analista_id,escola_id,data,tipo,subtipo,solucao,criado_em&order=data.desc,id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      agendaVisitas(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/visitas_agenda?select=id,analista_id,escola_id,data,hora,origem,tipo,foco,orientacao,status,criada_em,criada_por,visita_id,motivo_alteracao,data_original,remarcada_em&order=data,hora,id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      agendarVisita(v) {
        v = v || {};
        return chamar('/rest/v1/rpc/agendar_visita', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_analista: String(v.analista || ''),
            p_escola: Number(v.escola),
            p_data: String(v.data || ''),
            p_hora: v.hora ? String(v.hora) : null,
            p_origem: String(v.origem || ''),
            p_tipo: v.tipo ? String(v.tipo) : null,
            p_foco: v.foco ? String(v.foco) : null,
            p_orientacao: v.orientacao ? String(v.orientacao) : null
          }
        });
      },
      cancelarVisitaAgenda(id) {
        return chamar('/rest/v1/rpc/cancelar_visita_agenda', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id) }
        });
      },
      visitasCompletas(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/visitas?select=id,analista_id,escola_id,data,tipo,subtipo,participantes,solucao,observacao,objetivo,engajamento,boas_praticas,dificuldades,ocorrencias,ocorrencia_obs,agenda_id,presenca_id,turma,oficineiro_id,criado_em,editado_em&order=data.desc,id.desc&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      historicoVisitas(desde) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(desde))) return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/visitas_historico?select=id,visita_id,antes,em&order=em,id&em=gte.' + desde + 'T00:00:00-03:00',
          { token: token() }
        );
      },
      registrarVisita(v) {
        return chamar('/rest/v1/rpc/registrar_visita', { metodo: 'POST', token: token(), corpo: { p: v || {} } });
      },
      editarVisita(id, v) {
        return chamar('/rest/v1/rpc/editar_visita', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p: v || {} }
        });
      },
      presencasAnalista(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/presencas_analista?select=id,analista_id,escola_id,data,inicio,fim,distancia_inicio_m,distancia_fim_m,conferencia,agenda_id,observacao&order=inicio,id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      presencaAnalista(evento, escola, lat, lng, agenda, obs) {
        return comRecusa(
          chamar('/rest/v1/rpc/presenca_analista', {
            metodo: 'POST',
            token: token(),
            corpo: {
              p_evento: String(evento),
              p_escola: escola == null || escola === '' ? null : Number(escola),
              p_lat: lat == null ? null : Number(lat),
              p_lng: lng == null ? null : Number(lng),
              p_agenda: agenda ? Number(agenda) : null,
              p_obs: obs ? String(obs) : null
            }
          }),
          {
            evento: evento === 'fim' ? 'Saída' : 'Entrada',
            escola_id: escola == null || escola === '' ? null : Number(escola)
          }
        );
      },
      agendarMinhaVisita(v) {
        v = v || {};
        return chamar('/rest/v1/rpc/agendar_minha_visita', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_escola: Number(v.escola),
            p_data: String(v.data || ''),
            p_hora: v.hora ? String(v.hora) : null,
            p_origem: String(v.origem || ''),
            p_tipo: v.tipo ? String(v.tipo) : null,
            p_foco: v.foco ? String(v.foco) : null,
            p_orientacao: v.orientacao ? String(v.orientacao) : null
          }
        });
      },
      remarcarVisitaAgenda(id, data, hora, motivo) {
        return chamar('/rest/v1/rpc/remarcar_visita_agenda', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_id: Number(id),
            p_data: String(data || ''),
            p_hora: hora ? String(hora) : null,
            p_motivo: String(motivo || '')
          }
        });
      },
      cancelarMinhaVisita(id, motivo) {
        return chamar('/rest/v1/rpc/cancelar_minha_visita', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_motivo: String(motivo || '') }
        });
      },
      darBaixaOnboarding(id, data, forma, obs) {
        return chamar('/rest/v1/rpc/dar_baixa_onboarding', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_id: Number(id),
            p_data: String(data || ''),
            p_forma: String(forma || ''),
            p_obs: obs ? String(obs) : null
          }
        });
      },
      reabrirOnboarding(id) {
        return chamar('/rest/v1/rpc/reabrir_onboarding', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id) }
        });
      },
      jornadaPessoas() {
        return chamarTudo(
          '/rest/v1/jornada_pessoas?select=escola_id,nome,tipo,ano_escolar,dias_sem_acesso,dias_acesso,responsavel_turma,base_ref&order=escola_id,id',
          { token: token() }
        );
      },
      ordensServico() {
        return chamarTudo(
          '/rest/v1/onboarding_os?select=id,numero,secretaria,arquivo,recebida_em,importada_em&order=recebida_em,id',
          {
            token: token()
          }
        );
      },
      itensOnboarding() {
        return chamarTudo(
          '/rest/v1/onboarding_itens?select=id,os_id,nome,email,cpf_mascara,cargo,tipo,lotacao_original,escola_id,carteira_id,status,baixa_data,baixa_forma,baixa_obs,baixa_por&order=id',
          { token: token() }
        );
      },
      importarOs(os) {
        return chamar('/rest/v1/rpc/importar_os', { metodo: 'POST', token: token(), corpo: { p_os: os } });
      },
      atribuirOnboarding(id, carteira) {
        return chamar('/rest/v1/rpc/atribuir_onboarding', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_carteira: String(carteira || '') }
        });
      },
      pessoasDaEscola() {
        const q = '&papel=in.(oficineiro,direcao)&order=nome';
        return chamar('/rest/v1/perfis?select=id,nome,papel,escola_id,turno,ativo,documento_tipo' + q, {
          token: token()
        }).catch(() => chamar('/rest/v1/perfis?select=id,nome,papel,escola_id,turno,ativo' + q, { token: token() }));
      },
      nomesDaEscola() {
        return chamar('/rest/v1/rpc/nomes_da_escola', { metodo: 'POST', token: token(), corpo: {} });
      },
      oficineiros() {
        const q = '&papel=eq.oficineiro&order=nome';
        return chamar('/rest/v1/perfis?select=id,nome,escola_id,ativo,documento_tipo' + q, { token: token() }).catch(
          () => chamar('/rest/v1/perfis?select=id,nome,escola_id,ativo' + q, { token: token() })
        );
      },
      contratadasEscola() {
        return chamar('/rest/v1/rpc/contratadas_escola', { metodo: 'POST', token: token(), corpo: {} });
      },
      meuCiclo() {
        return chamar('/rest/v1/rpc/meu_ciclo', { metodo: 'POST', token: token(), corpo: {} }).catch(() => 'dia21');
      },
      escolas() {
        return chamar(
          '/rest/v1/escolas?select=id,sigla,nome,latitude,longitude,raio_m,endereco,carteira_id,ativa&order=sigla',
          { token: token() }
        );
      },
      presencasRede(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/presencas?select=' +
            CAMPOS_PRES +
            '&order=data.desc,inicio,id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      definirContratada(usuario, documento) {
        const d = String(documento || '').replace(/\D/g, '');
        if (d && d.length !== 11 && d.length !== 14)
          return Promise.reject(new Error('Informe um CNPJ (14 números) ou CPF (11 números) válido da contratada.'));
        return chamar('/rest/v1/rpc/definir_contratada', {
          metodo: 'POST',
          token: token(),
          corpo: { p_usuario: usuario, p_documento: d }
        });
      },
      contratadasGestao() {
        return chamar('/rest/v1/rpc/contratadas_gestao', { metodo: 'POST', token: token(), corpo: {} });
      },
      minhaContratada() {
        return chamar('/rest/v1/rpc/minha_contratada', { metodo: 'POST', token: token(), corpo: {} });
      },
      async envioDaGrade(ano) {
        const a = Number(ano);
        if (!(a >= 2024 && a <= 2100)) throw new Error('Ano letivo inválido.');
        const r = await chamarTudo(
          '/rest/v1/grade_envios?select=oficineiro_id,ano_letivo,status,enviado_em,decidido_em,comentario&order=id&ano_letivo=eq.' +
            a,
          { token: token() }
        );
        return r || [];
      },
      enviarGrade(ano) {
        return chamar('/rest/v1/rpc/enviar_grade', { metodo: 'POST', token: token(), corpo: { p_ano: Number(ano) } });
      },
      validarGrade(oficineiro, ano, ok, comentario) {
        return chamar('/rest/v1/rpc/validar_grade', {
          metodo: 'POST',
          token: token(),
          corpo: { p_oficineiro: oficineiro, p_ano: Number(ano), p_validar: !!ok, p_comentario: comentario || null }
        });
      },
      gradeRede(ano) {
        const a = Number(ano);
        if (!(a >= 2024 && a <= 2100)) return Promise.reject(new Error('Ano letivo inválido.'));
        return chamarTudo(
          '/rest/v1/grade_aulas?select=id,oficineiro_id,escola_id,ano_letivo,dia_semana,horario,inicio,fim,ano,turma,tipo,solucao,oficina,professor,espaco,observacao,componente,criado_em&order=dia_semana,inicio,id&ano_letivo=eq.' +
            a,
          { token: token() }
        );
      },
      registrosRedeDoDia(data) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(data))) return Promise.reject(new Error('Data inválida.'));
        return chamarTudo('/rest/v1/aulas_registro?select=id,grade_aula_id,situacao&order=id&data=eq.' + data, {
          token: token()
        });
      },
      registrosRede(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/aulas_registro?select=id,oficineiro_id,grade_aula_id,data,inicio,fim,situacao,revisao_status&order=data,inicio,id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      aulasRede(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/aulas_registro?select=id,oficineiro_id,escola_id,grade_aula_id,data,horario,inicio,fim,turma,tipo,solucao,oficina,presentes,matriculados,situacao,motivo,conteudo,professor_aula,mudanca,componente,atividade,objetivo,engajamento,proxima_aula,check_direcao,check_motivo,check_em,revisao_status,revisao_obs,revisado_em&order=data.desc,inicio,id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      lembretesRede(ini, fim) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(ini)) || !/^\d{4}-\d{2}-\d{2}$/.test(String(fim)))
          return Promise.reject(new Error('Período inválido.'));
        return chamarTudo(
          '/rest/v1/lembretes_registro?select=id,oficineiro_id,grade_aula_id,data,enviado_em&order=id&data=gte.' +
            ini +
            '&data=lte.' +
            fim,
          { token: token() }
        );
      },
      revisarAula(id, acao, comentario) {
        if (['revisado', 'devolvido', 'anulado', 'aguardando'].indexOf(acao) < 0)
          return Promise.reject(new Error('Ação inválida.'));
        return chamar('/rest/v1/rpc/revisar_aula', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_acao: acao, p_comentario: comentario || null }
        });
      },
      enviarLembrete(gradeAulaId, data) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(data))) return Promise.reject(new Error('Data inválida.'));
        return chamar('/rest/v1/rpc/enviar_lembrete', {
          metodo: 'POST',
          token: token(),
          corpo: { p_grade_aula_id: Number(gradeAulaId), p_data: data }
        });
      },
      meusLembretes() {
        return chamar('/rest/v1/rpc/meus_lembretes', { metodo: 'POST', token: token(), corpo: {} });
      },
      definirRaioEscola(escola, raio) {
        return chamar('/rest/v1/rpc/definir_raio_escola', {
          metodo: 'POST',
          token: token(),
          corpo: { p_escola: Number(escola), p_raio: Number(raio) }
        });
      },
      turmasRede() {
        return chamarTudo('/rest/v1/turmas?select=escola_id,ano,turma,matriculados&order=escola_id,ano,turma', {
          token: token()
        });
      },
      contasGestao() {
        return chamar('/rest/v1/rpc/contas_gestao', { metodo: 'POST', token: token(), corpo: {} });
      },
      carteiras() {
        return chamar('/rest/v1/carteiras?select=id,rotulo&order=id', { token: token() });
      },
      cadastrarUsuario(d) {
        d = d || {};
        const corpo = {
          acao: 'cadastrar',
          nome: String(d.nome || '').trim(),
          email: String(d.email || '').trim(),
          cpf: String(d.cpf || '').replace(/\D/g, ''),
          papel: d.papel
        };
        if (d.usuario) corpo.usuario = String(d.usuario).trim().toLowerCase();
        if (d.telefone) corpo.telefone = String(d.telefone).replace(/\D/g, '');
        if (d.escola_sigla) corpo.escola_sigla = String(d.escola_sigla);
        if (d.carteira_id) corpo.carteira_id = String(d.carteira_id);
        return chamar('/functions/v1/admin-usuarios', { metodo: 'POST', token: token(), corpo });
      },
      ativarConta(id, ativa) {
        return chamar('/functions/v1/admin-usuarios', {
          metodo: 'POST',
          token: token(),
          corpo: { acao: ativa ? 'reativar' : 'desativar', usuario_id: String(id) }
        });
      },
      alterarEscola(id, escola, vale, motivo) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(vale))) return Promise.reject(new Error('Data inválida.'));
        return chamar('/rest/v1/rpc/alterar_escola', {
          metodo: 'POST',
          token: token(),
          corpo: { p_usuario: String(id), p_escola: Number(escola), p_vale: vale, p_motivo: motivo }
        });
      },
      cancelarMudancaEscola(id) {
        return chamar('/rest/v1/rpc/cancelar_mudanca_escola', {
          metodo: 'POST',
          token: token(),
          corpo: { p_usuario: String(id) }
        });
      },
      mudancasEscola() {
        return chamarTudo(
          '/rest/v1/mudancas_escola?select=usuario_id,escola_anterior,escola_nova,vale_a_partir&cancelada_em=is.null&order=vale_a_partir,id',
          { token: token() }
        );
      },
      minhaMudancaEscola() {
        return chamar('/rest/v1/rpc/minha_mudanca_escola', { metodo: 'POST', token: token(), corpo: {} });
      },
      turmasDaEscola() {
        return chamar('/rest/v1/turmas?select=ano,turma,matriculados&order=ano,turma', { token: token() });
      },
      escolasAdmin() {
        return chamar(
          '/rest/v1/escolas?select=id,sigla,nome,endereco,telefone,carteira_id,latitude,longitude,raio_m,ativa,posicao_confirmada&order=sigla',
          { token: token() }
        );
      },
      turmasAdmin() {
        return chamarTudo('/rest/v1/turmas?select=id,escola_id,ano,turma,matriculados&order=escola_id,ano,turma', {
          token: token()
        });
      },
      adminAlterarPapel(id, papel, escola, carteira, motivo) {
        return chamar('/rest/v1/rpc/admin_alterar_papel', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_usuario: String(id),
            p_papel: String(papel),
            p_escola: escola ? Number(escola) : null,
            p_carteira: carteira ? String(carteira) : null,
            p_motivo: String(motivo || '')
          }
        });
      },
      adminExigirTrocaSenha(id, motivo) {
        return chamar('/rest/v1/rpc/admin_exigir_troca_senha', {
          metodo: 'POST',
          token: token(),
          corpo: { p_usuario: String(id), p_motivo: String(motivo || '') }
        });
      },
      adminRedefinirMfa(id, motivo) {
        return chamar('/functions/v1/admin-usuarios', {
          metodo: 'POST',
          token: token(),
          corpo: { acao: 'redefinir_mfa', usuario_id: String(id), motivo: String(motivo || '') }
        });
      },
      adminVerEmail(id) {
        return chamar('/functions/v1/admin-usuarios', {
          metodo: 'POST',
          token: token(),
          corpo: { acao: 'ver_email', usuario_id: String(id) }
        });
      },
      adminAlterarEmail(id, email, motivo) {
        return chamar('/functions/v1/admin-usuarios', {
          metodo: 'POST',
          token: token(),
          corpo: {
            acao: 'alterar_email',
            usuario_id: String(id),
            email: String(email || ''),
            motivo: String(motivo || '')
          }
        });
      },
      adminApagarConta(id, motivo) {
        return chamar('/functions/v1/admin-usuarios', {
          metodo: 'POST',
          token: token(),
          corpo: { acao: 'apagar', usuario_id: String(id), motivo: String(motivo || '') }
        });
      },
      adminSalvarEscola(e) {
        e = e || {};
        const num = v => (v === '' || v === null || v === undefined ? null : Number(v));
        return chamar('/rest/v1/rpc/admin_salvar_escola', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_id: e.id ? Number(e.id) : null,
            p_sigla: String(e.sigla || ''),
            p_nome: String(e.nome || ''),
            p_endereco: e.endereco ? String(e.endereco) : null,
            p_telefone: e.telefone ? String(e.telefone) : null,
            p_carteira: e.carteira_id ? String(e.carteira_id) : null,
            p_latitude: num(e.latitude),
            p_longitude: num(e.longitude),
            p_raio: num(e.raio_m),
            p_ativa: e.ativa !== false
          }
        });
      },
      adminSalvarTurma(escola, ano, turma, matriculados) {
        return chamar('/rest/v1/rpc/admin_salvar_turma', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_escola: Number(escola),
            p_ano: Number(ano),
            p_turma: String(turma || ''),
            p_matriculados:
              matriculados === '' || matriculados === null || matriculados === undefined ? null : Number(matriculados)
          }
        });
      },
      adminRemoverTurma(id) {
        return chamar('/rest/v1/rpc/admin_remover_turma', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id) }
        });
      },
      adminSalvarCarteira(id, rotulo) {
        return chamar('/rest/v1/rpc/admin_salvar_carteira', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: String(id || ''), p_rotulo: String(rotulo || '') }
        });
      },
      configuracoes() {
        return chamar('/rest/v1/configuracoes?select=suporte_email,suporte_telefone,suporte_horario&id=eq.1', {
          token: token()
        }).then(r => (Array.isArray(r) ? r[0] || null : null));
      },
      feriados() {
        return chamar('/rest/v1/feriados?select=data,nome,tipo&order=data', { token: token() });
      },
      adminSalvarConfiguracoes(c) {
        c = c || {};
        return chamar('/rest/v1/rpc/admin_salvar_configuracoes', {
          metodo: 'POST',
          token: token(),
          corpo: { p_email: c.email || null, p_telefone: c.telefone || null, p_horario: c.horario || null }
        });
      },
      adminSalvarFeriado(data, nome, tipo) {
        return chamar('/rest/v1/rpc/admin_salvar_feriado', {
          metodo: 'POST',
          token: token(),
          corpo: { p_data: String(data || ''), p_nome: String(nome || ''), p_tipo: String(tipo || '') }
        });
      },
      adminRemoverFeriado(data) {
        return chamar('/rest/v1/rpc/admin_remover_feriado', {
          metodo: 'POST',
          token: token(),
          corpo: { p_data: String(data || '') }
        });
      },
      adminConsulta(id, competencia) {
        return chamar('/rest/v1/rpc/admin_consulta', {
          metodo: 'POST',
          token: token(),
          corpo: { p_usuario: String(id), p_competencia: String(competencia) }
        });
      },
      adminCorrigirPresenca(id, inicio, fim, motivo) {
        return chamar('/rest/v1/rpc/admin_corrigir_presenca', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_inicio: inicio, p_fim: fim || null, p_motivo: String(motivo || '') }
        });
      },
      adminLancarPresenca(oficineiro, inicio, fim, motivo) {
        return chamar('/rest/v1/rpc/admin_lancar_presenca', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_oficineiro: String(oficineiro),
            p_inicio: inicio,
            p_fim: fim || null,
            p_motivo: String(motivo || '')
          }
        });
      },
      adminReabrirMes(oficineiro, competencia, motivo) {
        return chamar('/rest/v1/rpc/admin_reabrir_mes', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_oficineiro: String(oficineiro),
            p_competencia: String(competencia),
            p_motivo: String(motivo || '')
          }
        });
      },
      adminSituacaoGrade(oficineiro, ano, status, motivo) {
        return chamar('/rest/v1/rpc/admin_situacao_grade', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_oficineiro: String(oficineiro),
            p_ano: Number(ano),
            p_status: String(status),
            p_motivo: String(motivo || '')
          }
        });
      },
      adminSituacaoRegistro(id, status, motivo) {
        return chamar('/rest/v1/rpc/admin_situacao_registro', {
          metodo: 'POST',
          token: token(),
          corpo: { p_id: Number(id), p_status: String(status || ''), p_motivo: String(motivo || '') }
        });
      },
      adminAtividades(f) {
        f = f || {};
        return chamar('/rest/v1/rpc/admin_atividades', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_desde: f.desde || null,
            p_ate: f.ate || null,
            p_usuario: f.usuario || null,
            p_categoria: f.categoria || null,
            p_limite: f.limite || 500
          }
        });
      },
      adminAuditoria(f) {
        f = f || {};
        return chamar('/rest/v1/rpc/admin_auditoria', {
          metodo: 'POST',
          token: token(),
          corpo: {
            p_desde: f.desde || null,
            p_ate: f.ate || null,
            p_usuario: f.usuario || null,
            p_acao: f.acao || null,
            p_tabela: f.tabela || null,
            p_limite: f.limite || 300
          }
        });
      },

      minhaConta() {
        return chamar('/rest/v1/rpc/minha_conta', { metodo: 'POST', token: token(), corpo: {} });
      },
      async preferencias() {
        const r = await chamar('/rest/v1/rpc/minhas_preferencias', { metodo: 'POST', token: token(), corpo: {} });
        return r && typeof r === 'object' && !Array.isArray(r) ? r : {};
      },
      salvarPreferencias(p) {
        const ok = {
          tema: ['claro', 'escuro', 'auto'],
          texto: ['normal', 'grande', 'maior'],
          animacoes: ['sim', 'reduzir']
        };
        const corpo = {};
        Object.keys(p || {}).forEach(k => {
          if (ok[k] && ok[k].indexOf(p[k]) >= 0) corpo[k] = p[k];
        });
        return chamar('/rest/v1/rpc/salvar_preferencias', {
          metodo: 'POST',
          token: token(),
          corpo: { p_preferencias: corpo }
        });
      },
      async trocarSenhaAtual(atual, nova, confirma) {
        if (!atual) throw new Error('Digite a senha atual.');
        const falta = this.regraSenha(nova);
        if (falta.length) throw new Error('A senha nova precisa ter: ' + falta.join(', ') + '.');
        if (nova !== confirma) throw new Error('As duas senhas novas não são iguais.');
        if (nova === atual) throw new Error('A senha nova precisa ser diferente da atual.');
        await chamar('/functions/v1/acesso', {
          metodo: 'POST',
          token: token(),
          corpo: {
            acao: 'trocar_senha',
            senha_atual: String(atual),
            senha_nova: String(nova),
            senha_confirma: String(confirma)
          }
        });
      },
      async sairDeTodos() {
        await chamar('/auth/v1/logout?scope=global', { metodo: 'POST', token: token() });
        limpa();
        renovando = null;
      },

      usuarioId() {
        const id = sessao && claims(sessao.access_token).sub;
        return typeof id === 'string' && /^[A-Za-z0-9._-]{1,64}$/.test(id) ? id : '';
      },

      meuAcesso() {
        return chamar('/rest/v1/rpc/meu_acesso', { metodo: 'POST', token: token(), corpo: {} });
      },

      async fatores() {
        const u = await chamar('/auth/v1/user', { token: token() });
        return ((u && u.factors) || []).filter(f => f.factor_type === 'totp');
      },
      async cadastrarAutenticador() {
        const fs = await this.fatores();
        for (let i = 0; i < fs.length; i++) {
          if (fs[i].status !== 'verified')
            await chamar('/auth/v1/factors/' + encodeURIComponent(fs[i].id), { metodo: 'DELETE', token: token() });
        }
        const r = await chamar('/auth/v1/factors', {
          metodo: 'POST',
          token: token(),
          corpo: {
            factor_type: 'totp',
            friendly_name: 'Oficineiro+ ' + new Date().toISOString().slice(0, 16),
            issuer: 'Oficineiro+'
          }
        });
        const svg = String((r.totp && r.totp.qr_code) || '');
        const qr = /^data:image\//.test(svg)
          ? svg
          : svg.indexOf('<svg') >= 0
            ? 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
            : '';
        return { id: r.id, qr, segredo: r.totp && r.totp.secret };
      },
      async confirmarCodigo(fatorId, codigo) {
        codigo = String(codigo || '').replace(/\D/g, '');
        if (codigo.length !== 6) throw new Error('Digite os 6 números do aplicativo autenticador.');
        const d = await chamar('/auth/v1/factors/' + encodeURIComponent(fatorId) + '/challenge', {
          metodo: 'POST',
          token: token(),
          corpo: {}
        });
        guarda(
          await chamar('/auth/v1/factors/' + encodeURIComponent(fatorId) + '/verify', {
            metodo: 'POST',
            token: token(),
            corpo: { challenge_id: d.id, code: codigo }
          })
        );
      },

      regraSenha(s) {
        s = String(s || '');
        const falta = [];
        if (s.length < 12) falta.push('12 caracteres');
        if (!/[a-z]/.test(s)) falta.push('uma letra minúscula');
        if (!/[A-Z]/.test(s)) falta.push('uma letra maiúscula');
        if (!/[0-9]/.test(s)) falta.push('um número');
        if (!/[^A-Za-z0-9]/.test(s)) falta.push('um símbolo');
        return falta;
      },
      async trocarSenha(nova, confirma) {
        const falta = this.regraSenha(nova);
        if (falta.length) throw new Error('A senha precisa ter: ' + falta.join(', ') + '.');
        if (nova !== confirma) throw new Error('As duas senhas não são iguais.');
        await chamar('/auth/v1/user', { metodo: 'PUT', token: token(), corpo: { password: String(nova) } });
      }
    };
  })();
