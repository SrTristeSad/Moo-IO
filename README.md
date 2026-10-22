# Moo-IO

O codigo atualmente desenvolvido e **um projeto Windows completo**. Ele inclui o cliente Lua/LÖVE, o servidor Node.js local usado para hospedar partidas, assets, scripts, testes e geracao do ZIP offline. Esses componentes permanecem **juntos**, sem criar um servidor dedicado separado.

## Plataformas

- [Windows — projeto atual](windows/README.md) — toda a implementacao existente, inclusive o servidor local que pertence ao cliente Windows.
- [Android](android/README.md) — reservado para desenvolvimento futuro; **nenhum cliente Android implementado**.
- [Servidor independente](servidor/README.md) — reservado para desenvolvimento futuro; **nenhum produto de servidor independente implementado**.

## Abrir ou distribuir o Windows

- Para editar o codigo-fonte, entre em [windows/](windows/) e execute `windows/MOO-IO.vbs` com LÖVE instalado, ou use os comandos indicados em [windows/README.md](windows/README.md).
- Para obter um pacote que ja inclua LÖVE e Node, use **Actions > Moo IO - Windows pronto sem downloads** e o artefato `Moo-IO-Windows-Pronto.zip`.
- O pacote distribuivel mantem a estrutura que o jogo ja utiliza. **Nao foi reescrito o motor do cliente nem foi separado seu servidor local**.

Os workflows do GitHub permanecem em `.github/workflows/` na raiz porque essa e a pasta obrigatoria do GitHub Actions. Documentos gerais de licenca e seguranca tambem ficam disponiveis na raiz.
