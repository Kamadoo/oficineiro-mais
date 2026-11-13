const ORIGENS = (Deno.env.get('FSM_ORIGEM_PERMITIDA') ?? '')
  .split(',')
  .map((o) => o.trim().replace(/\/+$/, ''))
  .filter(Boolean);

export function cabecalhos(req: Request): HeadersInit {
  const origem = req.headers.get('origin') ?? '';
  return {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Vary': 'Origin',
    ...(ORIGENS.includes(origem)
      ? {
        'Access-Control-Allow-Origin': origem,
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
        'Access-Control-Max-Age': '600',
      }
      : {}),
  };
}

export function origemPermitida(req: Request): boolean {
  const origem = req.headers.get('origin');
  return origem === null || ORIGENS.includes(origem);
}

export function resposta(req: Request, status: number, corpo: unknown): Response {
  return new Response(JSON.stringify(corpo), { status, headers: cabecalhos(req) });
}

export class ErroPublico extends Error {
  constructor(
    public status: number,
    mensagem: string,
  ) {
    super(mensagem);
  }
}

export function texto(v: unknown, campo: string, min: number, max: number): string {
  if (typeof v !== 'string') throw new ErroPublico(400, `campo ${campo} obrigatório`);
  const s = v.normalize('NFC').replace(/\s+/g, ' ').trim();
  if (s.length < min || s.length > max) throw new ErroPublico(400, `campo ${campo} com tamanho inválido`);
  if (/[<>\u0000-\u001f]/.test(s)) throw new ErroPublico(400, `campo ${campo} com caracteres não permitidos`);
  return s;
}

export function email(v: unknown): string {
  const s = texto(v, 'email', 6, 160).toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(s)) throw new ErroPublico(400, 'e-mail inválido');
  return s;
}

export function uuid(v: unknown, campo: string): string {
  if (typeof v !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)) {
    throw new ErroPublico(400, `campo ${campo} inválido`);
  }
  return v.toLowerCase();
}

export async function lerJson(req: Request, maxBytes = 16_384): Promise<Record<string, unknown>> {
  const tipo = req.headers.get('content-type') ?? '';
  if (!tipo.includes('application/json')) throw new ErroPublico(415, 'envie JSON');
  const bruto = await req.text();
  if (bruto.length > maxBytes) throw new ErroPublico(413, 'requisição grande demais');
  try {
    const obj = JSON.parse(bruto);
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) throw new Error();
    return obj as Record<string, unknown>;
  } catch {
    throw new ErroPublico(400, 'JSON inválido');
  }
}
