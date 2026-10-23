# Moo-IO Android — cliente e servidor local integrados

O aplicativo utiliza **LÖVE 11.5a** para o jogo em Lua e **Node.js Mobile 18.20.4** para hospedar o mesmo motor de partidas do Windows. O Android não precisa de outro jogador, PC ou VPS para criar uma sala. A hospedagem inicia em um serviço Android separado do processo gráfico e mantém seus dados no armazenamento privado.

## Instalação sem conflito com APKs antigos

A instalação anterior falhava possivelmente por **assinaturas Android incompatíveis**.
Foi verificado que os APKs antigos têm certificados de depuração diferentes,
mesmo usando o mesmo ID `io.srtristesad.mooio`. O Android proíbe atualizações
que alteram a assinatura do pacote instalado
(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

**Correção desta build:** o instalador Beta usa o identificador
`io.srtristesad.mooio.beta`, título **Moo IO Beta** e pasta de servidor
privada própria. Assim, ele pode ser instalado **ao lado do aplicativo antigo,
sem desinstalar nem apagar os dados dele**.

Para atualizar a **mesma Beta** repetidamente sem conflito de certificados,
configure no GitHub Actions uma assinatura estável com os segredos
`MOOIO_BETA_KEYSTORE_B64`, `MOOIO_BETA_STORE_PASS`,
`MOOIO_BETA_KEY_ALIAS`, `MOOIO_BETA_KEY_PASS`.
Sem esses segredos, a compilação é assinada com uma chave Android Debug
temporária nova a cada runner; uma Beta futura poderá exigir uma desinstalação
ou outra assinatura estável. Nunca use certificado temporário para versões
de produção. O CI verifica com `apksigner` e `aapt` se o APK está assinado
e contém o identificador correto.

**Compatibilidade:** o servidor Node integrado está empacotado somente para
`arm64-v8a` e `x86_64`. Um aparelho Android que rode apenas código de
32 bits não é suportado por esta Beta. Se ela continuar falhando numa instalação
limpa, obtenha a mensagem do instalador ou o resultado de `adb install` para
distinguir arquitetura, versão Android e falta de espaço.

## HUD de sobrevivência — joysticks flutuantes

O antigo arranjo MOBA foi substituído por controles próprios para o survival. Dois joysticks flutuantes surgem exatamente onde os polegares encostam, sem bases fixas desenhadas quando não estão em uso. O toque à esquerda inicia movimento; o toque à direita inicia ataque e mira no mesmo dedo. A barra inferior é **uma única linha de atalhos progressivos**, inicialmente curta: novas opções são acrescentadas apenas após escolhas de evolução confirmadas pelo servidor. Ela se recentraliza enquanto couber na tela. Quando ficar comprida, o jogador desliza a própria linha na horizontal; **não existem páginas de inventário nem botões artificiais de habilidades**.

Os botões maiores de LOJA, CLÃ e TRIBO abrem, respectivamente, os sistemas existentes de compra/equipamentos, clãs permanentes e alianças temporárias da partida. Clãs de conta e Tribes são mecanismos diferentes. Os botões Loja, Clã, Tribo, Chat, TOP e Menu estão na faixa superior. As ofertas de evolução aparecem abaixo desses atalhos, mesmo com a escala máxima do HUD.

- **AUTO**: envia o mesmo comando de coleta/ataque automático do Windows.
- **Ping (!) ao lado do minimapa**: envia `S(1)`, igual à tecla **R** no Windows, para sinalizar a posição atual aos aliados.
- **MAP**: abre o mapa completo; toque num ponto para enviar `U(x,y)` aos aliados. O servidor valida coordenadas e cooldown.
- **TOP10**: abre um ranking com abas **OURO, VIDA, COMIDA, MADEIRA, PEDRA, ABATES e PONTOS**. As classificações vêm exclusivamente do servidor (pacote de pedido `Y`, resposta `n`), até dez jogadores por categoria e ocultação de identidades anônimas.
- A coluna esquerda usa apenas os **ícones originais de food, wood e stone** e suas quantidades recebidas do servidor, sem inventar nomes de recursos; os botões **PING** e **MAPA** continuam visíveis ao lado do minimapa.
- **Vida** aparece em barra vermelha acima da linha de atalhos; **nível e XP** ficam ao lado da vida, com valores autoritativos.
- **AUTO** continua ativo ao abrir Loja, Clã, Tribo, Chat, TOP, mapa e configurações. Ataque manual não altera o toggle automático. Só AUTO ou a tecla E enviam o toggle `K(1)`.

O APK Beta com servidor integrado precisa ser gerado pela Action **Moo IO Android autonomo - APK com servidor**. O workflow recompila o servidor Node a partir dos módulos atuais antes de incorporá-lo ao APK; evita Top 10 antigo/ausente em salas hospedadas no próprio Android.

## Vida útil do servidor e uso de memória

- **Ao abrir o Moo IO Beta ou navegar pelos menus:** o servidor Node.js **não** é iniciado; nenhuma notificação persistente de hospedagem deve aparecer.
- **Criar minha sala:** o cliente solicita ao Android que ligue o serviço Node.js isolado. Somente depois que a API do servidor responder e o código de sala estiver pronto a interface declara a sala aberta.
- **Sair/encerrar sala:** o cliente desliga o serviço nativo, remove a notificação e encerra o processo `:mooio_node` para liberar a RAM. Convidados conectados à sala são desconectados.
- **Fechar a janela ou remover o aplicativo dos recentes:** o serviço de hospedagem é encerrado com o aplicativo, mesmo se uma sala estava ativa.
- **Deixar o aplicativo em segundo plano com sala explicitamente aberta:** a sala pode continuar hospedada e a notificação informa isso. Para liberar a memória, encerre a sala ou feche o aplicativo.
- **Criar nova sala após encerrar:** um novo processo Node é criado do zero. Não se tenta reiniciar `node::Start` dentro do processo nativo anterior.

O controle de ligar/desligar está restrito a `127.0.0.1:8082` com um token aleatório guardado no armazenamento privado do aplicativo. Ele não é uma API pública de rede. A hospedagem e o jogo continuam nos protocolos originais do Moo-IO.

## Modo solo e multiplayer

1. Instale o `Moo-IO-Android-Beta-Instalavel.apk` gerado pela action **Moo IO Android autonomo - APK com servidor**.
2. Abra o aplicativo, escolha **Jogar**, selecione opcionalmente **0 a 8 bots** e pressione **Criar minha sala**. A interface só confirma a sala após resposta real do Node.
3. Clique **Jogar agora**. Sem Wi-Fi, o servidor usa `127.0.0.1`; a partida solo não exige internet.
4. Para receber amigos, conecte o telefone a uma rede Wi-Fi/hotspot privado e compartilhe o IP:8080 e o código da sala. Os convidados Windows ou Android escolhem **Entrar em outra sala** e digitam essas informações.
5. Se mudar de rede, feche e abra novamente o aplicativo para atualizar o endereço do servidor. O serviço permanece ativo apenas enquanto a sala estiver explicitamente hospedada; sair da sala o encerra.

**O Node é o responsável real pela simulação, jogadores, dano, recursos, animais, estruturas e validações.** O celular não inventa entidades.

## Controles touchscreen — revisão de estabilidade

| Controle | Função |
|---|---|
| Parte inferior esquerda (livre) | o joystick de movimento surge onde o dedo toca; arraste para mover |
| Parte inferior direita (livre) | o joystick de ataque e mira surge onde o dedo toca; segurar ataca, arrastar mira e soltar interrompe |
| Linha de atalhos inferior | cresce com armas, ferramentas, estruturas e consumíveis desbloqueados durante a evolução real do MooMoo.io |
| Deslizar horizontalmente na linha | revela opções fora da área visível, sem trocar de página nem equipar durante o gesto |
| Toque simples em um atalho | seleciona a opção correspondente após soltar o dedo; o servidor valida o equipamento |
| LOJA | abre o Shop real do servidor, com compras e equipamentos |
| CLÃ | abre a interface de clãs permanentes da conta |
| TRIBO | abre as alianças temporárias da partida |
| AUTO | alterna o comando original da tecla **E** do PC |
| CHAT | abre entrada de texto Android, teclado, ENVIAR e X para fechar |
| ! | ping rápido da posição, como R no PC |
| MAP ou minimapa | mapa ampliado para marcar posição aos aliados |
| TOP10 | tabela por recurso, pontuação, vida e abates |
| II | menu de pausa |

Os botões fictícios **Correr, Bolsa, Coleta, Construir e Trocar** foram removidos. A seleção de armas e estruturas fica na linha contínua de atalhos, sem inventário paginado ou menus artificiais. O jogo não ganha habilidades inexistentes: os desbloqueios são os permitidos pelo servidor do MooMoo.io.

### Ajustes de estabilidade

- Layout dos controles calculado pela resolução e pelos ajustes individuais, reutilizado durante desenho e movimento.
- Toques independentes por identificador, com origem flutuante para cada polegar. Um dedo não assume o controle do outro; manter o ataque enquanto desliza controla a mira, e soltá-lo termina o ataque.
- Renderização de estruturas otimizada com classificação por camadas reaproveitável, preservando a ordem original.
- Prévia de fundo do menu Android desenhada em resolução reduzida e atualizada com menor frequência.
- Intervalos de animação visual limitados após engasgos, sem alterar o tempo de rede do servidor.
- Tecla Voltar fecha o chat antes de abrir o menu de pausa.

**Ainda são necessários testes físicos de fluidez em aparelhos Android de diferentes capacidades.**

A marcação por coordenada utiliza o pacote `U`, com validação de limites e cooldown no servidor. Versões Android e Windows devem utilizar protocolo compatível.

## Ajustar tamanho e comportamento dos botões

Em **Configurações**, altere o tamanho geral e a opacidade do HUD. Toque em **Ajustar joysticks** para mudar individualmente o tamanho do movimento, o tamanho do ataque+mira e a zona morta. Em **Pausa → Configurações** também é possível alterar tamanho geral e opacidade. Todas as escolhas são salvas no armazenamento privado do app e restauradas ao abri-lo novamente.

## Bots reais no Android

A criação de sala passa a quantidade de bots selecionada (0–8) para o processo Node por meio de um endpoint privado de loopback protegido por token. O servidor recebe essa quantidade na variável de ambiente MOO_IO_BOT_COUNT, informa a quantidade efetiva no endpoint de status e o cliente recusa marcar a sala como pronta se houver divergência. Para trocar a quantidade, encerre a sala e crie outra. O cliente não inventa personagens.

## Correções da auditoria pós-PR #8

- O servidor Node embutido é atualizado por **SHA-256 do ZIP** e não mais apenas pelo versionCode do aplicativo, impedindo uso silencioso de JavaScript antigo após atualização da mesma Beta.
- A confirmação de sala pronta exige que o status do processo Node informe também a quantidade real de bots. A resposta sem esse campo não autoriza a interface a dizer que a sala está pronta.
- Se a solicitação de encerramento nativo falhar, o cliente mostra erro e não declara que a RAM foi liberada. Essa confirmação indica o aceite do controle nativo; a verificação de morte do processo continua coberta pelo teste de emulador.
- Testes de regressão acrescentados para encerramento não confirmado e resposta incompleta do servidor.

## Build e testes

- [APK autônomo](../.github/workflows/android-host-apk.yml): LÖVE + Node.js Mobile, bibliotecas nativas ARM64/x86_64 e servidor completo no APK.
- [Emulador do APK atual](../.github/workflows/android-host-apk.yml): instala o artefato do mesmo commit, testa 0 e 5 bots e confirma a parada do processo Node.
- [Testes de hospedagem Lua](../.github/workflows/android-host-tests.yml): não confirma a sala antes da resposta efetiva do Node, simula falhas e timeout.
- [Crossplay Lua/Node](../.github/workflows/game-e2e.yml): confirma conexão e jogo com o mesmo protocolo autoritativo.
- [Windows](../.github/workflows/package-windows.yml): ZIP com servidor Node Windows pronto.

A build Android faz um ajuste específico de compatibilidade nas expressões regulares de nomes de parâmetros de rota do Express 5, já que Node.js Mobile foi compilado sem os dados Unicode necessários. **Essa alteração não modifica o servidor Windows.**

### Validação conhecida e limitações

O APK com servidor integrado **compila** nas Actions. A validação de ciclo de vida no emulador ainda apresentou falhas em algumas execuções: iniciar o app não deve iniciar Node automaticamente, e o teste também precisa confirmar a porta do servidor e o encerramento do processo. Não considere o teste de emulador aprovado para uma nova build sem verificar a execução específica. O pacote offline de servidor também passou em testes HTTP no Linux. **Ainda não foram comprovadas a entrada no mundo, combate e estabilidade em celulares físicos**; trate-o como beta e reporte erros do aparelho.

Somente durante a hospedagem o serviço de Node opera em primeiro plano com uma notificação; ao encerrar a sala ou fechar o app, essa notificação é removida e o processo isolado é finalizado. Em caso de falha, `files/mooio-data/node-boot.log` (armazenamento privado) registra diagnósticos do Node. A versão antiga `Moo-IO-Android-Teste.apk` e o arquivo `.love` não incluem o servidor.

Use apenas LAN, hotspot ou VPN privada confiável, sem encaminhar a porta diretamente para a internet.