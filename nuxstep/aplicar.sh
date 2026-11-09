#!/usr/bin/env bash
#
# Aplica a marca Nuxstep sobre a árvore do upstream. Roda no runner, depois do
# checkout e antes de qualquer compilação.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RAIZ
cd "${RAIZ}"

log() { printf '%s\n' "==> $*"; }
die() {
	printf 'ERRO: %s\n' "$*" >&2
	exit 1
}

# shellcheck source=/dev/null
source nuxstep/versao.env
: "${UPSTREAM_TAG:?}" "${NUXSTEP_BUILD:?}" "${APP_NAME:?}"
readonly VERSAO="${UPSTREAM_TAG}-nuxstep.${NUXSTEP_BUILD}"

# "Builds gerados apenas a partir de tags oficiais do upstream, nunca da master."
#
# Descender da tag NÃO basta: a master também descende dela, e difere em mais de
# cem arquivos de código. A prova é a árvore ser igual à da tag em tudo que não
# é nosso.
git rev-parse -q --verify "refs/tags/${UPSTREAM_TAG}" >/dev/null ||
	die "a tag ${UPSTREAM_TAG} não existe neste clone (falta fetch-depth: 0 no checkout?)"

alheio="$(git diff --name-only "refs/tags/${UPSTREAM_TAG}" HEAD -- . \
	':(exclude)nuxstep' \
	':(exclude).github/dependabot.yml' \
	':(exclude).github/workflows/nuxstep-*.yml')"
[[ -z "${alheio}" ]] || die "esta árvore não é a da tag ${UPSTREAM_TAG}. Difere em:
${alheio}"

log "versão ${VERSAO} sobre a tag ${UPSTREAM_TAG}"

# Antes de aplicar: as premissas do upstream de que os patches dependem. Um
# patch pode aplicar limpo e mesmo assim não fazer efeito.
bash nuxstep/invariantes.sh --silencioso ||
	die "as premissas do upstream mudaram; rode ./nuxstep/invariantes.sh para o detalhe"

# ------------------------------------------------------------------- patches

shopt -s nullglob
patches=(nuxstep/patches/*.patch)
shopt -u nullglob
[[ "${#patches[@]}" -gt 0 ]] || die "nenhum patch em nuxstep/patches/"

for patch in "${patches[@]}"; do
	# --check antes de aplicar, e falha do patch é falha do build: patch que
	# não bate contra a tag significa que o upstream mudou o código embaixo.
	git apply --check "${patch}" || die "${patch} não aplica sobre ${UPSTREAM_TAG}"
	git apply "${patch}"
	log "aplicado ${patch}"
done

# --------------------------------------------------------------------- marca

# Cada arquivo presente substitui o do upstream; ausente, fica o do upstream.
instala_arte() {
	local origem="nuxstep/assets/$1" destino="$2"
	[[ -f "${origem}" ]] || return 0
	[[ -d "$(dirname "${destino}")" ]] || die "destino inexistente: ${destino}"
	cp -f "${origem}" "${destino}"
	log "arte: $1 -> ${destino}"
}

instala_arte icon.ico res/icon.ico
instala_arte icon.png res/icon.png
instala_arte icon.png flutter/assets/icon.png
instala_arte icon.icns flutter/macos/Runner/AppIcon.icns
instala_arte logo.png flutter/assets/logo.png
instala_arte logo_light.png flutter/assets/logo_light.png
instala_arte logo_dark.png flutter/assets/logo_dark.png

# ------------------------------------------------------------------- saídas

if [[ -n "${GITHUB_ENV:-}" ]]; then
	{
		printf 'VERSION=%s\n' "${UPSTREAM_TAG}"
		printf 'NUXSTEP_VERSION=%s\n' "${VERSAO}"
		printf 'NUXSTEP_APP_NAME=%s\n' "${APP_NAME}"
	} >>"${GITHUB_ENV}"
fi

log "pronto"
