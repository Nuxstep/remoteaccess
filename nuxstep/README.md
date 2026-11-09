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
`OVERWRITE_SETTINGS`, **dentro do `load_custom_client()`**, depois do corpo original.

O ponto de enganche é o que importa. Há **três entradas de processo** e só uma passa
pelo `core_main()`:

| Entrada | Processo |
|---|---|
| `src/core_main.rs` | o app |
| `src/flutter_ffi.rs` → `initialize()` | a camada Flutter |
| `src/service.rs` → `main()` | **o daemon de macOS, que roda como root** |

As três chamam `load_custom_client()`; só a primeira chama `core_main()`. Com a marca
no `core_main`, o daemon fica com `APP_NAME = "RustDesk"`, e três coisas quebram:

1. `write_plists()` grava `/Library/LaunchAgents/com.carriez.RustDesk_server.plist`
   enquanto o app procura `com.carriez.Nuxstep_server.plist` — **o acesso não
   supervisionado não sobe**.
2. `is_custom_client()` é literalmente `get_app_name() != "RustDesk"`. No daemon ele
   devolve `false`, o que **reabre a checagem de atualização contra
   `api.rustdesk.com` e a auto-atualização silenciosa como root** — o caminho que
   substituiria o nosso cliente pelo RustDesk do upstream, com o servidor deles.
3. O processo usa o servidor e a chave padrão.

Nada disso aparece ao compilar: aparece na máquina do cliente. O teste de instalação
tem de conferir o nome dos plists em `/Library/LaunchAgents` e `/Library/LaunchDaemons`.

> A documentação oficial descreve injetar `RENDEZVOUS_SERVER` e `RS_PUB_KEY` por
> variável de build. **Na 1.5.1 isso não existe**: as duas são `const` em
> `libs/hbb_common/src/config.rs`, e o `option_env!` que os forks citam não está nesta
> árvore. O caminho em runtime acima é o que funciona aqui.

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

**Não basta mudá-lo no `AppInfo.xcconfig`.** O `Info.plist` usa
`$(PRODUCT_BUNDLE_IDENTIFIER)`, mas o `project.pbxproj` define esse mesmo ajuste
literalmente nas três configurações de build, e o do `pbxproj` vence. Mudar só o
xcconfig compila, passa e entrega um bundle com o identificador do RustDesk — foi o que
aconteceu no primeiro build. Por isso o passo *Conferir a marca no bundle* lê o
`Info.plist` do produto: a garantia é o que saiu, não o que o patch diz.

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

## Quando o upstream muda

Há duas formas de quebrar, e a segunda é silenciosa:

| Quebra | Quem acusa |
|---|---|
| O patch deixa de **aplicar** | `git apply --check`, no build e no vigia |
| O patch aplica e deixa de **funcionar** | `nuxstep/invariantes.sh` |

A segunda é o caso real: o efeito de um patch depende de como o upstream usa o que ele
altera. `is_custom_client()` ser `get_app_name() != "RustDesk"` é o que faz definir
`APP_NAME` desligar a auto-atualização contra o RustDesk; no dia em que isso virar outra
coisa, o patch continua aplicando e o cliente volta a se atualizar sozinho para o
upstream. O `invariantes.sh` confere 16 premissas dessas, cada uma com o que quebra se
ela cair.

Ele roda em dois momentos:

- **em todo build**, dentro do `aplicar.sh`, antes dos patches — nenhum binário sai com
  uma premissa quebrada;
- **toda segunda-feira**, no workflow `nuxstep vigia upstream`, contra a **última tag
  estável e a master do upstream**. A master é o aviso mais cedo possível, porque é lá
  que a próxima tag nasce. O job falha, e a falha vira e-mail do GitHub.

O vigia também avisa quando sai uma tag estável mais nova que a do `versao.env`.

## Limitações conhecidas

**Sem assinatura de código.** No Windows o SmartScreen avisa na primeira execução; no
macOS o Gatekeeper bloqueia e o cliente precisa abrir pelo menu de contexto. Está no
plano como etapa futura (`docs/seguranca-repositorio-publico.md`, seção 6), com o
certificado acessível só por OIDC.
