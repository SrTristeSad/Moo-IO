# VPN privada — Moo IO

Esta etapa permite a amigos em redes fisicamente diferentes jogarem em uma sala por **IP virtual**, sem configurar encaminhamento de portas no roteador. A VPN precisa estar **instalada e conectada em todos os computadores**; o Moo IO nao instala nem configura a VPN de terceiros.

## Anfitriao (Windows)

1. Instale e conecte uma VPN privada com os amigos: **Tailscale**, **ZeroTier**, **Radmin VPN** ou **Hamachi**, por exemplo.
2. Confirme no aplicativo VPN qual IP **IPv4 virtual foi atribuido a este computador** (nao o IP publico do provedor). Com Tailscale costuma ser `100.64.x.x` a `100.127.x.x`; ZeroTier frequentemente usa redes RFC1918, como `10.x.x.x` ou `172.16-31.x.x`.
3. Abra `MOO-IO.vbs` e selecione **Servidor → VPN privada**.
4. Digite o IP virtual do **anfitriao** no campo do menu e escolha **Criar sala na VPN**.
5. O Moo IO verifica se esse IP pertence a uma interface IPv4 ativa do Windows e inicia o Node.js restrito a ele (TCP 8080). Um segundo endpoint local em `127.0.0.1:8081` controla apenas o processo.
6. Compartilhe o convite gerado, por exemplo `100.101.12.34:8080/abcd1234567890ef`. Dentro do jogo, escolha **Jogar agora** para participar da propria sala.

## Amigo

1. Entre na mesma VPN privada. O dono do grupo ou tailnet deve autorizar o dispositivo.
2. Abra o Moo IO, clique em **Jogar**, cole o convite completo e escolha **Entrar na partida**.
3. O cliente solicita um ticket de entrada com o codigo, autentica o WebSocket e inicia o personagem ao receber o handshake do servidor.

O convite sozinho **nao** insere um computador na rede virtual; a VPN deve dar conectividade entre os dois.

## Diagnostico

- **IP da VPN invalido:** use apenas IPv4 das faixas privadas (`10/8`, `172.16/12`, `192.168/16`), CGNAT usado pelo Tailscale (`100.64/10`) ou faixas usadas por redes VPN legadas (`25/8`, `26/8`). Enderecos publicos sao rejeitados nesta etapa.
- **O IP nao pertence ao computador:** confira se a VPN esta conectada **no anfitriao** e copie o IP atribuido a ele, nao o IP de outro membro.
- **Conexao negada/timeout:** revise as permissoes entre pares na VPN, regras do firewall do Windows **para o adaptador da VPN**, porta TCP 8080 e se a rede permite acesso ao IP do anfitriao.
- **Servidor sem abrir:** confira os erros apresentados na interface. O registro tecnico fica em `server/data/mooio-host.log`.
- **Conexao funciona mas nao entra no mundo:** verifique o estado de ingresso mostrado no jogo e os testes do cliente Lua. Nao trate sucesso de /ping como partida confirmada.
- **Nao desative o firewall inteiro.** Crie uma regra restrita ao adaptador da VPN, caso necessario.

## Protecoes e limites

O Node escuta somente no IP virtual selecionado e nao em `0.0.0.0`. O controle de encerramento permanece em loopback, acessivel apenas ao anfitriao. Os convites usam codigos aleatorios; os tickets do jogo continuam de uso unico.

Esta integracao **nao e um servidor publico seguro**: a API reconstruida ainda possui partes de autenticacao e CAPTCHA de testes e nao usa HTTPS/WSS end-to-end. Use apenas VPNs privadas com pessoas confiaveis. Nao exponha a porta para a internet comum, nao utilize VPS publica e nao encaminhe a porta no roteador.

Para testar atraves de Steam Networking ou servidores dedicados publicos sera necessaria uma infraestrutura adicional de autenticacao, rede e seguranca. Nao ha descoberta automatica de amigos ou instalacao de VPN pelo jogo.
