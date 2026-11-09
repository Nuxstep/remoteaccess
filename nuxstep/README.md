# Cliente de suporte remoto da Nuxstep

Fork de distribuição do RustDesk. O upstream não é editado: tudo o que a Nuxstep muda
está nesta pasta, como patch aplicado sobre uma **tag oficial** do upstream.

| Item | Valor |
|---|---|
| Tag do upstream | `nuxstep/versao.env` → `UPSTREAM_TAG` |
| Versão publicada | `<UPSTREAM_TAG>-nuxstep.<NUXSTEP_BUILD>` |
| Nome do app no sistema | `Nuxstep` |
| Servidor | `rustdesk.nuxstep.com` |
| Plataformas | Windows x64, macOS ARM64 |

As regras de segurança do pipeline estão no repositório de infraestrutura, em
`docs/seguranca-repositorio-publico.md`. Elas são normativas.

## Dois branches, de propósito

| Branch | O que é | Compila? |
|---|---|---|
| `master` | espelho do upstream + esta pasta + nossos workflows | **não** |
| `release/<tag>-nuxstep.<n>` | a **tag oficial** + esta pasta + nossos workflows | sim |

A master é onde a mudança é revisada; ela **não** serve para compilar, porque difere da
tag em mais de cem arquivos de código. O `aplicar.sh` recusa compilar fora de uma árvore
idêntica à da tag — a prova é `git diff` contra a tag, não o nome do branch, porque a
master também descende dela.

## Subir uma versão

```bash
tag=1.5.1 build=1                    # o que está em versao.env
git checkout -b "release/${tag}-nuxstep.${build}" "${tag}"
git checkout master -- nuxstep .github/workflows/nuxstep-build.yml .github/dependabot.yml
git commit -m "release: ${tag}-nuxstep.${build}"
git push -u origin "release/${tag}-nuxstep.${build}"
gh workflow run "nuxstep build" --ref "release/${tag}-nuxstep.${build}"
```

Para uma tag nova do upstream: atualize `UPSTREAM_TAG` em `versao.env` na master, volte
`NUXSTEP_BUILD` para `1` e refaça o branch. Se um patch não aplicar, o workflow falha em
`git apply --check` — rebase o patch contra a tag nova, nunca force o `git apply`.
Republicando a mesma tag, incremente `NUXSTEP_BUILD`.

## Os patches

### `0001-marca-e-servidor.patch`

Define `APP_NAME`, `PROD_RENDEZVOUS_SERVER` e a chave pública do servidor em
`OVERWRITE_SETTINGS`, logo depois do `load_custom_client()` do upstream.

É código e não configuração porque o mecanismo oficial de *custom client* valida a
config contra uma chave pública embutida da RustDesk (`read_custom_client` →
`sign::verify`): só a RustDesk Pro emite config aceita.

Não mexe no `hbb_common` porque ele é submódulo git e exigiria um segundo fork para
manter — e não precisa: `APP_NAME` e `PROD_RENDEZVOUS_SERVER` são `RwLock` graváveis em
runtime, e a chave sai da opção `key`.

`OVERWRITE_SETTINGS` tem precedência sobre a config do usuário e `is_option_can_save`
impede sobrescrever. É isso que impede apontar uma máquina com acesso não supervisionado
para outro servidor.

### `0002-bundle-macos.patch`

`PRODUCT_NAME = Nuxstep` **não é cosmético**. O app deriva o próprio caminho de
`APP_NAME`: `src/platform/macos.rs` monta `/Applications/{app_name}.app` em todo lugar
(instalação do serviço, verificação de "estou instalado?", atualização). Um bundle
chamado `RustDesk.app` com `APP_NAME = Nuxstep` instala, abre e **falha ao instalar o
serviço** — o sintoma aparece só na máquina do cliente.

O bundle identifier passa a ser nosso para que as permissões de Gravação de Tela e
Acessibilidade sejam concedidas ao app da Nuxstep, e não compartilhadas com uma
instalação do RustDesk na mesma máquina.

### O que NÃO é patch, de propósito

**`config::ORG` fica em `com.carriez`.** É tentador trocar. Não troque: `write_plists()`
monta o caminho do plist com o prefixo `com.carriez.` **literal no código**, enquanto
`get_full_name()` o monta a partir de `ORG`. Com `ORG` alterado, o serviço é escrito num
caminho e procurado noutro, e o `launchctl remove` erra o Label. Com `ORG` intacto os
dois caminhos dão `com.carriez.Nuxstep`, que é consistente.

O nome do produto, o fabricante e o ícone do instalador **não** são patch: o
`res/msi/preprocess.py` já aceita `--app-name` e `--manufacturer`, e o workflow os passa.

## `assets/` e `icon/`

`icon/` é a arte de origem (1700×1700); `assets/` é o que o build consome, gerado por
`./nuxstep/gerar-arte.sh` (ImageMagick + `iconutil`, roda só na máquina de quem mantém).
Cada arquivo de `assets/` presente substitui o do upstream; ausente, fica o do upstream.

| Arquivo | Vai para | Onde aparece |
|---|---|---|
| `icon.ico` | `res/icon.ico` | ícone do executável no Windows e do instalador MSI |
| `icon.png` | `res/icon.png`, `flutter/assets/` | ícone do app |
| `icon.icns` | `flutter/macos/Runner/AppIcon.icns` | ícone do app no macOS |
| `logo_light.png`, `logo_dark.png`, `logo.png` | `flutter/assets/` | marca dentro da interface |

A base é a arte de fundo escuro: é a única das três legível tanto em barra clara quanto
escura. A de fundo branco tem o chevron preto, que some no modo escuro; a transparente
não tem chevron. O glifo é recomposto **dentro** do ladrilho de canto arredondado, com
folga — arredondar a arte original cortaria as pontas do X.

## Limitações conhecidas

**Sem assinatura de código.** No Windows o SmartScreen avisa na primeira execução; no
macOS o Gatekeeper bloqueia e o cliente precisa abrir pelo menu de contexto. Está no
plano como etapa futura (`docs/seguranca-repositorio-publico.md`, seção 6), com o
certificado acessível só por OIDC.
