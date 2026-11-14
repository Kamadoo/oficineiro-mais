export const ORIGEM = 'https://app.exemplo.test';
export const SUPABASE = 'http://supabase.exemplo.test';

export type Pedido = { metodo: string; caminho: string; busca: URLSearchParams; corpo: unknown; cabecalhos: Headers };
type Rota = (p: Pedido) => Response | undefined;

let rota: Rota = () => undefined;
export const pedidos: Pedido[] = [];

export function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });
}

export function responder(nova: Rota) {
  rota = nova;
  pedidos.length = 0;
}

const manipuladores: ((req: Request) => Promise<Response>)[] = [];
let preparado = false;

function preparar() {
  if (preparado) return;
  preparado = true;
  Deno.env.set('SUPABASE_URL', SUPABASE);
  Deno.env.set('SUPABASE_ANON_KEY', 'chave-publica-de-teste');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'chave-de-servico-de-teste');
  Deno.env.set('FSM_ORIGEM_PERMITIDA', ORIGEM + '/');
  globalThis.fetch = async (entrada: string | URL | Request, init?: RequestInit) => {
    const req = new Request(entrada, init);
    const url = new URL(req.url);
    const texto = req.body ? await req.text() : '';
    let corpo: unknown = null;
    try {
      corpo = texto ? JSON.parse(texto) : null;
    } catch {
      corpo = texto;
    }
    const pedido = {
      metodo: req.method,
      caminho: url.pathname,
      busca: url.searchParams,
      corpo,
      cabecalhos: req.headers,
    };
    pedidos.push(pedido);
    return rota(pedido) ?? json({ message: 'rota sem resposta no teste: ' + req.method + ' ' + url.pathname }, 500);
  };
  (Deno as unknown as { serve: (h: (req: Request) => Promise<Response>) => unknown }).serve = (h) => {
    manipuladores.push(h);
    return {};
  };
}

export async function carregar(caminho: string): Promise<(req: Request) => Promise<Response>> {
  preparar();
  const antes = manipuladores.length;
  await import(caminho);
  if (manipuladores.length !== antes + 1) throw new Error('a função não registrou o Deno.serve');
  return manipuladores[antes];
}

export function pedir(
  corpo: unknown,
  opcoes: { metodo?: string; origem?: string | null; tipo?: string; token?: string } = {},
): Request {
  const cabecalhos: Record<string, string> = { 'Content-Type': opcoes.tipo ?? 'application/json' };
  if (opcoes.origem !== null) cabecalhos.Origin = opcoes.origem ?? ORIGEM;
  if (opcoes.token) cabecalhos.Authorization = 'Bearer ' + opcoes.token;
  const metodo = opcoes.metodo ?? 'POST';
  return new Request('https://funcoes.exemplo.test/', {
    method: metodo,
    headers: cabecalhos,
    body: metodo === 'POST' ? (typeof corpo === 'string' ? corpo : JSON.stringify(corpo)) : undefined,
  });
}

export function rpc(p: Pedido): string | null {
  const m = /^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(p.caminho);
  return m ? m[1] : null;
}
