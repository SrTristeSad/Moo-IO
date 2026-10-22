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


## Imagens: PNG verdadeiro e arte personalizada

O cliente espera 180 nomes de sprites nas categorias animais, armas,
chapeus, acessorios, recursos e icones. A origem congelada contem seis
imagens **WebP lossless com extensao .png**; elas sao imagens validas no
formato WebP, nao PNGs genuinos. A preparacao local converte o conteudo
para PNG verdadeiro preservando os pixels e a transparencia.

**Sem terminal no Windows:** instale Node.js 20+, LOVE 2D 11.5 e LuaSocket,
extraia o ZIP completo, execute `MOO-IO.vbs` e clique `Jogar`.
O proprio lancador prepara os PNGs antes de abrir o cliente, tanto para anfitrioes quanto para quem apenas entra por convite. Na primeira instalacao pode demorar por causa da transferencia. O servidor tambem verifica as imagens ao criar uma sala.
Se ainda nao tiver os sprites, o processo baixa a referencia congelada
do GitHub, convertendo os WebPs automaticamente. A faixa de status mostra
o andamento e eventuais erros. A inicializacao inicial exige internet
se nao houver a pasta de imagens antiga.

Preparacao manual opcional: `npm install`, `npm run assets:sync`
e `npm run assets:check` para verificar os PNGs resultantes.
O relatorio `ARTES-PENDENTES.txt` separa arquivos ausentes dos
arquivos com formato invalido.

O cliente carrega primeiro `assets/custom/img/<categoria>/<arquivo>.png`,
depois `assets/reference/img/<categoria>/<arquivo>.png`.
A pasta `assets/custom/img` pode conter seus sprites originais,
com nomes do `support/reference-image-manifest.json`.
O arco de diamante `weapons/bow_1_d.png` nao existe no pacote original:
sem arte propria, o cliente usa a imagem-base do arco, nao uma imagem falsa.

Para aproveitar uma instalacao antiga, indique a pasta que ja contem as
subpastas `animals`, `weapons` etc. em `MOO_IO_ART_SOURCE_DIR`
ou coloque-as em `assets/custom/img`. O script tambem verifica uma
pasta Moo-Quest irma.

**Direitos:** os arquivos originais de MooMoo.io/FRVR pertencem a terceiros,
por isso sao preparados para uso local e nao foram adicionados ao
repositorio. Voce pode versionar imagens suas em `assets/custom/img`
se possuir os direitos para distribui-las publicamente.
