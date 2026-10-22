# Moo IO

Jogo multiplayer em **Lua/LÖVE 2D**, com servidor de partida **Node.js**. Projeto comunitário separado do Moo-Quest; o servidor privado V2 do Moo-Quest **não está incluído**.

## Menu e saida segura da partida

O menu inicial usa como fundo a pre-visualizacao em tempo real do mundo
top-down ja existente no cliente Moo IO/MooMoo; e apenas uma demonstracao
visual local e **nao cria uma partida ou jogadores artificiais**.

**Esc durante a partida** abre o menu de pausa/configuracoes sobre o
mundo real recebido do servidor. A partida multiplayer continua rodando:
o jogador para de enviar comandos de movimento e ataque enquanto o menu
esta aberto, mas nao pausa os demais participantes. Na interface:

- **Voltar ao jogo**: fecha o menu, sem desconectar.
- **Configuracoes**: liga/desliga a grade do mapa e a tela cheia. Se voce for o anfitriao, inclui **Convidar amigos** para ver e copiar o convite da sala.
- **Sair da partida (convidado)**: desconecta somente este usuario.
- **Sair e encerrar sala (anfitriao)**: pergunta antes de desligar
  o servidor e desconectar todos. Cancelar mantem a sala funcionando.

A confirmacao vale tambem para o botao **Encerrar** na tela Jogar e para
o fechamento da janela no Windows quando o usuario hospeda uma sala.
O botao **Jogar** do menu principal apenas abre as escolhas, nao inicia
servidor nem entra em partida sozinho.

**Interface em partida:** o antigo botao **Clan** foi retirado do HUD, sem alterar as funcionalidades independentes de **Shop** e **Tribe**.

## Menu principal

| Tela | Para que serve |
| --- | --- |
| **Jogar** | Abre as opcoes para criar uma sala particular manualmente ou entrar em outra pelo IP e codigo. Criar nao inicia a partida automaticamente. |
| **Servidores** | Área própria para os futuros servidores dedicados **V2 Lite** e o catálogo de salas/contas via **Firebase**. Essas integrações ainda não estão conectadas a serviços externos. |
| **Configurações** | Grade do mapa, tela cheia e convite da sala quando o usuario e anfitriao. |

### Jogar sozinho e convidar amigos

1. Instale **Node.js 20+** e **LÖVE 2D 11.5** com LuaSocket. Baixe o ZIP completo do GitHub, **extraia todos os arquivos** e execute **MOO-IO.vbs** de dentro da pasta extraída (não execute direto de dentro do ZIP).
2. Clique em **Jogar**, depois em **Criar minha sala**. Apos criar, clique em **Jogar agora** para entrar; a sala nao e criada ou acessada automaticamente.
3. Dentro da partida, abra **Esc > Configuracoes > Convidar amigos > Copiar convite** e envie aos amigos. O antigo atalho F2 e o aviso permanente foram removidos.
4. Amigos abrem **Jogar**, digitam o IP/porta e o código de acesso separadamente **ou colam um convite completo**, e clicam em **Entrar na sala**.

Exemplo de convite: `192.168.1.10:8080/abcd1234567890ef`. O código de acesso é necessário para obter o ticket de entrada no servidor reconstruído. Quando alguém entra, o servidor Node é responsável por movimentação, animais, construções, recursos e combate. Não são criados jogadores ou entidades fictícios no cliente.

**Bots não foram adicionados.** A estrutura de sala particular permite incluí-los futuramente, mas não há comportamento de bots nem opções falsas na interface.

### Amigos de outras redes

Para partidas fora da mesma LAN, conecte os computadores a uma VPN privada (por exemplo, Tailscale, ZeroTier ou Radmin), selecione **VPN** dentro de **Jogar** e informe o endereço virtual atribuído ao PC anfitrião. O convite poderá ser usado pelos outros participantes da VPN.

Veja [Guia de VPN](docs/VPN-PRIVADA.md). A VPN deve estar instalada e conectada; o jogo não instala esses serviços nem atravessa CGNAT sozinho.

### Servidores V2 Lite e Firebase

A tela **Servidores** já separa os dois tipos de serviço. É uma organização da navegação, **não significa que as APIs já estejam funcionais**.

