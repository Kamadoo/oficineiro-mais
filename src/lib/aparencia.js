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

    const variaveis = escuro =>
      Object.entries(PALETA)
        .flatMap(([papel, pares]) =>
          pares.flatMap(([cor, claras]) =>
            claras.map(clara => `--${papel}-${clara.slice(1).toLowerCase()}:${escuro ? cor : clara}`)
          )
        )
        .join(';');

    const css = () => {
      const E = 'html[data-tema="escuro"]';
      return (
        `:root{${variaveis(false)};--fundo-13252c:#13252C;--fundo-mapa:#EBF1F2;--grade-mapa:#D7E2E5}` +
        '@media screen{' +
        `${E}{color-scheme:dark}` +
        `${E} body{background:#0E1A1E!important}` +
        `${E} #area-logada{${variaveis(true)};--fundo-mapa:#1B2D34;--grade-mapa:rgba(255,255,255,.05);color:#E6EEF0}` +
        `${E} #area-logada main{--fundo-13252c:#1F3B47}` +
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

    let guardado = {};
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
