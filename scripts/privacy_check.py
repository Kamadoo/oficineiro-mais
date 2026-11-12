import json
import os
import pathlib
import re
import sys
import unicodedata

RAIZ = pathlib.Path(__file__).resolve().parent.parent
REFERENCIA = os.environ.get("OFICINEIRO_DADOS_REAIS")
DOMINIOS_TESTE = ("exemplo.test", "example.com", "example.org", "w3.org")

CPF = re.compile(r"(?<![\d.])(\d{3})\.?(\d{3})\.?(\d{3})-?(\d{2})(?![\d])")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)")


def cpf_valido(d):
    if len(d) != 11 or d == d[0] * 11:
        return False
    for n in (9, 10):
        s = sum(int(d[i]) * (n + 1 - i) for i in range(n))
        if (s * 10) % 11 % 10 != int(d[n]):
            return False
    return True


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def nomes_de_referencia():
    nomes = set()
    if not REFERENCIA:
        return nomes
    pasta = pathlib.Path(REFERENCIA)
    for p in list(pasta.glob("*.json")) + list(pasta.glob("*.js")):
        texto = p.read_text(encoding="utf-8", errors="ignore")
        try:
            dados = json.loads(texto[texto.index("{"):texto.rindex("}") + 1])
        except ValueError:
            continue
        pilha = [dados]
        while pilha:
            v = pilha.pop()
            if isinstance(v, dict):
                if isinstance(v.get("nome"), str):
                    nomes.add(v["nome"])
                pilha.extend(v.values())
            elif isinstance(v, list):
                if v and isinstance(v[0], str) and len(v[0].split()) >= 2:
                    nomes.add(v[0])
                pilha.extend(v)
    return {n for n in nomes if len(n.split()) >= 2}


_NOMES = None


def mascarar(s):
    s = str(s)
    return s[:2] + "***" + s[-2:] if len(s) > 6 else "***"


def verificar(texto, origem):
    global _NOMES
    if _NOMES is None:
        _NOMES = nomes_de_referencia()
    achados = []
    for m in CPF.finditer(texto):
        d = "".join(m.groups())
        if cpf_valido(d):
            achados.append("%s: CPF válido %s" % (origem, mascarar(d)))
    for m in re.finditer(r"""(?<=['"])(\d{9,10})(?=['"])""", texto):
        if cpf_valido(m.group(1).zfill(11)):
            achados.append("%s: provável CPF sem zero à esquerda %s" % (origem, mascarar(m.group(1))))
    for m in EMAIL.finditer(texto):
        dominio = m.group(1).lower()
        if re.search(r"\.(png|jpe?g|svg|webp|gif|js|css|woff2?)$", dominio) or re.fullmatch(r"\d+(\.\d+)*x?", dominio):
            continue
        if not dominio.endswith(DOMINIOS_TESTE):
            achados.append("%s: e-mail fora dos domínios de teste %s" % (origem, mascarar(m.group(0))))
    if _NOMES:
        base = sem_acento(texto).lower()
        for n in _NOMES:
            k = sem_acento(n).lower()
            i = base.find(k)
            while i >= 0:
                antes = base[i - 1] if i else " "
                depois = base[i + len(k)] if i + len(k) < len(base) else " "
                if not (antes.isalnum() or depois.isalnum()):
                    achados.append("%s: nome da base de referência %s" % (origem, mascarar(n)))
                    break
                i = base.find(k, i + 1)
    return achados


def exigir_limpo(textos):
    achados = [a for origem, t in textos for a in verificar(t, origem)]
    if achados:
        print("\nDados pessoais encontrados; build interrompido:")
        for a in achados[:30]:
            print("   -", a)
        if len(achados) > 30:
            print("   ... e mais", len(achados) - 30)
        raise SystemExit(2)
    print("verificação de dados pessoais: ok (%d arquivos%s)" % (len(textos), ", %d nomes de referência" % len(_NOMES) if _NOMES else ""))


if __name__ == "__main__":
    arquivos = [p for p in (RAIZ / "src").rglob("*") if p.suffix in (".html", ".js", ".css") and p.name != "config.js"]
    exigir_limpo([(p.relative_to(RAIZ).as_posix(), p.read_text(encoding="utf-8", errors="ignore")) for p in arquivos])
    sys.exit(0)
