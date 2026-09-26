#!/bin/sh
# jira-io.sh — UNICO arquivo do plugin cstk-jira que referencia `jq`, o
# cliente HTTP de linha de comando (o mesmo binario de `cli/lib/http.sh`) e
# (FASE 4.2.3, dec-081) um utilitario de hash SHA-256, sob o carve-out 1.1.0
# do Principio II (POSIX sh, zero dependencia) — consentido pelo operador em
# block-002 (plan.md Runtime B1 / dec-021). O utilitario de hash preenche uma
# lacuna ja presente em data-model.md Entity SyncMarker (`written_summary_
# sha256`, ratificado antes desta onda) — mesma disciplina de confinamento
# do carve-out original: um UNICO ponto de acesso (este arquivo), mesmo
# padrao de fallback (exit 5, outbox preservado — jira-sync.sh drain trata
# como qualquer outra dependencia ausente). Decisao dec-081 (onda-022),
# operacional (nao fixa nenhum dos eixos estruturais da execucao).
#
# Ref: docs/specs/cstk-jira/plan.md SEC-1..SEC-5;
#      docs/specs/cstk-jira/contracts/plugin-scripts.md `jira-io.sh`;
#      docs/specs/cstk-jira/contracts/jira-rest.md (autenticacao Basic,
#      R1/R4/R6/R9); docs/specs/cstk-jira/data-model.md Entity
#      ProjectConfig/Credential/SyncMarker; tasks.md FASE 3 tarefas 3.1-3.5
#      + FASE 4 tarefa 4.2.3-4.2.5.
#
# ESCOPO ATE AGORA: 3.1 `deps-check`+`request` com host unico/SEC-5, 3.2
# allowlist de charset em PATH/SEC-1, 3.3 credencial temporaria segura/SEC-4,
# 3.4 classificacao fina de status HTTP, 3.5 `json-get`/`json-build` +
# JQL segura (SEC-3, abaixo).
#
# 3.5 (SEC-3 — `json-get`/`json-build`): este arquivo continua o
# UNICO ponto do plugin que invoca `jq` diretamente — `json-get`/`json-build`
# sao o wrapper que o motor (jira-sync.sh/jira-map.sh, FASE 4+) MUST usar em
# vez de chamar `jq` por conta propria.
#   `json-get FILTER`      — le JSON de stdin, aplica `jq -r FILTER`, exit 2
#                            se o filtro/entrada for invalido.
#   `json-build issue ...` — monta o corpo de R1 (`POST /rest/api/3/issue`,
#                            contracts/jira-rest.md): `fields.project.id`,
#                            `fields.issuetype.id`, `fields.summary`,
#                            `fields.parent.key` (opcional), `fields.description`
#                            em Atlassian Document Format (opcional). `--project-id`/
#                            `--issuetype-id`/`--parent-key` MUST passar pela mesma
#                            allowlist [A-Za-z0-9_-] de `validate-segment` (SEC-1)
#                            ANTES de entrar no corpo; `--summary`/`--description`
#                            sao texto livre, escapado por `jq --arg` (NUNCA
#                            concatenacao de string).
#   `json-build filter ...`— monta o corpo de R9 (`POST /rest/api/3/filter`,
#                            contracts/jira-rest.md): `name` (texto livre,
#                            `jq --arg`) e `jql` (SEC-3: montada so com o
#                            `--project-key` ja validado pela allowlist SEC-1
#                            — nenhum texto livre entra na JQL; `--name` nunca
#                            e interpolado em `jql`). Base da JQL do board
#                            (FR-013, plan.md SEC-3); o motor de board (FASE 7)
#                            reusa este subcomando.
#   `json-build board ...` — monta o corpo de R10 (`POST /rest/agile/1.0/board`,
#                            contracts/jira-rest.md, campos confirmados via
#                            OpenAPI oficial da Agile API): `name` (texto
#                            livre, `jq --arg`), `type` fixo em `"kanban"`
#                            (unico tipo de board previsto pela spec — US2),
#                            `filterId` (SEC-1: SOMENTE digitos, emitido como
#                            numero JSON via `--argjson` — o schema exige
#                            `integer`/`int64`, nunca string) e
#                            `location.projectKeyOrId` (`--project-key` MUST
#                            passar pela allowlist [A-Za-z0-9_-] de
#                            `validate-segment`, mesma disciplina de
#                            `json-build filter`) com `location.type` fixo em
#                            `"project"`.
#
# 3.4 (classificacao de status HTTP, dec-073): `request` ganhou a opcao
# `--op OP` (OP em `R1`..`R11`, contracts/jira-rest.md) para o motor
# (jira-sync.sh/jira-map.sh, FASE 4+) informar QUAL operacao esta servindo —
# `request` em si nao tem como inferir isso do METHOD+PATH sozinho. So os
# codigos abaixo ganham classificacao dedicada (demais codigos, ex. `400`/
# `409` fora de R4, `404`, `422`, mantem o comportamento pre-3.4: passthrough
# como sucesso, exit 0, corpo em stdout — nao inventar classificacao alem do
# que plan.md/contracts/jira-rest.md/checklists/api.md CHK009 exigem):
#   `401` (qualquer operacao)      => `classification=auth_failed`, exit 4,
#                                      nunca retry (FR-016/FR-019)
#   `403` em `--op R1`/`--op R2`   => `classification=permission_denied`,
#                                      exit 7 (NOVO — nao reusa o exit 6 ja
#                                      reservado em plugin-scripts.md para
#                                      conflito/orfao de outros scripts);
#                                      credencial valida, permissao
#                                      insuficiente — NUNCA reconfiguracao
#   `403` fora de R1/R2 (ou sem
#   `--op`, default conservador)   => `classification=auth_failed`, exit 4,
#                                      ate nova fonte que os distinga
#   `429`                          => `classification=deferred`, exit 1,
#                                      `retry_after=<s>` em stderr quando o
#                                      header `Retry-After` vier
#   `5xx` / erro de rede / timeout => ate 3 tentativas com backoff (`sleep`,
#                                      intervalo em `JIRA_IO_BACKOFF_SECONDS`,
#                                      default 2s, overridable p/ testes
#                                      rapidos); esgotadas => `deferred`,
#                                      exit 1
#   `400`/`409` em `--op R4`       => `classification=deferred`, exit 1
#                                      (transicao concorrente, change-notice
#                                      confirmado em contracts/jira-rest.md)
# Corpo da resposta so vai para stdout no caminho de sucesso (2xx e os
# codigos fora do escopo acima) — mesmo precedente do `3xx` (SEC-5), que
# nunca relaya corpo em erro.
#
# SEC-4 (tarefa 3.3): `request` agora envia autenticacao Basic (email + API
# token — data-model.md Entity Credential, `contracts/jira-rest.md` linha 5)
# via arquivo de config temporario do cliente HTTP (`-K`, diretiva `user =
# "email:token"`, que o cliente HTTP converte no header `Authorization`
# internamente — a credencial em si NUNCA aparece em argv). Arquivo + o
# diretorio privado que o contem sao criados com `umask 077` (elimina a
# janela de corrida entre "criar" e "restringir permissao", CWE-377) e
# removidos por `trap` em EXIT/INT/TERM — mesmo padrao "trap split" de
# `cli/lib/00c-bootstrap.sh` `_00c_release_lock` (EXIT roda a limpeza; INT/
# TERM chamam `exit` explicito, que entao dispara o EXIT trap em sequencia;
# sem o `exit` explicito, POSIX nao garante que o processo de fato termine
# so por ter um trap instalado no sinal). A credencial em si vem do arquivo
# global `${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials` (mesmo
# path de `jira-config.sh` `_JC_CRED_FILE`; existencia/permissao 0600
# conferidas via `jira-config.sh credential-check` ANTES de ler o conteudo).
#
# Subcomandos (contrato final documentado em plugin-scripts.md; os tres
# abaixo existem nesta tarefa):
#
#   jira-io.sh deps-check
#       — Confere `jq` e o cliente HTTP no PATH. Exit 5 + instrucao de
#         instalacao se faltar qualquer um dos dois (carve-out 1.1.0
#         condicao a).
#
#   jira-io.sh request METHOD PATH [--body-file F] [--op OP]
#       — METHOD restrito a allowlist FECHADA `GET`/`POST`/`PUT` — `DELETE`
#         nunca existe como opcao valida (FR-012); qualquer METHOD fora da
#         allowlist e uso incorreto (exit 2), nao erro de requisicao.
#         PATH MUST comecar com `/rest/`.
#         `--op OP` (opcional): OP em `R1`..`R11` (contracts/jira-rest.md) —
#         informa ao classificador de status (3.4, abaixo) qual operacao esta
#         sendo servida. OP fora dessa allowlist e uso incorreto (exit 2).
#         Omitido (ou fora de R1/R2) => tratamento conservador de `403` como
#         `auth_failed` (dec-073).
#         SEC-1: PATH e recusado (exit 2, SEM requisicao) se contiver `..`,
#         `//`, `\`, `@`, `#`, espaco, CR/LF ou qualquer outro byte de
#         controle, em qualquer posicao — esta e a checagem que cobre TODOS
#         os pontos de interpolacao do motor R1-R11 (contracts/jira-rest.md),
#         porque `request` e o UNICO ponto por onde qualquer chamada R1-R11
#         de fato dispara: bastando o motor futuro (jira-sync.sh/jira-map.sh,
#         FASE 4+) montar o PATH com os segmentos ja validados por
#         `validate-segment` (abaixo), esta guarda central cobre o resto.
#         Monta `https://<site_host><PATH>` com `site_host` lido de
#         `jira-config.sh get site_host` (ProjectConfig); valida por
#         IGUALDADE EXATA (sem userinfo, sem porta) o host que sera de fato
#         requisitado contra `site_host` ANTES de disparar a requisicao
#         (defesa auditavel — a URL e sempre construida aqui, nunca
#         reparseada de uma resposta).
#         SEC-5: o cliente HTTP roda SEM seguir redirect (nenhuma flag de
#         "seguir localizacao" e usada) e COM verificacao TLS sempre ativa
#         (nao existe flag neste script para desliga-la). Resposta `3xx`
#         => erro imediato, SEM disparar segunda requisicao — nao ha
#         caminhada manual de `Location` como em `cli/lib/http.sh`, porque
#         `jira-io.sh` so fala com UM host (`site_host`) por design.
#         SEC-4: ANTES de disparar a requisicao, confere `jira-config.sh
#         credential-check` (existencia + modo 0600) e le `email`/
#         `api_token` do arquivo de Credential; grava um arquivo de config
#         temporario do cliente HTTP (`umask 077`, diretorio privado,
#         removido por `trap` em EXIT/INT/TERM) com a diretiva `user =
#         "email:token"` e o passa via `-K` — a credencial NUNCA aparece em
#         argv/linha de comando do cliente HTTP nem em log.
#         Corpo da resposta em stdout; `http_status=<codigo>` na 1a linha
#         de stderr. 3.4: `401`/`403`/`429`/`5xx`-apos-retries/`400`-`409`-
#         em-R4 sao classificados (`classification=<token>` em stderr) em
#         vez de tratados como sucesso — ver bloco de comentarios 3.4 acima
#         para a tabela completa; demais codigos mantem o passthrough.
#
#   jira-io.sh validate-segment VALUE [VALUE...]
#       — SEC-1: valida cada VALUE contra a allowlist FECHADA de charset
#         `[A-Za-z0-9_-]` (nao-vazio, sem excecao). Uso pretendido: o motor
#         (jira-sync.sh/jira-map.sh, FASE 4+) chama isto para `jira_id`,
#         `jira_key` e `project_key` ANTES de interpolar qualquer PATH ou
#         JQL — nunca depois. Nao exige `jq`/cliente HTTP (deps-check nao e
#         chamado aqui): validacao de string pura, POSIX `case`. Exit 0 se
#         TODOS os VALUE casarem; exit 2 (uso incorreto) no primeiro que
#         falhar, sem revelar o valor bruto em stderr (pode conter bytes de
#         controle).
#
#   jira-io.sh json-get FILTER
#       — SEC-3: le JSON de stdin, aplica `jq -r FILTER` e imprime o
#         resultado em stdout. Wrapper de LEITURA — restringe `jq` a este
#         arquivo (nenhum outro script do plugin invoca `jq` diretamente).
#         Nao exige credencial/ProjectConfig (nao chama `_ji_cmd_deps_check`
#         completo — so confere `jq`, exit 5 se ausente). Filtro invalido ou
#         entrada nao-JSON => exit 2 (uso incorreto), sem ecoar o filtro
#         bruto em caso de erro (pode conter dado do chamador).
#
#   jira-io.sh json-build issue --project-id ID --issuetype-id ID
#                              --summary TEXT [--parent-key KEY]
#                              [--description TEXT]
#       — SEC-3: monta o corpo de R1 (`POST /rest/api/3/issue`,
#         contracts/jira-rest.md secao "Campos de request/response a partir
#         do OpenAPI oficial"): `fields.project.id`, `fields.issuetype.id`,
#         `fields.summary`, `fields.parent.key` (so se `--parent-key` vier),
#         `fields.description` em Atlassian Document Format (so se
#         `--description` vier). `--project-id`/`--issuetype-id`/
#         `--parent-key` MUST casar a mesma allowlist `[A-Za-z0-9_-]` de
#         `validate-segment` (SEC-1) — exit 2 caso contrario, SEM montar
#         corpo algum. `--summary`/`--description` sao texto livre: passam
#         por `jq --arg` (nunca concatenacao de string), preservando aspas/
#         barras/quebras de linha como JSON valido.
#
#   jira-io.sh json-build filter --name TEXT --project-key KEY
#       — SEC-3: monta o corpo de R9 (`POST /rest/api/3/filter`,
#         contracts/jira-rest.md): `{"name": TEXT, "jql": "project = \"KEY\""}`.
#         `--project-key` MUST casar a allowlist SEC-1 (mesma de
#         `validate-segment`) ANTES de entrar na JQL — exit 2 se falhar, SEM
#         montar JQL alguma; nenhum texto livre (titulo/descricao/`--name`)
#         e interpolado em `jql`. Base da JQL do filtro do board (FR-013,
#         plan.md SEC-3) — o motor de board (FASE 7) reusa este subcomando
#         em vez de montar JQL por conta propria.
#
#   jira-io.sh json-build board --name TEXT --filter-id ID --project-key KEY
#       — SEC-3: monta o corpo de R10 (`POST /rest/agile/1.0/board`,
#         contracts/jira-rest.md, campos confirmados via OpenAPI oficial da
#         Agile API, onda-029): `{"name": TEXT, "type": "kanban",
#         "filterId": <ID como numero>, "location": {"type": "project",
#         "projectKeyOrId": KEY}}`. `--filter-id` MUST ser SOMENTE digitos
#         (allowlist mais restrita que SEC-1, porque o schema oficial exige
#         `integer`/`format: int64` — nunca string) — exit 2 caso contrario,
#         SEM montar corpo algum; `--project-key` MUST casar a allowlist
#         SEC-1 (mesma de `validate-segment`). `type`/`location.type` sao
#         fixos (`kanban`/`project` — US2 so preve board kanban por projeto,
#         nunca scrum/board pessoal).
#
# Exit codes (mesma convencao de jira-config.sh):
#   0 sucesso
#   1 erro geral / falha de requisicao (rede, 3xx recusado, etc.) OU
#     `classification=deferred` (429; 5xx/rede/timeout apos ate 3
#     tentativas; 400/409 em `--op R4`) — candidato a retry pelo chamador
#   2 uso incorreto (METHOD fora da allowlist, PATH sem `/rest/`, PATH/
#     segmento fora da allowlist SEC-1, `--op` fora de R1..R11, args,
#     `json-get` com filtro/entrada invalidos, `json-build` com segmento
#     fora da allowlist SEC-1 ou campo obrigatorio ausente)
#   3 ProjectConfig ausente/inacessivel (propagado de jira-config.sh get)
#   4 credencial ausente/permissao insegura (propagado de jira-config.sh
#     credential-check) ou incompleta (falta `email`/`api_token` no arquivo)
#     OU `classification=auth_failed` (401 em qualquer operacao; 403 fora
#     de `--op R1`/`--op R2`) — nunca retry automatico (FR-016/FR-019)
#   5 dependencia ausente (`jq` fora do PATH — `json-get`/`json-build` so
#     exigem `jq`, nunca o cliente HTTP; `request`/`deps-check` exigem os
#     dois)
#   7 `classification=permission_denied` (403 em `--op R1`/`--op R2`,
#     dec-073) — credencial valida, permissao insuficiente no projeto/tipo;
#     NUNCA reconfiguracao de credencial (nao reusa o exit 6, ja reservado
#     em contracts/plugin-scripts.md para conflito/orfao de outros scripts)
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Credencial NUNCA por argv (aplicavel a partir da tarefa 3.3).

