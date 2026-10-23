# Moo-IO Android — cliente e servidor local integrados

O aplicativo utiliza **LÖVE 11.5a** para o jogo em Lua e **Node.js Mobile 18.20.4** para hospedar o mesmo motor de partidas do Windows. O Android não precisa de outro jogador, PC ou VPS para criar uma sala. A hospedagem inicia em um serviço Android separado do processo gráfico e mantém seus dados no armazenamento privado.

## HUD tático mobile — quatro atalhos e rankings

O layout Android é original, inspirado na organização funcional de MOBAs mobile: joystick esquerdo, mira independente na direita, **quatro botões de atalhos circulares** exibindo as quatro primeiras armas/estruturas realmente desbloqueadas, e **ataque manual grande**. Esses atalhos selecionam equipamentos existentes validados pelo Node (teclas 1–4); **ainda não existem quatro novos poderes/feitiços** com tempo de recarga. Eles poderão receber habilidades quando o sistema de habilidades for definido.

- **AUTO** na região do botão Flash de um MOBA: envia o mesmo comando `K(1)` da tecla **E** do Windows, alternando a coleta/ataque automático no servidor. Não simula um mouse continuamente pressionado.
- **Ping (!) ao lado do minimapa**: envia `S(1)`, igual à tecla **R** no Windows, para sinalizar a posição atual aos aliados.
- **MAP**: abre o mapa completo; toque num ponto para enviar `U(x,y)` aos aliados. O servidor valida coordenadas e cooldown.
- **TOP10**: abre um ranking com abas **OURO, VIDA, COMIDA, MADEIRA, PEDRA, ABATES e PONTOS**. As classificações vêm exclusivamente do servidor (pacote de pedido `Y`, resposta `n`), até dez jogadores por categoria e ocultação de identidades anônimas.
- A área sob o minimapa mostra **vida, ouro, comida, madeira, pedra e abates** obtidos das mensagens reais do jogo.

O APK com servidor integrado precisa ser gerado pela Action **Moo IO Android autonomo - APK com servidor**. O workflow recompila o servidor Node a partir dos módulos atuais antes de incorporá-lo ao APK; evita Top 10 antigo/ausente em salas hospedadas no próprio Android.

## Modo solo e multiplayer

1. Instale o `Moo-IO-Android-Servidor-Integrado.apk` gerado pela action **Moo IO Android autonomo - APK com servidor**.
2. Abra o aplicativo, escolha **Jogar → Criar minha sala**. A interface só apresenta a sala como pronta após receber resposta real do servidor Node.
3. Clique **Jogar agora**. Sem Wi-Fi, o servidor usa `127.0.0.1`; a partida solo não exige internet.
4. Para receber amigos, conecte o telefone a uma rede Wi-Fi/hotspot privado e compartilhe o IP:8080 e o código da sala. Os convidados Windows ou Android escolhem **Entrar em outra sala** e digitam essas informações.
5. Se mudar de rede, feche e abra novamente o aplicativo para atualizar o endereço do servidor. O serviço pode permanecer ativo enquanto o aplicativo está aberto.

**O Node é o responsável real pela simulação, jogadores, dano, recursos, animais, estruturas e validações.** O celular não inventa entidades.

## Controles touchscreen — revisão de estabilidade

| Controle | Função |
|---|---|
| Região inferior esquerda / joystick | movimento 360°; um dedo capturado nunca vira ataque |
| Região direita, deslizar | mira independente; não envia comandos de movimento |
| ATACAR | pressionar para atacar, soltar para parar; nunca controla o personagem |
| Quatro botões à direita | seleção dos quatro primeiros itens/armas realmente disponíveis |
| Faixa central inferior | itens a partir do quinto, em páginas de até cinco com setas |
| AUTO | alterna o comando original da tecla **E** do PC |
| CHAT | abre entrada de texto Android, teclado, ENVIAR e X para fechar |
| ! | ping rápido da posição, como R no PC |
| MAP ou minimapa | mapa ampliado para marcar posição aos aliados |
| TOP10 | tabela por recurso, pontuação, vida e abates |
| II | menu de pausa |

Os botões fictícios **Correr, Bolsa, Coleta, Construir e Trocar** foram removidos. A seleção de armas e estruturas fica no inventário horizontal real, sem menus artificiais. Os quatro primeiros ainda são atalhos de itens; habilidades especiais novas não estão implementadas.

### Ajustes de estabilidade

- Layout dos controles calculado uma vez por resolução e reutilizado durante desenho/movimento.
- Toques independentes por identificador: polegar esquerdo fica em movimento e direito em ataque/mira, mesmo se cruzarem a tela.
- Renderização de estruturas otimizada com classificação por camadas reaproveitável, preservando a ordem original.
- Prévia de fundo do menu Android desenhada em resolução reduzida e atualizada com menor frequência.
- Intervalos de animação visual limitados após engasgos, sem alterar o tempo de rede do servidor.
- Tecla Voltar fecha o chat antes de abrir o menu de pausa.

**Ainda são necessários testes físicos de fluidez em aparelhos Android de diferentes capacidades.**

A marcação por coordenada utiliza o pacote `U`, com validação de limites e cooldown no servidor. Versões Android e Windows devem utilizar protocolo compatível.

## Build e testes

- [APK autônomo](../.github/workflows/android-host-apk.yml): LÖVE + Node.js Mobile, bibliotecas nativas ARM64/x86_64 e servidor completo no APK.
- [Emulador Android](../.github/workflows/android-host-emulator.yml): primeiro testa Node mínimo e depois o servidor Moo-IO real; verifica resposta do controlador e presença dos dois processos Android.
- [Testes de hospedagem Lua](../.github/workflows/android-host-tests.yml): não confirma a sala antes da resposta efetiva do Node, simula falhas e timeout.
- [Crossplay Lua/Node](../.github/workflows/game-e2e.yml): confirma conexão e jogo com o mesmo protocolo autoritativo.
- [Windows](../.github/workflows/package-windows.yml): ZIP com servidor Node Windows pronto.

A build Android faz um ajuste específico de compatibilidade nas expressões regulares de nomes de parâmetros de rota do Express 5, já que Node.js Mobile foi compilado sem os dados Unicode necessários. **Essa alteração não modifica o servidor Windows.**

### Validação conhecida e limitações

O APK com servidor integrado **compilou** e o emulador confirmou inicialização do Node Mobile, inicialização do servidor completo, resposta real na porta de controle e dois processos Android ativos. O pacote offline de servidor também passou em testes HTTP no Linux. **Ainda não foram comprovadas a entrada no mundo, combate e estabilidade em celulares físicos**; trate-o como beta e reporte erros do aparelho.

O serviço de hospedagem fica em primeiro plano com uma notificação para cumprir as regras de execução Android. Em caso de falha, `files/mooio-data/node-boot.log` (armazenamento privado) registra diagnósticos do Node. A versão antiga `Moo-IO-Android-Teste.apk` e o arquivo `.love` não incluem o servidor.

Use apenas LAN, hotspot ou VPN privada confiável, sem encaminhar a porta diretamente para a internet.