const zlib = require('zlib');

function entradas(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const saida = {};
  let pos = 0;
  while (pos + 30 <= bytes.length && dv.getUint32(pos, true) === 0x04034b50) {
    const metodo = dv.getUint16(pos + 8, true);
    const tamanho = dv.getUint32(pos + 18, true);
    const nomeTam = dv.getUint16(pos + 26, true);
    const extraTam = dv.getUint16(pos + 28, true);
    const nome = Buffer.from(bytes.subarray(pos + 30, pos + 30 + nomeTam)).toString('utf8');
    const inicio = pos + 30 + nomeTam + extraTam;
    const dados = Buffer.from(bytes.subarray(inicio, inicio + tamanho));
    saida[nome] = (metodo === 8 ? zlib.inflateRawSync(dados) : dados).toString('utf8');
    pos = inicio + tamanho;
  }
  return saida;
}

function montar(partes, compactar = true) {
  const locais = [];
  const centrais = [];
  let deslocamento = 0;
  for (const [nome, texto] of Object.entries(partes)) {
    const nomeB = Buffer.from(nome, 'utf8');
    const original = Buffer.from(texto, 'utf8');
    const dados = compactar ? zlib.deflateRawSync(original) : original;
    const crc = zlib.crc32(original);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(compactar ? 8 : 0, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(dados.length, 18);
    local.writeUInt32LE(original.length, 22);
    local.writeUInt16LE(nomeB.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(compactar ? 8 : 0, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(dados.length, 20);
    central.writeUInt32LE(original.length, 24);
    central.writeUInt16LE(nomeB.length, 28);
    central.writeUInt32LE(deslocamento, 42);
    locais.push(local, nomeB, dados);
    centrais.push(central, nomeB);
    deslocamento += local.length + nomeB.length + dados.length;
  }
  const corpoCentral = Buffer.concat(centrais);
  const fim = Buffer.alloc(22);
  fim.writeUInt32LE(0x06054b50, 0);
  fim.writeUInt16LE(Object.keys(partes).length, 8);
  fim.writeUInt16LE(Object.keys(partes).length, 10);
  fim.writeUInt32LE(corpoCentral.length, 12);
  fim.writeUInt32LE(deslocamento, 16);
  return new Uint8Array(Buffer.concat([...locais, corpoCentral, fim]));
}

function arquivo(nome, bytes) {
  return { name: nome, size: bytes.length, arrayBuffer: async () => bytes.slice().buffer };
}

module.exports = { entradas, montar, arquivo };
