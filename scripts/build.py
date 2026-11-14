import base64
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil

from privacy_check import exigir_limpo

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SRC = RAIZ / "src"
PUBLIC = RAIZ / "public"
DIST = RAIZ / "dist"
ASSETS = DIST / "a"
ENTRADA = SRC / "index.dc.html"
RUNTIME = "../vendor/dc-runtime/dc-runtime.js"
PAGINAS_PUBLICAS = ("ajuda.html", "privacidade.html")
MARCA_PRIVADA = pathlib.Path(os.environ["OFICINEIRO_MARCA"]) if os.environ.get("OFICINEIRO_MARCA") else None

VENDOR_SHA256 = {
    "vendor/dc-runtime/dc-runtime.js": "3c7416fc787b8e244cbb8b5b9ec1d347237061ad13558875f5ab3a42622421ae",
    "vendor/leaflet/leaflet-1.9.4.js": "85d455b4522415f6badc42a0e7d17c919d100347d6b8958bd0dc738fdecd6d50",
    "vendor/leaflet/leaflet-1.9.4.css": "a7837102824184820dfa198d1ebcd109ff6d0ff9a2672a074b9a1b4d147d04c6",
    "vendor/react/react-18.3.1.production.min.js": "d949f1c3687aedadcedac85261865f29b17cd273997e7f6b2bfc53b2f9d4c4dd",
    "vendor/react/react-dom-18.3.1.production.min.js": "35f4f974f4b2bcd44da73963347f8952e341f83909e4498227d4e26b98f66f0d",
    "vendor/fonts/inter/inter.css": "d9a04c401dd8048a1398665a1039833c3f5027572503e7e55e8dc13d957a2e17",
}
REACT_SRI = {
    "vendor/react/react-18.3.1.production.min.js": "sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z",
    "vendor/react/react-dom-18.3.1.production.min.js": "sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1",
}
FONTE_INTER = re.compile(r'url\("\./(inter-[0-9a-f]{12}\.woff2?)"\)')
FONTES_GOOGLE = re.compile(r'<link href="https://fonts\.googleapis\.com/css2[^"]*" rel="stylesheet">')
PRECONEXAO = re.compile(r'<link rel="preconnect" href="https://fonts\.googleapis\.com">\n?')
REFERENCIA = re.compile(r'(src|href|srcset)="(\.{1,2}/[^"]+)"')
REFERENCIA_JS = re.compile(r"""(['"])(\.\./vendor/[^'"]+)\1""")

try:
    import zoneinfo

    GERADO = datetime.datetime.now(zoneinfo.ZoneInfo("America/Sao_Paulo")).strftime("%d/%m/%Y %H:%M")
except Exception:
    GERADO = datetime.datetime.now().strftime("%d/%m/%Y %H:%M")
VERSAO = json.loads((RAIZ / "package.json").read_text(encoding="utf-8"))["version"]


def caminho(ref):
    p = (SRC / ref).resolve()
    if RAIZ not in p.parents:
        raise SystemExit("referência fora do projeto: " + ref)
    return p


def rel(p):
    return p.relative_to(RAIZ).as_posix()


def ler_conferido(p):
    dados = p.read_bytes()
    chave = rel(p)
    if chave.startswith("vendor/") and chave in VENDOR_SHA256 and hashlib.sha256(dados).hexdigest() != VENDOR_SHA256[chave]:
        raise SystemExit(chave + ": arquivo de terceiros alterado")
    if chave == "src/lib/sobre.js":
        dados = dados.replace(b"__FSM_GERADO__", GERADO.encode("ascii")).replace(b"__FSM_VERSAO__", VERSAO.encode("ascii"))
    return dados