set -eu

_JI_NAME="jira-io"

_ji_die_usage() { printf '%s: %s\n' "$_JI_NAME" "$1" >&2; exit 2; }
_ji_die()       { printf '%s: %s\n' "$_JI_NAME" "$1" >&2; exit "${2:-1}"; }

_ji_usage() {
  cat <<'HELP'
jira-io.sh — cliente REST do plugin cstk-jira (unico arquivo com jq + cliente HTTP)

USO:
  jira-io.sh deps-check
      Confere jq + cliente HTTP no PATH.

  jira-io.sh request METHOD PATH [--body-file F] [--op OP]
      Requisicao HTTPS contra <site_host><PATH>. METHOD em GET/POST/PUT
      (DELETE nunca existe como opcao valida). PATH deve comecar com /rest/
      e nao pode conter .. // \ @ # espaco CR/LF/controle (SEC-1).
      Autenticacao Basic (email + API token de Credential) enviada via
      arquivo de config temporario do cliente HTTP (SEC-4) — nunca em argv.
      --op OP (opcional, R1..R11) informa a operacao para classificar 403
      (permission_denied em R1/R2, auth_failed nas demais/omitido) e 400/409
      (deferred em R4). 401/429/5xx/rede/timeout tambem sao classificados
      (classification=<token> em stderr) — ver cabecalho do script.

  jira-io.sh validate-segment VALUE [VALUE...]
      Valida cada VALUE contra a allowlist [A-Za-z0-9_-] (SEC-1), a usar
      pelo motor ANTES de interpolar jira_id/jira_key/project_key em
      PATH ou JQL.

  jira-io.sh json-get FILTER
      Le JSON de stdin, aplica 'jq -r FILTER'. Wrapper de leitura (SEC-3);
      unico ponto do plugin que invoca jq. So exige jq (nao exige cliente
      HTTP nem ProjectConfig/credencial).

  jira-io.sh json-build issue --project-id ID --issuetype-id ID
                             --summary TEXT [--parent-key KEY]
                             [--description TEXT]
      Monta o corpo de R1 (criar issue). ID/KEY passam pela allowlist
      [A-Za-z0-9_-] (SEC-1); summary/description sao texto livre, escapado
      via jq --arg.

  jira-io.sh json-build filter --name TEXT --project-key KEY
      Monta o corpo de R9 (criar filtro): {"name":..., "jql":...}. KEY
      passa pela allowlist SEC-1 ANTES de entrar na JQL (SEC-3) — nenhum
      texto livre (--name incluso) e interpolado em jql.

  jira-io.sh json-build board --name TEXT --filter-id ID --project-key KEY
      Monta o corpo de R10 (criar board kanban):
      {"name":...,"type":"kanban","filterId":<numero>,
      "location":{"type":"project","projectKeyOrId":...}}. ID (--filter-id)
      MUST ser so digitos (emitido como numero JSON, nunca string — o
      schema oficial da Agile API exige integer/int64); KEY (--project-key)
      passa pela allowlist [A-Za-z0-9_-] (SEC-1). --name e texto livre,
      escapado via jq --arg.

  jira-io.sh json-build transition --transition-id ID
      Monta o corpo de R4 (executar transicao): {"transition":{"id":ID}}.
      ID passa pela allowlist [A-Za-z0-9_-] (SEC-1).

  jira-io.sh json-build marker --local-key K --feature F
                              --written-summary-sha256 H --written-status S
                              --written-at T
      Monta o VALOR CRU do SyncMarker (R6 PUT, sem envelope {key,value} —
      a chave ja vai na URL): {"schema":1,"local_key":K,"feature":F,
      "written_summary_sha256":H,"written_status":S,"written_at":T}.
      Todos os campos sao texto livre, escapados via jq --arg (local_key/
      status podem conter pontos/espacos, ex. "4.2.1"/"In Progress").

  jira-io.sh json-build issue-update --summary TEXT [--description TEXT]
      Monta o corpo de R2 (editar issue, FR-003): {"fields":{"summary":...}}
      (+ "description" em ADF, opcional). SEM project/issuetype/parent —
      um update so envia os campos que mudam. summary/description texto
      livre, escapado via jq --arg.

  jira-io.sh sha256-stdin
      Le stdin, imprime o SHA-256 hex (sha256sum ou shasum -a 256, o que
      estiver no PATH). Usado pelo motor (jira-sync.sh, FASE 4.2.3) para
      comparar o titulo atual da issue contra `written_summary_sha256` do
      SyncMarker (data-model.md Entity SyncMarker) — so o hash e comparado/
      gravado, nunca o titulo em si (aviso oficial de nao guardar dado
      sensivel em entity property, research Decision 3).

EXIT CODES:
  0 sucesso   1 erro geral/requisicao/deferred   2 uso incorreto
  3 ProjectConfig ausente   4 credencial ausente/incompleta/auth_failed
  5 dependencia ausente   7 permission_denied (403 em R1/R2)
HELP
}

