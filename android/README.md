# Moo-IO Android — cliente e servidor local integrados

O aplicativo utiliza **LÖVE 11.5a** para o jogo em Lua e **Node.js Mobile 18.20.4** para hospedar o mesmo motor de partidas do Windows. O Android não precisa de outro jogador, PC ou VPS para criar uma sala. A hospedagem inicia em um serviço Android separado do processo gráfico e mantém seus dados no armazenamento privado.

## Modo solo e multiplayer

1. Instale o `Moo-IO-Android-Servidor-Integrado.apk` gerado pela action **Moo IO Android autonomo - APK com servidor**.
2. Abra o aplicativo, escolha **Jogar → Criar minha sala**. A interface só apresenta a sala como pronta após receber resposta real do servidor Node.
3. Clique **Jogar agora**. Sem Wi-Fi, o servidor usa `127.0.0.1`; a partida solo não exige internet.
4. Para receber amigos, conecte o telefone a uma rede Wi-Fi/hotspot privado e compartilhe o IP:8080 e o código da sala. Os convidados Windows ou Android escolhem **Entrar em outra sala** e digitam essas informações.
5. Se mudar de rede, feche e abra novamente o aplicativo para atualizar o endereço do servidor. O serviço pode permanecer ativo enquanto o aplicativo está aberto.

**O Node é o responsável real pela simulação, jogadores, dano, recursos, animais, estruturas e validações.** O celular não inventa entidades.

## Controles touchscreen

| Controle | Função |
|---|---|
| Joystick esquerdo | movimento 360° |
| Arrastar na direita | direção independente de mira/ataque |
| ATACAR | segurar para golpear; soltar para parar |
| AUTO | alterna ataque contínuo, desligado inicialmente |
| CORRER | continua movendo na última direção, não concede bônus de velocidade |
| MIRA | região indicativa para deslizar a mira |
| COLETA | golpe curto, enviado ao servidor |
| CONSTR. | seleciona construção disponível |
| TROCAR | troca equipamento selecionado |
| BOLSA | inventário recebido do servidor |
| CHAT | mensagens rápidas públicas |
| Minimapa | abre mapa ampliado para marcar coordenadas aos aliados |
| II | menu de pausa |

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