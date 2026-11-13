import functools
import http.server
import pathlib
import re
import sys
import contextlib

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DIST = RAIZ / "dist"
PORTA = int(sys.argv[1]) if len(sys.argv) > 1 else 5173
CONFIG = RAIZ / "src" / "config.js"


def cabecalhos():
    regras, atual = [], None
    for linha in (DIST / "_headers").read_text(encoding="utf-8").splitlines():
        if not linha.strip():
            continue
        if not linha.startswith((" ", "\t")):
            atual = (linha.strip(), [])
            regras.append(atual)
        elif atual:
            nome, valor = linha.strip().split(":", 1)
            atual[1].append((nome.strip(), valor.strip()))
    return regras


class Servidor(http.server.SimpleHTTPRequestHandler):
    regras = []

    def end_headers(self):
        caminho = self.path.split("?", 1)[0]
        for padrao, valores in self.regras:
            if caminho.startswith(padrao[:-1]) if padrao.endswith("*") else caminho == padrao:
                for nome, valor in valores:
                    if nome != "Strict-Transport-Security":
                        self.send_header(nome, valor)
        super().end_headers()

    def list_directory(self, path):
        self.send_error(404)

    def log_message(self, fmt, *args):
        if args and str(args[1]).startswith(("4", "5")):
            sys.stderr.write("  %s\n" % (fmt % args))


if __name__ == "__main__":
    if not (DIST / "index.html").exists():
        sys.exit("dist/ não encontrado: rode python scripts/build.py")
    if not re.search(r"https://[a-z0-9-]+\.supabase\.co", CONFIG.read_text(encoding="utf-8") if CONFIG.exists() else ""):
        print("Aviso: src/config.js sem endereço do Supabase; o login não vai funcionar.")
    Servidor.regras = cabecalhos()
    servidor = http.server.ThreadingHTTPServer(("127.0.0.1", PORTA), functools.partial(Servidor, directory=str(DIST)))
    print("http://localhost:%d" % PORTA)
    with contextlib.suppress(KeyboardInterrupt):
        servidor.serve_forever()
