window.FSM_MAPA = (() => {
  'use strict';

  let carregando = null;

  function carregarLeaflet(estilo, script) {
    if (window.L && window.L.map) return Promise.resolve(window.L);
    if (!carregando)
      carregando = new Promise((ok, erro) => {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = estilo;
        document.head.appendChild(link);
        const elemento = document.createElement('script');
        elemento.src = script;
        elemento.onload = () => (window.L ? ok(window.L) : erro());
        elemento.onerror = erro;
        document.head.appendChild(elemento);
      });
    return carregando;
  }

  return { carregarLeaflet };
})();
