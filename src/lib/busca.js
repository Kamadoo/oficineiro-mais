(() => {
  const original = window.fetch.bind(window);
  const publicado = endereco => {
    try {
      const url = new window.URL(endereco, window.location.href);
      return url.origin === window.location.origin && url.pathname.startsWith('/a/');
    } catch {
      return false;
    }
  };
  window.fetch = (entrada, opcoes) =>
    original(entrada, opcoes).then(resposta => {
      const endereco = typeof entrada === 'string' ? entrada : entrada && entrada.url;
      const metodo = String((opcoes && opcoes.method) || (entrada && entrada.method) || 'GET').toUpperCase();
      if (resposta.status !== 404 || metodo !== 'GET' || !publicado(endereco)) return resposta;
      return original(endereco, { ...(opcoes || {}), cache: 'reload' });
    });
})();
