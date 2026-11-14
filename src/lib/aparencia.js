window.FSM_APARENCIA =
  window.FSM_APARENCIA ||
  (() => {
    const CHAVE = 'fsm_aparencia';
    const VALORES = {
      tema: ['claro', 'escuro', 'auto'],
      texto: ['normal', 'grande', 'maior'],
      animacoes: ['sim', 'reduzir']
    };
    const PADRAO = { tema: 'claro', texto: 'normal', animacoes: 'sim' };
    let atual = {};
    let midia = null;

    const PALETA = {
      fundo: [
        ['#0E1A1E', ['#EEF3F4']],
        ['#15252B', ['#FFFFFF']],
        ['#1B2D34', ['#F7FAFB', '#F9FBFC', '#F5F9FA', '#F8FBFB', '#FAFCFC']],
        ['#22363E', ['#E8EEF0', '#EDF2F3', '#E3EBED', '#EBF1F2', '#DDE6E8']],
        ['#12303A', ['#EFF9FC', '#E4F5FA']],
        ['#3B1D1A', ['#FBEDEB']],
        ['#173022', ['#E2F2E5', '#EDF7EF']],
        ['#35290F', ['#FAEFD9', '#FDF6E7', '#FCF5E8']],
        ['#1A2440', ['#EFF3FD', '#E7EDFC']],
        ['#252450', ['#ECEBFC']]
      ],
      texto: [
        ['#E6EEF0', ['#1A2B33', '#333333']],
        ['#C5D2D6', ['#34464D', '#45575E', '#555555']],
        ['#9CB0B6', ['#5B6B70', '#7D8C91', '#8A999E', '#7E8E93']],
        ['#5FCDEE', ['#08617E', '#0B7EA3']],
        ['#F59A8F', ['#B42318', '#7A1F17', '#8A1C12']],
        ['#7FD79A', ['#23773A', '#1B5E2E']],
        ['#F0C46E', ['#7A4E0B', '#9A6212', '#5E4A26']],
        ['#8FB0FF', ['#1A3F9C', '#1F4FC4']],
        ['#ABA4FF', ['#4B41B8', '#6C60E6']]
      ],
      borda: [
        ['#34484F', ['#CFDADD', '#DDE6E8', '#DDDDDD', '#CCCCCC', '#B5C3C7', '#C3CFD2', '#E3EBED']],
        ['#1F5266', ['#BEE9F5', '#C9ECF6']],
        ['#2A3D45', ['#E9EFF1', '#E8EEF0']]
      ]
    };

    const NOME_DA_COR = {
      '#08617E': 'ciano-740',
      '#0B7EA3': 'ciano-660',
      '#1A2B33': 'ciano-850',
      '#1A3F9C': 'azul-640',
      '#1B5E2E': 'verde-760',
      '#1F4FC4': 'azul-550',
      '#23773A': 'verde-700',
      '#333333': 'cinza-800',
      '#34464D': 'cinza-750',
      '#45575E': 'cinza-680',
      '#4B41B8': 'indigo-510',
      '#555555': 'cinza-670',
      '#5B6B70': 'cinza-600',
      '#5E4A26': 'ambar-740',
      '#6C60E6': 'indigo-360',
      '#7A1F17': 'vermelho-720',
      '#7A4E0B': 'ambar-745',
      '#7D8C91': 'cinza-470',
      '#7E8E93': 'cinza-460',
      '#8A1C12': 'vermelho-690',
      '#8A999E': 'cinza-420',
      '#9A6212': 'ambar-660',
      '#B42318': 'vermelho-600',
      '#B5C3C7': 'cinza-250',
      '#BEE9F5': 'ciano-150',
      '#C3CFD2': 'cinza-210',
      '#C9ECF6': 'ciano-120',
      '#CCCCCC': 'cinza-200',
      '#CFDADD': 'cinza-160',
      '#DDDDDD': 'cinza-130',
      '#DDE6E8': 'cinza-110',
      '#E2F2E5': 'verde-80',
      '#E3EBED': 'cinza-90',
      '#E4F5FA': 'ciano-60',
      '#E7EDFC': 'azul-50',
      '#E8EEF0': 'cinza-70',
      '#E9EFF1': 'cinza-75',
      '#EBF1F2': 'cinza-60',
      '#ECEBFC': 'indigo-50',
      '#EDF2F3': 'cinza-65',
      '#EDF7EF': 'verde-50',
      '#EEF3F4': 'cinza-55',
      '#EFF3FD': 'azul-40',
      '#EFF9FC': 'ciano-40',
      '#F5F9FA': 'cinza-40',
      '#F7FAFB': 'cinza-20',
      '#F8FBFB': 'cinza-25',
      '#F9FBFC': 'cinza-30',
      '#FAEFD9': 'ambar-80',
      '#FAFCFC': 'cinza-35',
      '#FBEDEB': 'vermelho-50',
      '#FCF5E8': 'ambar-50',
      '#FDF6E7': 'ambar-55',
      '#FFFFFF': 'branco'
    };

    const DESTAQUES =
      '--destaque-ambar-310:#F2C66D;--destaque-ambar-450:#E0A93B;--destaque-ambar-510:#E0A21B;--destaque-ambar-745:#7A4E0B;--destaque-azul-500:#3B82C4;--destaque-azul-640:#1A3F9C;--destaque-azul-645:#1F5F99;--destaque-branco:#FFFFFF;--destaque-ciano-400:#3ECDF3;--destaque-ciano-660:#0B7EA3;--destaque-ciano-810:#22363E;--destaque-ciano-850:#1A2B33;--destaque-ciano-870:#15252B;--destaque-ciano-880:#13252C;--destaque-cinza-160:#CFDADD;--destaque-cinza-180:#C9D4D7;--destaque-cinza-210:#C3CFD2;--destaque-cinza-300:#A9B8BD;--destaque-cinza-40:#F5F9FA;--destaque-cinza-540:#6B7280;--destaque-cinza-55:#EEF3F4;--destaque-cinza-600:#5B6B70;--destaque-cinza-660:#4A5C62;--destaque-cinza-670:#555555;--destaque-indigo-360:#6C60E6;--destaque-laranja-370:#E3B45C;--destaque-laranja-480:#E0892B;--destaque-laranja-520:#E8590C;--destaque-laranja-630:#B5470A;--destaque-laranja-730:#8A5A00;--destaque-rosa-500:#DD2287;--destaque-verde-450:#35E47D;--destaque-verde-700:#23773A;--destaque-verde-760:#1B5E2E;--destaque-vermelho-600:#B42318';

    const variaveis = escuro =>
      Object.entries(PALETA)
        .flatMap(([papel, pares]) =>
          pares.flatMap(([cor, claras]) =>
            claras.map(clara => `--${papel}-${NOME_DA_COR[clara]}:${escuro ? cor : clara}`)
          )
        )
        .join(';');

    const css = () => {
      const E = 'html[data-tema="escuro"]';
      return (
        `:root{${variaveis(false)};${DESTAQUES};--fundo-ciano-880:#13252C;--fundo-mapa:#EBF1F2;--grade-mapa:#D7E2E5}` +
        '@media screen{' +
        `${E}{color-scheme:dark}` +
        `${E} body{background:#0E1A1E!important}` +
        `${E} #area-logada{${variaveis(true)};--fundo-mapa:#1B2D34;--grade-mapa:rgba(255,255,255,.05);color:#E6EEF0}` +
        `${E} #area-logada main{--fundo-ciano-880:#1F3B47}` +
        `${E} #area-logada input,${E} #area-logada select,${E} #area-logada textarea{color:#E6EEF0}` +
        `${E} #area-logada input:not([type="checkbox"]):not([type="radio"]):not([type="range"]),${E} #area-logada select,${E} #area-logada textarea{background-color:#15252B}` +
        `${E} #area-logada input::placeholder,${E} #area-logada textarea::placeholder{color:#7F959C}` +
        `${E} #area-logada .leaflet-container{background:#0E1A1E}` +
        'html[data-texto="grande"] #area-logada,html[data-texto="grande"] #fsm-config{zoom:1.125}' +
        'html[data-texto="maior"] #area-logada,html[data-texto="maior"] #fsm-config{zoom:1.25}' +
        '}' +
        'html[data-animacoes="reduzir"] *,html[data-animacoes="reduzir"] *::before,html[data-animacoes="reduzir"] *::after{animation:none!important;transition:none!important;scroll-behavior:auto!important}'
      );
    };

    const injetar = () => {
      if (document.getElementById('fsm-aparencia-css')) return;
      const el = document.createElement('style');
      el.id = 'fsm-aparencia-css';
      el.textContent = css();
      (document.head || document.documentElement).appendChild(el);
    };

    const limpar = p => {
      const r = {};
      Object.keys(VALORES).forEach(k => {
        if (p && VALORES[k].includes(p[k])) r[k] = p[k];
      });
      return r;
    };

    const escuroDoSistema = () => {
      try {
        return window.matchMedia('(prefers-color-scheme: dark)').matches;
      } catch (e) {
        return false;
      }
    };

    const aplicarNoHtml = () => {
      const p = { ...PADRAO, ...atual };
      const raiz = document.documentElement;
      const tema = p.tema === 'auto' ? (escuroDoSistema() ? 'escuro' : 'claro') : p.tema;
      raiz.setAttribute('data-tema', tema);
      raiz.setAttribute('data-texto', p.texto);
      raiz.setAttribute('data-animacoes', p.animacoes);
    };

    const vigiarSistema = () => {
      if (midia) return;
      try {
        midia = window.matchMedia('(prefers-color-scheme: dark)');
        const fn = () => {
          if ((atual.tema || PADRAO.tema) === 'auto') aplicarNoHtml();
        };
        if (midia.addEventListener) midia.addEventListener('change', fn);
        else if (midia.addListener) midia.addListener(fn);
      } catch (e) {}
    };

    const aplicar = (p, guardar) => {
      atual = { ...atual, ...limpar(p) };
      injetar();
      vigiarSistema();
      aplicarNoHtml();
      if (guardar !== false) {
        try {
          localStorage.setItem(CHAVE, JSON.stringify(atual));
        } catch (e) {}
      }
      return { ...PADRAO, ...atual };
    };

    let guardado;
    try {
      guardado = JSON.parse(localStorage.getItem(CHAVE) || '{}') || {};
    } catch (e) {
      guardado = {};
    }
    aplicar(guardado, false);

    return {
      VALORES,
      aplicar,
      atual: () => ({ ...PADRAO, ...atual }),
      temaEfetivo: () => document.documentElement.getAttribute('data-tema') || 'claro'
    };
  })();
