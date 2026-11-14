import json
import os
import subprocess
import sys
from pathlib import Path

DB = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PGDATABASE", "postgres")
ENV = {
    **os.environ,
    "PGHOST": os.environ.get("PGHOST", "127.0.0.1"),
    "PGPORT": os.environ.get("PGPORT", "54322"),
    "PGUSER": os.environ.get("PGUSER", "postgres"),
    "PGPASSWORD": os.environ.get("PGPASSWORD", "postgres"),
    "PGOPTIONS": " ".join(filter(None, [os.environ.get("PGOPTIONS", ""), "-c lc_messages=C"])),
}
USUARIOS = {
    "gerente": "00000000-0000-0000-0000-00000000a001",
    "coordenador": "00000000-0000-0000-0000-00000000a002",
    "administrador": "00000000-0000-0000-0000-00000000a003",
    "analista": "00000000-0000-0000-0000-00000000a004",
    "direcao": "00000000-0000-0000-0000-00000000a005",
    "oficineiro": "00000000-0000-0000-0000-00000000a006",
}
OUTRO_OFICINEIRO = "00000000-0000-0000-0000-00000000a007"


def rodar(sql, papel=None, uid=None, aal="aal2", rollback=True):
    pre = ["begin;"]
    if papel == "anon":
        pre += ["select set_config('request.jwt.claims', '{\"role\":\"anon\"}', true) \\g /dev/null", "set local role anon;"]
    elif papel:
        claims = json.dumps({"sub": uid, "role": "authenticated", "aal": aal})
        pre += [
            f"select set_config('request.jwt.claims', '{claims}', true) \\g /dev/null",
            "select set_config('t.hoje', '2026-11-09', true) \\g /dev/null",
            "set local role authenticated;",
        ]
    corpo = "\n".join(pre + [sql + ";", "rollback;" if rollback else "commit;"])
    r = subprocess.run(["psql", "-X", "-q", "-A", "-t", "-d", DB], input=corpo, capture_output=True, text=True, env=ENV)
    erro = next((linha for linha in r.stderr.splitlines() if "ERROR" in linha), "")
    return r.stdout.strip(), erro


def lista(sql):
    out, _ = rodar(sql)
    return [linha.split("|") for linha in out.splitlines() if linha]


def conferir(nome, atual):
    arquivo = Path(__file__).with_name("esperado") / f"{nome}.json"
    if os.environ.get("GRAVAR_ESPERADO") == "1":
        arquivo.parent.mkdir(exist_ok=True)
        arquivo.write_text(json.dumps(atual, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print("esperado gravado em", arquivo.name)
        return 0
    esperado = json.loads(arquivo.read_text(encoding="utf-8"))
    diferencas = []
    for chave in sorted(set(esperado) | set(atual)):
        if esperado.get(chave) != atual.get(chave):
            diferencas.append(f"{chave}: esperado {esperado.get(chave)!r}, obtido {atual.get(chave)!r}")
    print(len(diferencas), "diferenças em relação a", arquivo.name)
    for d in diferencas:
        print(" -", d)
    return 1 if diferencas else 0
