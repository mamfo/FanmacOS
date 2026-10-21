#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/FanmacOS.app"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
NAME="FanmacOS-$VERSION"
STAGE="$DIST/.stage"

if [[ ! -d "$APP" ]]; then
    echo "Compila a app primeiro: make build" >&2
    exit 1
fi

mkdir -p "$DIST"
rm -rf "$STAGE" "$DIST/$NAME.dmg" "$DIST/$NAME.zip" "$DIST/$NAME.sha256"
mkdir -p "$STAGE"

ditto "$APP" "$STAGE/FanmacOS.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/LEIA-ME.txt" <<EOF
FanmacOS $VERSION — temperaturas e ventoinhas na barra de menus
Desenvolvido por mamfo.net

INSTALAR
1. Arrasta FanmacOS.app para a pasta Applications.
2. Abre a app.
3. Se o macOS impedir a abertura (programador não identificado):
   - clica com o botão direito em FanmacOS.app e escolhe Abrir; ou
   - vai a Sistema de Definições > Privacidade e Segurança > "Abrir mesmo assim".
4. O controlo manual das ventoinhas pede a palavra-passe de administrador uma vez.

REQUISITOS
- Mac com Apple Silicon (M1 ou posterior)
- macOS 13 ou superior

NOTAS
- App assinada localmente (ad-hoc) e não notarizada.
- Remover o assistente de ventoinhas: menu do FanmacOS > Remover assistente de ventoinhas…
- Temperaturas sem root; ventoinhas via SMC.
- Mais informação: https://mamfo.net
EOF

hdiutil create \
    -volname "FanmacOS $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DIST/$NAME.dmg" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"
rm -rf "$STAGE"

(
    cd "$DIST"
    shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME.sha256"
)

echo ""
echo "Distribuição criada em dist/:"
ls -lh "$DIST/$NAME.dmg" "$DIST/$NAME.zip" "$DIST/$NAME.sha256" | awk '{print "  " $9 " (" $5 ")"}'