- **V2 Lite:** servidor dedicado comunitário. Falta validar o protocolo e integrar o cliente ao serviço.
- **Firebase:** futura autenticação de usuários, amigos, descoberta e lista de salas. Falta vincular um projeto Firebase, configurar regras e credenciais de aplicação. Firebase não substitui o motor de jogo Node nem garante comunicação direta pela internet.

Para entrar em uma sala **Moo IO compatível**, utilize o campo IP/código de **Jogar**.

## Interface em blocos e correção do servidor interno

O menu usa painéis retangulares, relevos e cores inspiradas em jogos de blocos, sem reutilizar texturas, fontes ou imagens proprietárias do Minecraft. O botão **Voltar** fica no canto superior direito, fora da área do logotipo; a mensagem de erro/status aparece numa faixa própria no rodapé. **Tentar novamente** só aparece quando ocorre uma falha.

Foi corrigida a localização do script interno. Antes o cliente usava `love.filesystem.getSourceBaseDirectory()`, que aponta para o diretório **pai** do jogo, e por isso mostrava um falso erro de `start-server.ps1` ausente. Agora o Moo IO verifica a pasta da origem real com `love.filesystem.getSource()` e somente inicia quando existem `main.lua`, `server/src/index.js` e `scripts/start-server.ps1` juntos. Se algum arquivo estiver realmente faltando, a interface explica que é necessário extrair o ZIP completo.

## Testes

```bash
npm install --prefix server
npm test
```

O GitHub Actions verifica conexões/tickets, navegação do menu e um cliente Lua/LÖVE recebendo confirmação real de partida e renderizando HUD a partir do Node. Verifique os resultados em [Actions](https://github.com/SrTristeSad/Moo-IO/actions).

O anfitriao Windows e a conexao entre PCs reais ainda exigem teste pratico; os testes automatizados nao confirmam funcionamento em todos os adaptadores de rede ou instalacoes locais.

## Segurança, artes e código aberto

Esta versão é para LAN ou VPN **privada confiável**. A API herdada tem mecanismos de autenticação de desenvolvimento; **não exponha o servidor à internet pública**. Consulte [SECURITY.md](SECURITY.md).

As artes definitivas ficam para depois. Este repositório não redistribui imagens nem scripts proprietários do jogo oficial; recursos próprios com licença apropriada podem ficar em `assets/custom/img/`.

Servidor reconstruído baseado em [al007ex/moomoo-clone](https://github.com/al007ex/moomoo-clone), commit `06f7c1ca965a7628671676c8d9a7efd3997bb5e7` (Apache-2.0). Cliente Lua importado do snapshot autorizado anterior ao V2 do Moo-Quest. Contribuições novas Moo IO e cliente distribuídas sob AGPL-3.0-only, respeitando as atribuições anteriores. Veja [NOTICE.md](NOTICE.md) e [LICENSE](LICENSE).


## Artes incluídas do arquivo moomoo-io.zip

O projeto usa as imagens do ZIP fornecido pelo usuário em 22/10/2026.
**Não usa os placeholders Kenney**. O pacote contém exatamente 176
imagens: 168 PNGs e 8 WebPs que estavam apenas renomeados como .png.
As 8 imagens são convertidas para PNG legítimo, mantendo as mesmas
dimensões, pixels e transparência.

As imagens são versionadas em `assets/custom/img/`; ao jogar
**não acontece download de imagens nem conversão**. O arquivo inicial
`assets/custom/img/weapons/hammer_1.png` é PNG verdadeiro.

O ZIP enviado não inclui seis nomes de sprites previstos pelo cliente:
`animals/boar_1.png`, `animals/crab_1.png`, `animals/yeti_1.png`,
`hats/hat_59.png`, `hats/hat_60.png` e `hats/hat_61.png`.
Eles não foram inventados nem substituídos por outras imagens.
O arquivo `support/reference-image-manifest.json` lista todos os
180 nomes esperados. Nenhum processo de recuperação é executado no
computador do jogador.

O código de importação em `tools/import-uploaded-art.mjs` verifica
o hash agregado dos 176 arquivos originais antes de publicar. Esse
checksum vem do ZIP enviado pelo usuário e impede aceitar arquivos
diferentes de um espelho congelado. A conversão e a publicação ocorrem
apenas uma vez no GitHub Actions.

**Direitos autorais:** fornecer o ZIP não comprova autorização para
redistribuição pública de arte pertencente a terceiros. É necessário
verificar os direitos desses arquivos antes de qualquer lançamento
comercial ou distribuição pública do jogo.