# Resolve o diretorio deste script SO quando necessario (nao no topo do
# arquivo) — deps-check nao deve exigir `dirname`/`cd` alem do que o
# proprio interprete `sh` ja oferece como builtin, mantendo o cenario de
# "PATH minimo sem jq/curl" (task 3.1.5) livre de acoplamento acidental.
_ji_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

# _ji_config_get KEY — delega a jira-config.sh (mesmo diretorio deste
# script); jira-io.sh NUNCA duplica a leitura/validacao de ProjectConfig.
_ji_config_get() {
  "$(_ji_script_dir)/jira-config.sh" get "$1"
}

# --- Credential (SEC-4, tarefa 3.3) -------------------------------------
#
# Path identico a `_JC_CRED_FILE` de jira-config.sh (data-model.md Entity
# Credential: arquivo GLOBAL unico por maquina, fora do repo). jira-io.sh
# NAO duplica a checagem de existencia/permissao (delega a `jira-config.sh
# credential-check`, que ja e a dona dessa validacao) — so LE o conteudo
# (email/api_token) apos essa checagem passar.
_JI_CRED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials"

# _ji_cred_check — delega a jira-config.sh credential-check (existencia +
# modo 0600 exato do arquivo de Credential). Nunca imprime conteudo.
_ji_cred_check() {
  "$(_ji_script_dir)/jira-config.sh" credential-check
}

