window.FSM_ONB = (() => {
  const LIM = { arquivo: 5 * 1024 * 1024, entradas: 2000, descompactado: 30 * 1024 * 1024, linhas: 5000 };

  function norm(s) {
    return String(s || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9 ]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }
  const STOP = {
    e: 1,
    m: 1,
    em: 1,
    cei: 1,
    escola: 1,
    municipal: 1,
    creche: 1,
    de: 1,
    da: 1,
    do: 1,
    dos: 1,
    das: 1,
    prof: 1,
    professor: 1,
    professora: 1
  };
  function toks(s) {
    return norm(s)
      .split(' ')
      .filter(t => t.length > 1 && !STOP[t]);
  }

  function matchEscola(lot, lista) {
    const L = lista || [];
    const raw = String(lot || '').trim();
    const sig = (raw.match(/^([A-Za-zÀ-ú]{1,6})\s*-\s*/) || [])[1];
    if (sig) {
      const bySig = L.filter(l => l.sig && l.sig.toLowerCase() === sig.toLowerCase())[0];
      if (bySig) return { sig: bySig.sig, n: bySig.n, cs: bySig.cs, conf: 'sigla' };
    }
    const t = toks(raw.replace(/^[A-Za-zÀ-ú]{1,6}\s*-\s*/, ''));
    let best = null;
    let bs = 0;
    if (!t.length) return null;
    L.forEach(l => {
      const lt = toks(l.n.replace(/^[A-Za-zÀ-ú]{1,6}\s*-\s*/, ''));
      if (!lt.length) return;
      const hit = t.filter(x => lt.indexOf(x) >= 0).length;
      const sc = hit / t.length;
      if (hit >= Math.min(2, t.length) && sc > bs) {
        bs = sc;
        best = l;
      }
    });
    if (!best && /\bnte\b|nucleo de tecnologia/.test(norm(raw))) best = L.filter(l => l.sig === 'NTE')[0];
    return best ? { sig: best.sig, n: best.n, cs: best.cs, conf: 'nome' } : null;
  }

  function dec(s) {
    return String(s || '')
      .replace(/&#(\d+);/g, (m, n) => String.fromCharCode(+n))
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/\u00a0/g, ' ')
      .trim();
  }
  function falha(msg) {
    throw new Error('Arquivo inválido: ' + msg);
  }
  async function inflar(data, max) {
    const rd = new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw')).getReader();
    const partes = [];
    let tot = 0;
    for (;;) {
      const r = await rd.read();
      if (r.done) break;
      tot += r.value.length;
      if (tot > max) {
        try {
          rd.cancel();
        } catch (e) {}
        falha('conteúdo descompactado grande demais.');
      }
      partes.push(r.value);
    }
    const out = new Uint8Array(tot);
    let o = 0;
    partes.forEach(p => {
      out.set(p, o);
      o += p.length;
    });
    return new TextDecoder().decode(out);
  }
  async function unzip(buf) {
    const u = new Uint8Array(buf);
    const dv = new DataView(u.buffer);
    let e = u.length - 22;
    let gasto = 0;
    if (u.length < 22) falha('não é um .xlsx.');
    while (e > 0 && dv.getUint32(e, true) !== 0x06054b50) e--;
    if (e <= 0) falha('não é um .xlsx.');
    let off = dv.getUint32(e + 16, true);
    const n = dv.getUint16(e + 10, true);
    const out = {};
    if (n > LIM.entradas || off >= u.length) falha('estrutura do arquivo fora do esperado.');
    for (let i = 0; i < n; i++) {
      if (off + 46 > u.length || dv.getUint32(off, true) !== 0x02014b50)
        falha('estrutura do arquivo fora do esperado.');
      const m = dv.getUint16(off + 10, true);
      const csz = dv.getUint32(off + 20, true);
      const nl = dv.getUint16(off + 28, true);
      const el = dv.getUint16(off + 30, true);
      const cl = dv.getUint16(off + 32, true);
      const lo = dv.getUint32(off + 42, true);
      const name = new TextDecoder().decode(u.slice(off + 46, off + 46 + nl));
      off += 46 + nl + el + cl;
      ((m, lo, csz) => {
        out[name] = async () => {
          if (lo + 30 > u.length) falha('estrutura do arquivo fora do esperado.');
          const lnl = dv.getUint16(lo + 26, true);
          const lel = dv.getUint16(lo + 28, true);
          const ini = lo + 30 + lnl + lel;
          if (ini + csz > u.length) falha('estrutura do arquivo fora do esperado.');
          const data = u.slice(ini, ini + csz);
          let txt;
          if (m === 0) txt = new TextDecoder().decode(data);
          else if (m === 8) txt = await inflar(data, LIM.descompactado - gasto);
          else falha('compactação não suportada.');
          gasto += txt.length;
          if (gasto > LIM.descompactado) falha('conteúdo descompactado grande demais.');
          return txt;
        };
      })(m, lo, csz);
    }
    return out;
  }
  async function linhasDaAba(file, escolher, oQue) {
    if (!file || !/\.xlsx$/i.test(file.name || '')) falha('envie ' + oQue + ' em .xlsx.');
    if (file.size > LIM.arquivo) falha('o arquivo passa de 5 MB.');
    const z = await unzip(await file.arrayBuffer());
    if (!z['xl/workbook.xml'] || !z['xl/_rels/workbook.xml.rels']) falha('não é uma planilha do Excel.');
    const wb = await z['xl/workbook.xml']();
    const sheets = Array.from(wb.matchAll(/<sheet [^>]*name="([^"]+)"[^>]*r:id="([^"]+)"/g)).map(m => [
      dec(m[1]),
      m[2]
    ]);
    if (!sheets.length) falha('a planilha não tem abas.');
    const rels = await z['xl/_rels/workbook.xml.rels']();
    const alvo = escolher(sheets) || sheets[0];
    const tgt =
      (rels.match(new RegExp('Id="' + alvo[1] + '"[^>]*Target="([^"]+)"')) ||
        rels.match(new RegExp('Target="([^"]+)"[^>]*Id="' + alvo[1] + '"')) ||
        [])[1] || 'worksheets/sheet1.xml';
    const path = 'xl/' + tgt.replace(/^\/?xl\//, '').replace(/^\//, '');
    let ss = [];
    if (z['xl/sharedStrings.xml']) {
      const t = await z['xl/sharedStrings.xml']();
      ss = Array.from(t.matchAll(/<si>([\s\S]*?)<\/si>/g)).map(m =>
        Array.from(m[1].matchAll(/<t[^>]*>([^<]*)</g))
          .map(x => x[1])
          .join('')
      );
    }
    if (!z[path]) falha('aba da planilha não encontrada.');
    const x = await z[path]();
    const linhasXml = Array.from(x.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g));
    if (linhasXml.length > LIM.linhas + 50) falha('mais de ' + LIM.linhas + ' linhas.');
    return linhasXml.map(r => {
      if (r[1].length > 20000) falha('linha da planilha grande demais.');
      const o = {};
      r[1]
        .split(/(?=<c\s)/)
        .map(f => f.match(/^<c r="([A-Z]+)\d+"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/))
        .filter(Boolean)
        .forEach(c => {
          const ty = (c[2].match(/t="(\w+)"/) || [])[1];
          const v = (c[3] || '').match(/<v>([^<]*)</);
          const is = (c[3] || '').match(/<t[^>]*>([^<]*)</);
          let val = v ? v[1] : is ? is[1] : '';
          if (ty === 's') val = ss[+val];
          o[c[1]] = dec(val);
        });
      return o;
    });
  }
  async function lerPlanilha(file) {
    const R = await linhasDaAba(file, sheets => sheets[0], 'a planilha');
    const hi = R.findIndex(r => Object.values(r).filter(v => String(v || '').trim()).length >= 2);
    if (hi < 0) throw new Error('A planilha está vazia.');
    const cab = {};
    Object.keys(R[hi]).forEach(k => {
      cab[k] = norm(R[hi][k]);
    });
    const linhas = R.slice(hi + 1)
      .filter(r => Object.values(r).some(v => String(v || '').trim()))
      .map(r => {
        const o = {};
        Object.keys(cab).forEach(k => {
          if (cab[k]) o[cab[k]] = String(r[k] || '').trim();
        });
        return o;
      });
    if (linhas.length > LIM.linhas) falha('mais de ' + LIM.linhas + ' linhas.');
    return { colunas: Object.values(cab).filter(Boolean), linhas };
  }
  async function lerOS(file) {
    const R = await linhasDaAba(
      file,
      sheets => sheets.filter(s => /ativa/i.test(s[0]) && !/desativa/i.test(s[0]))[0],
      'a planilha da OS'
    );
    const titulo = (R[0] && Object.values(R[0]).join(' ')) || '';
    const num = (titulo.match(/N[º°o]\s*0*(\d+)/i) || file.name.match(/OS\s*0*(\d+)/i) || [])[1] || '?';
    const sec =
      (titulo.match(/\b(SEMED|SEMAD|SEMSA)\b/i) || file.name.match(/(SEMED|SEMAD|SEMSA)/i) || [])[1] || 'SEMED';
    const hi = R.findIndex(r => Object.values(r).some(v => /NOME DO USU/i.test(v)));
    if (hi < 0) throw new Error('Não encontrei a linha de cabeçalho (NOME DO USUÁRIO) no arquivo.');
    const H = {};
    Object.keys(R[hi]).forEach(k => {
      H[norm(R[hi][k])] = k;
    });
    function col(re) {
      const k = Object.keys(H).filter(h => re.test(h))[0];
      return k ? H[k] : null;
    }
    const C = {
      seq: col(/^seq/),
      tipo: col(/^tipo/),
      nome: col(/nome/),
      email: col(/mail/),
      login: col(/login/),
      mat: col(/matricula/),
      lot: col(/lotacao/),
      cargo: col(/cargo/)
    };
    if (R.length - hi - 1 > LIM.linhas) falha('mais de ' + LIM.linhas + ' linhas.');
    const rows = R.slice(hi + 1)
      .filter(r => C.nome && r[C.nome])
      .map(r => ({
        seq: r[C.seq] || '',
        tipo: r[C.tipo] || '',
        nome: r[C.nome].replace(/\s+/g, ' '),
        email: (r[C.email] || '').toLowerCase(),
        login: r[C.login] || '',
        matricula: r[C.mat] || '',
        lotacao: (r[C.lot] || '').replace(/\s+/g, ' '),
        cargo: r[C.cargo] || ''
      }));
    return { num, sec: sec.toUpperCase(), arquivo: file.name, rows };
  }

  return {
    matchEscola,
    lerOS,
    lerPlanilha
  };
})();
