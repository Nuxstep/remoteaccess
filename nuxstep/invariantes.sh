#!/usr/bin/env bash
#
# Confere as premissas do upstream de que os nossos patches dependem.
#
# Um patch pode continuar aplicando limpo e mesmo assim deixar de funcionar,
# porque o que ele faz depende de como o upstream usa o que ele altera. Cada
# item abaixo é uma dessas premissas, com o que quebra se ela cair.
#
# Roda sobre a árvore do upstream ANTES dos patches.
#
# Uso: ./nuxstep/invariantes.sh [--silencioso]

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RAIZ
cd "${RAIZ}"

SILENCIOSO=false
[[ "${1:-}" != "--silencioso" ]] || SILENCIOSO=true
readonly SILENCIOSO

FALHAS=0

ok() { ${SILENCIOSO} || printf '  ok   %s\n' "$1"; }

falha() {
	printf '  FALHA %s\n' "$1" >&2
	printf '        %s\n' "$2" >&2
	FALHAS=$((FALHAS + 1))
	if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
		printf -- '- **%s** — %s\n' "$1" "$2" >>"${GITHUB_STEP_SUMMARY}"
	fi
}

# Premissa expressa como "este padrão aparece pelo menos uma vez neste arquivo".
exige_presenca() {
	local descricao="$1" arquivo="$2" padrao="$3" consequencia="$4"
	if [[ -f "${arquivo}" ]] && grep -qE "${padrao}" "${arquivo}"; then
		ok "${descricao}"
	else
		falha "${descricao}" \
			"o padrão /${padrao}/ sumiu de ${arquivo}. ${consequencia}"
	fi
}

# Premissa expressa como "este padrão aparece N vezes neste arquivo". Só onde o
# número em si é a premissa; do contrário, um refactor inocente vira alarme.
exige() {
	local descricao="$1" arquivo="$2" padrao="$3" esperado="$4" consequencia="$5"
	local achado
	if [[ ! -f "${arquivo}" ]]; then
		falha "${descricao}" "o arquivo ${arquivo} não existe mais. ${consequencia}"
		return 0
	fi
	achado="$(grep -cE "${padrao}" "${arquivo}" || true)"
	if [[ "${achado}" == "${esperado}" ]]; then
		ok "${descricao}"
	else
		falha "${descricao}" \
			"em ${arquivo}, o padrão /${padrao}/ aparece ${achado}x e esperávamos ${esperado}x. ${consequencia}"
	fi
}

${SILENCIOSO} || printf 'Invariantes do upstream\n'

# --------------------------------------------------- ponto de enganche da marca

# O patch 0001 entra DENTRO do load_custom_client porque ele é o único ponto
# comum às entradas de processo. Se o upstream criar uma quarta entrada que não
# passe por ele, a marca não chega lá.
exige_presenca "load_custom_client existe" \
	src/common.rs 'pub fn load_custom_client\(\)' \
	"É onde o patch 0001 entra. Sem ela, o patch não tem onde enganchar."

# windows.rs recarrega a config dentro do app já marcado (não é entrada de
# processo). Está na lista para que um arquivo NOVO apareça como diferença.
chamadores_esperados="src/core_main.rs src/flutter_ffi.rs src/platform/windows.rs src/service.rs"
chamadores_achados="$(grep -rlE '(crate::|common::)?load_custom_client\(\)' \
	--include='*.rs' src/ | grep -v '^src/common.rs$' | sort | tr '\n' ' ' |
	sed 's/ $//')"
if [[ "${chamadores_achados}" == "${chamadores_esperados}" ]]; then
	ok "as entradas que chamam load_custom_client sao as conhecidas"
else
	falha "as entradas de processo mudaram" \
		"esperado '${chamadores_esperados}', achado '${chamadores_achados}'. Uma entrada nova que não chame load_custom_client roda SEM a marca: servidor e chave padrão, e is_custom_client() falso."
fi

# --------------------------------------------- o que a marca liga e desliga

# is_custom_client() é o interruptor que o upstream usa para desligar a
# atualização automática. Ele deriva do APP_NAME, que é o que o patch define.
exige_presenca "is_custom_client deriva do APP_NAME" \
	src/common.rs 'get_app_name\(\) != "RustDesk"' \
	"Se passar a derivar de outra coisa, definir APP_NAME deixa de desligar a checagem de atualização, e o cliente volta a olhar para api.rustdesk.com."