# _ji_cred_read KEY — imprime o valor de KEY (`email`|`api_token`) em
# $_JI_CRED_FILE; exit 1 se a chave nao existir. Mesmo parse de
# `_jc_read_raw` em jira-config.sh (linha a linha, split no PRIMEIRO '=',
# '#'/branco ignorados) — deliberadamente NAO extraido para um helper
# compartilhado (cada script mantem sua propria copia minima, sem
# acoplamento entre os dois arquivos alem do path do arquivo e do
# subcomando `credential-check`).
_ji_cred_read() {
  _jicr_key="$1"
  _jicr_found="no"
  while IFS= read -r _jicr_line || [ -n "$_jicr_line" ]; do
    case "$_jicr_line" in
      ''|'#'*)
        : # linha em branco ou comentario — ignorada
        ;;
      *=*)
        _jicr_k=${_jicr_line%%=*}
        _jicr_v=${_jicr_line#*=}
        if [ "$_jicr_k" = "$_jicr_key" ]; then
          printf '%s\n' "$_jicr_v"
          _jicr_found="yes"
        fi
        ;;
    esac
  done < "$_JI_CRED_FILE"
  [ "$_jicr_found" = "yes" ]
}

# _ji_curlrc_escape VALUE — escapa `\` e `"` para uso dentro de um valor
# entre aspas duplas na diretiva `user = "..."` de um arquivo `-K` do
# cliente HTTP (sintaxe de config: valores entre aspas suportam escape de
# `\`/`"` — defesa contra api_token/email com esses bytes, ainda que raro).
_ji_curlrc_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# _ji_cred_cleanup — acao do trap EXIT de `request`: remove o arquivo de
# config temporario de credencial + o arquivo de resposta + o arquivo de
# headers (3.4), depois o diretorio privado (so remove se ja estiver vazio —
# `rmdir` com `|| :` porque, sob `set -eu`, uma falha de `rmdir` sendo o
# ULTIMO comando de um `&&`/`if` NAO e isenta de errexit). Variaveis podem
# estar vazias (sinal chegou antes de qualquer recurso existir) — `rm -f`/o
# guard `[ -n ... ]` cobrem esse caso sem diagnostico de erro.
_ji_cred_cleanup() {
  rm -f -- "$_jir_cred_file" "$_jir_tmp_out" "$_jir_header_file" 2>/dev/null
  if [ -n "$_jir_cred_dir" ]; then
    rmdir -- "$_jir_cred_dir" 2>/dev/null || :
  fi
}

# _ji_op_allowed OP — allowlist FECHADA da flag `--op` (3.4, dec-073): OP
# MUST ser uma das operacoes R1-R11 documentadas em contracts/jira-rest.md.
_ji_op_allowed() {
  case "$1" in
    R1|R2|R3|R4|R5|R6|R7|R8|R9|R10|R11) return 0 ;;
    *) return 1 ;;
  esac
}

# _ji_extract_retry_after HEADERFILE — le o header `Retry-After` (segundos)
# de um dump de resposta HTTP (curl `-D`), case-insensitive, ultima
# ocorrencia (RFC permite so 1, mas evita ambiguidade se houver mais de uma).
# Imprime so o valor numerico (sem CR/LF/espaco); vazio se ausente/ilegivel.
# Nunca falha sob `set -eu`: se HEADERFILE nao existir/nao tiver o header, a
# pipeline termina no `tr` (sempre exit 0), resultando em string vazia.
_ji_extract_retry_after() {
  [ -r "$1" ] || { printf ''; return 0; }
  LC_ALL=C grep -i '^Retry-After:' -- "$1" 2>/dev/null \
    | tail -n 1 \
    | sed 's/^[Rr][Ee][Tt][Rr][Yy]-[Aa][Ff][Tt][Ee][Rr]:[[:space:]]*//' \
    | tr -d '\r\n '
}

# _ji_fail_status STATUS CLASSIFICATION EXITCODE MSG [RETRY_AFTER]
# — 3.4: encerra `request` com o protocolo estruturado de classificacao de
# falha (dec-073): `http_status=<STATUS>` (omitido se STATUS vazio, caso do
# erro de rede puro sem resposta HTTP), `classification=<CLASSIFICATION>`,
# `retry_after=<n>` (so quando o 5o argumento vier nao-vazio), e por fim a
# mensagem humana + exit code via `_ji_die` (mesma convencao das demais
# falhas deste script).
_ji_fail_status() {
  _jifs_status="$1"
  _jifs_class="$2"
  _jifs_exit="$3"
  _jifs_msg="$4"
  _jifs_retry_after="${5:-}"
  [ -n "$_jifs_status" ] && printf 'http_status=%s\n' "$_jifs_status" >&2
  printf 'classification=%s\n' "$_jifs_class" >&2
  [ -n "$_jifs_retry_after" ] && printf 'retry_after=%s\n' "$_jifs_retry_after" >&2
  _ji_die "$_jifs_msg" "$_jifs_exit"
}

_ji_cmd_deps_check() {
  _jidc_missing=""
  command -v jq   >/dev/null 2>&1 || _jidc_missing="$_jidc_missing jq"
  command -v curl >/dev/null 2>&1 || _jidc_missing="$_jidc_missing curl"
  if [ -n "$_jidc_missing" ]; then
    _ji_die "dependencia(s) ausente(s) no PATH:$_jidc_missing — instale (ex.: 'brew install jq curl' no macOS, 'apt-get install jq curl' em distros Debian/Ubuntu) e reexecute" 5
  fi
  return 0
}

# _ji_require_jq — 3.5: `json-get`/`json-build` so precisam de `jq` (nunca do
# cliente HTTP nem de ProjectConfig/credencial) — checagem dedicada, mais
# estreita que `_ji_cmd_deps_check` (que tambem exige o cliente HTTP).
_ji_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _ji_die "dependencia ausente no PATH: jq — instale (ex.: 'brew install jq' no macOS, 'apt-get install jq' em distros Debian/Ubuntu) e reexecute" 5
}

# _ji_require_sha256 — `sha256-stdin` (FASE 4.2.3, dec-081) so precisa de UM
# utilitario de hash (nem jq nem cliente HTTP). `sha256sum` (coreutils/
# Linux) tem precedencia; `shasum -a 256` (macOS default) e o fallback —
# mesma deteccao/precedencia de `cli/lib/compat.sh` `sha256_stdin` no resto
# do toolkit (nao reusada aqui: este plugin e distribuido separadamente e
# nao depende de `cli/lib/`, carve-out 1.1.0 confinado a este arquivo).
# Preenche `_JI_SHA_TOOL` com o nome do binario escolhido.
_ji_require_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    _JI_SHA_TOOL="sha256sum"
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    _JI_SHA_TOOL="shasum"
    return 0
  fi
  _ji_die "dependencia ausente no PATH: sha256sum ou shasum — instale (ex.: coreutils no Linux; shasum ja vem por padrao no macOS) e reexecute" 5
}

# _ji_cmd_sha256_stdin — le stdin, imprime SHA-256 hex (40... 64 chars) +
# newline. So os primeiros 64 chars da 1a coluna do output do binario
# (sha256sum/shasum imprimem "<hash>  -" ou "<hash>  <arquivo>").
_ji_cmd_sha256_stdin() {
  _ji_require_sha256
  if [ "$_JI_SHA_TOOL" = "sha256sum" ]; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# _ji_method_allowed METHOD — allowlist FECHADA (FR-012): DELETE nunca
# existe como opcao valida, mesmo digitado corretamente.
_ji_method_allowed() {
  case "$1" in
    GET|POST|PUT) return 0 ;;
    *) return 1 ;;
  esac
}

# _ji_charset_ok VALUE — SEC-1: allowlist FECHADA [A-Za-z0-9_-], nao-vazio.
# POSIX puro (case + bracket expression), sem dependencia externa. Usado
# tanto por `validate-segment` quanto (potencialmente) por chamadores
# futuros que queiram validar um valor isolado antes de montar PATH/JQL.
_ji_charset_ok() {
  [ -n "$1" ] || return 1
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# _ji_digits_ok VALUE — SEC-1 (mais restrita que _ji_charset_ok): allowlist
# FECHADA [0-9], nao-vazio. Usado por `json-build board --filter-id` (R10,
# contracts/jira-rest.md onda-029) porque o schema oficial da Agile API
# exige `filterId` como `integer`/`format: int64` — nunca string. Um valor
# fora deste charset NUNCA vira `--argjson` (evita jq falhar tentando
# converter texto arbitrario em numero, ou pior, jq interpretar o valor
# como expressao).
_ji_digits_ok() {
  [ -n "$1" ] || return 1
  case "$1" in
    *[!0-9]*) return 1 ;;
  esac
  return 0
}