class Publicador:
    def __init__(self):
        self.publicados = {}
        self.textos = []

    def gravar(self, nome, dados):
        partes = nome.rsplit(".", 2) if nome.endswith(".dc.html") else nome.rsplit(".", 1)
        final = "%s.%s.%s" % (partes[0], hashlib.sha256(dados).hexdigest()[:12], ".".join(partes[1:]))
        (ASSETS / final).write_bytes(dados)
        if not final.endswith((".woff", ".woff2", ".png", ".webp")):
            self.textos.append(("dist/a/" + final, dados.decode("utf-8")))
        return "./a/" + final

    def arquivo(self, p):
        chave = rel(p)
        if chave not in self.publicados:
            privada = MARCA_PRIVADA / p.name if MARCA_PRIVADA and p.parent == PUBLIC / "brand" else None
            dados = privada.read_bytes() if privada and privada.exists() else ler_conferido(p)
            self.publicados[chave] = self.gravar(p.name, dados)
        return self.publicados[chave]

    def preparar(self, texto, css_fontes):
        texto = PRECONEXAO.sub("", texto)
        texto = FONTES_GOOGLE.sub(lambda _: '<link href="%s" rel="stylesheet">' % css_fontes, texto)

        def troca(m):
            if m.group(2).startswith("./a/"):
                return m.group(0)
            return '%s="%s"' % (m.group(1), self.arquivo(caminho(m.group(2))))

        texto = REFERENCIA.sub(troca, texto)
        texto = REFERENCIA_JS.sub(lambda m: m.group(1) + self.arquivo(caminho(m.group(2))) + m.group(1), texto)
        restos = [x for x in ("fonts.googleapis.com", "unpkg.com", "../vendor/", "../public/", "./lib/", "./styles/") if x in texto]
        if restos:
            raise SystemExit("referência não publicada: " + ", ".join(restos))
        return texto


def json_seguro(v):
    return json.dumps(v, ensure_ascii=False).replace("</", "<\\u002F")


def icones():
    favicon = re.sub(r"<metadata>.*?</metadata>", "", (PUBLIC / "brand" / "favicon.svg").read_text(encoding="utf-8"), flags=re.S)
    png32 = (PUBLIC / "brand" / "png" / "favicon-32.png").read_bytes()
    return "\n".join(
        [
            '<meta name="theme-color" content="#13252C">',
            '<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,%s">' % base64.b64encode(favicon.encode("utf-8")).decode("ascii"),
            '<link rel="icon" type="image/png" sizes="32x32" href="data:image/png;base64,%s">' % base64.b64encode(png32).decode("ascii"),
            '<link rel="apple-touch-icon" href="brand/png/favicon-180.png">',
            '<link rel="manifest" href="manifest.webmanifest">',
        ]
    )


