window.FSM_QR =
  window.FSM_QR ||
  (() => {
    const ECC_POR_BLOCO = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26];
    const BLOCOS = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5];
    const VERSAO_MAXIMA = 10;
    const MARGEM = 4;

    const multiplicar = (x, y) => {
      let z = 0;
      for (let i = 7; i >= 0; i--) {
        z = (z << 1) ^ ((z >>> 7) * 0x11d);
        z ^= ((y >>> i) & 1) * x;
      }
      return z & 0xff;
    };

    const divisor = grau => {
      const resultado = new Array(grau).fill(0);
      resultado[grau - 1] = 1;
      let raiz = 1;
      for (let i = 0; i < grau; i++) {
        for (let j = 0; j < grau; j++) {
          resultado[j] = multiplicar(resultado[j], raiz);
          if (j + 1 < grau) resultado[j] ^= resultado[j + 1];
        }
        raiz = multiplicar(raiz, 0x02);
      }
      return resultado;
    };

    const resto = (dados, gerador) => {
      const resultado = new Array(gerador.length).fill(0);
      for (const byte of dados) {
        const fator = byte ^ resultado.shift();
        resultado.push(0);
        gerador.forEach((coeficiente, i) => (resultado[i] ^= multiplicar(coeficiente, fator)));
      }
      return resultado;
    };

    const modulosBrutos = versao => {
      let resultado = (16 * versao + 128) * versao + 64;
      if (versao >= 2) {
        const alinhamentos = Math.floor(versao / 7) + 2;
        resultado -= (25 * alinhamentos - 10) * alinhamentos - 55;
        if (versao >= 7) resultado -= 36;
      }
      return resultado;
    };

    const capacidade = versao => Math.floor(modulosBrutos(versao) / 8) - ECC_POR_BLOCO[versao] * BLOCOS[versao];

    const posicoesDeAlinhamento = versao => {
      if (versao === 1) return [];
      const tamanho = versao * 4 + 17,
        quantidade = Math.floor(versao / 7) + 2,
        passo = Math.floor((versao * 8 + quantidade * 3 + 5) / (quantidade * 4 - 4)) * 2,
        resultado = [6];
      for (let posicao = tamanho - 7; resultado.length < quantidade; posicao -= passo) resultado.splice(1, 0, posicao);
      return resultado;
    };

    const bytesDe = texto => Array.from(new TextEncoder().encode(String(texto)));

    const escolherVersao = bytes => {
      for (let versao = 1; versao <= VERSAO_MAXIMA; versao++) {
        const bits = 4 + (versao < 10 ? 8 : 16) + bytes.length * 8;
        if (bits <= capacidade(versao) * 8) return versao;
      }
      return 0;
    };

    const codificarDados = (bytes, versao) => {
      const bits = [];
      const acrescentar = (valor, tamanho) => {
        for (let i = tamanho - 1; i >= 0; i--) bits.push((valor >>> i) & 1);
      };
      acrescentar(4, 4);
      acrescentar(bytes.length, versao < 10 ? 8 : 16);
      bytes.forEach(byte => acrescentar(byte, 8));
      const limite = capacidade(versao) * 8;
      acrescentar(0, Math.min(4, limite - bits.length));
      acrescentar(0, (8 - (bits.length % 8)) % 8);
      for (let enchimento = 0xec; bits.length < limite; enchimento ^= 0xec ^ 0x11) acrescentar(enchimento, 8);
      const dados = [];
      for (let i = 0; i < bits.length; i += 8) dados.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));
      return dados;
    };

    const intercalar = (dados, versao) => {
      const quantidade = BLOCOS[versao],
        eccPorBloco = ECC_POR_BLOCO[versao],
        brutos = Math.floor(modulosBrutos(versao) / 8),
        curtos = quantidade - (brutos % quantidade),
        tamanhoCurto = Math.floor(brutos / quantidade),
        gerador = divisor(eccPorBloco),
        blocos = [];
      for (let i = 0, k = 0; i < quantidade; i++) {
        const bloco = dados.slice(k, k + tamanhoCurto - eccPorBloco + (i < curtos ? 0 : 1));
        k += bloco.length;
        const correcao = resto(bloco, gerador);
        if (i < curtos) bloco.push(0);
        blocos.push(bloco.concat(correcao));
      }
      const resultado = [];
      for (let i = 0; i < blocos[0].length; i++)
        blocos.forEach((bloco, j) => {
          if (i !== tamanhoCurto - eccPorBloco || j >= curtos) resultado.push(bloco[i]);
        });
      return resultado;
    };

    const MASCARAS = [
      (x, y) => (x + y) % 2 === 0,
      (x, y) => y % 2 === 0,
      x => x % 3 === 0,
      (x, y) => (x + y) % 3 === 0,
      (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
      (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
      (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
      (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0
    ];

    const montar = (versao, codigos, mascara) => {
      const tamanho = versao * 4 + 17,
        modulos = Array.from({ length: tamanho }, () => new Array(tamanho).fill(false)),
        funcao = Array.from({ length: tamanho }, () => new Array(tamanho).fill(false));
      const marcar = (x, y, escuro) => {
        modulos[y][x] = escuro;
        funcao[y][x] = true;
      };
      for (let i = 0; i < tamanho; i++) {
        marcar(6, i, i % 2 === 0);
        marcar(i, 6, i % 2 === 0);
      }
      [
        [3, 3],
        [tamanho - 4, 3],
        [3, tamanho - 4]
      ].forEach(([cx, cy]) => {
        for (let dy = -4; dy <= 4; dy++)
          for (let dx = -4; dx <= 4; dx++) {
            const x = cx + dx,
              y = cy + dy,
              d = Math.max(Math.abs(dx), Math.abs(dy));
            if (x >= 0 && x < tamanho && y >= 0 && y < tamanho) marcar(x, y, d !== 2 && d !== 4);
          }
      });
      const alinhamentos = posicoesDeAlinhamento(versao),
        ultimo = alinhamentos.length - 1;
      alinhamentos.forEach((ay, i) =>
        alinhamentos.forEach((ax, j) => {
          if ((i === 0 && j === 0) || (i === 0 && j === ultimo) || (i === ultimo && j === 0)) return;
          for (let dy = -2; dy <= 2; dy++)
            for (let dx = -2; dx <= 2; dx++) marcar(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
        })
      );
      const formato = (() => {
        const dados = mascara;
        let r = dados;
        for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
        return ((dados << 10) | r) ^ 0x5412;
      })();
      const bit = (valor, i) => ((valor >>> i) & 1) === 1;
      for (let i = 0; i <= 5; i++) marcar(8, i, bit(formato, i));
      marcar(8, 7, bit(formato, 6));
      marcar(8, 8, bit(formato, 7));
      marcar(7, 8, bit(formato, 8));
      for (let i = 9; i < 15; i++) marcar(14 - i, 8, bit(formato, i));
      for (let i = 0; i < 8; i++) marcar(tamanho - 1 - i, 8, bit(formato, i));
      for (let i = 8; i < 15; i++) marcar(8, tamanho - 15 + i, bit(formato, i));
      marcar(8, tamanho - 8, true);
      if (versao >= 7) {
        let r = versao;
        for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25);
        const bits = (versao << 12) | r;
        for (let i = 0; i < 18; i++) {
          const a = tamanho - 11 + (i % 3),
            b = Math.floor(i / 3);
          marcar(a, b, bit(bits, i));
          marcar(b, a, bit(bits, i));
        }
      }
      let i = 0;
      for (let direita = tamanho - 1; direita >= 1; direita -= 2) {
        if (direita === 6) direita = 5;
        for (let vertical = 0; vertical < tamanho; vertical++)
          for (let j = 0; j < 2; j++) {
            const x = direita - j,
              subindo = ((direita + 1) & 2) === 0,
              y = subindo ? tamanho - 1 - vertical : vertical;
            if (!funcao[y][x] && i < codigos.length * 8) {
              modulos[y][x] = bit(codigos[i >>> 3], 7 - (i & 7));
              i++;
            }
          }
      }
      const aplicar = MASCARAS[mascara];
      for (let y = 0; y < tamanho; y++)
        for (let x = 0; x < tamanho; x++) if (!funcao[y][x] && aplicar(x, y)) modulos[y][x] = !modulos[y][x];
      return modulos;
    };

    const penalidade = modulos => {
      const tamanho = modulos.length;
      let total = 0,
        escuros = 0;
      const linha = (obter, k) => {
        const valores = [];
        for (let i = 0; i < tamanho; i++) valores.push(obter(k, i));
        return valores;
      };
      const PADRAO = [true, false, true, true, true, false, true];
      const verificar = valores => {
        let corrida = 1;
        for (let i = 1; i <= valores.length; i++) {
          if (i < valores.length && valores[i] === valores[i - 1]) corrida++;
          else {
            if (corrida >= 5) total += corrida - 2;
            corrida = 1;
          }
        }
        for (let i = 0; i + 7 <= valores.length; i++) {
          if (!PADRAO.every((v, k) => valores[i + k] === v)) continue;
          const antes = i >= 4 && [1, 2, 3, 4].every(k => !valores[i - k]),
            depois = i + 11 <= valores.length && [7, 8, 9, 10].every(k => !valores[i + k]);
          if (antes || depois) total += 40;
        }
      };
      for (let k = 0; k < tamanho; k++) {
        verificar(linha((y, x) => modulos[y][x], k));
        verificar(linha((x, y) => modulos[y][x], k));
      }
      for (let y = 0; y < tamanho; y++)
        for (let x = 0; x < tamanho; x++) {
          if (modulos[y][x]) escuros++;
          if (
            x + 1 < tamanho &&
            y + 1 < tamanho &&
            modulos[y][x] === modulos[y][x + 1] &&
            modulos[y][x] === modulos[y + 1][x] &&
            modulos[y][x] === modulos[y + 1][x + 1]
          )
            total += 3;
        }
      const area = tamanho * tamanho;
      total += Math.max(0, Math.ceil(Math.abs(escuros * 20 - area * 10) / area) - 1) * 10;
      return total;
    };

    const matriz = (texto, mascaraFixa) => {
      const bytes = bytesDe(texto),
        versao = escolherVersao(bytes);
      if (!versao) return null;
      const codigos = intercalar(codificarDados(bytes, versao), versao);
      if (mascaraFixa != null) return montar(versao, codigos, mascaraFixa);
      let melhor = null,
        menor = Infinity;
      for (let mascara = 0; mascara < 8; mascara++) {
        const modulos = montar(versao, codigos, mascara),
          pontos = penalidade(modulos);
        if (pontos < menor) {
          menor = pontos;
          melhor = modulos;
        }
      }
      return melhor;
    };

    const desenho = texto => {
      const modulos = matriz(texto);
      if (!modulos) return null;
      const partes = [];
      modulos.forEach((linha, y) => {
        for (let x = 0; x < linha.length; x++) {
          if (!linha[x]) continue;
          let fim = x;
          while (fim + 1 < linha.length && linha[fim + 1]) fim++;
          partes.push('M' + (x + MARGEM) + ' ' + (y + MARGEM) + 'h' + (fim - x + 1) + 'v1h-' + (fim - x + 1) + 'z');
          x = fim;
        }
      });
      return { tamanho: modulos.length + MARGEM * 2, caminho: partes.join('') };
    };

    return { matriz, desenho };
  })();
