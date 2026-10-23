# Moo-IO

Jogo de sobrevivência e combate 2D com um mundo multiplayer compartilhado por **Windows e Android**. Ambos utilizam Lua/LÖVE e se conectam ao mesmo servidor de partida Node.js; o servidor local continua dentro de `windows/`.

## Plataformas

- [Windows](windows/README.md) — cliente completo, servidor local, bots, salas LAN/VPN, convites e ZIP offline.
- [Android — teste](android/README.md) — cliente Lua/LÖVE adaptado ao touchscreen, mira por arrasto, joystick, ataque manual/automático, mapa de marcação, atalhos de inventário e chat; build APK debug.
- [Servidor independente](servidor/README.md) — reservado para um futuro produto de hospedagem, **não implementado**.

## Builds para testes

No menu **Actions** deste repositório, escolha:

- **Moo IO - Windows pronto sem downloads**: artefato `Moo-IO-Windows-Pronto.zip`; extrair completamente, executar `MOO-IO.vbs`.
- **Moo IO - Android APK**: artefato `Moo-IO-Android-APK-Teste` com `Moo-IO-Android-Teste.apk`; APK de desenvolvimento do LÖVE 11.5a.
- **Moo IO - Android LÖVE (teste)**: `Moo-IO-Android-Teste.love` para o LÖVE no Android.

Ambos podem entrar na **mesma sala LAN/VPN privada** criada pelo cliente Windows, usando IP e código de convite. Para o marcador tático por coordenadas, utilize versões do Android e do servidor Windows construídas a partir desta revisão ou posterior. Testes automatizados de protocolo e de entrada Lua/Node passaram; conexão entre aparelhos físicos ainda deve ser validada.

## Organização

As pastas `android/`, `windows/` e `servidor/` são separadas; criar o Android **não apagou nem reescreveu o jogo Windows**. A pasta `servidor/` ainda é só reserva, não o Node.js embutido, que permanece em `windows/server/`.

**Segurança:** versão LAN/VPN privada de teste, sem segurança adequada para hospedar publicamente na internet. Consulte [SECURITY.md](SECURITY.md).
