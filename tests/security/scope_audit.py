import json
import subprocess

from common import ENV, DB, USUARIOS, OUTRO_OFICINEIRO

DIR = USUARIOS["direcao"]
OF = USUARIOS["oficineiro"]


def como(papel_uid, preparo, chamada):
    claims = json.dumps({"sub": papel_uid, "role": "authenticated", "aal": "aal2"})
    corpo = "\n".join([
        "begin;",
        preparo + ";" if preparo else "",
        f"select set_config('request.jwt.claims', '{claims}', true) \\g /dev/null",
        "select set_config('t.hoje', '2026-11-09', true) \\g /dev/null",
        "set local role authenticated;",
        chamada + ";",
        "rollback;",
    ])
    r = subprocess.run(["psql", "-X", "-q", "-A", "-t", "-d", DB], input=corpo, capture_output=True, text=True, env=ENV)
    erro = next((l.split("ERROR:", 1)[1].strip() for l in r.stderr.splitlines() if "ERROR" in l), "")
    return ("ERRO " + erro) if erro else ("OK " + r.stdout.strip()[:120])


EJP = "(select id from public.escolas where sigla='Ejp')"
ECL = "(select id from public.escolas where sigla='Ecl')"
casos = {
    "direção valida grade de outra escola": (
        DIR,
        f"update public.grade_envios set status='enviada' where oficineiro_id='{OUTRO_OFICINEIRO}'",
        f"select public.validar_grade('{OUTRO_OFICINEIRO}', 2026::smallint, true, null)",
    ),
    "direção confere aula de outra escola": (
        DIR,
        f"update public.aulas_registro set oficineiro_id='{OUTRO_OFICINEIRO}', escola_id={EJP}, data='2026-01-05' where id=1",
        "select public.conferir_aula(1, true, null)",
    ),
    "direção aprova relatório de outra escola": (
        DIR,
        f"delete from public.relatorios_mensais where oficineiro_id='{OUTRO_OFICINEIRO}'; update public.relatorios_mensais set oficineiro_id='{OUTRO_OFICINEIRO}', escola_id={EJP}, status='fechado' where id=1",
        "select public.aprovar_relatorio(1)",
    ),
    "direção devolve relatório de outra escola": (
        DIR,
        f"delete from public.relatorios_mensais where oficineiro_id='{OUTRO_OFICINEIRO}'; update public.relatorios_mensais set oficineiro_id='{OUTRO_OFICINEIRO}', escola_id={EJP}, status='fechado' where id=1",
        "select public.devolver_relatorio(1, 'motivo qualquer de teste')",
    ),
    "direção lê espelho de oficineiro de outra escola": (DIR, "", f"select public.espelho_oficineiro('{OUTRO_OFICINEIRO}', '2026-11-01')"),
    "oficineiro lê espelho de outro oficineiro": (OF, "", f"select public.espelho_oficineiro('{OUTRO_OFICINEIRO}', '2026-11-01')"),
    "oficineiro revela CPF": (OF, "", "select public.revelar_cpf(1)"),
    "direção revela CPF": (DIR, "", "select public.revelar_cpf(1)"),
    "analista agenda visita fora da carteira": (
        USUARIOS["analista"],
        "",
        f"select public.agendar_minha_visita({ECL}::smallint, '2026-11-20', '09:00', 'rotina', 'acompanhamento', 'foco', null)",
    ),
    "analista lê perfis fora da carteira": (
        USUARIOS["analista"],
        "",
        f"select count(*) from public.perfis where escola_id is not null and escola_id not in (select id from public.escolas where carteira_id='CS1')",
    ),
    "oficineiro salva preferências com HTML": (OF, "", "select public.salvar_preferencias('{\"tema\":\"<img src=x onerror=alert(1)>\"}'::jsonb)"),
    "oficineiro injeta SQL no tipo de ajuste": (
        OF,
        "",
        "select public.solicitar_ajuste($$x'); drop table public.perfis; --$$, '2026-11-05', '08:00', null, null, '12:00', 'motivo de teste suficiente')",
    ),
    "oficineiro injeta SQL em registrar_atividade": (OF, "", "select public.registrar_atividade($$a' or '1'='1$$, '{}'::jsonb)"),
    "coordenador altera papel para administrador": (
        USUARIOS["coordenador"],
        "",
        f"select public.admin_alterar_papel('{OF}', 'administrador', null, null, 'motivo de teste suficiente')",
    ),
    "gerente cancela visita e consulta auditoria completa": (USUARIOS["gerente"], "", "select count(*) from public.admin_auditoria(null, null, null, null, null, 10)"),
    "oficineiro marca presença longe da escola": (OF, "", "select public.marcar_presenca('entrada', 10.0, 10.0, 5)"),
    "oficineiro marca presença com precisão falsa (0 m)": (OF, "", "select public.marcar_presenca('entrada', -20.0, -43.9, 0)"),
}
res = {k: como(*v) for k, v in casos.items()}
for k, v in res.items():
    print(f"{k}: {v}")
json.dump(res, open("scope_audit.json", "w"), ensure_ascii=False, indent=1)
