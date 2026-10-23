# Moo-IO Android — client LÖVE 11.5a

Cliente móvel **real em Lua/LÖVE** baseado no mesmo jogo Windows. Todo o mundo, assets e protocolo de sessão vêm do Moo-IO existente. A autoridade sobre recursos, dano, equipamentos, animais e posições continua no **Node.js que o Windows hospeda**.

## Controles no Android

| Controle | Ação |
|---|---|
| Joystick esquerdo | movimentação 360° |
| Arraste do lado direito | aponta arma/ataque independentemente do movimento |
| ATACAR | ataque ao segurar; para ao soltar |
| AUTO | ataque contínuo, desligado por padrão |
| CORRER | continua andando na última direção escolhida (não aumenta velocidade do personagem) |
| MIRA | área visual de orientação; arraste no lado direito para mudar direção |
| COLETA | toque para golpe/coleta e solta automaticamente |
| CONSTR. | seleciona a próxima estrutura do inventário sincronizado com o servidor |
| TROCAR | seleciona próxima arma disponível |
| BOLSA | abre armas/estruturas existentes recebidas pelo servidor |
| CHAT | mensagens rápidas de chat público, não exclusivamente para o time |
| Minimapa | abre mapa completo; toque num ponto envia coordenadas ao jogador e colegas da mesma tribo |
| II | menu de pausa e saída |

Nenhum botão cria recursos, estruturas ou dano localmente. O pacote de marcação de coordenada `U` é validado pelo servidor e usa cooldown normal do ping. Para utilizá-lo, **o anfitrião Windows deve estar usando o servidor da mesma branch**.

## Como testar Windows e Android juntos

1. Baixe **Moo-IO-Windows-Pronto.zip** na action **Moo IO - Windows pronto sem downloads** dessa branch e extraia inteiro num PC Windows.
2. Abra `MOO-IO.vbs` no Windows, escolha **Jogar > Criar minha sala**; opcionalmente habilite bots, depois clique **Jogar agora**.
3. Baixe **Moo-IO-Android-Teste.apk** na action **Moo IO - Android APK**; instale no Android (APK debug de teste).
4. Conecte os dois dispositivos à **mesma rede local Wi-Fi/LAN**. No Android, abra **Jogar > Entrar em outra sala**, digite o IP:porta e o código da sala mostrados no Windows; clique **Entrar na sala**. Também funciona em VPN privada compatível, desde que o Android consiga alcançar o IP e a porta TCP do anfitrião.
5. Teste ao mesmo tempo a movimentação, animais, coleta, ataque e os marcadores no mapa. O servidor é único, portanto ambos veem o mesmo mundo.

### Build automatizada

- [Android APK](../.github/workflows/android-apk.yml) — compila LÖVE Android `11.5a` (commit `55feb38`) com o jogo incorporado; entrega APK debug assinado automaticamente **apenas para testes**, não destinado à Play Store.
- [Android .love](../.github/workflows/android-love.yml) — teste de sintaxe, controles multitouch e pacote LÖVE.
- [Windows ZIP](../.github/workflows/package-windows.yml) — distribui o cliente Windows com Node e LÖVE incorporados.
- [Crossplay E2E](../.github/workflows/game-e2e.yml) — usa o mesmo servidor Node em testes com Windows Lua e Android Lua em modo de simulação de toques no Linux.

### Limitações

A interface e os controles móveis precisam ser testados em celulares reais (resoluções, desempenho, teclado do chat e sensibilidade da mira). **Passar nos testes de CI não confirma que APK, conexão entre aparelhos físicos e desempenho estão perfeitos.** Não abra a sala na internet pública; use LAN/VPN privada. O projeto conserva o Windows original em sua própria pasta, sem apagar funções. O APK debug usa chave de teste e não deve ser publicado como release comercial.

## Hospedagem local no proprio Android (experimental)

**Objetivo:** o celular cria sua propria sala sem PC, VPS ou outro jogador. O APK integrado inclui
o jogo Lua/LÖVE e o mesmo servidor Node.js presente no Windows, compilado com Node.js Mobile
(libnode.so) e iniciado numa thread nativa do aplicativo.

- Abra o jogo, toque em JOGAR e em CRIAR MINHA SALA.
- Depois da confirmacao real do Node.js, toque em JOGAR AGORA.
- Sem rede Wi-Fi o servidor usa loopback 127.0.0.1 para jogo solo.
- Com Wi-Fi/hotspot privado, o servidor escuta no endereco IPv4 privado do aparelho;
  amigos Windows e Android podem entrar com IP:8080 e codigo de convite.
- O codigo e gerado e armazenado com seguranca no armazenamento privado do app.
- Os dados do servidor sao persistentes e sobrevivem a reinicializacao do aplicativo.
- Ao sair da sala o servidor continua em memoria enquanto o aplicativo estiver aberto,
  porque o Node/V8 integrado nao deve ser reiniciado no mesmo processo.
- Se trocar de rede Wi-Fi, feche e reabra o aplicativo para reassociar o IP.

**Build correto para esta funcao:** action 'Moo IO Android autonomo - APK com servidor',
arquivo 'Moo-IO-Android-Servidor-Integrado.apk'. A action Android APK anterior produz
somente cliente e NAO atende a este requisito. O servidor integrado precisa passar
na compilacao nativa e num teste de inicializacao no dispositivo antes de ser dado
como comprovadamente funcional. Nao confunda APK gerado com servidor validado.

Requisitos de rede: nenhuma internet para jogar solo. Para multiplayer sem internet
externa, Wi-Fi/hotspot local com TCP/8080 acessivel entre os aparelhos.
