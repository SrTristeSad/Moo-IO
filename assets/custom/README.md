# Artes personalizadas do Moo-IO

Coloque **somente artes que voce possui o direito de publicar** nas
subpastas `img/animals/`, `img/weapons/`, `img/hats/`,
`img/accessories/`, `img/resources/` e `img/icons/`.

O cliente procura estas imagens antes das de referencia.
Cada `.png` deve conter bytes PNG validos (nao WebP renomeado).
Os nomes aceitos estao em `support/reference-image-manifest.json`.
Nenhum sprite de MooMoo.io/FRVR e distribuido nesta pasta.

Apos preparar imagens, execute `npm run assets:check` para auditar
os PNGs locais de referencia.
