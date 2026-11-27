window.FSM_PRESENCA_AJUDA =
  window.FSM_PRESENCA_AJUDA ||
  (() => {
    const NOMES = {
      windows: 'computador com Windows',
      android: 'celular Android',
      iphone: 'iPhone',
      computador: 'computador'
    };

    const aparelho = navegador => {
      const nav = navegador || {},
        agente = String(nav.userAgent || ''),
        plataforma = String((nav.userAgentData && nav.userAgentData.platform) || nav.platform || '');
      if (/iPhone|iPad|iPod/i.test(agente) || (/Mac/i.test(plataforma + agente) && nav.maxTouchPoints > 1))
        return 'iphone';
      if (/Android/i.test(agente + plataforma)) return 'android';
      if (/Win/i.test(plataforma + agente)) return 'windows';
      return 'computador';
    };

    const temGps = tipo => tipo === 'android' || tipo === 'iphone';

    const PERMISSAO_DO_SITE =
      'No navegador, toque no cadeado ao lado do endereço do site e deixe "Localização" como "Permitir".';
    const ATUALIZAR = 'Toque em "Atualizar local" e aguarde até 30 segundos.';

    const PASSOS = {
      bloqueada: {
        windows: [
          'Abra o menu Iniciar e entre em Configurações > Privacidade e segurança > Localização.',
          'Ligue as três chaves da tela, inclusive a última: "Permitir que os aplicativos da área de trabalho acessem sua localização".',
          PERMISSAO_DO_SITE,
          'Aperte a tecla F5 para recarregar a página.',
          ATUALIZAR
        ],
        android: [
          'Puxe a barra do alto da tela para baixo e ligue "Localização".',
          PERMISSAO_DO_SITE,
          'Recarregue a página.',
          ATUALIZAR
        ],
        iphone: [
          'Abra Ajustes > Privacidade e Segurança > Serviços de Localização e ligue a chave.',
          'Na mesma tela, toque no navegador (Safari ou Chrome), escolha "Durante o Uso" e ligue "Localização Exata".',
          'Volte ao site e recarregue a página.',
          ATUALIZAR
        ],
        computador: [
          'Ligue a localização nas configurações do computador.',
          PERMISSAO_DO_SITE,
          'Recarregue a página.',
          ATUALIZAR
        ]
      },
      aproximada: {
        windows: [
          'Abra o menu Iniciar e entre em Configurações > Privacidade e segurança > Localização.',
          'Ligue as três chaves, inclusive "Permitir que os aplicativos da área de trabalho acessem sua localização".',
          'Ligue o Wi-Fi do computador, mesmo usando cabo de rede: o Windows usa as redes próximas para achar o local.',
          PERMISSAO_DO_SITE,
          'Aperte a tecla F5 para recarregar a página.',
          ATUALIZAR,
          'Se a precisão continuar alta, use o celular.'
        ],
        android: [
          'Puxe a barra do alto da tela para baixo e ligue "Localização".',
          'Em Configurações > Localização, ligue "Precisão da localização do Google".',
          'Nas permissões do site no navegador, escolha a localização "Precisa".',
          'Vá para perto de uma janela ou para uma área aberta.',
          ATUALIZAR
        ],
        iphone: [
          'Abra Ajustes > Privacidade e Segurança > Serviços de Localização.',
          'Toque no navegador (Safari ou Chrome) e ligue "Localização Exata".',
          'Vá para perto de uma janela ou para uma área aberta.',
          ATUALIZAR
        ],
        computador: [
          'Ligue a localização e o Wi-Fi do computador.',
          PERMISSAO_DO_SITE,
          'Recarregue a página.',
          ATUALIZAR,
          'Se a precisão continuar alta, use o celular.'
        ]
      },
      fora: [
        'Confira se a escola escolhida é a da visita.',
        'Aproxime-se do prédio: o círculo tracejado no mapa mostra a área aceita.',
        ATUALIZAR,
        'Se você já está na escola e o mapa mostra outro lugar, avise o coordenador: o endereço da escola pode estar errado no cadastro.'
      ]
    };

    const TITULOS = {
      bloqueada: 'A localização está desligada',
      aproximada: 'A localização está aproximada',
      fora: 'Você está fora da área da escola'
    };

    const passos = (tipo, situacao) => {
      const grupo = PASSOS[situacao];
      if (!grupo) return [];
      return (Array.isArray(grupo) ? grupo : grupo[tipo] || grupo.computador).slice();
    };

    return {
      aparelho,
      temGps,
      passos,
      nome: tipo => NOMES[tipo] || NOMES.computador,
      titulo: situacao => TITULOS[situacao] || ''
    };
  })();
