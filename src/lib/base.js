window.FSM_BASE = (() => {
  const MES = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro'
  ];
  const WD = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  const WDL = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
  const FIXOS = {
    '01-01': 'Confraternização Universal',
    '04-21': 'Tiradentes',
    '05-01': 'Dia do Trabalho',
    '09-07': 'Independência do Brasil',
    '10-12': 'Nossa Senhora Aparecida',
    '11-02': 'Finados',
    '11-15': 'Proclamação da República',
    '11-20': 'Consciência Negra',
    '12-25': 'Natal'
  };
  const MOVEIS = {
    '2026-02-16': 'Carnaval',
    '2026-02-17': 'Carnaval',
    '2026-04-03': 'Sexta-feira Santa',
    '2026-06-04': 'Corpus Christi',
    '2027-02-08': 'Carnaval',
    '2027-02-09': 'Carnaval',
    '2027-03-26': 'Sexta-feira Santa',
    '2027-05-27': 'Corpus Christi'
  };
  function p2(n) {
    return String(n).padStart(2, '0');
  }
  function iso(d) {
    return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate());
  }
  function add(d, n) {
    const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    x.setDate(x.getDate() + n);
    return x;
  }
  function feriado(d) {
    const extra = typeof window !== 'undefined' && window.FSM_FERIADOS ? window.FSM_FERIADOS[iso(d)] : '';
    return MOVEIS[iso(d)] || FIXOS[iso(d).slice(5)] || extra || '';
  }
  function letivo(d) {
    const w = d.getDay();
    return w > 0 && w < 6 && !feriado(d);
  }
  function prevLetivo(d) {
    let x = add(d, -1);
    while (!letivo(x)) x = add(x, -1);
    return x;
  }
  function nextLetivo(d) {
    let x = add(d, 1);
    while (!letivo(x)) x = add(x, 1);
    return x;
  }
  function hm(m) {
    return p2(Math.floor(m / 60)) + ':' + p2(m % 60);
  }
  function dur(m) {
    return Math.floor(m / 60) + 'h' + p2(m % 60);
  }
  function dm(d) {
    return p2(d.getDate()) + '/' + p2(d.getMonth() + 1);
  }
  function dmy(d) {
    return dm(d) + '/' + d.getFullYear();
  }

  function nowMin() {
    const n = new Date();
    return n.getHours() * 60 + n.getMinutes();
  }

  function N(n) {
    return Number(n).toLocaleString('pt-BR');
  }

  let cicloPadrao = 'dia21';
  function mensal(t) {
    return (t || cicloPadrao) === 'mensal';
  }
  function cicloDe(documento, papel) {
    return documento === 'CPF' && (!papel || papel === 'oficineiro') ? 'mensal' : 'dia21';
  }
  function definirCiclo(t) {
    cicloPadrao = t === 'mensal' ? 'mensal' : 'dia21';
  }
  function cicloComp(d, t) {
    if (mensal(t)) return new Date(d.getFullYear(), d.getMonth(), 1);
    return d.getDate() >= 21
      ? new Date(d.getFullYear(), d.getMonth() + 1, 1)
      : new Date(d.getFullYear(), d.getMonth(), 1);
  }
  function cicloIni(c, t) {
    if (mensal(t)) return new Date(c.getFullYear(), c.getMonth(), 1);
    return new Date(c.getFullYear(), c.getMonth() - 1, 21);
  }
  function cicloFim(c, t) {
    if (mensal(t)) return new Date(c.getFullYear(), c.getMonth() + 1, 0);
    return new Date(c.getFullYear(), c.getMonth(), 20);
  }

  function cicloTxt(c, t) {
    return dm(cicloIni(c, t)) + ' a ' + dm(cicloFim(c, t));
  }

  function prazo(d, t) {
    return dm(cicloFim(cicloComp(d, t), t)) + ' às 23:59';
  }

  function docPresenca(o) {
    const LIM = 480,
      DIAS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
    const hora = t => {
      if (!t) return '//';
      const d = new Date(t);
      return hm(d.getHours() * 60 + d.getMinutes());
    };
    const trab = p => {
      if (p.trabalhado_min != null) return p.trabalhado_min;
      let m = Math.round((new Date(p.fim) - new Date(p.inicio)) / 60000);
      if (p.pausa_inicio && p.pausa_fim) m -= Math.round((new Date(p.pausa_fim) - new Date(p.pausa_inicio)) / 60000);
      return Math.max(0, m);
    };
    const ajuste = dia =>
      (o.ajustes || [])
        .filter(a => a.data === dia && a.status === 'aprovada')
        .sort((x, y) => String(y.analisado_em || '').localeCompare(String(x.analisado_em || '')))[0];
    const off = (b, txt) => ({
      data: b.data,
      dia: b.dia,
      c1: '',
      c2: '',
      c3: '',
      c4: '',
      total: '',
      obs: '',
      offTxt: txt,
      rs: 1,
      mostraM: 'table-cell',
      mostraN: 'none'
    });
    const linhas = [];
    let contab = 0,
      naoContab = 0,
      trabalhados = 0,
      faltasJ = 0,
      faltasN = 0;
    for (let d = add(o.ini, 0); iso(d) <= iso(o.ate); d = add(d, 1)) {
      const dia = iso(d),
        dw = d.getDay(),
        b = { data: dm(d), dia: DIAS[dw] },
        p = (o.pres || []).filter(x => x.data === dia)[0],
        aj = ajuste(dia);
      if (!p && (dw === 0 || dw === 6)) {
        const ant = linhas[linhas.length - 1];
        if (dw === 0 && ant && ant.sab) {
          ant.rs = 2;
          const cont = off(b, '');
          cont.mostraM = 'none';
          linhas.push(cont);
        } else {
          const l = off(b, 'Sábado/Domingo');
          l.sab = dw === 6;
          linhas.push(l);
        }
        continue;
      }
      if (!p && feriado(d)) {
        linhas.push(off(b, 'Feriado / Recesso'));
        continue;
      }
      if (!p) {
        const just = !!(aj && aj.tipo === 'falta'),
          falta = just || (o.comGrade ? o.comGrade(dia) : true);
        if (falta && dia < o.hojeIso) {
          if (just) faltasJ++;
          else faltasN++;
        }
        linhas.push({
          data: b.data,
          dia: b.dia,
          c1: '//',
          c2: '//',
          c3: '//',
          c4: '//',
          total: '00:00',
          obs: just
            ? 'Falta justificada · aprovada em ' + dm(new Date(aj.analisado_em))
            : dia === o.hojeIso
              ? 'Presença ainda não registrada hoje'
              : falta
                ? 'Falta não justificada'
                : 'Sem atividade na grade',
          offTxt: '',
          rs: 1,
          mostraM: 'none',
          mostraN: 'table-cell'
        });
        continue;
      }
      const fechado = !!p.fim && !(p.pausa_inicio && !p.pausa_fim),
        t = fechado ? trab(p) : null,
        obs = [];
      if (!fechado)
        obs.push(
          p.fim ? 'Volta do almoço não registrada' : dia === o.hojeIso ? 'Jornada em andamento' : 'Saída não registrada'
        );
      else {
        trabalhados++;
        contab += Math.min(t, LIM);
        if (t > LIM) {
          naoContab += t - LIM;
          obs.push(t - LIM + ' min acima de 8h, não contabilizados');
        }
        if (!p.pausa_inicio) obs.push('Jornada sem almoço');
      }
      if (aj && aj.tipo !== 'falta') obs.push('Horários ajustados por justificativa aprovada');
      linhas.push({
        data: b.data,
        dia: b.dia,
        c1: hora(p.inicio),
        c2: hora(p.pausa_inicio),
        c3: hora(p.pausa_fim),
        c4: hora(p.fim),
        total: t == null ? '—' : hm(Math.min(t, LIM)),
        obs: obs.join(' · '),
        offTxt: '',
        rs: 1,
        mostraM: 'none',
        mostraN: 'table-cell'
      });
    }
    return {
      linhas,
      total: hm(contab),
      resumo: [
        ['Horas contabilizadas', dur(contab)],
        ['Não contabilizadas', dur(naoContab)],
        ['Dias trabalhados', String(trabalhados)],
        ['Faltas justificadas', String(faltasJ)],
        ['Faltas não justificadas', String(faltasN)]
      ].map(x => ({ l: x[0], v: x[1] }))
    };
  }
  function docAtividades(itens) {
    const corta = t => {
      const x = String(t || '').trim();
      return x.length > 200 ? x.slice(0, 197).replace(/\s+$/, '') + '…' : x;
    };
    const min = (a, b) => {
      const x = String(a || '').slice(0, 5),
        y = String(b || '').slice(0, 5);
      if (!/^\d\d:\d\d$/.test(x) || !/^\d\d:\d\d$/.test(y)) return 0;
      return Math.max(
        0,
        Number(y.slice(0, 2)) * 60 + Number(y.slice(3)) - Number(x.slice(0, 2)) * 60 - Number(x.slice(3))
      );
    };
    const real = itens.filter(i => i.sit === 'Realizada'),
      nao = itens.filter(i => i.sit === 'Não realizada');
    return {
      linhas: itens.map(i => ({
        data: dm(i.d),
        horario: String(i.inicio || '').slice(0, 5) + '–' + String(i.fim || '').slice(0, 5),
        turma: i.turma || '—',
        atividade: i.atividade || '—',
        sit: i.sit,
        sitCor: i.sit === 'Realizada' ? '#1B5E2F' : i.sit === 'Não realizada' ? '#B42319' : '#7A4E0C',
        estud: i.sit === 'Realizada' && i.presentes != null ? String(i.presentes) : '—',
        registro: i.sit === 'Agendada' ? 'Sem registro' : corta(i.registro)
      })),
      resumo: [
        ['Agendadas', String(itens.length)],
        ['Realizadas', String(real.length)],
        ['Não realizadas', String(nao.length)],
        ['Estudantes atendidos', String(real.reduce((t, i) => t + (i.presentes || 0), 0))],
        ['Horas em atividade', dur(real.reduce((t, i) => t + min(i.inicio, i.fim), 0))]
      ].map(x => ({ l: x[0], v: x[1] }))
    };
  }
  function docAssinatura(papel, nome, em) {
    const d = em ? new Date(em) : null;
    return {
      papel,
      nome: nome || '',
      temNome: !!nome,
      stamp: d ? 'Assinado eletronicamente em ' + dmy(d) + ' às ' + hm(d.getHours() * 60 + d.getMinutes()) : '',
      temStamp: !!d
    };
  }
  const ATEND_VISITA = {
    Suporte: [
      'Apoio a usuários',
      'Solicitação da escola',
      'Problema técnico (triagem no local)',
      'Intervenção Aulas Regulares',
      'Intervenção Programa Construtores – Minecraft'
    ],
    Implantação: ['Instalação', 'Onboarding de novos usuários'],
    Acompanhamento: [
      'Indicadores de uso',
      'Reunião com a Direção',
      'Plano de ação',
      'Programa Construtores – Oficina Minecraft',
      'Aulas regulares – Alunos'
    ],
    Formação: ['Formação de professores', 'Formação de servidores', 'Formação com Oficineiros']
  };
  const ORIGEM_VISITA = {
    mapa_calor: ['Mapa de calor · Jornada do Usuário', '#E0892B', 'var(--fundo-faefd9)', 'var(--texto-7a4e0b)'],
    relatorio: ['Mapa de calor · Jornada do Usuário', '#E0892B', 'var(--fundo-faefd9)', 'var(--texto-7a4e0b)'],
    demanda: ['Demanda da escola', 'var(--texto-8a999e)', 'var(--fundo-eef3f4)', 'var(--texto-45575e)'],
    gerencia: ['Vinculada pela gerência', 'var(--texto-0b7ea3)', 'var(--fundo-e4f5fa)', 'var(--texto-08617e)'],
    analista: ['Iniciativa do analista', 'var(--texto-6c60e6)', 'var(--fundo-ecebfc)', 'var(--texto-4b41b8)']
  };
  const ORIGENS_VISITA = ['mapa_calor', 'demanda', 'gerencia', 'analista'];
  function origemVisita(k) {
    return k === 'relatorio' ? 'mapa_calor' : k;
  }
  function eixoGrade(intervalos, opc) {
    const o = opc || {},
      ini = o.ini == null ? 420 : o.ini,
      fim = o.fim == null ? 1020 : o.fim,
      pxMin = o.pxMin || 1.75,
      livre = o.livre || 40,
      cresce = !!o.cresce;
    const lim = m => Math.max(ini, Math.min(fim, m));
    const ints = (intervalos || []).map(x => [lim(x[0]), lim(x[1])]).filter(x => x[1] > x[0]);
    let marcos = [ini, fim];
    ints.forEach(x => {
      marcos.push(x[0], x[1]);
    });
    marcos = marcos.filter((m, i) => marcos.indexOf(m) === i).sort((x, y) => x - y);
    const ocupado = (a, b) => ints.some(x => x[0] < b && x[1] > a);
    const segs = [];
    for (let i = 0; i < marcos.length - 1; i++) {
      const a = marcos[i],
        b = marcos[i + 1];
      if (ocupado(a, b)) segs.push({ ini: a, fim: b, ocupado: true });
      else
        for (let c = a; c < b;) {
          const n = Math.min(b, Math.floor(c / 60) * 60 + 60);
          segs.push({ ini: c, fim: n, ocupado: false });
          c = n;
        }
    }
    segs.forEach((sg, k) => {
      sg.marco = ints.some(x => x[0] === sg.ini || x[1] === sg.ini);
      sg.linha = k + 2;
      sg.gr = k + 2 + ' / ' + (k + 3);
      const h = sg.ocupado ? Math.max(24, Math.round((sg.fim - sg.ini) * pxMin)) : livre;
      sg.altura = cresce ? 'minmax(' + h + 'px,auto)' : h + 'px';
    });
    const linhaDe = m => {
      const v = lim(m);
      if (v >= fim) return segs.length + 2;
      for (let k = 0; k < segs.length; k++) if (segs[k].ini >= v) return segs[k].linha;
      return segs.length + 2;
    };
    return {
      segs,
      linhas: ['auto'].concat(segs.map(sg => sg.altura)).join(' '),
      linhaDe,
      faixa: (m0, m1) => {
        const r0 = linhaDe(m0);
        return r0 + ' / ' + Math.max(linhaDe(m1), r0 + 1);
      }
    };
  }

  function Mes(d) {
    const s = MES[d.getMonth()];
    return s.charAt(0).toUpperCase() + s.slice(1) + ' ' + d.getFullYear();
  }

  const TIPOS = {
    R: ['Aula regular', 'var(--texto-1f4fc4)', 'var(--fundo-e7edfc)'],
    P: ['Projeto tempo integral', 'var(--texto-9a6212)', 'var(--fundo-faefd9)'],
    F: ['Formação de professores', 'var(--texto-6c60e6)', 'var(--fundo-ecebfc)'],
    C: ['Oficina de tecnologia', 'var(--texto-23773a)', 'var(--fundo-e2f2e5)']
  };
  function detTipo(g) {
    return !g ? '' : g.tipo === 'P' ? g.oficina || '' : g.solucao || '';
  }
  const VIS_FOCOS = ['Alunos', 'Professores', 'Servidores', 'Direção'];
  function dataDe(dia) {
    const [y, m, d] = String(dia).slice(0, 10).split('-').map(Number);
    return new Date(y, m - 1, d);
  }
  function hojeIso() {
    return new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
  }
  function agoraMin() {
    const [h, m] = new Date()
      .toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit', hour12: false })
      .split(':')
      .map(Number);
    return h * 60 + m;
  }
  function minDe(h) {
    const [a, b] = String(h || '0:0')
      .split(':')
      .map(Number);
    return a * 60 + (b || 0);
  }
  function hmDe(h) {
    return String(h || '').slice(0, 5);
  }
  function dmTs(v) {
    return v
      ? new Date(v).toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit' })
      : '';
  }
  function dmIso(dia) {
    return String(dia).slice(8, 10) + '/' + String(dia).slice(5, 7);
  }
  function dmyIso(dia) {
    return dia ? dmIso(dia) + '/' + String(dia).slice(0, 4) : '';
  }
  function mesIni(dia, k) {
    const d = dataDe(dia);
    return iso(new Date(d.getFullYear(), d.getMonth() + (k || 0), 1));
  }
  function cicloIniIso(comp) {
    return iso(cicloIni(dataDe(comp)));
  }
  function cicloFimIso(comp) {
    return iso(cicloFim(dataDe(comp)));
  }
  function mesTxt(dia) {
    return MES[Number(String(dia).slice(5, 7)) - 1] + ' de ' + String(dia).slice(0, 4);
  }
  function segDe(dia) {
    const d = dataDe(dia);
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    return iso(d);
  }
  function pct(a, b) {
    return b ? Math.round((a / b) * 100) : null;
  }
  function pctTxt(v) {
    return v == null ? '—' : v + '%';
  }
  function exC(v) {
    return v == null
      ? 'var(--texto-8a999e)'
      : v >= 90
        ? 'var(--texto-23773a)'
        : v >= 75
          ? 'var(--texto-6c60e6)'
          : v >= 50
            ? '#E0892B'
            : 'var(--texto-b42318)';
  }
  function numero(n) {
    return Number(n || 0).toLocaleString('pt-BR');
  }
  function plural(n, um, varios) {
    return numero(n) + ' ' + (n === 1 ? um : varios);
  }
  function msgErro(x, padrao) {
    return x && x.message ? x.message.charAt(0).toUpperCase() + x.message.slice(1) : padrao;
  }
  function normTxt(t) {
    return String(t || '')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '');
  }
  function proxUtil(dia) {
    let d = dataDe(dia);
    while (!letivo(d)) d = add(d, 1);
    return iso(d);
  }
  function agregar(grade, regs, ini, ate, mud, hoje, agora) {
    const chave = {},
      porId = {};
    regs.forEach(r => {
      if (r.grade_aula_id) chave[r.grade_aula_id + '|' + r.data] = r;
    });
    grade.forEach(g => (porId[g.id] = g));
    const escNaData = (uid, dia) => {
      const ms = mud.filter(m => m.usuario_id === uid);
      if (!ms.length) return null;
      let e = ms[0].escola_anterior;
      ms.forEach(m => {
        if (m.vale_a_partir <= dia) e = m.escola_nova;
      });
      return e;
    };
    const oc = [],
      usados = new Set();
    if (!ini || !ate || ini > ate) return { oc, extras: [] };
    for (let d = dataDe(ini); iso(d) <= ate; d = add(d, 1)) {
      const dw = d.getDay(),
        dia = iso(d);
      if (dw < 1 || dw > 5) continue;
      const fer = !!feriado(d);
      grade.forEach(g => {
        if (g.dia_semana !== dw || Number(g.ano_letivo) !== d.getFullYear()) return;
        if (g.criado_em && dia < iso(new Date(g.criado_em))) return;
        if (dia === hoje && minDe(g.fim) > agora) return;
        const reg = chave[g.id + '|' + dia];
        if (!reg) {
          const eD = escNaData(g.oficineiro_id, dia);
          if (eD != null && eD !== g.escola_id) return;
        }
        const valido = reg && reg.revisao_status !== 'anulado';
        if (reg && !fer) usados.add(reg.id);
        oc.push({
          g,
          iso: dia,
          of: g.oficineiro_id,
          esc: g.escola_id,
          tipo: g.tipo,
          sol: (valido && detTipo(reg)) || detTipo(g) || '',
          reg: valido ? reg : null,
          anul: !!reg && !valido,
          st: fer ? 'canc' : valido ? (reg.situacao === 'Não realizada' ? 'nao' : 'real') : 'sreg'
        });
      });
    }
    const extras = regs.filter(
      r =>
        !usados.has(r.id) &&
        r.data >= ini &&
        r.data <= ate &&
        r.revisao_status !== 'anulado' &&
        r.situacao !== 'Não realizada'
    );
    return { oc, extras, porId };
  }
  const ANOS = [-2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  const TURMAS_PADRAO = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  function anoTxt(a) {
    return Number(a) === -2
      ? '1º período'
      : Number(a) === -1
        ? '2º período'
        : Number(a) === 0
          ? 'Educação infantil'
          : a + 'º ano';
  }
  function hmTs(v) {
    return v
      ? new Date(v).toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' })
      : '';
  }
  function turmaTxt(g) {
    return !g ? '' : g.tipo === 'F' || g.ano == null ? 'Professores' : anoTxt(g.ano) + ' · Turma ' + g.turma;
  }
  function minDeHora(h) {
    const p = String(h || '').split(':');
    return Number(p[0]) * 60 + Number(p[1] || 0);
  }
  const PRAZO_UTEIS = 5;
  function prazoDe(comp) {
    let d = add(dataDe(cicloFimIso(comp)), 1),
      n = letivo(d) ? 1 : 0;
    while (n < PRAZO_UTEIS) {
      d = nextLetivo(d);
      n++;
    }
    return iso(d);
  }
  function cliente() {
    const c = (window.FSM_CONFIG && window.FSM_CONFIG.cliente) || {};
    const orgao = c.orgao || 'Prefeitura Municipal';
    return {
      orgao,
      orgaoTitulo: orgao.toLocaleUpperCase('pt-BR'),
      cidade: c.cidade || '',
      projeto: c.projeto || 'Inclusão Digital'
    };
  }
  return {
    cliente,
    ATEND_VISITA,
    ORIGEM_VISITA,
    ORIGENS_VISITA,
    origemVisita,
    WD,
    WDL,
    iso,
    add,
    feriado,
    letivo,
    prevLetivo,
    nextLetivo,
    hm,
    dur,
    dm,
    dmy,
    nowMin,
    N,
    docPresenca,
    docAtividades,
    docAssinatura,
    cicloDe,
    definirCiclo,
    cicloComp,
    cicloIni,
    cicloFim,
    cicloTxt,
    prazo,
    eixoGrade,
    Mes,
    TIPOS,
    detTipo,
    VIS_FOCOS,
    dataDe,
    hojeIso,
    agoraMin,
    minDe,
    hmDe,
    dmTs,
    dmIso,
    dmyIso,
    mesIni,
    cicloIniIso,
    cicloFimIso,
    mesTxt,
    segDe,
    pct,
    pctTxt,
    exC,
    numero,
    plural,
    msgErro,
    normTxt,
    proxUtil,
    agregar,
    ANOS,
    TURMAS_PADRAO,
    anoTxt,
    hmTs,
    turmaTxt,
    minDeHora,
    PRAZO_UTEIS,
    prazoDe,
    p2,
    MESES: MES
  };
})();
