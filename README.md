# Moo-IO

Jogo multiplayer 2D com clientes **Windows e Android**, usando Lua/LÖVE e um servidor de partida Node.js comum às duas plataformas.

## Plataformas

- [Windows](windows/README.md): cliente + servidor Node embutido, salas privadas LAN/VPN, convites e bots; execução pelo ZIP preparado.
- [Android](android/README.md): cliente com joystick, mira independente, botões de ataque e inventário, **servidor Node.js Mobile integrado ao APK** e modo de criação de sala no celular.
- [Servidor separado](servidor/README.md): pasta reservada para um futuro servidor dedicado, ainda não implementado.

## Como obter as builds

Em [GitHub Actions](https://github.com/SrTristeSad/Moo-IO/actions):

- **Moo IO - Windows pronto sem downloads**: `Moo-IO-Windows-Pronto.zip` — extraia inteiro e execute `MOO-IO.vbs`.
- **Moo IO Android autonomo - APK com servidor**: `Moo-IO-Android-Servidor-Integrado.apk` — cliente Android e servidor local incorporados; não precisa de Windows, VPS ou internet para hospedar uma sala solo.
- **Moo IO Android offline host - emulador**: verifica a inicialização real do servidor no Android.
- A compilação antiga **Android somente cliente (legado)** não incorpora o servidor e não deve ser usada para testar o modo autônomo.

### Jogar

No Windows ou no Android, abra **Jogar → Criar minha sala → Jogar agora**. Para outros jogadores participarem, conectem-se ao mesmo Wi-Fi/hotspot privado e usem o IP/porta e código da sala do anfitrião. O anfitrião Android executa Node no próprio aparelho; o Windows não é obrigatório.

**Estado da versão Android:** a compilação nativa e a inicialização do servidor no emulador passaram. A entrada numa partida completa e o desempenho em telefones físicos ainda precisam de validação. O aplicativo é beta, não publicação final na Play Store.

## Organização e segurança

As pastas `windows/` e `android/` preservam seus clientes independentes. O servidor Windows original continua integrado em `windows/server/`; a build Android incorpora uma versão compatível desse mesmo servidor.

Não exponha a porta diretamente à internet: esta implementação está limitada ao uso em LAN/hotspot ou VPN privada confiável. Leia [SECURITY.md](SECURITY.md).