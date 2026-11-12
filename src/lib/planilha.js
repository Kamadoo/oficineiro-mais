(() => {
  'use strict';

  const CRC = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(b) {
    let c = 0xffffffff;
    for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }
  function utf8(s) {
    return new TextEncoder().encode(s);
  }

  function zip(arquivos) {
    const partes = [];
    const central = [];
    let pos = 0;
    arquivos.forEach(f => {
      const nome = utf8(f.nome);
      const dados = utf8(f.texto);
      const crc = crc32(dados);
      const h = new DataView(new ArrayBuffer(30));
      h.setUint32(0, 0x04034b50, true);
      h.setUint16(4, 20, true);
      h.setUint16(6, 0x0800, true);
      h.setUint16(8, 0, true);
      h.setUint16(10, 0, true);
      h.setUint16(12, 0x21, true);
      h.setUint32(14, crc, true);
      h.setUint32(18, dados.length, true);
      h.setUint32(22, dados.length, true);
      h.setUint16(26, nome.length, true);
      h.setUint16(28, 0, true);
      partes.push(new Uint8Array(h.buffer), nome, dados);
      const c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true);
      c.setUint16(4, 20, true);
      c.setUint16(6, 20, true);
      c.setUint16(8, 0x0800, true);
      c.setUint16(10, 0, true);
      c.setUint16(12, 0, true);
      c.setUint16(14, 0x21, true);
      c.setUint32(16, crc, true);
      c.setUint32(20, dados.length, true);
      c.setUint32(24, dados.length, true);
      c.setUint16(28, nome.length, true);
      c.setUint16(30, 0, true);
      c.setUint16(32, 0, true);
      c.setUint16(34, 0, true);
      c.setUint16(36, 0, true);
      c.setUint32(38, 0, true);
      c.setUint32(42, pos, true);
      central.push(new Uint8Array(c.buffer), nome);
      pos += 30 + nome.length + dados.length;
    });
    const tamCentral = central.reduce((t, p) => t + p.length, 0);
    const fim = new DataView(new ArrayBuffer(22));
    fim.setUint32(0, 0x06054b50, true);
    fim.setUint16(8, arquivos.length, true);
    fim.setUint16(10, arquivos.length, true);
    fim.setUint32(12, tamCentral, true);
    fim.setUint32(16, pos, true);
    return new Blob(partes.concat(central, [new Uint8Array(fim.buffer)]), {
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    });
  }

  function xml(s) {
    return String(s)
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g, '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
  function coluna(i) {
    let s = '';
    i++;
    while (i > 0) {
      const m = (i - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      i = Math.floor((i - 1) / 26);
    }
    return s;
  }
  function numero(v) {
    if (typeof v === 'number' && isFinite(v)) return v;
    if (typeof v === 'string' && /^-?(0|[1-9]\d{0,8})$/.test(v.trim())) return Number(v.trim());
    return null;
  }
  function vazia(l) {
    return !l || !l.length || l.every(v => v == null || String(v).trim() === '');
  }

  const ESTILOS =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    '<fonts count="4"><font><sz val="11"/><color rgb="FF17191C"/><name val="Calibri"/></font>' +
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' +
    '<font><b/><sz val="14"/><color rgb="FF150D2E"/><name val="Calibri"/></font>' +
    '<font><i/><sz val="11"/><color rgb="FF5F6368"/><name val="Calibri"/></font></fonts>' +
    '<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
    '<fill><patternFill patternType="solid"><fgColor rgb="FF8E0A5C"/><bgColor indexed="64"/></patternFill></fill>' +
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF8F6FB"/><bgColor indexed="64"/></patternFill></fill></fills>' +
    '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>' +
    '<border><left style="thin"><color rgb="FFD8D2E6"/></left><right style="thin"><color rgb="FFD8D2E6"/></right><top style="thin"><color rgb="FFD8D2E6"/></top><bottom style="thin"><color rgb="FFD8D2E6"/></bottom><diagonal/></border></borders>' +
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
    '<cellXfs count="6">' +
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>' +
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>' +
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>' +
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
    '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  function planilha(linhas, nomeAba) {
    linhas = (linhas || []).map(l => (Array.isArray(l) ? l : [l]));
    const maxCols = linhas.reduce((m, l) => Math.max(m, l.length), 1);
    const tipos = [];
    let cab = -1;
    let zebra = 0;
    let primeiroCab = -1;
    let fimPrimeira = -1;
    linhas.forEach((l, i) => {
      if (vazia(l)) {
        tipos.push('vazia');
        if (primeiroCab >= 0 && fimPrimeira < 0) fimPrimeira = i - 1;
        cab = -1;
        return;
      }
      const anteriorVazia = i === 0 || tipos[i - 1] === 'vazia';
      const ehCab =
        l.length >= 2 &&
        anteriorVazia &&
        i + 1 < linhas.length &&
        !vazia(linhas[i + 1]) &&
        l.every(v => typeof v === 'string' && numero(v) === null);
      if (i === 0 && l.length === 1 && maxCols > 1) {
        tipos.push('titulo');
        return;
      }
      if (cab < 0 && !ehCab && primeiroCab < 0 && l.length <= 2 && maxCols > 2) {
        tipos.push('sub');
        return;
      }
      if (ehCab) {
        tipos.push('cab');
        cab = i;
        zebra = 0;
        if (primeiroCab < 0) primeiroCab = i;
        return;
      }
      tipos.push(zebra++ % 2 ? 'zebra' : 'corpo');
    });
    if (primeiroCab >= 0 && fimPrimeira < 0) fimPrimeira = linhas.length - 1;
    const larg = [];
    for (let c = 0; c < maxCols; c++) larg[c] = 8;
    linhas.forEach((l, i) => {
      if (tipos[i] === 'titulo' || tipos[i] === 'sub') return;
      l.forEach((v, c) => {
        const t = String(v == null ? '' : v);
        const maior = t.split('\n').reduce((m, p) => Math.max(m, p.length), 0);
        larg[c] = Math.max(larg[c], Math.min(60, maior + 2));
      });
    });
    let x =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">';
    x += '<sheetViews><sheetView workbookViewId="0" showGridLines="0">';
    if (primeiroCab >= 0)
      x +=
        '<pane ySplit="' +
        (primeiroCab + 1) +
        '" topLeftCell="A' +
        (primeiroCab + 2) +
        '" activePane="bottomLeft" state="frozen"/>';
    x += '</sheetView></sheetViews><sheetFormatPr defaultRowHeight="16"/><cols>';
    larg.forEach((w, c) => {
      x += '<col min="' + (c + 1) + '" max="' + (c + 1) + '" width="' + w + '" customWidth="1"/>';
    });
    x += '</cols><sheetData>';
    linhas.forEach((l, i) => {
      const tp = tipos[i];
      const st = { titulo: 4, sub: 5, cab: 1, corpo: 2, zebra: 3 }[tp] || 0;
      x +=
        '<row r="' +
        (i + 1) +
        '"' +
        (tp === 'cab' ? ' ht="22" customHeight="1"' : tp === 'titulo' ? ' ht="24" customHeight="1"' : '') +
        '>';
      if (tp !== 'vazia') {
        const n = tp === 'corpo' || tp === 'zebra' || tp === 'cab' ? Math.max(l.length, maxCols) : l.length;
        for (let c = 0; c < n; c++) {
          const v = l[c];
          const ref = coluna(c) + (i + 1);
          const num = tp === 'cab' ? null : numero(v);
          if (num !== null) x += '<c r="' + ref + '" s="' + st + '"><v>' + num + '</v></c>';
          else if (v == null || v === '') x += '<c r="' + ref + '" s="' + st + '"/>';
          else
            x +=
              '<c r="' + ref + '" s="' + st + '" t="inlineStr"><is><t xml:space="preserve">' + xml(v) + '</t></is></c>';
        }
      }
      x += '</row>';
    });
    x += '</sheetData>';
    if (primeiroCab >= 0 && fimPrimeira > primeiroCab)
      x += '<autoFilter ref="A' + (primeiroCab + 1) + ':' + coluna(maxCols - 1) + (fimPrimeira + 1) + '"/>';
    x +=
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/><pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>';
    const aba = xml(
      String(nomeAba || 'Planilha')
        .replace(/[\\/?*[\]:]/g, ' ')
        .slice(0, 31) || 'Planilha'
    );
    return zip([
      {
        nome: '[Content_Types].xml',
        texto:
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
      },
      {
        nome: '_rels/.rels',
        texto:
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
      },
      {
        nome: 'xl/workbook.xml',
        texto:
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="' +
          aba +
          '" sheetId="1" r:id="rId1"/></sheets></workbook>'
      },
      {
        nome: 'xl/_rels/workbook.xml.rels',
        texto:
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
      },
      { nome: 'xl/styles.xml', texto: ESTILOS },
      { nome: 'xl/worksheets/sheet1.xml', texto: x }
    ]);
  }

  function baixar(linhas, nome, aba) {
    const arquivo = String(nome || 'planilha').replace(/\.(csv|xlsx)$/i, '') + '.xlsx';
    const blob = planilha(linhas, aba);
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = arquivo;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
      URL.revokeObjectURL(a.href);
      a.remove();
    }, 1000);
    if (window.FSM_AUTH && window.FSM_AUTH.registrarAtividade)
      window.FSM_AUTH.registrarAtividade('EXPORTACAO', {
        formato: 'Excel',
        arquivo,
        tela: String(aba || ''),
        linhas: Array.isArray(linhas) ? linhas.length : 0
      });
  }

  window.FSM_PLANILHA = { gerar: planilha, baixar };
})();
