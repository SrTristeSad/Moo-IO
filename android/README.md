# Moo-IO — Android (cliente em desenvolvimento)

Port do **jogo Lua/LÖVE do Windows** com os mesmos módulos de mundo, rede, sprites, personagens, equipamentos e protocolo. Android entra no **servidor Node.js que o Windows hospeda**; o celular não inicia servidor local.

## Controles de dois polegares

- **Deslize na esquerda:** movimenta o personagem em 360 graus, para ao soltar.
- **Deslize na direita:** aponta arma e direção do ataque independentemente do movimento.
- **ATACAR:** segure para golpear, coletar e atacar; solte para parar.
- **AUTO:** liga e desliga o ataque contínuo; começa desligado e desativa ao entrar em menus ou mapa.
- **Minimapa (canto superior esquerdo):** abre mapa grande, toque num ponto para mandar uma marcação visual a você e aos aliados da mesma tribo.
- **II (canto superior direito):** abre o menu de pausa da partida.
- Ações, inventário, danos e posições continuam validados pelo Node, sem jogadores ou objetos artificiais no celular.

A marcação de coordenada usa a extensão de protocolo U do Moo-IO e **exige o servidor Windows atualizado** com esta branch. O servidor valida limites do mapa e aplica o mesmo intervalo do ping de posição S.

## Executar versão de teste

A Action **Moo IO - Android LÖVE (teste)** confere a sintaxe dos arquivos Lua, roda testes de controle multitouch e produz `Moo-IO-Android-Teste.love`. Este arquivo pode ser aberto com o aplicativo oficial **LÖVE for Android 11.5**. Para entrar numa sala, use **Jogar > Entrar em outra sala** e informe IP e código do convite.

**Não é um APK independente, ainda.** É preciso completar o empacotamento com `love2d/love-android`, integrar o teclado virtual, adaptar os menus para telas pequenas e validar os controles em celulares reais. A opção herdada de criar sala funciona somente no Windows. O servidor dedicado V2 Lite e o Firebase não estão integrados nesta etapa.

Use somente LAN ou VPN privada confiável; consulte [SECURITY.md](../SECURITY.md). O cliente Windows não foi substituído.
