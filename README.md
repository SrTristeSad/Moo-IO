# Moo IO

Jogo multiplayer em **Lua/LÖVE 2D**, com servidor de partida **Node.js**. Projeto comunitário separado do Moo-Quest; o servidor privado V2 do Moo-Quest **não está incluído**.

## Menu principal

| Tela | Para que serve |
| --- | --- |
| **Jogar** | Cria uma sala particular ao ser selecionado. O jogo inicia o servidor interno e entra automaticamente na partida; amigos podem ser convidados. Também permite entrar em outra sala pelo IP e código. |
| **Servidores** | Área própria para os futuros servidores dedicados **V2 Lite** e o catálogo de salas/contas via **Firebase**. Essas integrações ainda não estão conectadas a serviços externos. |
| **Configurações** | Grade do mapa e tela cheia. |

### Jogar sozinho e convidar amigos

1. Instale **Node.js 20+** e **LÖVE 2D 11.5** com LuaSocket. Baixe o ZIP completo do GitHub, **extraia todos os arquivos** e execute **MOO-IO.vbs** de dentro da pasta extraída (não execute direto de dentro do ZIP).
2. Clique em **Jogar**. O cliente começa a criar sua sala particular sem abrir um terminal e tenta entrar nela assim que estiver pronta.
3. Dentro da partida, pressione **F2** para abrir o convite da sala. Use **Copiar convite** e envie aos amigos.
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

O anfitrião Windows e a conexão entre PCs reais ainda exigem teste prático; os testes em CI não confirmam funcionamento em todos os adaptadores de rede ou instalações locais.

## Segurança, artes e código aberto

Esta versão é para LAN ou VPN **privada confiável**. A API herdada tem mecanismos de autenticação de desenvolvimento; **não exponha o servidor à internet pública**. Consulte [SECURITY.md](SECURITY.md).

As artes definitivas ficam para depois. Este repositório não redistribui imagens nem scripts proprietários do jogo oficial; recursos próprios com licença apropriada podem ficar em `assets/custom/img/`.

Servidor reconstruído baseado em [al007ex/moomoo-clone](https://github.com/al007ex/moomoo-clone), commit `06f7c1ca965a7628671676c8d9a7efd3997bb5e7` (Apache-2.0). Cliente Lua importado do snapshot autorizado anterior ao V2 do Moo-Quest. Contribuições novas Moo IO e cliente distribuídas sob AGPL-3.0-only, respeitando as atribuições anteriores. Veja [NOTICE.md](NOTICE.md) e [LICENSE](LICENSE).


## Artes incluídas no GitHub — sem preparação ao jogar

O repositório distribui os 180 arquivos gráficos requeridos pelo
cliente diretamente em `assets/custom/img/`, separados em `animals/`,
`weapons/`, `hats/`, `accessories/`, `resources/` e `icons/`.

Nenhum sprite é baixado, convertido ou gerado no computador do jogador.
`MOO-IO.vbs` abre o jogo com as imagens já presentes; o servidor não
executa nenhuma instalação de imagens. Se estiver faltando o martelo,
o lançador informa que o pacote baixado está incompleto.

**Arte diferente do original:** a distribuição usa assets CC0 da
Kenney, não os sprites originais da FRVR/MooMoo.io. O conjunto fornece
imagens reais, mas certas armas, roupas e animais são alternativas
visuais e precisarão de artes personalizadas para reproduzir o estilo
que você deseja. Os nomes exigidos pelo código são preservados.

A relação de imagens, licença, fonte e mudanças está em
`assets/custom/CC0-PROVENANCE.md`. `npm run assets:check` é destinado
aos desenvolvedores e aos testes, e não precisa ser executado para jogar.
