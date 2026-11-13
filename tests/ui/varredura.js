const fs = require('fs');
const http = require('http');
const path = require('path');
const { chromium } = require('playwright');
const { AxeBuilder } = require('@axe-core/playwright');
const { atender } = require('./postgrest');

const DIST = path.resolve(__dirname, '..', '..', 'dist');
const PORTA = Number(process.env.PORTA || 5199);
const PERFIS = {
  gerente: '00000000-0000-0000-0000-00000000a001',
  coordenador: '00000000-0000-0000-0000-00000000a002',
  administrador: '00000000-0000-0000-0000-00000000a003',
  analista: '00000000-0000-0000-0000-00000000a004',
  direcao: '00000000-0000-0000-0000-00000000a005',
  oficineiro: '00000000-0000-0000-0000-00000000a006'
};
const TIPOS = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.webmanifest': 'application/manifest+json'
};
const IMPACTOS_GRAVES = ['serious', 'critical'];
const REGRAS_DE_AVISO = ['label-content-name-mismatch'];

function servir() {
  const servidor = http.createServer((pedido, resposta) => {
    const caminho = decodeURIComponent(new URL(pedido.url, 'http://localhost').pathname);
    const arquivo = path.join(DIST, caminho.endsWith('/') ? caminho + 'index.html' : caminho);
    if (!arquivo.startsWith(DIST) || !fs.existsSync(arquivo)) {
      resposta.writeHead(404);
      return resposta.end();
    }
    resposta.writeHead(200, { 'Content-Type': TIPOS[path.extname(arquivo)] || 'application/octet-stream' });
    fs.createReadStream(arquivo).pipe(resposta);
  });
  return new Promise(ok => servidor.listen(PORTA, '127.0.0.1', () => ok(servidor)));
}

async function esperarCarregar(pagina) {
  await pagina.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  await pagina.waitForTimeout(300);
}

async function acessibilidade(pagina) {
  const resultado = await new AxeBuilder({ page: pagina }).include('#area-logada').analyze();
  const descrever = v => v.id + ' (' + v.nodes.length + '): ' + v.nodes[0].html.replace(/\s+/g, ' ').slice(0, 220);
  const relevantes = resultado.violations.filter(v => IMPACTOS_GRAVES.includes(v.impact));
  return {
    graves: relevantes.filter(v => !REGRAS_DE_AVISO.includes(v.id)).map(descrever),
    avisos: relevantes.filter(v => REGRAS_DE_AVISO.includes(v.id)).map(descrever)
  };
}

async function varrerPerfil(navegador, perfil, usuario, tema) {
  const contexto = await navegador.newContext({
    viewport: { width: 1360, height: 900 },
    timezoneId: 'America/Sao_Paulo',
    locale: 'pt-BR',
    serviceWorkers: 'block'
  });
  const pagina = await contexto.newPage();
  await pagina.clock.setFixedTime(new Date('2026-11-09T10:00:00-03:00'));
  const falhas = [];
  const avisos = [];
  pagina.on('pageerror', erro => falhas.push('erro de página: ' + erro.message));
  await contexto.route(
    u => !u.hostname.endsWith('supabase.co') && u.hostname !== '127.0.0.1',
    rota => rota.abort()
  );
  await contexto.route('https://*.supabase.co/**', async rota => {
    const pedido = rota.request();
    const r = atender(pedido.method(), pedido.url(), pedido.headers(), pedido.postData());
    if (r.status >= 400) falhas.push(`http ${r.status}: ${pedido.method()} ${new URL(pedido.url()).pathname}`);
    await rota.fulfill({
      status: r.status,
      contentType: 'application/json',
      body: r.corpo == null ? '' : JSON.stringify(r.corpo)
    });
  });
  await contexto.addInitScript(id => window.sessionStorage.setItem('fsm_rt', 'rt-' + id), usuario);
  await contexto.addInitScript(
    escolhido =>
      window.localStorage.setItem(
        'fsm_aparencia',
        JSON.stringify({ tema: escolhido, texto: 'normal', animacoes: 'sim' })
      ),
    tema
  );
  const menu = pagina.locator('aside nav button');
  const abrir = async () => {
    await pagina.goto(`http://127.0.0.1:${PORTA}/`);
    return menu
      .first()
      .waitFor({ timeout: 30000 })
      .then(() => true)
      .catch(() => false);
  };
  const telas = [];
  if (!(await abrir()) && !(await abrir())) falhas.push('o menu não apareceu');
  await esperarCarregar(pagina);
  const quantidade = await menu.count();
  try {
    for (let i = 0; i < quantidade; i++) {
      const botao = menu.nth(i);
      const rotulo = (await botao.innerText()).replace(/\s+/g, ' ').trim();
      await botao.click();
      await esperarCarregar(pagina);
      const texto = await pagina.locator('main').innerText();
      if (!texto.trim()) falhas.push(rotulo + ': tela vazia');
      const { graves, avisos: alertas } = await acessibilidade(pagina);
      graves.forEach(violacao => falhas.push(rotulo + ': acessibilidade ' + violacao));
      alertas.forEach(violacao => avisos.push(rotulo + ': ' + violacao));
      telas.push(rotulo);
    }
  } catch (erro) {
    falhas.push('a varredura parou: ' + erro.message.split('\n')[0]);
  }
  await contexto.close();
  return { telas, falhas, avisos };
}

async function principal() {
  if (!fs.existsSync(path.join(DIST, 'index.html'))) throw new Error('gere o site antes: python scripts/build.py');
  const servidor = await servir();
  const navegador = await chromium.launch();
  const temas = (process.env.TEMAS || 'claro,escuro').split(',');
  let total = 0;
  let falhas = 0;
  for (const tema of temas) {
    for (const [perfil, usuario] of Object.entries(PERFIS)) {
      const resultado = await varrerPerfil(navegador, perfil, usuario, tema);
      total += resultado.telas.length;
      falhas += resultado.falhas.length;
      console.log(`${tema} · ${perfil}: ${resultado.telas.length} telas, ${resultado.falhas.length} falha(s)`);
      resultado.falhas.forEach(falha => console.log('  - ' + falha));
      resultado.avisos.forEach(aviso => console.log('  aviso: ' + aviso));
    }
  }
  await navegador.close();
  servidor.close();
  console.log(`${total} telas varridas, ${falhas} falha(s)`);
  if (falhas) process.exit(1);
}

principal().catch(erro => {
  console.error(erro);
  process.exit(1);
});
