# Moo-IO — Windows

## Acesso público direto com HTTPS/WSS verificados

**Novo:** o cliente reconhece convites de salas publicados pelo gateway Caddy, no formato `https://normal.jogo.seudominio.com/CODIGO`. Ao entrar em uma sala V2, a página de autenticação abre no navegador; as solicitações da API, o ticket, o protocolo e o WebSocket passam por uma ponte TLS validada. Para partidas públicas, não existe fallback para HTTP/WS.

O certificado do servidor é verificado pelo mecanismo confiável da plataforma: `tls.connect` do Node 22 já distribuído no **Windows**, ou `SSLSocketFactory`/`SSLParameters.setEndpointIdentificationAlgorithm("HTTPS")` no **Android**. Ambos validam autoridade certificadora, validade, hostname SNI e TLS 1.2+. Certificados vencidos, autoassinados não confiáveis ou de outro domínio impedem a conexão. Não há opção de ignorar certificados.

No Windows, o jogo inicia sob demanda um relay Node oculto, em `127.0.0.1:8469`, usando `runtime/node/node.exe` + `scripts/tls-relay.mjs`. O filho é encerrado ao sair do jogo. No Android, `MooIOActivity` inicia a ponte Java no processo normal do app, sem iniciar o servidor Node de hospedagem e sem notificação persistente. A comunicação local requer um token aleatório privado, e a ponte só permite destinos DNS e porta 443.

O jogador deve informar o convite HTTPS completo na tela **Jogar**. O backend da VPS precisa estar configurado com Caddy, DNS e TLS válidos; as portas internas da sala e do painel administrativo continuam privadas. Em redes LAN/VPN, convites por IP continuam usando o modo anterior.

Esta versão muda o **código-fonte** Android e Windows. O Windows exige reconstrução do ZIP; o Android exige um novo APK nativo com `MooIOTlsBridge.java`. Instalações antigas não ganham TLS até receberem um pacote atualizado. O teste do transportador no GitHub não substitui uma validação real em dispositivos Android conectados a uma VPS.


## Login V2 pelo navegador (LAN/VPN privada)

O cliente não solicita senha no jogo. No menu **Jogar**, informe o convite privado da sala (IP/porta/código), escolha **Entrar na conta V2 (navegador)** e autorize no site HTTPS da VPS. Volte ao Moo-IO; o cliente consulta a sala automaticamente e entra quando a autorização termina. O código PKCE é gerado com fonte criptográfica de entropia e usado uma só vez.

O protocolo protege o segredo central: a sala consulta o serviço de identidade localmente, consome o código PKCE e devolve ao cliente somente um JWT específico de 15 minutos. Sem a infraestrutura Caddy/identidade da VPS, use a entrada LAN original.

**Limite:** o transportador Lua continua usando HTTP/WS para partidas por IP privado. Para tráfego entre redes, use uma VPN criptografada; acesso público direto por domínio HTTPS/WSS ainda exige cliente TLS próprio. Não envie credenciais ou tokens por IP público sem TLS.

**Moo-IO** é um jogo multiplayer de sobrevivência e combate em 2D, com visão de cima. Explore o mapa, reúna recursos, construa estruturas, equipe armas e enfrente animais e outros jogadores.

## O jogo

- **Exploração e sobrevivência:** percorra o mapa, encontre animais e obtenha comida, madeira e pedra.
- **Construção de bases:** use recursos para colocar paredes, armadilhas e estruturas de defesa e apoio.
- **Combate:** utilize armas corpo a corpo e de longa distância para caçar, se defender e enfrentar outros jogadores.
- **Evolução:** ganhe experiência, avance de idade e desbloqueie novos equipamentos e construções.
- **Equipamentos e loja:** escolha itens, chapéus e acessórios com diferentes efeitos durante as partidas.
- **Interface de partida:** acompanhe vida, recursos, experiência, inventário, mapa e classificação dos jogadores.

## Salas e multiplayer

O cliente Windows permite **criar sua própria sala** com um servidor local integrado. A sala só é criada quando você escolhe **Criar minha sala** — abrir o menu **Jogar** não inicia uma partida automaticamente.

Você pode jogar em uma rede local (**LAN**) ou usar uma rede **VPN privada** já configurada para reunir amigos de outros lugares. Também é possível **entrar em uma sala existente** pelo endereço IP e código de convite.

O dono da sala pode abrir **Esc → Convidar amigos** para copiar o convite e compartilhá-lo com os participantes.

## Bots de IA

Ao criar uma sala, o anfitrião pode **ativar ou desativar bots** e escolher de **0 a 8 bots**. Por padrão, eles ficam desligados.

Os bots são controlados pelo servidor e participam do mesmo mundo dos jogadores. Eles podem explorar, procurar recursos, caçar, atacar, recuar diante de ameaças e reaparecer após serem derrotados.

## Menu durante a partida

A tecla **Esc** abre um menu sobre o mundo do jogo, com as opções **Voltar ao jogo**, **Configurações**, **Convidar amigos** e **Sair da partida**.

Nas configurações, é possível alterar a exibição da grade do mapa e o modo de tela cheia. O mundo multiplayer continua em funcionamento enquanto o menu está aberto.

Se o anfitrião escolher sair e encerrar a sala, o jogo **pede confirmação antes de desligar o servidor local e desconectar os participantes**. Um convidado pode sair sem encerrar a sala dos demais.

## Versão Windows

Esta versão reúne o **cliente para Windows**, o **servidor local de partidas** e os recursos visuais do jogo. O pacote Windows preparado inclui os componentes necessários para iniciar o cliente e hospedar salas sem baixar dependências ou converter imagens durante a abertura.