def construir():
    if DIST.exists():
        shutil.rmtree(DIST)
    ASSETS.mkdir(parents=True)
    pub = Publicador()

    fontes = SRC.parent / "vendor" / "fonts" / "inter"
    css_inter = ler_conferido(fontes / "inter.css").decode("utf-8")
    for nome in sorted(set(FONTE_INTER.findall(css_inter))):
        dados = (fontes / nome).read_bytes()
        if not nome.startswith("inter-" + hashlib.sha256(dados).hexdigest()[:12]):
            raise SystemExit("fonte alterada: " + nome)
        (ASSETS / nome).write_bytes(dados)
    css_fontes = pub.gravar("inter.css", css_inter.encode("utf-8"))

    recursos = {}
    for arq in sorted((SRC / "components").glob("*.dc.html")):
        texto = pub.preparar(arq.read_text(encoding="utf-8"), css_fontes)
        recursos["./components/" + arq.name] = pub.gravar(arq.name, texto.encode("utf-8"))

    react = pub.arquivo(RAIZ / "vendor" / "react" / "react-18.3.1.production.min.js")
    react_dom = pub.arquivo(RAIZ / "vendor" / "react" / "react-dom-18.3.1.production.min.js")
    runtime = pub.arquivo(RAIZ / "vendor" / "dc-runtime" / "dc-runtime.js")

    pagina = ENTRADA.read_text(encoding="utf-8")
    if pagina.count('<script src="%s"></script>' % RUNTIME) != 1:
        raise SystemExit('index.dc.html: esperava um único <script src="%s">' % RUNTIME)
    script_recursos = "window.__resources = %s;" % json_seguro(recursos)
    hash_recursos = base64.b64encode(hashlib.sha256(script_recursos.encode("utf-8")).digest()).decode("ascii")
    cabeca = "\n".join(
        [
            "<script>%s</script>" % script_recursos,
            '<script src="%s" integrity="%s"></script>' % (react, REACT_SRI["vendor/react/react-18.3.1.production.min.js"]),
            '<script src="%s" integrity="%s"></script>' % (react_dom, REACT_SRI["vendor/react/react-dom-18.3.1.production.min.js"]),
            '<script src="%s"></script>' % runtime,
        ]
    )
    pagina = pagina.replace('<script src="%s"></script>' % RUNTIME, cabeca, 1)
    pagina = pub.preparar(pagina, css_fontes)
    if 'rel="manifest"' not in pagina:
        pagina = pagina.replace(
            '<meta name="robots" content="noindex, nofollow">', '<meta name="robots" content="noindex, nofollow">\n' + icones(), 1
        )
    pub.textos.append(("dist/index.html", pagina))
    exigir_limpo(pub.textos)
    (DIST / "index.html").write_text(pagina, encoding="utf-8", newline="\n")

    (DIST / "brand" / "png").mkdir(parents=True)
    for nome in ("favicon.svg", "png/favicon-32.png", "png/favicon-180.png", "png/favicon-192.png", "png/favicon-512.png"):
        shutil.copy2(PUBLIC / "brand" / nome, DIST / "brand" / nome)
    shutil.copy2(PUBLIC / "manifest.webmanifest", DIST / "manifest.webmanifest")
    for nome in PAGINAS_PUBLICAS:
        texto = (PUBLIC / nome).read_text(encoding="utf-8")
        exigir_limpo([("dist/" + nome, texto)])
        (DIST / nome).write_text(texto, encoding="utf-8", newline="\n")
    (DIST / "robots.txt").write_text("User-agent: *\nDisallow: /\n", encoding="utf-8", newline="\n")
    escrever_cabecalhos(hash_recursos)
    print("dist/ gerado: %d componentes, %d arquivos publicados" % (len(recursos), len(list(ASSETS.iterdir()))))


def escrever_cabecalhos(hash_recursos):
    config = SRC / "config.js"
    m = re.search(r"https://[a-z0-9-]+\.supabase\.co", config.read_text(encoding="utf-8") if config.exists() else "")
    csp = "; ".join(
        [
            "default-src 'self'",
            "script-src 'self' 'unsafe-eval' 'sha256-%s'" % hash_recursos,
            "style-src 'self' 'unsafe-inline'",
            "font-src 'self'",
            "img-src 'self' data: blob: https://server.arcgisonline.com",
            ("connect-src 'self' data: blob: " + (m.group(0) if m else "")).strip(),
            "worker-src 'self' blob:",
            "frame-src 'self' data: blob:",
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'none'",
            "frame-ancestors 'none'",
        ]
    )
    (DIST / "_headers").write_text(
        "\n".join(
            [
                "/*",
                "  Content-Security-Policy: " + csp,
                "  Strict-Transport-Security: max-age=31536000",
                "  Cross-Origin-Opener-Policy: same-origin",
                "  X-Content-Type-Options: nosniff",
                "  X-Frame-Options: DENY",
                "  Referrer-Policy: no-referrer",
                "  Permissions-Policy: geolocation=(self), camera=(), microphone=()",
                "  X-Robots-Tag: noindex, nofollow",
                "",
                "/",
                "  Cache-Control: no-cache",
                "",
                "/index.html",
                "  Cache-Control: no-cache",
                "",
                "/a/*",
                "  Cache-Control: public, max-age=31536000, immutable",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


if __name__ == "__main__":
    construir()
