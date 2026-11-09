#!/usr/bin/env bash
#
# Gera os arquivos de `nuxstep/assets/` a partir da arte em `nuxstep/icon/`.
# Roda na máquina de quem mantém (precisa de ImageMagick e iconutil, macOS);
# o resultado é versionado, então o build no runner não depende disto.
#
# Uso: ./nuxstep/gerar-arte.sh

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RAIZ
readonly ORIGEM="${RAIZ}/nuxstep/icon"
readonly DESTINO="${RAIZ}/nuxstep/assets"
TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "${TMP}"' EXIT

# Base: a arte de fundo escuro. É a única das três legível tanto em barra
# clara quanto escura — a de fundo branco some no modo escuro e a transparente
# perde o chevron.
readonly BASE="${ORIGEM}/Fundo.png"
readonly BASE_CLARA="${ORIGEM}/Fundo 2.png"

readonly FUNDO_ESCURO='#090909'
readonly FUNDO_CLARO='#ffffff'
readonly LADO=1700
readonly RAIO=306   # 18% do lado: canto arredondado sem virar círculo
readonly GLIFO=1190 # 70% do lado: a marca inteira cabe sem encostar no canto

log() { printf '%s\n' "==> $*"; }

for arquivo in "${BASE}" "${BASE_CLARA}"; do
	[[ -f "${arquivo}" ]] || {
		printf 'ERRO: falta %s\n' "${arquivo}" >&2
		exit 1
	}
done
mkdir -p "${DESTINO}"

# ------------------------------------------------- ladrilho de canto redondo

log "ladrilho"

# A arte original encosta nas bordas, então arredondar o canto dela cortaria as
# pontas do X. O glifo é separado do fundo e recomposto menor dentro do
# ladrilho, com folga.
magick "${BASE}" -fuzz 12% -transparent "${FUNDO_ESCURO}" -trim +repage \
	"PNG32:${TMP}/glifo.png"

magick -size "${LADO}x${LADO}" xc:black -fill white \
	-draw "roundrectangle 0,0 $((LADO - 1)),$((LADO - 1)) ${RAIO},${RAIO}" \
	"${TMP}/mascara.png"

# `-alpha set` no fundo e `-alpha off` na máscara: sem isso o resultado sai
# sem canal alfa nenhum e o canto arredondado some sem erro.
magick -size "${LADO}x${LADO}" "xc:${FUNDO_ESCURO}" -alpha set \
	"${TMP}/mascara.png" -alpha off \
	-compose CopyOpacity -composite "PNG32:${TMP}/ladrilho-vazio.png"

magick "${TMP}/ladrilho-vazio.png" \
	\( "${TMP}/glifo.png" -resize "${GLIFO}x${GLIFO}" \) \
	-gravity center -compose over -composite "PNG32:${TMP}/ladrilho.png"

# ----------------------------------------------------------- ícone do Windows

# Tamanhos que o Windows de fato pede: 16 e 32 na barra e no Explorer, 48 e 256
# em ícones grandes. Sem os pequenos, o Windows reduz o de 256 e o resultado
# fica borrado.
log "icon.ico"
magick "${TMP}/ladrilho.png" -define icon:auto-resize=256,128,64,48,32,24,16 \
	"${DESTINO}/icon.ico"

# ------------------------------------------------------------- ícone genérico

log "icon.png"
magick "${TMP}/ladrilho.png" -resize 512x512 "${DESTINO}/icon.png"

# --------------------------------------------------------------- ícone macOS

# A Apple desenha o ícone dentro de ~82% da tela, com margem transparente: um
# ladrilho que sangra até a borda fica maior que os vizinhos no Dock.
log "icon.icns"
iconset="${TMP}/Nuxstep.iconset"
mkdir -p "${iconset}"
for tamanho in 16 32 64 128 256 512 1024; do
	interno=$((tamanho * 82 / 100))
	magick "${TMP}/ladrilho.png" -resize "${interno}x${interno}" \
		-background none -gravity center -extent "${tamanho}x${tamanho}" \
		"${TMP}/macos-${tamanho}.png"
done
cp "${TMP}/macos-16.png" "${iconset}/icon_16x16.png"
cp "${TMP}/macos-32.png" "${iconset}/icon_16x16@2x.png"
cp "${TMP}/macos-32.png" "${iconset}/icon_32x32.png"
cp "${TMP}/macos-64.png" "${iconset}/icon_32x32@2x.png"
cp "${TMP}/macos-128.png" "${iconset}/icon_128x128.png"
cp "${TMP}/macos-256.png" "${iconset}/icon_128x128@2x.png"
cp "${TMP}/macos-256.png" "${iconset}/icon_256x256.png"
cp "${TMP}/macos-512.png" "${iconset}/icon_256x256@2x.png"
cp "${TMP}/macos-512.png" "${iconset}/icon_512x512.png"
cp "${TMP}/macos-1024.png" "${iconset}/icon_512x512@2x.png"
iconutil --convert icns --output "${DESTINO}/icon.icns" "${iconset}"

# --------------------------------------------------- logos da interface

# Dentro da interface não entra ladrilho: entra a marca sobre o fundo do tema.
# Por isso o fundo chapado sai, e cada tema recebe a versão cujo chevron
# contrasta — o chevron preto é invisível no tema escuro, e o branco no claro.
logo() {
	local origem="$1" cor="$2" saida="$3"
	magick "${origem}" -fuzz 12% -transparent "${cor}" \
		-trim +repage -resize x512 \
		-background none -gravity center -extent 1024x512 \
		"${DESTINO}/${saida}"
	log "${saida}"
}

logo "${BASE}" "${FUNDO_ESCURO}" logo_dark.png
logo "${BASE_CLARA}" "${FUNDO_CLARO}" logo_light.png
cp "${DESTINO}/logo_light.png" "${DESTINO}/logo.png"
log "logo.png (cópia da versão clara; só usada se o tema não tiver a sua)"

log "pronto em ${DESTINO}"
ls -la "${DESTINO}"
