window.FSM_NOVIDADES =
  window.FSM_NOVIDADES ||
  (() => {
    const TODOS = ['administrador', 'gerente', 'coordenador', 'analista', 'direcao', 'oficineiro'];
    const ABAIXO = {
      administrador: TODOS,
      gerente: ['gerente', 'coordenador', 'analista', 'direcao', 'oficineiro'],
      coordenador: ['coordenador', 'analista', 'direcao', 'oficineiro'],
      analista: ['analista', 'oficineiro'],
      direcao: ['direcao'],
      oficineiro: ['oficineiro']
    };
    const NOMES = {
      administrador: 'Administrador',
      gerente: 'Gerente',
      coordenador: 'Coordenador',
      analista: 'Analista',
      direcao: 'Direção',
      oficineiro: 'Oficineiro'
    };
    const LISTA = [
      {
        id: 1,
        data: '2026-11-13',
        perfis: ['oficineiro'],
        texto: 'A presença pode ser marcada mesmo sem internet: ela fica guardada e é enviada quando a conexão volta.'
      },
      {
        id: 2,
        data: '2026-11-13',
        perfis: TODOS,
        texto: 'Em Configurações, o Guia rápido mostra o passo a passo das tarefas do seu perfil.'
      },
      {
        id: 3,
        data: '2026-11-13',
        perfis: ['gerente'],
        texto:
          'As agendas mostram o nome da escola e a solução de cada aula, com legenda e exportação para Excel; a agenda dos oficineiros fica na tela Oficineiros.'
      },
      {
        id: 4,
        data: '2026-11-13',
        perfis: ['coordenador'],
        texto: 'Atividades e Produtividade mostram o nome completo da escola, e não só a sigla.'
      },
      {
        id: 5,
        data: '2026-11-14',
        perfis: ['coordenador', 'direcao'],
        texto: 'As presenças marcadas sem internet aparecem identificadas, para facilitar a conferência.'
      },
      {
        id: 6,
        data: '2026-11-14',
        perfis: ['oficineiro'],
        texto: 'No Relatório, o botão Justificar leva direto à Presença do dia a justificar.'
      },
      {
        id: 7,
        data: '2026-11-14',
        perfis: ['oficineiro'],
        texto: 'Os documentos do mês trazem um código no rodapé, que permite conferir no site se são verdadeiros.'
      },
      {
        id: 8,
        data: '2026-11-16',
        perfis: TODOS,
        texto:
          'Na entrada, a opção "Esqueceu sua senha?" envia um código ao e-mail institucional para você criar uma senha nova.'
      },
      {
        id: 9,
        data: '2026-11-16',
        perfis: ['oficineiro'],
        texto:
          'Na Grade de Atividades, o campo Ano mostra todos os anos, do 1º período ao 9º ano, e as turmas de A a H.'
      },
      {
        id: 10,
        data: '2026-11-17',
        perfis: ['analista'],
        texto: 'O registro de visita aceita várias turmas de uma vez.'
      },
      {
        id: 11,
        data: '2026-11-17',
        perfis: ['analista', 'gerente'],
        texto:
          'A Jornada do Usuário foi renovada: situação de cada escola, sugestões de visita com "Aceitar e agendar" e a agenda da semana.'
      },
      {
        id: 12,
        data: '2026-11-23',
        perfis: TODOS,
        texto:
          'A entrada fica válida por até 26 horas, e a mensagem de senha fraca ficou mais clara: basta escolher outra.'
      },
      {
        id: 13,
        data: '2026-11-23',
        perfis: ['administrador'],
        texto: 'Nova aba para enviar por e-mail os convites de primeiro acesso.'
      },
      {
        id: 14,
        data: '2026-11-23',
        perfis: ['analista', 'gerente'],
        texto:
          'Jornada no mês da leitura: aulas previstas e realizadas da carteira, visita sugerida por dia e telas bem mais rápidas.'
      },
      {
        id: 15,
        data: '2026-11-24',
        perfis: ['analista', 'gerente'],
        texto:
          'Jornada: o analista aponta no detalhe da escola os usuários que precisam de tratativa, e o gerente acompanha tudo na aba Tratativas.'
      },
      {
        id: 16,
        data: '2026-11-24',
        perfis: ['analista', 'gerente'],
        texto: 'Jornada: novas abas Escolas e Mediadores, com ranking por usuários engajados.'
      },
      {
        id: 17,
        data: '2026-11-24',
        perfis: ['administrador'],
        texto:
          'Jornada: parâmetros de aulas e a carga diária da base de acessos ficam reunidos no perfil do Administrador.'
      },
      {
        id: 18,
        data: '2026-11-25',
        perfis: ['administrador'],
        texto:
          'A base de acessos aceita a planilha baixada direto do B.I., sem ajustes, e reconhece a escola pelo nome mesmo quando escrito de outro jeito.'
      },
      {
        id: 19,
        data: '2026-11-25',
        perfis: TODOS,
        texto: 'Corrigida a tela em branco que podia aparecer logo depois de uma atualização do site.'
      },
      {
        id: 20,
        data: '2026-11-25',
        perfis: ['gerente'],
        texto:
          'No onboarding, o CPF da OS é lido corretamente, inclusive quando a planilha apaga o zero do início; essas linhas não são mais recusadas.'
      },
      {
        id: 21,
        data: '2026-11-25',
        perfis: ['gerente', 'coordenador', 'administrador'],
        texto:
          'Ao criar uma conta, você escolhe se o convite de primeiro acesso já sai por e-mail; a escolha é obrigatória.'
      },
      {
        id: 27,
        data: '2026-11-27',
        perfis: ['oficineiro', 'gerente', 'coordenador', 'administrador'],
        texto:
          'Novo cargo Oficineiro, só com projeto tempo integral. O de Inclusão Digital fica com Minecraft e Outro no tempo integral e ganha Eduminers na formação de professores.'
      }
    ];

    const ultima = () => LISTA.reduce((m, n) => Math.max(m, n.id), 0);

    const dataCurta = iso => {
      const [a, m, d] = String(iso || '').split('-');
      return d && m && a ? d + '/' + m + '/' + a : '';
    };

    const paraPerfil = (papel, vista) => {
      const alcance = ABAIXO[papel];
      if (!alcance) return [];
      const desde = Number(vista) || 0;
      return LISTA.filter(n => n.id > desde && n.perfis.some(p => alcance.indexOf(p) >= 0))
        .sort((a, b) => b.id - a.id)
        .map(n => {
          const proprio = n.perfis.indexOf(papel) >= 0;
          return {
            id: n.id,
            data: dataCurta(n.data),
            texto: n.texto,
            para: proprio
              ? ''
              : n.perfis
                  .filter(p => alcance.indexOf(p) >= 0)
                  .map(p => NOMES[p])
                  .join(', ')
          };
        });
    };

    return { lista: LISTA, ultima, paraPerfil, abaixo: ABAIXO };
  })();