# _ji_path_has_forbidden_bytes PATH — SEC-1: verdadeiro (exit 0) se PATH
# contiver qualquer um dos padroes/bytes proibidos: `..`, `//`, `\`, `@`,
# `#`, espaco, ou qualquer byte de controle (inclui CR/LF). Aplicado ao
# PATH inteiro recebido por `request` — como `request` e o UNICO ponto de
# disparo de requisicao (deps-check nao conta), esta e a guarda central que
# cobre todos os pontos de interpolacao do motor (R1-R11), independente de
# onde/como o PATH foi montado antes de chegar aqui.
_ji_path_has_forbidden_bytes() {
  case "$1" in
    *..*|*//*|*"\\"*|*@*|*"#"*|*" "*) return 0 ;;
  esac
  # LF: printf '%s' sem terminador; wc -l so conta se ha \n EMBUTIDO no meio
  # do valor (nao um trailing newline artificial, que nao existe aqui).
  _jipfb_lines=$(printf '%s' "$1" | wc -l | tr -d ' ')
  [ "$_jipfb_lines" -gt 0 ] && return 0
  # CR e qualquer outro byte de controle (grep opera por linha; LF ja foi
  # coberto acima porque grep nunca veria o \n como dado de uma linha).
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    return 0
  fi
  return 1
}

