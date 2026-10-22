# Moo IO

Projeto comunitario de multiplayer com **cliente Lua / LOVE 2D** e **servidor Node.js reconstruido**, separado do Moo-Quest privado. O codigo do **Server V2 do Moo-Quest nao esta incluido**.

## Windows — jogar sem terminal

Requisitos: Node.js 20+, LÖVE 2D 11.5 e LuaSocket disponivel no runtime LÖVE. Requer internet **somente na instalacao inicial das dependencias do Node**.

1. Extraia o projeto no computador.
2. Execute **MOO-IO.vbs** (recomendado; abre a interface do jogo sem terminal). MOO-IO.bat redireciona para o mesmo launcher.
3. O menu inicial oferece **JOGAR**, **SERVIDOR** e **CONFIGURACOES**.
4. Em **SERVIDOR**, clique em **CRIAR SALA LAN**. O servidor Node inicia em segundo plano; o jogo mostra a instalacao, o andamento e os erros na propria tela.
5. Quando a sala estiver pronta, clique em **COPIAR CONVITE**, envie a um amigo da mesma rede ou escolha **JOGAR AGORA**.
6. O amigo abre seu Moo IO, escolhe **JOGAR**, cola o convite no campo e pressiona **ENTRAR NA PARTIDA**.
7. O cliente faz ticket, WebSocket, handshake criptografado e envia o spawn automaticamente. A tela do mundo so aparece depois da confirmacao real do servidor.

Convite de exemplo (apenas ilustrativo): `192.168.1.10:8080/a1b2c3d4e5f6a7b8`.

**Nao e necessario abrir PowerShell, CMD ou o painel do servidor para hospedar ou entrar.** O Node pode ser instalado como dependencia do jogo em versoes futuras, mas nesta etapa o usuario precisa ter Node.js instalado. A primeira instalacao pode baixar pacotes com npm sem mostrar terminal.

## Jogar pela VPN com amigos fora da sua casa

A VPN precisa estar instalada e conectada **nos dois computadores**. No jogo, abra **Servidor → VPN privada**, informe o IPv4 virtual do anfitriao mostrado pelo Tailscale, ZeroTier, Radmin VPN ou similar e clique em **Criar sala na VPN**. O Moo IO escuta apenas nesse endereco e mostra um convite `IP:8080/CODIGO`. O amigo abre **Jogar** e cola o convite.

O modo VPN aceita apenas faixas de enderecos privados ou de redes virtuais conhecidas, nunca IPs publicos arbitrarios. O controle do servidor fica apenas no computador anfitriao. **Nao abra a porta no roteador nem publique a sala na internet**: o backend herdado ainda usa autenticacao de testes.

Guia completo: [docs/VPN-PRIVADA.md](docs/VPN-PRIVADA.md).

## Funcionalidades do novo menu

- **Jogar:** definir apelido, colar convite, entrar automaticamente na partida e tentar novamente quando houver erro.
- **Servidor:** escolher LAN ou VPN privada, hospedar sala na interface de rede selecionada, copiar convite, entrar na propria sala e encerra-la.
- **Configuracoes:** grade do mapa e tela cheia.
- **Dentro da partida:** WASD, mouse, barra de itens, ataque, coleta, loja e demais recursos do cliente Lua herdado. Esc permite retornar ao menu sem desligar a sala hospedada.

As artes proprietarias do jogo original NAO estao no pacote. Para renderizacao completa, coloque apenas PNGs com licenca valida em `assets/custom/img/<categoria>/<arquivo>.png`. O cliente nao inventa entidades ou sprites ausentes.

## Erros e limitacoes

- O convite permite **LAN ou VPN privada** por IP virtual, inclusive entre amigos em cidades diferentes na mesma VPN. Ainda nao ha Steam Networking, instalacao automatica de VPN nem servidor publico seguro; nao exponha a porta 8080 publicamente.
- Se o computador estiver em Wi-Fi com isolamento de clientes ou firewall bloqueando TCP 8080, o convite nao conseguira conectar.
- Se o Node nao iniciar, a interface apresenta um erro; consulte `server/data/mooio-host.log` para diagnostico tecnico quando necessario. Esse arquivo nao precisa ser aberto por jogadores comuns.
- A conexao convidada da base reconstruida possui login/CAPTCHA de desenvolvimento e nao esta pronta para servidores na internet. Consulte SECURITY.md.
- A renderizacao e gameplay foram testadas automaticamente em Linux contra um servidor Node real. A experiencia visual e a hospedagem oculta no Windows ainda devem ser testadas em computadores de jogadores.

## Testes

```bash
npm install --prefix server
npm test
```

O GitHub Actions executa testes do protocolo/tickets e um teste de partida Lua/LÖVE contra o servidor Node real, exigindo spawn confirmado e renderizacao da HUD. Veja [Actions](https://github.com/SrTristeSad/Moo-IO/actions).

## Codigo aberto e creditos

- Servidor reconstruido de [al007ex/moomoo-clone](https://github.com/al007ex/moomoo-clone), commit `06f7c1ca965a7628671676c8d9a7efd3997bb5e7`, sob **Apache License 2.0**, com avisos preservados em `licenses/upstream-server-APACHE-2.0.txt`.
- Cliente Lua derivado do snapshot autorizado do Moo-Quest, commit `5ad8c32d1889dcb94e5645982acc2a0f2d570e09`, anterior ao V2.
- Codigo novo Moo IO e cliente sob **AGPL-3.0-only**, respeitando direitos preexistentes e os termos Apache-2.0. Consulte LICENSE e NOTICE.md.
- Nao sao distribuidos bundle oficial FRVR, artes ou sons proprietarios, nem o Server V2 privado.

Quem modificar e distribuir este projeto deve cumprir as licencas correspondentes, inclusive disponibilizando o codigo das modificacoes quando aplicavel. Nao e obrigatorio enviar o codigo especificamente para este repositorio.
