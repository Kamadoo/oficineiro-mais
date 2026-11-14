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
const ABAS = process.env.ABAS !== '0';
const CELULAR = process.env.CELULAR !== '0';

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

const limpo = texto => texto.replace(/\s+/g, ' ').trim();

async function acessibilidade(pagina, alvo = '#area-logada') {
  const resultado = await new AxeBuilder({ page: pagina }).include(alvo).analyze();
  const descrever = v => v.id + ' (' + v.nodes.length + '): ' + limpo(v.nodes[0].html).slice(0, 220);
  return resultado.violations.filter(v => IMPACTOS_GRAVES.includes(v.impact)).map(descrever);
}

async function examinar(pagina, rotulo, falhas, celular) {
  const texto = await pagina.locator('main').innerText();
  if (!texto.trim()) falhas.push(rotulo + ': tela vazia');
  for (const violacao of await acessibilidade(pagina)) falhas.push(rotulo + ': acessibilidade ' + violacao);
  if (celular) {
    const sobra = await pagina.evaluate(() => globalThis.document.documentElement.scrollWidth - globalThis.innerWidth);
    if (sobra > 1) falhas.push(rotulo + ': rolagem horizontal de ' + sobra + ' px');
  }
}

async function examinarGaveta(pagina, rotulo, falhas) {
  const abridor = pagina.locator('main button[aria-haspopup="dialog"]:visible').first();
  if (!(await abridor.count())) return 0;
  const nome = limpo((await abridor.getAttribute('aria-label')) || (await abridor.innerText()));
  const onde = rotulo + ' · ' + nome;
  await abridor.click();
  const gaveta = pagina.locator('[role=dialog]:visible').first();
  const abriu = await gaveta.waitFor({ timeout: 3000 }).then(
    () => true,
    () => false
  );
  if (!abriu) {
    falhas.push(onde + ': a gaveta não abriu');
    return 0;
  }
  await pagina.waitForTimeout(300);
  for (const violacao of await acessibilidade(pagina, '[role=dialog]'))
    falhas.push(onde + ': acessibilidade ' + violacao);
  await pagina.keyboard.press('Escape');
  await gaveta.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => falhas.push(onde + ': Esc não fechou'));
  return 1;
}

async function examinarAbas(pagina, rotulo, falhas, celular) {
  const abas = pagina.locator('main [role=tab]');
  const quantidade = await abas.count();
  let vistas = 0;
  for (let i = 1; i < quantidade; i++) {
    const aba = abas.nth(i);
    if (!(await aba.isVisible())) continue;
    const onde = rotulo + ' › ' + limpo(await aba.innerText());
    await aba.click();
    await esperarCarregar(pagina);
    await examinar(pagina, onde, falhas, celular);
    if (!celular) vistas += await examinarGaveta(pagina, onde, falhas);
    vistas++;
  }
  if (quantidade > 1) {
    await abas.first().click();
    await esperarCarregar(pagina);
  }
  return vistas;
}

async function varrerPerfil(navegador, usuario, tema, celular) {
  const contexto = await navegador.newContext({
    viewport: celular ? { width: 390, height: 844 } : { width: 1360, height: 900 },
    isMobile: celular,
    hasTouch: celular,
    timezoneId: 'America/Sao_Paulo',
    locale: 'pt-BR',
    serviceWorkers: 'block'
  });
  const pagina = await contexto.newPage();
  await pagina.clock.setFixedTime(new Date('2026-11-09T10:00:00-03:00'));
  const falhas = [];
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
  const abrirMenu = pagina.locator('button[aria-label="Abrir menu"]:visible');
  const abrir = async () => {
    await pagina.goto(`http://127.0.0.1:${PORTA}/`);
    return menu
      .first()
      .waitFor({ state: 'attached', timeout: 30000 })
      .then(() => true)
      .catch(() => false);
  };
  const telas = [];
  let extras = 0;
  if (!(await abrir()) && !(await abrir())) falhas.push('o menu não apareceu');
  await esperarCarregar(pagina);
  const quantidade = await menu.count();
  try {
    for (let i = 0; i < quantidade; i++) {
      if (celular && (await abrirMenu.count())) {
        await abrirMenu.first().click();
        await pagina.waitForTimeout(250);
      }
      const botao = menu.nth(i);
      const rotulo = (celular ? 'celular · ' : '') + limpo(await botao.innerText());
      await botao.click();
      await esperarCarregar(pagina);
      await examinar(pagina, rotulo, falhas, celular);
      if (!celular) extras += await examinarGaveta(pagina, rotulo, falhas);
      if (ABAS) extras += await examinarAbas(pagina, rotulo, falhas, celular);
      telas.push(rotulo);
    }
  } catch (erro) {
    falhas.push('a varredura parou: ' + erro.message.split('\n')[0]);
  }
  await contexto.close();
  return { telas, falhas, extras };
}

async function principal() {
  if (!fs.existsSync(path.join(DIST, 'index.html'))) throw new Error('gere o site antes: python scripts/build.py');
  const servidor = await servir();
  const navegador = await chromium.launch();
  const temas = (process.env.TEMAS || 'claro,escuro').split(',');
  const so = process.env.SO ? process.env.SO.split(',') : null;
  const rodadas = temas.map(tema => [tema, false]);
  if (CELULAR) rodadas.push([temas[0], true]);
  let total = 0;
  let extras = 0;
  let falhas = 0;
  for (const [tema, celular] of rodadas) {
    for (const [perfil, usuario] of Object.entries(PERFIS)) {
      if (so && !so.includes(perfil)) continue;
      const resultado = await varrerPerfil(navegador, usuario, tema, celular);
      total += resultado.telas.length;
      extras += resultado.extras;
      falhas += resultado.falhas.length;
      const rodada = celular ? 'celular' : tema;
      console.log(
        `${rodada} · ${perfil}: ${resultado.telas.length} telas, ${resultado.extras} abas e gavetas, ${resultado.falhas.length} falha(s)`
      );
      resultado.falhas.forEach(falha => console.log('  - ' + falha));
    }
  }
  await navegador.close();
  servidor.close();
  console.log(`${total} telas varridas, ${extras} abas e gavetas, ${falhas} falha(s)`);
  if (falhas) process.exit(1);
}

principal().catch(erro => {
  console.error(erro);
  process.exit(1);
});
