import json
import re
import sys

from common import USUARIOS, OUTRO_OFICINEIRO, lista, rodar

ESCOLA_OUTRA = lista("select id from public.escolas where sigla='Ejp'")[0][0]
PADRAO = {
    "uuid": f"'{OUTRO_OFICINEIRO}'",
    "bigint": "1",
    "integer": "10",
    "smallint": ESCOLA_OUTRA + "::smallint",
    "text": "'motivo de teste suficiente'",
    "date": "'2026-11-03'",
    "jsonb": "'{}'::jsonb",
    "boolean": "true",
    "time without time zone": "'09:00'",
    "timestamp with time zone": "'2026-11-03 09:00-03'",
    "double precision": "-20.0",
    "bigint[]": "'{1}'::bigint[]",
    "date[]": "'{2026-11-10}'::date[]",
}
funcoes = lista(
    "select p.proname, pg_get_function_identity_arguments(p.oid) from pg_proc p where p.pronamespace='public'::regnamespace order by 1"
)
matriz = {}
for nome, args in funcoes:
    valores = []
    for a in [x.strip() for x in args.split(",") if x.strip()]:
        tipo = re.sub(r"^\w+\s+", "", a)
        valores.append(PADRAO.get(tipo, "null"))
    chamada = f"select public.{nome}({', '.join(valores)})"
    linha = {}
    for papel, uid in USUARIOS.items():
        out, erro = rodar(chamada, papel, uid)
        if not erro:
            linha[papel] = "OK " + out[:80].replace("\n", " ")
        else:
            m = re.search(r"ERROR:\s+(.*)", erro)
            linha[papel] = "ERRO " + (m.group(1)[:90] if m else erro[:90])
    matriz[f"{nome}({args})"] = linha
json.dump(matriz, open("rpc_matrix.json", "w"), ensure_ascii=False, indent=1)
for f, l in matriz.items():
    ok = [p for p, v in l.items() if v.startswith("OK")]
    print(f.split("(")[0], "→ aceito por:", ",".join(ok) or "ninguém")