exige_presenca "a checagem de atualização respeita is_custom_client" \
	src/common.rs 'if is_custom_client\(\) \{' \
	"É o que impede o cliente de oferecer a atualização do upstream, que substituiria a nossa marca e o nosso servidor."

exige_presenca "a auto-atualização como root respeita is_custom_client" \
	src/updater.rs 'if crate::is_custom_client\(\)' \
	"É o que impede o LaunchDaemon de trocar silenciosamente o nosso cliente pelo RustDesk do upstream."

# ------------------------------------------------- o que força o ORG intacto

# write_plists monta o caminho com o prefixo literal, e get_full_name o monta a
# partir do ORG. Enquanto os dois existirem assim, ORG tem de ficar com.carriez.
exige "write_plists usa o prefixo com.carriez literal" \
	src/platform/macos.rs '"/Library/Launch(Daemons|Agents)/com\.carriez\.\{\}_(service|server)\.plist"' 4 \
	"É a razão de NÃO trocarmos config::ORG. Se o upstream passar a montar pelo ORG, a decisão muda e o nuxstep/README.md precisa ser revisto."

exige_presenca "ORG continua com.carriez" \
	libs/hbb_common/src/config.rs 'ORG: RwLock<String> = RwLock::new\("com\.carriez"' \
	"get_full_name() monta o nome do plist a partir daqui, e write_plists usa o literal. Divergir separa onde o serviço é escrito de onde é procurado."

# ---------------------------------------------- o nome do app vira caminho

exige_presenca "o bundle de macOS vem do APP_NAME" \
	src/platform/macos.rs '/Applications/\{\}\.app' \
	"É por isso que PRODUCT_NAME tem de ser Nuxstep. Se o upstream parar de derivar do APP_NAME, o patch 0002 vira ruído -- ou pior, conflito."

exige "o pbxproj fixa o bundle identifier" \
	flutter/macos/Runner.xcodeproj/project.pbxproj 'PRODUCT_BUNDLE_IDENTIFIER = ' 3 \
	"O patch 0002 troca as 3 ocorrências. Número diferente significa configuração de build nova, que sairia com o identificador do RustDesk."

exige "build.py copia o service para dentro do bundle" \
	build.py 'Build/Products/Release/RustDesk\.app/Contents/MacOS/' 1 \
	"O patch 0002 reescreve este caminho. Sem ele, o bundle renomeado sai sem o binário do daemon."

# ------------------------------------------------------ parâmetros do MSI

exige_presenca "preprocess.py aceita --app-name" \
	res/msi/preprocess.py '"--app-name"' \
	"O workflow passa --app-name em vez de patchar o instalador. Sem o parâmetro, o MSI volta a se chamar RustDesk."

exige_presenca "preprocess.py aceita --manufacturer" \
	res/msi/preprocess.py '"--manufacturer"' \
	"Idem: sem ele o fabricante volta a ser Purslane Tech Pte. Ltd."

exige_presenca "o ícone do MSI vem de res/icon.ico" \
	res/msi/preprocess.py 'icon_src = .*icon\.ico' \
	"É assim que a nossa arte entra no instalador, sem patch."

# ------------------------------------------ o que a marca escreve em runtime

exige_presenca "APP_NAME é gravável em runtime" \
	libs/hbb_common/src/config.rs 'APP_NAME: RwLock<String>' \
	"O patch grava nele. Virando const, a marca passa a exigir patch no hbb_common, que é submódulo."

exige_presenca "PROD_RENDEZVOUS_SERVER é gravável em runtime" \
	libs/hbb_common/src/config.rs 'PROD_RENDEZVOUS_SERVER: RwLock<String>' \
	"É por onde apontamos o cliente para o nosso servidor."

exige_presenca "OVERWRITE_SETTINGS tem precedência" \
	libs/hbb_common/src/config.rs 'OVERWRITE_SETTINGS: RwLock' \
	"É o que impede quem usa o cliente de trocar a chave do servidor."

# -------------------------------------------------------------------- saída

if [[ "${FALHAS}" -gt 0 ]]; then
	printf '\n%s premissa(s) do upstream mudaram. Os patches podem aplicar limpo e ainda assim não funcionar.\n' "${FALHAS}" >&2
	exit 1
fi

${SILENCIOSO} || printf 'todas as premissas de pé\n'
