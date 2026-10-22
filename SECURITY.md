# Seguranca — LAN e VPN privada confiavel

A API reconstruida possui autenticacao/CAPTCHA de testes; o anticheat nao foi revisado para internet publica e nao ha TLS/WSS no transporte da aplicacao. Nao e um servidor publico seguro.

**Use apenas rede local confiavel ou VPN privada com membros autorizados.** VPN criptografa o tunel entre os participantes, mas nao corrige a autenticacao legada do jogo.

- O servidor so aceita binding a IPv4 de LAN/VPN privada; 0.0.0.0 e IP publico sao rejeitados.
- No modo VPN Windows, o endereco informado precisa estar atribuido a uma interface ativa do computador anfitriao.
- O endpoint de controle do processo GUI fica em 127.0.0.1, na porta do jogo + 1, com codigo obrigatorio para encerrar a sala.
- O convite e exigido antes de emitir ticket, mas outros endpoints herdados podem ser acessados por membros da rede VPN.
- Mantenha o firewall ativo e permita TCP 8080 somente para interfaces/sub-redes da VPN ou da LAN escolhidas.
- Nao faca port forwarding no roteador, nao abra tunel publico, nao hospede em VPS publica com esta versao.
- Nao reutilize senhas pessoais como codigo de convite.

Hospedagem publica futura precisa de autenticacao real, controle de abusos, autorizacao de API por sessao, TLS/WSS, auditoria de seguranca, verificacao de antifraude e protecao contra solicitacoes maliciosas.

Veja docs/VPN-PRIVADA.md para conexao entre amigos.