_ji_cmd_request() {
  _ji_cmd_deps_check

  [ "$#" -ge 2 ] || _ji_die_usage "request requer METHOD e PATH"
  _jir_method="$1"
  _jir_path="$2"
  shift 2

  _jir_body_file=""
  _jir_op=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --body-file)
        [ "$#" -ge 2 ] || _ji_die_usage "--body-file requer argumento"
        _jir_body_file="$2"
        shift 2
        ;;
      --op)
        [ "$#" -ge 2 ] || _ji_die_usage "--op requer argumento"
        _jir_op="$2"
        shift 2
        ;;
      *)
        _ji_die_usage "argumento desconhecido: $1"
        ;;
    esac
  done

  # 3.4/dec-073: --op (opcional) informa qual operacao R-n esta sendo
  # servida, para classificar 403 (permission_denied em R1/R2) e 400/409
  # (deferred em R4). Fora da allowlist fechada => uso incorreto (exit 2).
  if [ -n "$_jir_op" ]; then
    _ji_op_allowed "$_jir_op" || _ji_die_usage \
      "--op invalido: $_jir_op (permitido: R1..R11 — contracts/jira-rest.md)"
  fi

  _ji_method_allowed "$_jir_method" || _ji_die_usage \
    "METHOD invalido: $_jir_method (permitido: GET, POST, PUT — DELETE nunca existe como opcao valida, FR-012)"

  case "$_jir_path" in
    /rest/*) : ;;
    *) _ji_die_usage "PATH deve comecar com /rest/: $_jir_path" ;;
  esac

  # SEC-1 (tarefa 3.2): recusa PATH com byte/sequencia proibida SEM disparar
  # requisicao. Valor bruto NAO e ecoado (pode conter CR/LF/controle).
  if _ji_path_has_forbidden_bytes "$_jir_path"; then
    _ji_die_usage "PATH contem byte/sequencia proibida (.. // \\ @ # espaco CR/LF/controle) — recusado sem requisicao (SEC-1)"
  fi

  if [ -n "$_jir_body_file" ] && [ ! -r "$_jir_body_file" ]; then
    _ji_die_usage "--body-file nao legivel: $_jir_body_file"
  fi

  _jir_site_host=$(_ji_config_get site_host) \
    || _ji_die "nao foi possivel obter site_host de ProjectConfig" 3
  [ -n "$_jir_site_host" ] || _ji_die "site_host vazio em ProjectConfig" 3

  _jir_url="https://${_jir_site_host}${_jir_path}"

  # SEC-5 / defesa-em-profundidade (asserção auditavel, FR-015): o host
  # efetivamente presente na URL montada MUST ser byte-a-byte igual a
  # site_host — a URL e sempre construida aqui a partir do literal de
  # ProjectConfig, nunca reparseada de uma resposta ou de outra fonte;
  # esta checagem existe para que uma futura mudanca acidental na
  # montagem da URL (ex.: reintroduzir `-L`/seguir Location) seja pega
  # por este teste antes de qualquer requisicao real.
  _jir_after_scheme=${_jir_url#https://}
  _jir_url_host=${_jir_after_scheme%%/*}
  if [ "$_jir_url_host" != "$_jir_site_host" ]; then
    _ji_die "host divergente detectado antes da requisicao (esperado '$_jir_site_host', obtido '$_jir_url_host') — abortado sem requisicao" 1
  fi

  # SEC-4 (tarefa 3.3): declarar os recursos temporarios ANTES de instalar
  # o trap unico — cobre EXIT/INT/TERM mesmo que um sinal chegue antes de
  # qualquer recurso existir. Trap "split" (mesmo padrao de
  # cli/lib/00c-bootstrap.sh `_00c_release_lock`): EXIT roda a limpeza;
  # INT/TERM chamam `exit` explicito, que entao dispara o EXIT trap em
  # sequencia — sem o `exit` explicito, um sinal fatal por convencao (INT/
  # TERM) NAO teria garantia de terminar so por ter a acao instalada.
  _jir_cred_dir=""
  _jir_cred_file=""
  _jir_tmp_out=""
  _jir_header_file=""
  trap '_ji_cred_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  _ji_cred_check \
    || _ji_die "credencial rejeitada (ausente ou permissao insegura) — rode 'jira-config.sh credential-check' para diagnostico" 4

  _jir_email=$(_ji_cred_read email) \
    || _ji_die "credencial incompleta: campo 'email' ausente em $_JI_CRED_FILE" 4
  _jir_api_token=$(_ji_cred_read api_token) \
    || _ji_die "credencial incompleta: campo 'api_token' ausente em $_JI_CRED_FILE" 4
  [ -n "$_jir_email" ] \
    || _ji_die "credencial incompleta: campo 'email' vazio em $_JI_CRED_FILE" 4
  [ -n "$_jir_api_token" ] \
    || _ji_die "credencial incompleta: campo 'api_token' vazio em $_JI_CRED_FILE" 4

  # `umask 077` ANTES de criar diretorio E arquivo — elimina a janela de
  # corrida entre "criar" e "restringir permissao" (CWE-377/SEC-4).
  # `mktemp -d` ja cria com 0700 nos dois lados (GNU/BSD); o umask garante
  # o mesmo para o ARQUIVO criado logo abaixo por redirecionamento simples.
  _jir_orig_umask=$(umask)
  umask 077
  _jir_cred_dir=$(mktemp -d "${TMPDIR:-/tmp}/jira-io-cred.XXXXXX") \
    || _ji_die "falha ao criar diretorio temporario de credencial" 1
  _jir_cred_file="$_jir_cred_dir/curlrc"
  _jir_email_esc=$(_ji_curlrc_escape "$_jir_email")
  _jir_token_esc=$(_ji_curlrc_escape "$_jir_api_token")
  printf 'user = "%s:%s"\n' "$_jir_email_esc" "$_jir_token_esc" > "$_jir_cred_file"
  umask "$_jir_orig_umask"

  _jir_tmp_out=$(mktemp "${TMPDIR:-/tmp}/jira-io.XXXXXX") \
    || _ji_die "falha ao criar arquivo temporario de resposta" 1
  _jir_header_file=$(mktemp "${TMPDIR:-/tmp}/jira-io-headers.XXXXXX") \
    || _ji_die "falha ao criar arquivo temporario de headers" 1

  # 3.4: `5xx`/erro de rede/timeout ganham ate 3 tentativas com backoff
  # (`sleep` entre tentativas, NUNCA apos a ultima) antes de virar
  # `deferred` — `JIRA_IO_BACKOFF_SECONDS` permite testes rapidos (default
  # 2s em producao). `429`/`401`/`403`/etc. NAO entram neste loop: uma
  # unica tentativa basta para classifica-los (abaixo).
  _jir_max_attempts=3
  _jir_backoff_seconds="${JIRA_IO_BACKOFF_SECONDS:-2}"
  _jir_attempt=1
  _jir_network_fail="no"
  while :; do
    _jir_ec=0
    : > "$_jir_header_file"
    # Sem `-L` (SEC-5: nunca seguir redirect) e sem `-k`/`--insecure` (TLS
    # sempre verificado — nao ha flag neste script para desativar). `-K`
    # carrega a credencial (SEC-4) — NUNCA aparece como argv literal. `-D`
    # captura os headers de resposta (3.4: le `Retry-After` em 429).
    if [ -n "$_jir_body_file" ]; then
      _jir_status=$(curl -sS --connect-timeout 10 --max-time 60 \
        -K "$_jir_cred_file" \
        -X "$_jir_method" \
        -H 'Accept: application/json' -H 'Content-Type: application/json' \
        --data-binary "@${_jir_body_file}" \
        -D "$_jir_header_file" \
        -o "$_jir_tmp_out" -w '%{http_code}' \
        -- "$_jir_url") || _jir_ec=$?
    else
      _jir_status=$(curl -sS --connect-timeout 10 --max-time 60 \
        -K "$_jir_cred_file" \
        -X "$_jir_method" \
        -H 'Accept: application/json' \
        -D "$_jir_header_file" \
        -o "$_jir_tmp_out" -w '%{http_code}' \
        -- "$_jir_url") || _jir_ec=$?
    fi

    if [ "$_jir_ec" -ne 0 ]; then
      _jir_network_fail="yes"
    else
      case "$_jir_status" in
        5??) _jir_network_fail="yes" ;;
        *) _jir_network_fail="no" ;;
      esac
    fi

    [ "$_jir_network_fail" = "no" ] && break
    [ "$_jir_attempt" -ge "$_jir_max_attempts" ] && break
    sleep "$_jir_backoff_seconds" 2>/dev/null || :
    _jir_attempt=$((_jir_attempt + 1))
  done

  if [ "$_jir_network_fail" = "yes" ]; then
    if [ "$_jir_ec" -ne 0 ]; then
      _ji_fail_status "" deferred 1 \
        "requisicao falhou apos $_jir_attempt tentativa(s) (cliente HTTP exit $_jir_ec, deferred, backoff esgotado): $_jir_method $_jir_path"
    else
      _ji_fail_status "$_jir_status" deferred 1 \
        "resposta $_jir_status apos $_jir_attempt tentativa(s) (deferred, backoff esgotado): $_jir_method $_jir_path"
    fi
  fi

  case "$_jir_status" in
    3??)
      _ji_die "resposta $_jir_status (redirecionamento) recusada SEM nova requisicao — SEC-5 nunca segue Location: $_jir_method $_jir_path" 1
      ;;
    401)
      _ji_fail_status "$_jir_status" auth_failed 4 \
        "resposta 401 (auth_failed) — credencial invalida/expirada, nunca retry automatico (FR-016/FR-019): $_jir_method $_jir_path"
      ;;
    403)
      if [ "$_jir_op" = "R1" ] || [ "$_jir_op" = "R2" ]; then
        _ji_fail_status "$_jir_status" permission_denied 7 \
          "resposta 403 em $_jir_op (permission_denied) — credencial valida, permissao insuficiente no projeto/tipo, NUNCA reconfigurar credencial: $_jir_method $_jir_path"
      else
        _ji_fail_status "$_jir_status" auth_failed 4 \
          "resposta 403 fora de R1/R2 (sem fonte que distinga) — tratado como auth_failed ate nova fonte: $_jir_method $_jir_path"
      fi
      ;;
    429)
      _jir_retry_after=$(_ji_extract_retry_after "$_jir_header_file")
      _ji_fail_status "$_jir_status" deferred 1 \
        "resposta 429 (deferred) — rate limit, respeitar Retry-After quando presente: $_jir_method $_jir_path" \
        "$_jir_retry_after"
      ;;
    400|409)
      if [ "$_jir_op" = "R4" ]; then
        _ji_fail_status "$_jir_status" deferred 1 \
          "resposta $_jir_status em transicao concorrente (R4, deferred) — candidato a retry (change-notice confirmado): $_jir_method $_jir_path"
      fi
      ;;
  esac

  printf 'http_status=%s\n' "$_jir_status" >&2
  cat -- "$_jir_tmp_out"
  return 0
}

# _ji_cmd_validate_segment VALUE [VALUE...] — SEC-1: valida cada VALUE
# contra a allowlist FECHADA [A-Za-z0-9_-]. Nao exige jq/cliente HTTP (nao
# chama _ji_cmd_deps_check). Uso pretendido: o motor (jira-sync.sh/
# jira-map.sh) chama isto para jira_id/jira_key/project_key ANTES de montar
# PATH ou JQL — a mesma allowlist que `request` reforca no PATH inteiro.
_ji_cmd_validate_segment() {
  [ "$#" -ge 1 ] || _ji_die_usage "validate-segment requer ao menos 1 VALUE"
  for _jivs_val in "$@"; do
    _ji_charset_ok "$_jivs_val" \
      || _ji_die_usage "segmento fora da allowlist [A-Za-z0-9_-] (SEC-1) — jira_id/jira_key/project_key devem casar esse charset antes de qualquer interpolacao em PATH ou JQL"
  done
  return 0
}

# _ji_cmd_json_get FILTER — 3.5 (SEC-3): le JSON de stdin, aplica
# `jq -r FILTER`. Wrapper de LEITURA — restringe `jq` a este arquivo (nenhum
# outro script do plugin invoca `jq` diretamente). So exige `jq` (nunca o
# cliente HTTP nem ProjectConfig/credencial). Filtro invalido ou entrada
# nao-JSON => exit 2 (uso incorreto); o FILTER bruto nao e ecoado no erro
# (pode conter dado sensivel vindo do chamador).
_ji_cmd_json_get() {
  [ "$#" -eq 1 ] || _ji_die_usage "json-get requer exatamente 1 FILTER"
  _jig_filter="$1"
  _ji_require_jq
  jq -r "$_jig_filter" 2>/dev/null \
    || _ji_die_usage "json-get: filtro invalido ou entrada em stdin nao e JSON valido"
  return 0
}

# _ji_cmd_json_build MODE [ARGS...] — 3.5 (SEC-3): dispatcher interno de
# `json-build`. MODE em {issue, filter, board, transition, marker} —
# allowlist FECHADA (mesmo estilo de `_ji_method_allowed`/`_ji_op_allowed`).
_ji_cmd_json_build() {
  _jib_mode="${1:-}"
  if [ "$#" -ge 1 ]; then
    shift
  fi
  case "$_jib_mode" in
    issue)
      _ji_cmd_json_build_issue "$@"
      ;;
    filter)
      _ji_cmd_json_build_filter "$@"
      ;;
    board)
      _ji_cmd_json_build_board "$@"
      ;;
    transition)
      _ji_cmd_json_build_transition "$@"
      ;;
    marker)
      _ji_cmd_json_build_marker "$@"
      ;;
    issue-update)
      _ji_cmd_json_build_issue_update "$@"
      ;;
    '')
      _ji_die_usage "json-build requer MODE (issue, filter, board, transition, marker, issue-update)"
      ;;
    *)
      _ji_die_usage "json-build: MODE desconhecido: $_jib_mode (validos: issue, filter, board, transition, marker, issue-update)"
      ;;
  esac
}

# _ji_cmd_json_build_issue --project-id ID --issuetype-id ID --summary TEXT
#                          [--parent-key KEY] [--description TEXT]
# — 3.5 (SEC-3): monta o corpo de R1 (`POST /rest/api/3/issue`,
# contracts/jira-rest.md). `--project-id`/`--issuetype-id`/`--parent-key`
# MUST casar a allowlist [A-Za-z0-9_-] (SEC-1) — a mesma de
# `validate-segment` — ANTES de entrar no corpo; `--summary`/`--description`
# sao texto livre, passados a `jq --arg` (NUNCA concatenacao de string), o
# que preserva aspas/barras/quebras de linha como JSON valido.
_ji_cmd_json_build_issue() {
  _jbi_project_id=""
  _jbi_issuetype_id=""
  _jbi_summary=""
  _jbi_parent_key=""
  _jbi_description=""
  _jbi_have_summary="no"
  _jbi_have_parent="no"
  _jbi_have_description="no"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project-id)
        [ "$#" -ge 2 ] || _ji_die_usage "--project-id requer argumento"
        _jbi_project_id="$2"
        shift 2
        ;;
      --issuetype-id)
        [ "$#" -ge 2 ] || _ji_die_usage "--issuetype-id requer argumento"
        _jbi_issuetype_id="$2"
        shift 2
        ;;
      --summary)
        [ "$#" -ge 2 ] || _ji_die_usage "--summary requer argumento"
        _jbi_summary="$2"
        _jbi_have_summary="yes"
        shift 2
        ;;
      --parent-key)
        [ "$#" -ge 2 ] || _ji_die_usage "--parent-key requer argumento"
        _jbi_parent_key="$2"
        _jbi_have_parent="yes"
        shift 2
        ;;
      --description)
        [ "$#" -ge 2 ] || _ji_die_usage "--description requer argumento"
        _jbi_description="$2"
        _jbi_have_description="yes"
        shift 2
        ;;
      *)
        _ji_die_usage "json-build issue: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_jbi_project_id" ] \
    || _ji_die_usage "json-build issue requer --project-id"
  [ -n "$_jbi_issuetype_id" ] \
    || _ji_die_usage "json-build issue requer --issuetype-id"
  [ "$_jbi_have_summary" = "yes" ] \
    || _ji_die_usage "json-build issue requer --summary"

  # SEC-1: ids/keys ANTES de entrar no corpo — mesma allowlist de
  # `validate-segment`. Falha SEM montar corpo algum (nenhuma chamada a jq).
  _ji_charset_ok "$_jbi_project_id" \
    || _ji_die_usage "--project-id fora da allowlist [A-Za-z0-9_-] (SEC-1)"
  _ji_charset_ok "$_jbi_issuetype_id" \
    || _ji_die_usage "--issuetype-id fora da allowlist [A-Za-z0-9_-] (SEC-1)"
  if [ "$_jbi_have_parent" = "yes" ]; then
    _ji_charset_ok "$_jbi_parent_key" \
      || _ji_die_usage "--parent-key fora da allowlist [A-Za-z0-9_-] (SEC-1)"
  fi

  _ji_require_jq

  _jbi_have_parent_json="false"
  [ "$_jbi_have_parent" = "yes" ] && _jbi_have_parent_json="true"
  _jbi_have_description_json="false"
  [ "$_jbi_have_description" = "yes" ] && _jbi_have_description_json="true"

  jq -n \
    --arg pid "$_jbi_project_id" \
    --arg tid "$_jbi_issuetype_id" \
    --arg summary "$_jbi_summary" \
    --arg parent_key "$_jbi_parent_key" \
    --arg description "$_jbi_description" \
    --argjson have_parent "$_jbi_have_parent_json" \
    --argjson have_description "$_jbi_have_description_json" \
    '{fields: {project: {id: $pid}, issuetype: {id: $tid}, summary: $summary}}
     | if $have_parent then .fields.parent = {key: $parent_key} else . end
     | if $have_description then
         .fields.description = {
           type: "doc",
           version: 1,
           content: [{type: "paragraph", content: [{type: "text", text: $description}]}]
         }
       else . end'
}

# _ji_cmd_json_build_issue_update --summary TEXT [--description TEXT] —
# feature cstk-jira FASE 10 tarefa 10.2 (FR-003): monta o corpo de R2
# (`PUT /rest/api/3/issue/{issueIdOrKey}`, `contracts/jira-rest.md` R2 —
# mesmo schema `IssueUpdateDetails` de R1, mas so os campos que MUDAM: uma
# edicao nunca precisa reenviar `project`/`issuetype`). Deliberadamente SEM
# `--project-id`/`--issuetype-id`/`--parent-key` (imutaveis num update de
# summary/description — reenvia-los seria dado nao-tocado, alem de exigir
# resolucao de IDs que o chamador de update nao tem motivo para buscar de
# novo). summary/description via `jq --arg` (nunca concatenacao de string,
# mesma disciplina de `json-build issue`); description usa a MESMA forma ADF
# (paragrafo unico).
_ji_cmd_json_build_issue_update() {
  _jbu_summary=""
  _jbu_description=""
  _jbu_have_summary="no"
  _jbu_have_description="no"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --summary)
        [ "$#" -ge 2 ] || _ji_die_usage "--summary requer argumento"
        _jbu_summary="$2"
        _jbu_have_summary="yes"
        shift 2
        ;;
      --description)
        [ "$#" -ge 2 ] || _ji_die_usage "--description requer argumento"
        _jbu_description="$2"
        _jbu_have_description="yes"
        shift 2
        ;;
      *)
        _ji_die_usage "json-build issue-update: argumento desconhecido: $1"
        ;;
    esac
  done

  [ "$_jbu_have_summary" = "yes" ] \
    || _ji_die_usage "json-build issue-update requer --summary"

  _ji_require_jq

  _jbu_have_description_json="false"
  [ "$_jbu_have_description" = "yes" ] && _jbu_have_description_json="true"

  jq -n \
    --arg summary "$_jbu_summary" \
    --arg description "$_jbu_description" \
    --argjson have_description "$_jbu_have_description_json" \
    '{fields: {summary: $summary}}
     | if $have_description then
         .fields.description = {
           type: "doc",
           version: 1,
           content: [{type: "paragraph", content: [{type: "text", text: $description}]}]
         }
       else . end'
}

# _ji_cmd_json_build_filter --name TEXT --project-key KEY — 3.5 (SEC-3):
# monta o corpo de R9 (`POST /rest/api/3/filter`, contracts/jira-rest.md):
# `{"name": TEXT, "jql": "project = \"KEY\""}`. `--project-key` MUST casar a
# allowlist [A-Za-z0-9_-] (SEC-1) ANTES de entrar na JQL — recusado (exit 2)
# SEM montar JQL alguma; `--name` (texto livre) NUNCA e interpolado em
# `jql` (so entra no campo `name` via `jq --arg`).
_ji_cmd_json_build_filter() {
  _jbf_name=""
  _jbf_project_key=""
  _jbf_have_name="no"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        [ "$#" -ge 2 ] || _ji_die_usage "--name requer argumento"
        _jbf_name="$2"
        _jbf_have_name="yes"
        shift 2
        ;;
      --project-key)
        [ "$#" -ge 2 ] || _ji_die_usage "--project-key requer argumento"
        _jbf_project_key="$2"
        shift 2
        ;;
      *)
        _ji_die_usage "json-build filter: argumento desconhecido: $1"
        ;;
    esac
  done

  [ "$_jbf_have_name" = "yes" ] \
    || _ji_die_usage "json-build filter requer --name"
  [ -n "$_jbf_project_key" ] \
    || _ji_die_usage "json-build filter requer --project-key"

  # SEC-3: --project-key MUST passar pela allowlist SEC-1 ANTES de entrar na
  # JQL — nenhum texto livre (ex.: titulo/descricao) e aceito aqui. Falha
  # SEM montar JQL alguma.
  _ji_charset_ok "$_jbf_project_key" \
    || _ji_die_usage "--project-key fora da allowlist [A-Za-z0-9_-] (SEC-1) — recusado antes de montar JQL (SEC-3)"

  _ji_require_jq

  _jbf_jql="project = \"${_jbf_project_key}\""
  jq -n --arg name "$_jbf_name" --arg jql "$_jbf_jql" '{name: $name, jql: $jql}'
}

# _ji_cmd_json_build_board --name TEXT --filter-id ID --project-key KEY —
# FASE 7 tarefa 7.1 (contracts/jira-rest.md R10, campos confirmados via
# OpenAPI oficial da Agile API onda-029): monta
# {"name":TEXT,"type":"kanban","filterId":<ID numero>,
# "location":{"type":"project","projectKeyOrId":KEY}}. `--filter-id` MUST
# ser SOMENTE digitos (`_ji_digits_ok` — o schema exige integer/int64,
# nunca string) e e emitido via `--argjson` (nunca `--arg`, que produziria
# uma string JSON). `--project-key` MUST casar a allowlist SEC-1 (mesma de
# `validate-segment`/`json-build filter`). `--name` e texto livre, escapado
# via `jq --arg`. `type`/`location.type` sao fixos: a spec (US2) so preve
# board kanban por projeto, nunca scrum/board pessoal (`location.type=user`).
_ji_cmd_json_build_board() {
  _jbb_name=""
  _jbb_filter_id=""
  _jbb_project_key=""
  _jbb_have_name="no"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        [ "$#" -ge 2 ] || _ji_die_usage "--name requer argumento"
        _jbb_name="$2"
        _jbb_have_name="yes"
        shift 2
        ;;
      --filter-id)
        [ "$#" -ge 2 ] || _ji_die_usage "--filter-id requer argumento"
        _jbb_filter_id="$2"
        shift 2
        ;;
      --project-key)
        [ "$#" -ge 2 ] || _ji_die_usage "--project-key requer argumento"
        _jbb_project_key="$2"
        shift 2
        ;;
      *)
        _ji_die_usage "json-build board: argumento desconhecido: $1"
        ;;
    esac
  done

  [ "$_jbb_have_name" = "yes" ] \
    || _ji_die_usage "json-build board requer --name"
  [ -n "$_jbb_filter_id" ] \
    || _ji_die_usage "json-build board requer --filter-id"
  [ -n "$_jbb_project_key" ] \
    || _ji_die_usage "json-build board requer --project-key"

  _ji_digits_ok "$_jbb_filter_id" \
    || _ji_die_usage "--filter-id fora da allowlist [0-9] (SEC-1) — schema exige integer/int64"
  _ji_charset_ok "$_jbb_project_key" \
    || _ji_die_usage "--project-key fora da allowlist [A-Za-z0-9_-] (SEC-1)"

  _ji_require_jq
  jq -n --arg name "$_jbb_name" --argjson filterId "$_jbb_filter_id" \
        --arg projectKeyOrId "$_jbb_project_key" \
    '{name: $name, type: "kanban", filterId: $filterId,
      location: {type: "project", projectKeyOrId: $projectKeyOrId}}'
}

# _ji_cmd_json_build_transition --transition-id ID — FASE 4.2.5 (dec-081):
# monta o corpo de R4 (`POST .../transitions`, contracts/jira-rest.md):
# {"transition":{"id":ID}}. ID MUST casar a allowlist [A-Za-z0-9_-] (SEC-1)
# — mesma disciplina de --project-id/--issuetype-id em `json-build issue`.
_ji_cmd_json_build_transition() {
  _jbt_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --transition-id)
        [ "$#" -ge 2 ] || _ji_die_usage "--transition-id requer argumento"
        _jbt_id="$2"
        shift 2
        ;;
      *)
        _ji_die_usage "json-build transition: argumento desconhecido: $1"
        ;;
    esac
  done
  [ -n "$_jbt_id" ] || _ji_die_usage "json-build transition requer --transition-id"
  _ji_charset_ok "$_jbt_id" \
    || _ji_die_usage "--transition-id fora da allowlist [A-Za-z0-9_-] (SEC-1)"

  _ji_require_jq
  jq -n --arg id "$_jbt_id" '{transition: {id: $id}}'
}

# _ji_cmd_json_build_marker --local-key K --feature F
#                          --written-summary-sha256 H --written-status S
#                          --written-at T — FASE 4.2.5 (dec-081): monta o
# VALOR CRU do SyncMarker (R6 PUT — contracts/jira-rest.md R6 confirma que
# o corpo e o `value` sem envelope, a chave ja vai na URL; data-model.md
# Entity SyncMarker define os campos). `schema` e fixo em 1 (unica versao
# ate agora). Todos os campos sao texto livre (local_key pode conter pontos,
# ex. "4.2.1"; written_status pode conter espacos, ex. "In Progress") —
# escapados via jq --arg, NUNCA concatenacao de string (SEC-3).
_ji_cmd_json_build_marker() {
  _jbm_local_key=""
  _jbm_feature=""
  _jbm_sha=""
  _jbm_status=""
  _jbm_at=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --local-key)
        [ "$#" -ge 2 ] || _ji_die_usage "--local-key requer argumento"
        _jbm_local_key="$2"; shift 2 ;;
      --feature)
        [ "$#" -ge 2 ] || _ji_die_usage "--feature requer argumento"
        _jbm_feature="$2"; shift 2 ;;
      --written-summary-sha256)
        [ "$#" -ge 2 ] || _ji_die_usage "--written-summary-sha256 requer argumento"
        _jbm_sha="$2"; shift 2 ;;
      --written-status)
        [ "$#" -ge 2 ] || _ji_die_usage "--written-status requer argumento"
        _jbm_status="$2"; shift 2 ;;
      --written-at)
        [ "$#" -ge 2 ] || _ji_die_usage "--written-at requer argumento"
        _jbm_at="$2"; shift 2 ;;
      *)
        _ji_die_usage "json-build marker: argumento desconhecido: $1"
        ;;
    esac
  done
  [ -n "$_jbm_local_key" ] || _ji_die_usage "json-build marker requer --local-key"
  [ -n "$_jbm_feature" ] || _ji_die_usage "json-build marker requer --feature"
  [ -n "$_jbm_sha" ] || _ji_die_usage "json-build marker requer --written-summary-sha256"
  [ -n "$_jbm_status" ] || _ji_die_usage "json-build marker requer --written-status"
  [ -n "$_jbm_at" ] || _ji_die_usage "json-build marker requer --written-at"

  _ji_require_jq
  jq -n --argjson schema 1 \
    --arg local_key "$_jbm_local_key" \
    --arg feature "$_jbm_feature" \
    --arg sha "$_jbm_sha" \
    --arg status "$_jbm_status" \
    --arg at "$_jbm_at" \
    '{schema: $schema, local_key: $local_key, feature: $feature,
      written_summary_sha256: $sha, written_status: $status, written_at: $at}'
}

# --- dispatcher ---------------------------------------------------------

_ji_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_ji_sub" in
  ''|-h|--help|help)
    _ji_usage
    exit 0
    ;;
  deps-check)
    _ji_cmd_deps_check "$@"
    ;;
  validate-segment)
    _ji_cmd_validate_segment "$@"
    ;;
  request)
    _ji_cmd_request "$@"
    ;;
  json-get)
    _ji_cmd_json_get "$@"
    ;;
  json-build)
    _ji_cmd_json_build "$@"
    ;;
  sha256-stdin)
    _ji_cmd_sha256_stdin "$@"
    ;;
  *)
    _ji_die_usage "subcomando desconhecido: $_ji_sub (validos: deps-check, request, validate-segment, json-get, json-build, sha256-stdin)"
    ;;
esac
