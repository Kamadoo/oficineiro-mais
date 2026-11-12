import json
import sys

from common import DB, USUARIOS, OUTRO_OFICINEIRO, lista, rodar

tabelas = [t[0] for t in lista("select relname from pg_class where relnamespace='public'::regnamespace and relkind='r' order by 1")]
funcoes = lista(
    "select p.proname, pg_get_function_identity_arguments(p.oid) from pg_proc p where p.pronamespace='public'::regnamespace order by 1"
)
colunas = {
    t: [c[0] for c in lista(f"select column_name from information_schema.columns where table_schema='public' and table_name='{t}'")]
    for t in tabelas
}
EXCLUSAO_DA_PROPRIA_LINHA = {("oficineiro", "grade_aulas"): "oficineiro_id"}

achados = []

for t in tabelas:
    out, erro = rodar(f"select count(*) from public.{t}", "anon")
    if not erro:
        achados.append(f"ANON lê {t}: {out} linhas")
for nome, args in funcoes:
    out, erro = rodar(f"select has_function_privilege('anon', 'public.{nome}({args})', 'execute')")
    if out == "t":
        achados.append(f"ANON executa {nome}({args})")

for papel, uid in USUARIOS.items():
    for t in tabelas:
        out, erro = rodar(f"select count(*) from public.{t}", papel, uid, aal="aal1")
        if not erro and out not in ("0", ""):
            achados.append(f"SEM MFA {papel} lê {t}: {out} linhas")

visiveis = {}
for papel, uid in USUARIOS.items():
    for t in tabelas:
        out, erro = rodar(f"select count(*) from public.{t}", papel, uid)
        visiveis[(papel, t)] = out if not erro else "negado"

for t in tabelas:
    cols = colunas[t]
    if "oficineiro_id" in cols:
        out, erro = rodar(f"select count(*) from public.{t} where oficineiro_id <> '{USUARIOS['oficineiro']}'", "oficineiro", USUARIOS["oficineiro"])
        if not erro and out not in ("0", ""):
            achados.append(f"VAZAMENTO oficineiro vê {out} linhas de outro oficineiro em {t}")
    if "escola_id" in cols:
        for papel in ("direcao", "oficineiro"):
            out, erro = rodar(
                f"select count(*) from public.{t} where escola_id is distinct from (select escola_id from public.perfis where id='{USUARIOS[papel]}')",
                papel,
                USUARIOS[papel],
            )
            if not erro and out not in ("0", "") and t not in ("escolas",):
                achados.append(f"ESCOPO {papel} vê {out} linhas de outra escola em {t}")

for papel in ("oficineiro", "direcao", "analista", "coordenador", "gerente"):
    uid = USUARIOS[papel]
    for t in tabelas:
        cols = colunas[t]
        alvo = cols[1] if len(cols) > 1 else cols[0]
        out, erro = rodar(f"with x as (update public.{t} set {alvo} = {alvo} returning 1) select count(*) from x", papel, uid)
        if not erro and out not in ("0", ""):
            achados.append(f"ESCRITA DIRETA {papel} atualiza {out} linhas de {t}")
        out, erro = rodar(f"with x as (delete from public.{t} returning 1) select count(*) from x", papel, uid)
        if not erro and out not in ("0", ""):
            dono = EXCLUSAO_DA_PROPRIA_LINHA.get((papel, t))
            if not dono:
                achados.append(f"APAGA DIRETO {papel} apaga {out} linhas de {t}")
                continue
            alheias, erro = rodar(
                f"with x as (delete from public.{t} where {dono} <> '{uid}' returning 1) select count(*) from x", papel, uid
            )
            if erro or alheias not in ("0", ""):
                achados.append(f"APAGA DIRETO {papel} apaga {alheias or '?'} linhas de outras pessoas em {t}")

for papel in ("oficineiro", "analista", "direcao", "coordenador", "gerente"):
    uid = USUARIOS[papel]
    out, erro = rodar(f"update public.perfis set papel='administrador' where id='{uid}' returning papel", papel, uid)
    if not erro and out:
        achados.append(f"ESCALADA {papel} virou administrador por UPDATE")
    out, erro = rodar(f"insert into public.perfis (id, nome, papel) values (gen_random_uuid(), 'X', 'administrador') returning id", papel, uid)
    if not erro and out:
        achados.append(f"ESCALADA {papel} criou perfil administrador")

for schema in ("privado", "auditoria", "vault", "auth", "cron"):
    for papel in ("oficineiro",):
        objs = lista(
            f"select c.relname from pg_class c where c.relnamespace='{schema}'::regnamespace and c.relkind in ('r','v')"
        )
        for (o,) in objs:
            out, erro = rodar(f"select count(*) from {schema}.{o}", papel, USUARIOS[papel])
            if not erro:
                achados.append(f"ESQUEMA {papel} lê {schema}.{o}: {out}")

json.dump({"visiveis": {f"{p}|{t}": v for (p, t), v in visiveis.items()}, "achados": achados}, open("rls_audit.json", "w"), ensure_ascii=False, indent=1)
print(len(tabelas), "tabelas,", len(funcoes), "funções;", len(achados), "achados")
for a in achados:
    print(" -", a)
sys.exit(1 if achados else 0)
