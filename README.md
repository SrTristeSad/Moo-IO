# Moo IO

Servidor comunitario para jogar em rede local: **cliente Lua / LOVE 2D + Node.js**.

Projeto independente de [Moo-Quest](https://github.com/SrTristeSad/Moo-Quest). **O servidor privado V2 nao foi incluido.**

## Jogar com amigo na mesma rede (Windows)

Requisitos: **Node.js 20+**, **LOVE 2D 11.5**, e runtime LuaSocket disponivel no LOVE.

1. Baixe o ZIP deste repositorio e extraia.
2. Inicie **MOO-IO.bat** no PC anfitriao.
3. Escolha **1 - Criar sala local**. Na primeira vez, o instalador baixa as dependencias npm.
4. Copie o convite exibido, por exemplo: 192.168.1.10:8080/a1b2c3d4e5f6a7b8
5. No segundo PC, usando a MESMA rede, inicie **MOO-IO.bat**, escolha **2 - Entrar por convite** e cole o texto.
6. Apos a conexao WebSocket, cada jogador pressiona Play no cliente.

O servidor utiliza tickets individuais via POST /api/join e WebSocket /s/LC. O cliente Lua busca as constantes publicas do protocolo em GET /mooio/protocol. O codigo de convite e validado ANTES da emissao do ticket.

### Limitacoes da primeira entrega

- Conexao por IP:porta/codigo, nao convites automaticos Steam nem relay/NAT.
- Somente redes LAN confiaveis. Nao publique a porta 8080 na internet.
- O cliente depende de sprites adicionais com licenca valida em assets/custom/img; as imagens oficiais nao sao distribuidas.
- O servidor original reconstruido possui autenticacao/CAPTCHA de testes e nao esta pronto para uso publico.
- A partida pode ser hospedada na LAN; ainda falta validar gameplay visual e sincronizacao real em dois computadores Windows.

### Diagnostico

Se o amigo nao conecta: confira rede local, isolamento do Wi-Fi, IP, porta e firewall Windows (TCP 8080).
Se LuaSocket nao estiver disponivel, instale um runtime LÖVE compativel ou suas dependencias LuaSocket.
Se Play nao ativar, consulte o status tecnico exibido no menu.

### Testar backend

Instale as dependencias do servidor: **npm install --prefix server**

Execute testes: **npm test**

Os testes exercitam rejeicao de convites errados, emissao de tickets validos e duas conexoes WebSocket. Testes automatizados nao garantem compatibilidade visual ou FPS no cliente Windows.

## Licencas e atribuicoes

- Backend reconstruido a partir de [al007ex/moomoo-clone](https://github.com/al007ex/moomoo-clone), commit 06f7c1ca965a7628671676c8d9a7efd3997bb5e7, sob **Apache-2.0**. Configuracao anti-cheat local foi produzida separadamente, pois estava ausente da origem.
- Cliente Lua importado do snapshot proprio Moo-Quest, commit 5ad8c32d1889dcb94e5645982acc2a0f2d570e09, anterior ao Server V2.
- Codigo novo Moo IO sob **AGPL-3.0-only**. Consulte LICENSE, NOTICE.md e licenses/upstream-server-APACHE-2.0.txt.
- As obrigacoes de distribuicao do codigo-fonte seguem as licencas aplicaveis; nao e necessario publicar alteracoes especificamente neste repo se outra forma valida de acesso ao codigo for oferecida.
- Sem bundle JS oficial nem arte/sons de FRVR neste repositorio.

## Proximas etapas

Convites pela interface do jogo, mundos individuais, comandos administrativos por chat, hospedagem dedicada e relay/Steam para conexao fora da LAN.
