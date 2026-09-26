# Tarefas cstk-jira - Plugin de integracao com Jira Cloud

Escopo: plugin `plugins/cstk-jira/` que converte uma feature documentada
(spec + tasks.md) em Epic > Task > Sub-task no Jira Cloud, mantem um board
dedicado por projeto-alvo e sincroniza status durante execucoes autonomas
`feature-00c`/`agente-00c` — conforme `spec.md`, `plan.md`, `data-model.md`,
`quickstart.md` e `contracts/{jira-rest,rovo-mcp,hooks,plugin-scripts}.md`.

**Legenda de status:**
- `[ ]` Pendente
- `[~]` Em andamento
- `[x]` Concluido
- `[!]` Bloqueado

**Legenda de criticidade:**
- `[C]` Critico - Impacto financeiro, regulatorio ou de seguranca
- `[A]` Alto - Funcionalidade core sem a qual o plugin nao opera
- `[M]` Medio - Necessario mas pode ser adiado sem impacto imediato

**Tier de entrega usado na geracao deste backlog**: nao aplicavel (feature
`cstk-jira` nao foi gerada com tier de entrega citado nos args da invocacao;
backlog completo, sem omissao de fases — `/feature-00c` nunca propaga tier).

---

## FASE 0 - Reconferencia Bloqueante do Contrato REST `[C]`

Ref: plan.md Constitution Check (Principio VI "PASS condicionado");
`contracts/jira-rest.md` "Continua fora do contrato apos a onda-005";
`quickstart.md` Cenario 6; checklists/api.md CHK003/CHK004/CHK007.

Bloqueante: NENHUMA tarefa de FASE 3 (cliente REST) pode comecar antes desta
fase confirmar (ou corrigir) os campos ainda marcados `(exemplo)`/RECONFERIR/
NAO ENCONTRADO. Executada uma unica vez, contra um site Jira Cloud de teste
do operador (nunca produtivo).

### 0.1 Roundtrip real contra Jira Cloud de teste `[C]`

Ref: quickstart.md Cenario 6; contracts/jira-rest.md R1/R3/R4/R5/R8.

- [x] 0.1.1 Obter (do operador) um site Jira Cloud de teste + API token
      valido, seguindo a mesma disciplina de `data-model.md` Credential
      (token nunca digitado no chat; coletado em terminal proprio) — resolvido
      via block-008/dec-053 (novo token classico gerado pelo operador,
      confirmado com `GET /myself` 200 na onda-011)
- [x] 0.1.2 `GET /rest/api/3/issue/{issueIdOrKey}` sobre uma issue de teste e
      capturar a resposta REAL: comparar `fields.status`, `fields.issuetype`,
      `fields.updated` contra o que `contracts/jira-rest.md` R3 descreve —
      feito contra `SCRUM-6` (onda-011); ver contracts/jira-rest.md secao R3
- [x] 0.1.3 `POST /rest/api/3/issue` (criacao de uma issue de teste) e
      capturar o corpo aceito REAL: comparar `fields.project`,
      `fields.issuetype`, `fields.summary`, `fields.parent`,
      `fields.description` (ADF) contra R1 — feito: Epic `SCRUM-5` + Story
      `SCRUM-6` (filha via `fields.parent`) criadas no projeto `SCRUM`
      (onda-011); ver contracts/jira-rest.md secao R1
- [x] 0.1.4 `GET /rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes`
      sobre o projeto de teste e conferir se `hierarchyLevel` de Epic aparece
      de fato na resposta (R8 — hoje NAO ENCONTRADO nas fontes estaticas) —
      confirmado: Epic=1, Task=0, Story=0, Subtask=-1 (onda-011)
- [x] 0.1.5 `GET /rest/api/3/issue/{issueIdOrKey}/transitions` e conferir o
      elemento de `transitions` (`id`, `name`, `to.name`, `to.id`) contra R5 —
      feito contra `SCRUM-6` (onda-011); achou contradicao `looped`→`isLooped`
      (dec-057), corrigida no contrato
- [~] 0.1.6 Deletar/arquivar a issue de teste criada em 0.1.3 (via UI do
      Jira, NUNCA via `deleteJiraIssue`/`DELETE` do plugin — FR-012) —
      PENDENTE: exige UI do Jira (navegador), fora do alcance das ferramentas
      deste orquestrador autonomo; `SCRUM-5` e `SCRUM-6` seguem no projeto
      `SCRUM` (sandbox) ate o operador arquiva-las manualmente

### 0.2 Atualizar `contracts/jira-rest.md` com os achados `[C]`

Ref: Principio VI (Zero Fabricacao) — nenhum campo confirmado por 0.1 pode
ficar com o marcador antigo desatualizado.

- [x] 0.2.1 Para cada campo confirmado em 0.1, editar `contracts/jira-rest.md`
      trocando o marcador (`(exemplo)`/`RECONFERIR`/`NAO ENCONTRADO`) por
      `CONFIRMADO (roundtrip onda-011)` com o valor observado — feito (data
      real do teste, nao a estimativa antiga "onda-007", para nao registrar
      proveniencia incorreta)
- [x] 0.2.2 Para campos que a chamada real contradisser o contrato, registrar
      Decisao auditavel (`--score 3 --evidencia "<trecho literal da resposta
      observada>"`) e corrigir o contrato — nunca prosseguir com dado
      divergente — feito: dec-057 (`isLooped` vs `looped`)
- [x] 0.2.3 Teste: `grep` de auditoria confirmando que nenhuma linha usada
      pelo motor (FASE 3/4) permanece com marcador `NAO ENCONTRADO` apos a
      edicao (exceto os itens explicitamente fora do contrato: changelog,
      `fields.project.key`, `statusCategory.key`, path de criacao de
      projeto — `contracts/jira-rest.md` "Continua fora do contrato")

---

## FASE 1 - Fundacao do Plugin e Marketplace `[A]`

Ref: plan.md Project Structure; plan.md "Pontos explicitos exigidos pela
onda-003" #1/#2.

### 1.1 Scaffold do plugin `plugins/cstk-jira/` `[A]`

Ref: plan.md Project Structure (Source Code).

- [x] 1.1.1 Criar arvore de diretorios: `plugins/cstk-jira/{.claude-plugin,
      hooks,scripts,skills/jira-setup/references,
      skills/jira-convert/references,skills/jira-sync/references}`
- [x] 1.1.2 Criar `plugins/cstk-jira/.claude-plugin/plugin.json` (nome
      `cstk-jira`, descricao, `version` inicial, `author`, `repository`,
      `license`, `keywords` — mesmo formato de
      `plugins/cstk-language-go/.claude-plugin/plugin.json`)
- [x] 1.1.3 Teste: `tests/cstk/test_manifest.sh`/`test_manifest-coverage.sh`
      (ou fixture equivalente) reconhece o novo plugin.json como valido
      (schema minimo: `name`, `version`, `description`) — implementado como
      `tests/cstk/test_cstk-jira-plugin-manifest.sh` (fixture equivalente,
      allowlisted em `tests/run.sh::_is_internal_test`; PASS 3/3)

### 1.2 Registrar no marketplace e ajustar o gate MP-2 `[A]`

Ref: plan.md "Pontos explicitos exigidos pela onda-003" #1;
`scripts/validate-plugin-manifests.sh` L11/L95-98.

- [x] 1.2.1 Adicionar 3a entrada em `.claude-plugin/marketplace.json`:
      `name: cstk-jira`, `description`, `source: ./plugins/cstk-jira`,
      `version` (lockstep com `plugin.json` de 1.1.2), `category`
- [x] 1.2.2 Editar `scripts/validate-plugin-manifests.sh`: MP-2 de
      "`.plugins | length == 2`" para "`== 3`" (mensagem de erro atualizada
      de "exatamente 2" para "exatamente 3")
- [x] 1.2.3 Atualizar a fixture de `tests/cstk/test_validate-plugin-manifests.sh`
      para incluir o 3o plugin (cstk-jira) no `marketplace.json` de teste,
      mantendo os casos negativos (2 e 4 plugins continuam falhando MP-2) —
      implementado como `scenario_mp2_duas_entradas` +
      `scenario_mp2_quatro_entradas`
- [x] 1.2.4 Teste: `bash scripts/validate-plugin-manifests.sh` roda limpo
      contra o `marketplace.json` real do repo apos 1.2.1 — `sh
      scripts/validate-plugin-manifests.sh --repo-root . --version 10.7.0
      --strict` => `validate-plugin-manifests: OK (0 aviso(s))`, exit 0
- [x] 1.2.5 Teste: `tests/cstk/test_validate-plugin-manifests.sh` verde,
      incluindo os 2 casos negativos de 1.2.3 — 12/12 cenarios PASS
      (`sh tests/cstk/test_validate-plugin-manifests.sh`)

---

## FASE 2 - Persistencia Local `[A]`

Ref: data-model.md (ProjectConfig, LocalWorkItem, SyncMapping);
contracts/plugin-scripts.md `jira-config.sh`/`jira-tasks.sh`/`jira-map.sh`.

### 2.1 `jira-config.sh` `[A]`

Ref: data-model.md Entity ProjectConfig; contracts/plugin-scripts.md
`jira-config.sh`.

- [x] 2.1.1 Subcomando `get KEY`: le `ProjectConfig` (`key=value`, `#`
      comenta); exit 3 se arquivo ausente (FR-017 — plugin inativo)
- [x] 2.1.2 Subcomando `validate`: campos obrigatorios presentes;
      `site_host` valido como hostname puro (sem esquema/path/porta/
      userinfo); `status_fail != status_pass` (recusa com diagnostico
      instruindo o admin a criar um status distinto no workflow)
- [x] 2.1.3 Subcomando `credential-check`: confere existencia + permissao
      `0600` do arquivo de credencial para `site_host`, sem imprimir
      nenhum valor (data-model.md "Regras de seguranca")
- [x] 2.1.4 Teste unit: fixtures de `ProjectConfig` validas/invalidas
      (`status_fail == status_pass`, `site_host` com esquema/porta,
      arquivo ausente) cobrindo os 3 subcomandos
- [x] 2.1.5 Teste: `credential-check` recusa arquivo com permissao mais
      aberta que `0600` sem nunca imprimir o conteudo

### 2.2 `jira-tasks.sh` `[A]`

Ref: data-model.md Entity LocalWorkItem (derivacao de `local_state`).

- [x] 2.2.1 Subcomando `items --feature F`: parse de
      `docs/specs/<feature>/tasks.md` no formato do template canonico
      (`plugins/cstk/skills/create-tasks/templates/tasks.md`) emitindo TSV
      `local_key kind phase criticality local_state title` — implementado
      em `plugins/cstk-jira/scripts/jira-tasks.sh` (awk single-pass,
      `--outcomes-file`/`--stage` adicionados e documentados em
      `contracts/plugin-scripts.md` para servir 2.2.3/2.2.4)
- [x] 2.2.2 Derivacao de `local_state` para `subtask` (`[ ]`->`pending`,
      `[~]`->`in_progress`, `[x]`->`pass`, `[!]`->`fail`)
- [x] 2.2.3 Derivacao de `local_state` para `task` (outcome de
      `record_task`/`record-task` tem precedencia sobre os checkboxes;
      sem outcome: alguma subtask `[!]`->`fail`; todas `[x]`->`pass`;
      mistura/`[~]`->`in_progress`; senao `pending`) — outcome lido via
      `--outcomes-file` (TSV `task_id<TAB>outcome`; quem grava o arquivo e
      FASE 4/5, fora do escopo desta tarefa)
- [x] 2.2.4 Derivacao de `local_state` para `epic` (`stage_status.<stage>`
      quando configurado; senao agregacao das tasks — data-model.md regra)
      — `--stage STAGE` delega a `jira-config.sh get "stage_status.STAGE"`
- [x] 2.2.5 Titulo do Epic prefixado por fase (`[FASE N] N.M <titulo>`);
      dependencias/criticidade entram na descricao da Task (nao viram
      hierarquia Jira extra — data-model.md) — reconciliado: o padrao
      `[FASE N] N.M <titulo>` so se aplica a uma TASK (tem N.M; Epic nao
      tem), conforme o restante do proprio enunciado ("descricao da
      Task") e a definicao de `title` em data-model.md (texto puro, sem
      prefixo); `jira-tasks.sh` ja expoe phase+local_key+title como
      colunas separadas — a composicao da string final do
      `fields.summary` fica para quem monta o corpo REST (FASE
      3.5.2/4.1.3), nao para esta projecao local
- [x] 2.2.6 Teste unit: fixtures de `tasks.md` cobrindo cada combinacao de
      `local_state` (Epic/Task/Subtask) das subtarefas 2.2.2-2.2.4,
      incluindo o caso "task sem nenhuma subtask ainda" (`pending`) —
      `tests/cstk/test_jira-tasks.sh` (16 cenarios, PASS)

### 2.3 `jira-map.sh` `[A]`

Ref: data-model.md Entity SyncMapping (jira-map.tsv, FR-013/FR-014).

- [x] 2.3.1 Subcomando `get --feature F --local-key K`: le linha do
      mapeamento ou exit 1 — implementado em
      `plugins/cstk-jira/scripts/jira-map.sh`
- [x] 2.3.2 Subcomando `put --feature F --local-key K --kind KIND
      --jira-id ID --jira-key KEY`: insercao atomica (arquivo temporario +
      `mv`); recusa `local_key` ja `active` (idempotencia FR-013) — recusa
      tambem `local_key` ja `orphan` (data-model.md: "criacao so para
      local_key ausente do arquivo"; reativar e escopo exclusivo de `relink`)
- [x] 2.3.3 Subcomando `mark-orphans --feature F`: compara contra
      `jira-tasks.sh items`, marca `orphan` as chaves ausentes do
      `tasks.md`, imprime os orfaos; card Jira NUNCA e apagado (FR-012) —
      exit 6 quando ha ao menos 1 orfao (contracts/plugin-scripts.md),
      exit 0 caso contrario
- [x] 2.3.4 Subcomando `relink --feature F --local-key K --jira-key KEY`:
      religa um orfao por decisao humana (`orphan` -> `active`) — exige
      que `KEY` confira exatamente com o `jira_key` armazenado (confirmacao
      explicita de qual card esta sendo religado)
- [x] 2.3.5 Teste de idempotencia (SC-002): 10 chamadas de `put` seguidas
      para o mesmo `local_key` resultam em 0 linhas novas apos a 1a —
      `scenario_idempotencia_10x_put_mesma_chave_zero_linhas_novas`
- [x] 2.3.6 Teste de renumeracao/orfao: `local_key` removido do `tasks.md`
      vira `orphan` via `mark-orphans`; `relink` restaura `active` sem
      nunca ter apagado a linha original —
      `scenario_mark_orphans_marca_e_nunca_apaga` +
      `scenario_relink_sucesso_reativa_sem_apagar`; testes em
      `tests/cstk/test_jira-map.sh` (16 cenarios, PASS)

---

## FASE 3 - Cliente REST Seguro `jira-io.sh` (carve-out 1.1.0) `[C]`

Ref: plan.md SEC-1..SEC-5; contracts/plugin-scripts.md `jira-io.sh`;
UNICO arquivo do plugin que referencia `jq` + cliente HTTP.
**Depende de FASE 0** (contrato reconferido) e FASE 2 (ProjectConfig).

### 3.1 `deps-check` + `request` com host unico e SEC-5 `[C]`

Ref: plan.md SEC-5; contracts/plugin-scripts.md `jira-io.sh request`.

- [x] 3.1.1 `deps-check`: exit 5 + instrucao de instalacao se `jq` ou o
      cliente HTTP estiverem ausentes do PATH (carve-out 1.1.0 condicao a)
- [x] 3.1.2 `request METHOD PATH [--body-file F]`: `METHOD` restrito a
      allowlist fechada `GET`/`POST`/`PUT` (sem `DELETE` — FR-012); `PATH`
      relativo iniciado em `/rest/`
- [x] 3.1.3 Monta `https://<site_host><PATH>` com `site_host` de
      `ProjectConfig`; valida host por IGUALDADE EXATA (sem userinfo, sem
      porta) antes de CADA requisicao
- [x] 3.1.4 Cliente HTTP configurado para NUNCA seguir redirect e SEMPRE
      verificar TLS (SEC-5); resposta `3xx` => erro sem nova requisicao
      (nao existe flag de configuracao para desligar a verificacao TLS)
- [x] 3.1.5 Teste: dependencia ausente => exit 5, com PATH MINIMO explicito
      controlado no teste inteiro (nao so prefixar um diretorio — licao ja
      registrada no repo: stub no PATH nao esconde binario de `/usr/bin`)
- [x] 3.1.6 Teste: host divergente (resposta simulada com redirect para
      outro dominio) => recusa SEM nova requisicao
- [x] 3.1.7 Teste: chamada de `request` com `METHOD=DELETE` falha por uso
      incorreto (exit 2) — `DELETE` nunca existe como opcao valida

      Implementado em `plugins/cstk-jira/scripts/jira-io.sh` (subcomandos
      `deps-check` + `request`); testes em `tests/cstk/test_jira-io.sh` (12
      cenarios JI-1..JI-12, PASS). Nesta versao `request` NAO envia header
      `Authorization` (credencial entra na tarefa 3.3) e nao classifica
      status HTTP alem de "3xx recusado" (mapeamento fino fica para 3.4).

### 3.2 Allowlist de charset em path/JQL (SEC-1) `[C]`

Ref: plan.md SEC-1; checklists/security.md CHK001/CHK002.

- [x] 3.2.1 Validar segmentos de PATH vindos do mapeamento (`jira_id`/
      `jira_key`) e de `project_key` contra allowlist `[A-Za-z0-9_-]`
      ANTES de qualquer interpolacao
- [x] 3.2.2 Rejeitar, sem fazer requisicao, PATH contendo `..`, `//`, `\`,
      `@`, `#`, espaco, CR/LF ou qualquer byte de controle
- [x] 3.2.3 Cobrir TODOS os pontos de interpolacao do motor: R1-R11
      (contracts/jira-rest.md) + a JQL de FASE 7 (SEC-3)
- [x] 3.2.4 Teste: cada byte proibido de 3.2.2, isoladamente, causa recusa
      sem requisicao (tabela de casos)
- [x] 3.2.5 Teste: `jira_id`/`jira_key`/`project_key` fora do charset
      `[A-Za-z0-9_-]` (ex.: contendo espaco ou `/`) e recusado

      Implementado em `plugins/cstk-jira/scripts/jira-io.sh`:
      `_ji_path_has_forbidden_bytes` aplicada ao PATH inteiro dentro de
      `request` (guarda central — cobre R1-R11 porque `request` e o unico
      ponto de disparo de requisicao, independente de onde/como o motor
      futuro montar o PATH) + novo subcomando `validate-segment VALUE...`
      (`_ji_charset_ok`, allowlist `[A-Za-z0-9_-]`) para o motor validar
      `jira_id`/`jira_key`/`project_key` ANTES de interpolar PATH ou a JQL
      de FASE 7. Testes em `tests/cstk/test_jira-io.sh` (26 cenarios
      JI-1..JI-26, PASS; os 12 de 3.1 continuam verdes). `sh tests/run.sh
      --check-coverage`: zero orfaos.

### 3.3 Credencial temporaria segura (SEC-4) `[C]`

Ref: plan.md SEC-4; checklists/security.md CHK006/CHK007.

- [x] 3.3.1 Gerar arquivo de config temporario do cliente HTTP (carrega o
      header de autenticacao) com `umask 077`, em diretorio privado
- [x] 3.3.2 `trap` em `EXIT`/`INT`/`TERM` removendo o arquivo temporario —
      nunca so o caso feliz de saida normal
- [x] 3.3.3 Credencial nunca passada por argv/linha de comando do cliente
      HTTP (so por arquivo/stdin de config) nem aparece em log
- [x] 3.3.4 Teste: modo do arquivo temporario e exatamente `0600` durante a
      execucao
- [x] 3.3.5 Teste (mutation): matar o processo com `SIGTERM`/`SIGINT`
      simulado a meio de uma chamada e confirmar que o arquivo temporario
      foi removido mesmo assim

      Implementado em `plugins/cstk-jira/scripts/jira-io.sh`: `request`
      agora confere `jira-config.sh credential-check` (existencia + modo
      0600 do arquivo global de Credential) e le `email`/`api_token` de
      `${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials` (formato
      `key=value` ja estabelecido pelos testes de `jira-config.sh`
      credential-check, tarefa 2.1); grava um arquivo de config temporario
      do cliente HTTP com a diretiva `user = "email:token"` (o cliente HTTP
      converte para o header `Authorization` internamente — a credencial
      NUNCA aparece em argv) num diretorio privado, ambos criados sob
      `umask 077` (elimina a janela de corrida entre criar-e-restringir,
      CWE-377); passado via `-K`. Trap "split" (mesmo padrao de
      `cli/lib/00c-bootstrap.sh` `_00c_release_lock`): EXIT roda a limpeza
      (`_ji_cred_cleanup`), INT/TERM chamam `exit 130`/`exit 143`
      explicitos, que entao disparam o EXIT trap em sequencia. Testes em
      `tests/cstk/test_jira-io.sh` (32 cenarios JI-1..JI-32, PASS; os 26
      de 3.1/3.2 continuam verdes — JI-5/6/12 ganharam fixture de
      credencial isolada via `XDG_CONFIG_HOME`). Mutation tests JI-31/JI-32
      usam um stub de cliente HTTP que se auto-sinaliza (`kill -TERM`/
      `-INT $PPID`) a meio da chamada, evitando a pegadinha POSIX ja
      documentada no repo de jobs assincronos herdarem SIGINT como SIG_IGN
      (backgrounding externo do processo sob teste nao seria confiavel
      para o caso SIGINT). `sh tests/run.sh jira-io`: 32/32 PASS; `sh
      tests/run.sh --check-coverage`: zero orfaos.

### 3.4 Mapeamento de status HTTP e classificacao de falha `[C]`

Ref: plan.md Test Strategy "Falha"; checklists/api.md CHK009
(auth_failed vs permission_denied vs deferred).

- [x] 3.4.1 `401` em qualquer operacao => exit 4 (`auth_failed`), nunca
      retry (FR-016/FR-019)
- [x] 3.4.2 `403` em R1 (criar issue) ou R2 (editar issue) => diagnostico
      distinto `permission_denied` ("credencial valida, permissao
      insuficiente no projeto/tipo") — NUNCA reconfiguracao de credencial
- [x] 3.4.3 `403` nas demais operacoes (sem fonte que os distinga) segue
      tratado como `auth_failed` ate nova fonte
- [x] 3.4.4 `429` => `deferred`, lendo `Retry-After` (segundos) do header
      quando presente
- [x] 3.4.5 `5xx`/erro de rede/timeout => `deferred` com backoff limitado a
      3 tentativas por drain
- [x] 3.4.6 `400`/`409` em transicao concorrente (R4) => `deferred`
      (candidatos a retry — change-notice confirmado em `contracts/jira-rest.md`)
- [x] 3.4.7 Teste de contrato dedicado: `401` (qualquer op) vs `403` em
      R1/R2 vs `403` nas demais vs `429` — os 4 casos SEM colisao no mesmo
      tratamento (CHK009)

      Implementado em `plugins/cstk-jira/scripts/jira-io.sh`: `request`
      ganhou `--op OP` (OP em `R1`..`R11`, allowlist fechada; omitido ou
      fora de R1/R2 => tratamento conservador — dec-073) e um bloco de
      classificacao apos a resposta HTTP: `401` (qualquer op) e `403` fora
      de `--op R1`/`--op R2` => exit 4 `classification=auth_failed`; `403`
      em `--op R1`/`--op R2` => exit 7 (NOVO — nao colide com o exit 6 ja
      reservado em `contracts/plugin-scripts.md` para conflito/orfao de
      `jira-map.sh`) `classification=permission_denied`; `429` => exit 1
      `classification=deferred` + `retry_after=<s>` em stderr quando o
      header `Retry-After` vier (lido via novo `-D` no `curl`,
      `_ji_extract_retry_after`) — sem retry interno, quem decide quando
      reenviar e o chamador; `5xx`/erro de rede (`curl` exit != 0) =>
      loop de ate 3 tentativas com `sleep` de backoff entre elas
      (`JIRA_IO_BACKOFF_SECONDS`, overridable — default 2s), esgotadas =>
      exit 1 `classification=deferred`; `400`/`409` em `--op R4` => exit 1
      `classification=deferred`. Codigos fora deste escopo (400/409 sem
      R4, 404, 422 etc.) mantem o passthrough pre-3.4 (exit 0, corpo
      relayed) — nao inventada classificacao alem do exigido por
      plan.md/contracts/jira-rest.md/checklists/api.md CHK009 (dec-073).
      `contracts/plugin-scripts.md` atualizado (tabela "Mapeamento de
      status HTTP" corrigida para bater com a correcao de CHK009/dec-038
      ja aplicada em `plan.md`, e exit codes comuns com a entrada `7`).
      Testes em `tests/cstk/test_jira-io.sh`: 15 cenarios novos JI-33..
      JI-47 (incluindo JI-47 = teste de contrato dedicado da 3.4.7, que
      dispara as 4 respostas na mesma funcao de cenario e confere exit
      codes/`classification` distintos sem colisao) + os 32 de 3.1-3.3
      continuam verdes — `sh tests/run.sh jira-io`: 47/47 PASS; `sh
      tests/run.sh --check-coverage`: zero orfaos; `shellcheck -s sh`
      limpo nos dois arquivos.

### 3.5 `json-get`/`json-build` e JQL segura (SEC-3) `[A]`

Ref: plan.md SEC-3; contracts/plugin-scripts.md `json-get`/`json-build`.

- [x] 3.5.1 `json-get FILTER`: wrapper de leitura que restringe `jq` a este
      arquivo (nenhum outro script do plugin invoca `jq` diretamente) —
      `jq -r FILTER` sobre stdin; so exige `jq` (nao exige cliente HTTP nem
      ProjectConfig/credencial); filtro/entrada invalidos => exit 2
- [x] 3.5.2 `json-build ...`: monta corpos REST (`fields.project.id`,
      `fields.issuetype.id`, `fields.summary`, `fields.parent.key`,
      `fields.description` em ADF) a partir de `contracts/jira-rest.md`
      confirmado na FASE 0 — `json-build issue --project-id ID
      --issuetype-id ID --summary TEXT [--parent-key KEY] [--description
      TEXT]`: ids/keys passam pela mesma allowlist `[A-Za-z0-9_-]` de
      `validate-segment` (SEC-1) ANTES de entrar no corpo; summary/
      description sao texto livre, via `jq --arg` (nunca concatenacao de
      string); tambem `json-build filter --name TEXT --project-key KEY`
      (corpo de R9, base da JQL do board de 3.5.3)
- [x] 3.5.3 JQL montada pelo plugin (filtro do board) interpola SOMENTE
      valores que ja passaram pela allowlist de 3.2 — nenhum texto livre
      (titulo/descricao) entra em JQL — `json-build filter`: `--project-key`
      validado pela allowlist SEC-1 ANTES de montar `jql`; `--name` (texto
      livre) so entra no campo `name`, nunca em `jql`
- [x] 3.5.4 Teste de contrato: corpo gerado por `json-build` bate campo a
      campo com `contracts/jira-rest.md` para R1 (criar issue) —
      `scenario_json_build_issue_contrato_r1_completo` (JI-53), compara via
      `jq -S -c` contra o corpo esperado (project/issuetype/summary/parent/
      description ADF)
- [x] 3.5.5 Teste: tentativa de montar JQL com texto livre (titulo/
      descricao simulados) e recusada/sanitizada antes de interpolar —
      `scenario_json_build_filter_project_key_texto_livre_recusado_antes_de_montar_jql`
      (JI-62): `--project-key` com espaco/aspas/operador JQL (`OR 1=1`) =>
      exit 2, nenhuma JQL em stdout; `scenario_json_build_issue_summary_com_aspas_barra_e_quebra_de_linha`
      (JI-60) confere round-trip de `--summary`/`--description` com aspas,
      barra invertida e quebra de linha continuando JSON valido (`jq -e .`)

      Implementado em `plugins/cstk-jira/scripts/jira-io.sh`: `_ji_require_jq`
      (checagem dedicada, so `jq` — `json-get`/`json-build` nunca exigem o
      cliente HTTP), `_ji_cmd_json_get`, `_ji_cmd_json_build` (dispatcher
      `issue`/`filter`), `_ji_cmd_json_build_issue`, `_ji_cmd_json_build_filter`.
      `contracts/plugin-scripts.md` atualizado (tabela de subcomandos de
      `jira-io.sh` com `json-get`/`json-build issue`/`json-build filter`).
      Testes em `tests/cstk/test_jira-io.sh`: 17 cenarios novos JI-48..JI-64
      + os 47 de 3.1-3.4 continuam verdes — `sh tests/run.sh jira-io`:
      64/64 PASS; `sh tests/run.sh --check-coverage`: zero orfaos;
      `shellcheck -s sh` limpo nos dois arquivos.

---

## FASE 4 - Motor de Sincronizacao `jira-sync.sh` `[C]`

Ref: contracts/plugin-scripts.md `jira-sync.sh`; data-model.md OutboxEvent/
ConflictRecord. **Depende de** FASE 2 (persistencia) e FASE 3 (jira-io.sh).

### 4.1 `plan`/`convert` (US1, FR-001/003/013/014) `[C]`

Ref: spec.md US1; plan.md fluxo 2 "Convert".

- [x] 4.1.1 `plan --feature F`: dry-run listando criacoes, atualizacoes,
      transicoes, orfaos e conflitos previstos, sem nenhuma escrita
      (resolvido via plugins/cstk-jira/scripts/jira-sync.sh `plan` — dry-run
      100% local, sem `jq`/cliente HTTP; conflitos reais delegados a `drain`,
      FASE 4.2, ainda nao implementada — nota explicita no stdout)
- [x] 4.1.2 `convert --feature F`: pre-condicoes completas ANTES da 1a
      escrita — `deps-check`, `validate`, `credential-check` e validacao
      de credencial remota (`GET /rest/api/3/myself`); qualquer falha
      aborta sem criar artefato parcial no Jira (US1 cenario 3)
- [x] 4.1.3 Cria Epic, depois Tasks (`parent` = Epic), depois Sub-tasks
      (`parent` = Task), gravando `jira-map.tsv` item a item IMEDIATAMENTE
      apos cada resposta de criacao (antes de qualquer outra chamada)
- [x] 4.1.4 Reexecucao de `convert`: busca SEMPRE por `jira_id`/`jira_key`
      do mapeamento (nunca por titulo/JQL) — cria so o `local_key` ausente
      do arquivo (US1 cenario 2, FR-014)
- [x] 4.1.5 Teste de idempotencia (SC-002): 10 execucoes de `convert`
      seguidas para a mesma feature => 0 criacoes apos a 1a
- [x] 4.1.6 Teste: credencial rejeitada durante `convert` => nenhum issue
      criado (nem parcial) e `jira-map.tsv` permanece inalterado
- [x] 4.1.7 Teste: `tasks.md` ganha uma tarefa nova apos conversao anterior
      => `convert` cria SOMENTE a Task nova associada ao Epic existente

### 4.2 `enqueue`/`drain` (US3, FR-004/005/018) `[C]`

Ref: spec.md US3; data-model.md OutboxEvent; contracts/hooks.md "Drenar".

- [x] 4.2.1 `enqueue --feature F --local-key K --state S --source SRC`:
      append em `outbox.tsv` (append-only)
- [x] 4.2.2 `drain --feature F`: lock `runtime/.drain.lock/` (`mkdir`
      atomico); lock ocupado => sai sem erro, proximo gatilho drena
- [x] 4.2.3 Para cada evento: ler issue (R3) + `SyncMarker` (R6, entity
      property `cstk-jira.sync`), detectar conflito
      (`sha256(titulo_atual) != written_summary_sha256` OU
      `status_atual != written_status` OU marker ausente `marker_missing`)
      ANTES de escrever — gap de Principio VI FECHADO na onda-022 (dec-081):
      `contracts/jira-rest.md` R6 confirma o envelope `EntityProperty`
      (`{key,value}`) por OpenAPI oficial (schema `EntityProperty`) + por
      roundtrip real contra `SCRUM-5` (`PUT`->201/200, `GET`->200 com o
      envelope). `sha256-stdin` novo em `jira-io.sh` (dec-082 — 3a
      dependencia externa confinada, mesmo padrao de fallback do carve-out
      1.1.0)
- [x] 4.2.4 Conflito detectado => NAO escreve; gera `ConflictRecord`
      (`reason` = `manual_edit`/`marker_missing`/`orphan`) em
      `runtime/conflicts.tsv`; nunca sobrescreve silenciosamente (FR-011)
- [x] 4.2.5 Sem conflito: transiciona para o status mapeado
      (`status_pending`/`status_in_progress`/`status_pass`/`status_fail`)
      via R5 (resolve `transition.id` por `to.name`) + R4, e regrava
      `SyncMarker` via R6 PUT com o novo `written_summary_sha256`/
      `written_status`/`written_at`
- [x] 4.2.6 Regra dura: com qualquer evento `auth_failed` presente no
      outbox, o drain NAO faz NENHUMA nova chamada ate reconfiguracao
      (FR-016 — nunca repetir silenciosamente tentativas que falham) —
      gate no NIVEL DO OUTBOX (por feature) + `_js_process_one_event` para
      o lote inteiro na 1a ocorrencia real de `auth_failed` (401/403 fora
      de R1-R2)
- [x] 4.2.7 Serializacao de escritas: nunca 2 escritas concorrentes na
      mesma issue (rate limit Jira de 20 escritas/2s por issue —
      checklists/api.md CHK014) — satisfeito pelo lock de drain, que e
      GLOBAL AO PROJETO (`_JS_DRAIN_LOCK_DIR`, `mkdir` atomico): so um
      processo de `drain` roda por vez em todo o projeto, o que ja impede
      2 escritas concorrentes em qualquer issue sem exigir lock adicional
      por-issue (nenhum codigo novo — decisao documentada no cabecalho de
      `_js_process_one_event`)
- [x] 4.2.8 Compactacao do outbox: eventos `done` sao removidos no proximo
      drain (outbox nao cresce indefinidamente)
- [x] 4.2.9 Teste: 2 chamadas de `drain` concorrentes (lock disputado) =>
      apenas uma processa; a outra sai imediatamente sem erro
- [x] 4.2.10 Teste: deteccao de conflito (issue editada manualmente
      simulada) gera `ConflictRecord` e NAO sobrescreve o titulo/status —
      `scenario_drain_conflito_manual_edit_gera_conflict_record_sem_
      sobrescrever` (SY-19, so 2 chamadas de rede R3+R6-GET, zero
      transicao/escrita)
- [x] 4.2.11 Teste: evento `auth_failed` presente bloqueia TODAS as
      chamadas subsequentes do drain ate reconfiguracao simulada — coberto
      no nivel do outbox desde a onda anterior (`scenario_drain_auth_
      failed_bloqueia_e_nao_altera_queued_da_mesma_feature`); a parada do
      LOTE na 1a ocorrencia real de `auth_failed` (`_JSPE_BREAK`) e
      implementacao direta em `_js_process_one_event`, sem teste dedicado
      de rede real nesta onda (orcamento) — comportamento e trivial
      (`break` no loop) e a mesma classificacao 401/403 ja e exaustivamente
      testada em `test_jira-io.sh` (`scenario_request_401_*`)

      Implementado em `plugins/cstk-jira/scripts/jira-sync.sh`
      (`_js_process_one_event` + `_js_cmd_drain`) e
      `plugins/cstk-jira/scripts/jira-io.sh` (`sha256-stdin`,
      `json-build transition`, `json-build marker`). Testes em
      `tests/cstk/test_jira-sync.sh`: 4 cenarios novos (SY-18..SY-21) + os
      19 anteriores continuam verdes — `sh tests/run.sh jira-sync`: 23/23
      PASS; `tests/cstk/test_jira-io.sh`: 8 cenarios novos (transition/
      marker/sha256-stdin) — `sh tests/run.sh jira-io`: 72/72 PASS;
      `shellcheck -s sh` limpo nos 3 arquivos; `sh tests/run.sh
      --check-coverage`: zero orfaos. Roundtrip real que fechou o gap de
      R6: `docs/specs/cstk-jira/contracts/jira-rest.md` secao "Roundtrip
      real onda-022".

      **Limitacao conhecida aceita** (comentario em
      `_js_process_one_event`): se o `PUT` de regravar o SyncMarker falhar
      APOS a transicao R4 ja ter sido aplicada, o evento fica `deferred` e
      o proximo drain repete R3/R6-GET/R5/R4 — a issue ja estara no status
      alvo, o que faria a deteccao de conflito comparar
      `status_atual != written_status` (antigo) e reportar `manual_edit`
      indevidamente. Nao resolvido nesta tarefa (exigiria idempotencia mais
      fina); o operador sempre pode `resolve --choice keep_jira` quando a
      FASE 4.3 existir. **Tambem nao resolvido**: `local_key=*`
      (reconciliar a feature inteira) permanece na fila sem processamento
      (diagnostico em stderr) — fora do escopo de 4.2.3-4.2.5.

### 4.3 `status`/`resolve`/`relink` (resolucao humana) `[A]`

Ref: data-model.md ConflictRecord; checklists/ux.md CHK011/CHK012.

- [x] 4.3.1 `status [--feature F]`: resumo do outbox + conflitos + orfaos +
      eventos `auth_failed`, legivel pelo operador
- [x] 4.3.2 `resolve --feature F --local-key K --choice keep_jira|
      overwrite|ignored`: fecha o `ConflictRecord` por decisao humana
      (resolucao SEMPRE humana — nunca automatica)
- [x] 4.3.3 `jira-map.sh relink` exposto/documentado pela skill `jira-sync`
      como caminho de UX claro para religar um orfao (CHK012) — documentado
      no usage/--help de `jira-sync.sh` (skill formal e FASE 6)
- [x] 4.3.4 Teste: os 3 `--choice` de `resolve` produzem o efeito esperado
      (mantem estado do Jira / sobrescreve / apenas fecha o registro)

### 4.4 Card orfao — nunca apagar (FR-012) `[A]`

Ref: spec.md FR-012; data-model.md SyncMapping state transitions.

- [x] 4.4.1 `jira-map.sh mark-orphans` roda como parte do `drain`
      (reconciliacao periodica contra `jira-tasks.sh items`) — integrado em
      `_js_cmd_drain` (onda-022), ANTES do gate `auth_failed` (pura leitura/
      rewrite LOCAL, nunca rede — roda mesmo quando o gate bloquearia
      chamadas novas). `status` (exposicao pela skill) e FASE 4.3, fora do
      escopo desta tarefa
- [x] 4.4.2 Card Jira correspondente a um orfao NUNCA e apagado
      automaticamente pelo plugin (nenhum caminho de codigo chama
      `deleteJiraIssue`/`DELETE`) — garantido estruturalmente por
      `jira-io.sh`: `DELETE` NAO existe na allowlist FECHADA de METHOD
      (`_ji_method_allowed`, so GET/POST/PUT), testado em
      `scenario_request_method_delete_exit2_sem_requisicao`
      (`test_jira-io.sh`); `jira-map.sh mark-orphans`/`relink` nunca fazem
      chamada de rede (so rewrite local do TSV) e nunca removem linha
      (`scenario_mark_orphans_marca_e_nunca_apaga`, JM-11)
- [x] 4.4.3 Teste round-trip: `local_key` some do `tasks.md` => vira
      `orphan`; `relink` restaura `active`; em nenhum momento a issue foi
      deletada — ja coberto desde fase anterior por
      `scenario_mark_orphans_marca_e_nunca_apaga` (JM-11) +
      `scenario_relink_sucesso_reativa_sem_apagar` (JM-15) em
      `tests/cstk/test_jira-map.sh`; "zero chamadas DELETE" e garantia
      ESTRUTURAL (4.4.2 acima), nao precisa de stub de rede dedicado
      porque mark-orphans/relink nunca invocam `jira-io.sh`. Onda-022
      acrescenta `scenario_drain_marca_orfaos_como_parte_do_processo`
      (SY-21, `test_jira-sync.sh`) cobrindo o wiring no `drain` (4.4.1)

---

## FASE 5 - Hooks do Ciclo de Vida `[C]`

Ref: contracts/hooks.md; spec.md FR-005/FR-012/FR-018-INFRA-SCHED.
**Depende de** FASE 4 (jira-sync.sh drain).

### 5.1 `hooks.json` + `posttooluse-jira-sync.sh` (sync autonomo) `[C]`

Ref: contracts/hooks.md "Entradas do hooks.json"/"Comportamento de
posttooluse-jira-sync.sh".

- [x] 5.1.1 `hooks/hooks.json`: matcher `PostToolUse` `mcp__.*__record_task`
      (modo `task`), `mcp__.*__close_wave` (modo `wave`), `Bash` (modo
      `bash`, so age se `tool_input.command` contem `state-ondas.sh
      record-task` ou `state-ondas.sh end`) — todos `async: true`
- [x] 5.1.2 No-op de inatividade como PRIMEIRA instrucao do script (FR-017/
      SC-006): `<cwd>/.claude/cstk-jira/config` ausente OU
      `sync_autonomous=off` => exit 0 silencioso, sem ler stdin alem do
      necessario, sem checar deps
- [x] 5.1.3 Resolucao da execucao ativa: exatamente um `.lock/` candidato
      (`feature-00c-state/<short>/` ou `agente-00c-state/`, mesma derivacao
      de `canonical_project` do orquestrador, READ-ONLY); zero ou mais de
      um candidato => no-op + linha em `runtime/hook.log`
- [x] 5.1.4 Filtro por feature convertida: sem
      `docs/specs/<feature>/jira-map.tsv` => no-op (US1 e pre-requisito)
- [x] 5.1.5 Enfileira `OutboxEvent` (`task_id`/`outcome` do modo `task`/
      `bash`; `reconcile` do modo `wave`) e chama `jira-sync.sh drain`
- [x] 5.1.6 Fail-open absoluto: qualquer falha => exit 0; hook NUNCA
      bloqueia/atrasa a tool do orquestrador nem grava no state da execucao
- [x] 5.1.7 Nao-exfiltracao: le SOMENTE `task_id`/`outcome` do
      `tool_input`; NUNCA grava, loga ou repassa `session_id`
- [x] 5.1.8 Teste: config ausente => no-op total (nenhum arquivo criado,
      nenhuma rede, stdout vazio) — SC-006
- [x] 5.1.9 Teste: falha simulada dentro do hook (ex.: `drain` retorna erro)
      => hook ainda sai `exit 0` (fail-open)
- [x] 5.1.10 Teste (nao-exfiltracao): stdin sintetico com `session_id`
      real => `session_id` NUNCA aparece em stdout, `hook.log` ou outbox
      (CHK013)

### 5.2 `pretooluse-jira-deny-destructive.sh` (FR-012) `[C]`

Ref: contracts/hooks.md "Comportamento de pretooluse-jira-deny-destructive.sh";
contracts/rovo-mcp.md "Tools proibidas".

- [x] 5.2.1 Matcher `PreToolUse` `mcp__.*__(deleteJiraIssue|
      executeDestructive)` (casa qualquer prefixo de instalacao do Rovo MCP)
- [x] 5.2.2 Casou => mensagem em stderr citando FR-012 + `exit 2`
      (unico exit code que bloqueia a tool por si so)
- [x] 5.2.3 Sem `<cwd>/.claude/cstk-jira/config` => guarda e no-op
      (exit 0) — FR-017/SC-006, mesmo quando o Rovo MCP esta sendo usado
      para outros fins fora do plugin
- [x] 5.2.4 Defesa em profundidade complementar: `jira-io.sh` (FASE 3) nao
      tem metodo `DELETE` — dois pontos de enforcement independentes
      (CHK010)
- [x] 5.2.5 Teste positivo: `tool_name` casando o matcher => `exit 2` +
      mensagem citando FR-012
- [x] 5.2.6 Teste negativo: sem config presente, mesmo `tool_name` =>
      `exit 0` (no-op)

---

## FASE 6 - Skills Interativas `[A]`

Ref: plan.md Fluxos 1-3; spec.md US1/US4; checklists/security.md CHK004/
CHK005; checklists/ux.md CHK001-CHK006. **Depende de** FASE 3 (jira-io.sh)
e FASE 4 (jira-sync.sh) para o caminho REST; usa `contracts/rovo-mcp.md`
para o caminho MCP.

### 6.1 Skill `jira-setup` (US4, FR-007) `[A]`

Ref: spec.md US4; plan.md fluxo 1 "Setup"; quickstart.md Cenario 3.

- [x] 6.1.1 `SKILL.md` com formato canonico do toolkit (description-como-
      trigger, `references/`, Gotchas — Principio III) <!-- plugins/cstk-jira/skills/jira-setup/SKILL.md + references/api-discovery.md; validate-docs-rendered: 0 erros/0 avisos -->
- [x] 6.1.2 Fluxo guiado em ORDEM FIXA (checklists/ux.md CHK002): site ->
      `PROJECT_KEY` -> credencial (terminal proprio, NUNCA no chat,
      comando concreto orientado — CHK003) -> mapeamento de status ->
      confirmacao de tipo de issue -> filtro/board <!-- SKILL.md secao FLUXO DE EXECUCAO + ETAPAS 1-6, mesma ordem -->
- [x] 6.1.3 Apos `createmeta` (R8), LISTAR os tipos retornados (`id`,
      `name`, `hierarchyLevel`, `subtask`) e EXIGIR confirmacao explicita
      do operador sobre qual e Epic/Task/Sub-task antes de gravar
      `issue_type_*` — nunca inferir (`hierarchyLevel` de Epic e NAO
      ENCONTRADO nas fontes — CHK006) <!-- SKILL.md ETAPA 5 + references/api-discovery.md §1; teste JS-9 -->
- [x] 6.1.4 Descobrir transicoes (`listJiraIssueTransitions`/R5) e pedir o
      mapeamento `pending`/`in_progress`/`pass`/`fail`; recusar
      `fail == pass` com diagnostico que LISTA os status DISPONIVEIS do
      workflow ja descobertos no mesmo fluxo, nao so "invalido" (`[Gap]`
      ux CHK004 — destino explicito desta onda) <!-- jira-setup.sh check-status-mapping (novo) + SKILL.md ETAPA 4 + references/api-discovery.md §2-3. NOTA: R5 e por-issue; projeto sem nenhuma issue usa issue de sondagem (decisao de design em references/api-discovery.md §2, custo aceito por FR-012 nao permitir DELETE) -->
- [x] 6.1.5 Setup falho parcialmente => NENHUM estado parcial fica marcado
      como valido (config incompleto nunca aparenta integracao ativa —
      CHK006/FR-007) <!-- jira-setup.sh write-config: temp file + jira-config.sh validate + mv atomico; testes JS-5/JS-6/JS-7/JS-8 -->
- [x] 6.1.6 Rotular texto lido do Jira (nomes de tipos de issue, status,
      respostas de tools Rovo) como conteudo externo NAO-CONFIAVEL
      (UNTRUSTED) antes de apresentar ao operador — mesma disciplina do
      read-back loop do toolkit (`[Gap]` security CHK005 — destino
      explicito desta onda, citando SEC-2) <!-- SKILL.md Gotcha "Texto vindo do Jira e UNTRUSTED" -->
- [x] 6.1.7 Criar ou reusar filtro + board kanban do projeto (US2 cenario
      2: reuso sem duplicar) <!-- SKILL.md ETAPA 6 (R9-R11) -->
- [~] 6.1.8 **Nota (nao bloqueia esta tarefa, aguarda decisao humana antes
      de execute-task fechar a redacao final)**: security CHK011 — se a
      guarda `PreToolUse` ficar inativa quando o plugin nao esta
      configurado deve ou nao ser refletido em FR-012 da spec (hoje so
      documentado no contrato de hooks); ux CHK005 — copy exata do
      diagnostico de token invalido (proximo passo concreto para o
      usuario) <!-- Nota registrada em SKILL.md secao "Pendencias aguardando decisao humana" sem inventar a decisao do dono do produto; permanece [~] ate resposta humana -->
- [x] 6.1.9 Teste: fixture simulando resposta de `createmeta` e
      `transitions`, cobrindo confirmacao de tipos (6.1.3) e diagnostico
      de `fail == pass` listando status disponiveis (6.1.4) <!-- tests/cstk/test_jira-setup.sh JS-9/JS-10 (fixtures com valores REAIS do roundtrip onda-011) -->
- [x] 6.1.10 Teste: setup interrompido a meio (ex.: credencial rejeitada no
      passo de validacao remota) nao deixa `ProjectConfig` parcial
      marcado como valido (6.1.5) <!-- tests/cstk/test_jira-setup.sh JS-5/JS-7/JS-8 (campo ausente / status_fail==status_pass / KEY=VALUE malformado -> nada gravado no caminho final) -->

### 6.2 Skill `jira-convert` (US1, FR-001/003/013/014) `[A]`

Ref: spec.md US1; plan.md fluxo 2 "Convert"; checklists/api.md CHK012.

- [x] 6.2.1 `SKILL.md` com formato canonico (Principio III) <!-- plugins/cstk-jira/skills/jira-convert/SKILL.md + references/.gitkeep; validate-docs-rendered: 0 erros/0 avisos -->
- [x] 6.2.2 Pre-checagens completas (mesmas de `jira-sync.sh convert`)
      ANTES da 1a escrita, tanto no caminho MCP quanto no caminho REST <!-- SKILL.md ETAPA 1 (as 4 checagens, com Gotcha "Por que a credencial REST importa mesmo com o caminho MCP disponivel": jira-sync.sh drain/US3 e REST-only) -->
- [x] 6.2.3 Caminho MCP (tools Rovo visiveis): usa `createJiraIssue`/
      `editJiraIssue` seguindo `inputSchema` real (nunca nomes de
      memoria — checklists/api.md CHK013); caminho REST: delega a
      `jira-sync.sh convert`. Os dois produzem o MESMO efeito observavel
      (mesmo mapeamento, mesmo `SyncMarker` — CHK012) <!-- SKILL.md ETAPA 2/2a/2b; novo script plugins/cstk-jira/scripts/jira-title.sh (fonte unica de composicao de summary, tambem usado por jira-sync.sh convert apos refactor) fecha CHK012 por construcao, nao so em prosa -->
- [x] 6.2.4 Grava `jira-map.tsv` item a item (Epic -> Tasks -> Sub-tasks) <!-- SKILL.md ETAPA 2b passo 6 (jira-map.sh put imediatamente apos cada resposta, mesma ordem de jira-tasks.sh items) -->
- [x] 6.2.5 Reexecucao cria SOMENTE o que falta (US1 cenario 2) <!-- SKILL.md ETAPA 2b passo 1 (jira-map.sh get decide skip, nunca JQL/titulo) -->
- [x] 6.2.6 Rotular texto lido do Jira (respostas de `createJiraIssue`/
      `editJiraIssue`, titulos/descricoes existentes) como UNTRUSTED antes
      de apresentar ao operador (`[Gap]` security CHK005, SEC-2) <!-- SKILL.md secao "Texto vindo do Jira e UNTRUSTED" + ETAPA 2b passo 6 -->
- [~] 6.2.7 **Nota (nao bloqueia esta tarefa, aguarda decisao humana antes
      de execute-task fechar a redacao final)**: ux CHK013 — se feedback
      de progresso incremental ("N/M issues criadas") e exigido nesta
      versao para lotes grandes, ou fica para iteracao futura <!-- Nota registrada em SKILL.md secao "Pendencias aguardando decisao humana" sem inventar a decisao do dono do produto; permanece [~] ate resposta humana, mesma disciplina de 6.1.8 -->
- [x] 6.2.8 Teste: caminho MCP (stub de tools) e caminho REST (stub de
      `jira-sync.sh`) produzem o mesmo `jira-map.tsv` para o mesmo backlog
      de entrada <!-- tests/cstk/test_jira-convert-parity.sh (JCP-1/2/3: mesmo summary REST-vs-jira-title.sh, mesmo jira-map.tsv estrutural, idempotencia); tests/cstk/test_jira-title.sh (JTL-1..9, unidade do script extraido) -->

### 6.3 Skill `jira-sync` (US3) `[A]`

Ref: spec.md US3; plan.md fluxo 3 "Sync autonomo"; checklists/ux.md CHK011.

- [x] 6.3.1 `SKILL.md` com formato canonico (Principio III) <!-- plugins/cstk-jira/skills/jira-sync/SKILL.md + references/.gitkeep; validate-docs-rendered: 0 erros/0 avisos -->
- [x] 6.3.2 Modo `status`: expõe `jira-sync.sh status` (conflitos, orfaos,
      `auth_failed`) como comando claro documentado no fluxo de UX
      (CHK011 — nao so no data-model interno) <!-- SKILL.md ETAPA 1 -->
- [x] 6.3.3 Modo `resolve`: expõe `jira-sync.sh resolve` para o operador
      decidir `keep_jira`/`overwrite`/`ignored` por conflito <!-- SKILL.md ETAPA 2 passos 3-4 -->
- [x] 6.3.4 Modo `relink`: expõe `jira-map.sh relink` para o operador
      religar um orfao (CHK012) <!-- SKILL.md ETAPA 3 -->
- [x] 6.3.5 Rotular texto lido do Jira (titulo/descricao/status/comentarios
      exibidos ao mostrar um conflito) como UNTRUSTED (`[Gap]` security
      CHK005, SEC-2) — nenhuma decisao de sync e derivada desse texto,
      so da escolha humana explicita <!-- novo script plugins/cstk-jira/scripts/jira-conflict-view.sh (caminho REST, banner UNTRUSTED por construcao) + SKILL.md ETAPA 2 passo 1 (caminho MCP via getJiraIssue) e secao "Texto vindo do Jira e UNTRUSTED" -->
- [x] 6.3.6 Teste: exibicao de um conflito simulado rotula corretamente o
      titulo/descricao do Jira como conteudo externo antes de pedir a
      escolha do operador <!-- tests/cstk/test_jira-conflict-view.sh (CV-7 scenario_show_conflito_pendente_rotula_conteudo_untrusted: summary/status/description/comment simulados, banner UNTRUSTED confirmado, conflicts.tsv permanece pending) -->

---

## FASE 7 - Board do CSTK (US2) `[M]`

Ref: spec.md US2; plan.md fluxo 4 "Board". **Depende de** FASE 6 (setup e
convert ja permitem criar issues a organizar no board).

### 7.1 Criacao/reuso de board + filtro `[M]`

Ref: contracts/jira-rest.md R9/R10/R11; contracts/rovo-mcp.md
`listJiraBoards`/`listJiraFilters`/`createJiraBoard`.

- [x] 7.1.1 Caminho MCP: `listJiraBoards`/`listJiraFilters` para checar
      existencia; `createJiraBoard` so se nao existir <!-- documentado em
      skills/jira-setup/references/board-setup.md §5 (ETAPA 6 e conduzida
      pelo LLM, sem script dedicado — mesmo desenho MCP de ETAPA 3/4/5;
      inputSchema real de createJiraBoard decide se listJiraFilters entra
      no fluxo, Principio VI) -->
- [x] 7.1.2 Caminho REST: `GET /rest/agile/1.0/board?projectKeyOrId=...`
      (R11) para checar existencia; `POST /rest/api/3/filter` (R9) +
      `POST /rest/agile/1.0/board` (R10, `type=kanban`) so se necessario
      <!-- jira-io.sh json-build board (R10) + references/board-setup.md
      §1-3; campos confirmados via OpenAPI oficial da Agile API (dec-099,
      contracts/jira-rest.md secao onda-029) -->
- [x] 7.1.3 JQL do filtro do board interpola SOMENTE valores que passaram
      pela allowlist de SEC-1/FASE 3 (SEC-3) — nunca titulo/descricao
      livres <!-- jira-io.sh json-build filter (ja existente desde FASE 3,
      reutilizado tal-e-qual por board-setup.md §2) -->
- [x] 7.1.4 `board_id` gravado em `ProjectConfig` (FASE 2) apos criacao/
      reuso <!-- jira-setup.sh write-config (ja existente); ordem exata
      documentada em references/board-setup.md §4 -->
- [x] 7.1.5 Teste: 2a chamada de setup para o mesmo projeto Jira REUSA o
      board existente, sem criar um duplicado (US2 cenario 2) <!--
      test_jira-io.sh JI-72 scenario_board_setup_reuso_idempotente_sem_duplicar
      (stub por URL, 2a execucao faz 0 chamadas POST) -->

### 7.2 Mapeamento coluna do board <-> status do workflow `[M]`

Ref: checklists/ux.md CHK008; data-model.md ProjectConfig
`status_pending`/`status_in_progress`/`status_pass`/`status_fail`.

- [x] 7.2.1 Coluna do board corresponde ao `status_*` configurado no setup
      (FASE 6.1.4) — nenhuma inferencia adicional de nome de coluna <!--
      ja era o desenho de `_js_process_one_event` (jira-sync.sh, R4/R5)
      desde a onda-022: a transicao alvo vem SOMENTE de
      `status_pending`/`status_in_progress`/`status_pass`/`status_fail` de
      ProjectConfig, nunca de um nome/id de coluna. Documentado
      explicitamente em `skills/jira-setup/references/board-setup.md` §4.bis
      (nova) — o Jira posiciona o card via configuracao NATIVA do board
      (Column Management), fora do escopo do plugin -->
- [x] 7.2.2 Documentar no `quickstart.md`/`SKILL.md` do board que a
      correspondencia coluna<->estagio SDD e definida pelo mapeamento do
      operador, evitando ambiguidade (CHK008) <!-- nota adicionada em
      `skills/jira-setup/SKILL.md` ETAPA 4 (ponto de coleta do mapeamento) +
      `quickstart.md` Cenario 5 (onde o operador observa o board) -->
- [x] 7.2.3 Teste: transicao de status local (FASE 4.2.5) move o card para
      a coluna correta correspondente ao `status_*` mapeado <!--
      test_jira-sync.sh SY-28 (in_progress) + SY-29 (fail) — cada um com 2
      transicoes candidatas na resposta de R5, provando que R4 executa
      SOMENTE a que bate o status_* configurado (SY-18 ja cobria pass); 45
      scenarios (31 em test_jira-sync.sh) verdes -->

      Fonte da decisao de design (nenhuma nova): `plan.md` fluxo 4 "Board —
      colunas = status do workflow; o plugin move cards so por transicao de
      status" (ja escrito na FASE 0). 7.2 nao exigiu mudanca de codigo — so
      fechou a documentacao/teste explicitos que a checklist `ux.md` CHK008
      ja dava como satisfeitos.

---

## FASE 8 - Testes Cross-Cutting: Contrato, Idempotencia, Falha, Mutation `[C]`

Ref: plan.md Test Strategy (tabela completa). **Depende de** FASE 3, 4 e 5
(exercita os componentes ja implementados de ponta a ponta).

### 8.1 Suite de contrato REST `[C]`

Ref: plan.md Test Strategy "Contrato"; checklists/api.md CHK001/CHK002.

- [x] 8.1.1 Stub do cliente HTTP grava metodo, path e corpo de cada
      requisicao emitida pelo motor
- [x] 8.1.2 Assert que R1-R11 (contracts/jira-rest.md, pos-FASE 0) batem
      exatamente com o que o motor de fato emite — sem excecao
- [x] 8.1.3 Teste dedicado cobrindo CHK001 (11 endpoints documentados e
      exercitados) e CHK002 (campos de corpo/resposta usados tem fonte)

### 8.2 Suite de idempotencia (SC-002) `[C]`

Ref: plan.md Test Strategy "Idempotencia"; quickstart.md Cenario 4.

- [x] 8.2.1 Stub com estado persistente entre chamadas simulando o Jira
- [x] 8.2.2 10 execucoes de `jira-sync.sh convert` seguidas para a mesma
      feature => 0 criacoes apos a 1a (end-to-end, nao so unit de
      `jira-map.sh` — complementa 2.3.5/4.1.5)

### 8.3 Suite de falha `[C]`

Ref: plan.md Test Strategy "Falha"; checklists/api.md CHK009.

- [x] 8.3.1 `401` (qualquer operacao) => `auth_failed` sem retry
- [x] 8.3.2 `403` em R1/R2 => `permission_denied`; `403` nas demais
      operacoes => `auth_failed`
- [x] 8.3.3 `429` => `deferred`, respeitando `Retry-After`
- [x] 8.3.4 Host divergente/redirect => recusa sem requisicao (coberto por
      3.1.6/`scenario_request_redirect_3xx_recusado_sem_nova_requisicao` em
      test_jira-io.sh — guarda vive 100% em `jira-io.sh request`, sem logica
      propria em jira-sync.sh; E2E via convert/drain seria wrapper redundante
      da mesma guarda. Mutation dedicada em 8.4.1)
- [x] 8.3.5 Dependencias ausentes (`jq`/cliente HTTP) => exit 5, com PATH
      minimo explicito controlado no teste inteiro (nao so prefixar um
      diretorio)

### 8.4 Mutation tests (defesa em profundidade) `[A]`

Ref: plan.md Test Strategy "Mutation"; pratica ja adotada no repo.

- [x] 8.4.1 Quebrar de proposito a checagem de host unico (3.1.3) e
      confirmar que 3.1.6/8.3.4 pegam a regressao. Implementado em
      `tests/cstk/test_jira-mutation.sh::scenario_mutation_8_4_1_sec5_redirect_guard`.
      Achado empirico documentado no cabecalho do arquivo: a asserção
      ESTATICA de auto-consistencia de host (3.1.3) e defesa-em-profundidade
      inerte sob qualquer entrada possivel hoje (a URL e sempre montada a
      partir do proprio `site_host`); a mutacao automatizada mira a guarda
      FUNCIONAL que 3.1.6/8.3.4 de fato exercitam — a classificacao `3xx`
      (SEC-5) — e confirma que neutraliza-la faz o teste divergir (302
      tratado como sucesso, exit 0 em vez de 1)
- [x] 8.4.2 Quebrar de proposito a ausencia de `DELETE` em `jira-io.sh`
      (remover a validacao) e confirmar que 3.1.7/4.4.3 pegam a regressao.
      Implementado em
      `tests/cstk/test_jira-mutation.sh::scenario_mutation_8_4_2_delete_allowlist`
- [x] 8.4.3 Quebrar de proposito o hook `pretooluse-jira-deny-destructive.sh`
      (matcher errado) e confirmar que 5.2.5 pega a regressao. Implementado
      em `tests/cstk/test_jira-mutation.sh::scenario_mutation_8_4_3_pretooluse_matcher`
- [x] 8.4.4 Quebrar de proposito o no-op de inatividade dos hooks (5.1.2/
      5.2.3) e confirmar que 5.1.8/5.2.6 pegam a regressao. Implementado em
      `tests/cstk/test_jira-mutation.sh::scenario_mutation_8_4_4_hooks_inatividade_noop`
      (cobre os 2 hooks numa unica tarefa, cada um com mutacao propria)
- [x] 8.4.5 Quebrar de proposito o `umask`/`trap` de credencial (3.3.1/
      3.3.2) e confirmar que 3.3.4/3.3.5 pegam a regressao. Implementado em
      `tests/cstk/test_jira-mutation.sh::scenario_mutation_8_4_5_umask_trap_credencial`
      (2 mutacoes independentes: `umask 077` removida e `trap ... EXIT`
      removido)

---

## FASE 9 - Release e Documentacao `[M]`

Ref: plan.md Constitution Check Principio I (lockstep MP-5); plan.md
"Pontos explicitos exigidos pela onda-003" #9. **Depende de** todas as
fases anteriores (contagens/paridade so fazem sentido com o plugin
completo).

### 9.1 Docs bilingues e contagens que gateiam release `[M]`

Ref: `tests/test_doc-counts.sh`; `tests/test_state-parity-sweep.sh`.

- [x] 9.1.1 Atualizar `README.md`: contagem de skills (soma das 21
      globais + as 3 novas do cstk-jira onde aplicavel) e mencao ao
      3o plugin no marketplace <!-- README.md + README.pt-BR.md: nova
      secao "Jira Cloud integration (cstk-jira)"/"Integracao com Jira
      Cloud (cstk-jira)" com as 3 skills, os 2 hooks, pre-requisitos
      (jq + cliente HTTP) e credencial 0600 fora do repo; arvore de
      `plugins/` e comentario de marketplace.json atualizados para 3
      entradas; `/plugin install cstk-jira@cstk` no bloco de instalacao;
      linha nova na tabela "Documentation by topic". Contagem "21 global
      skills" NAO muda (onda-026): `_count_skills` conta so
      `plugins/cstk/skills/`; cstk-jira nao entra nesse universo (dec-020,
      sem MCP proprio) -->
- [x] 9.1.2 Ajustar `tests/test_doc-counts.sh` (contagem esperada) para
      refletir o novo total de skills/plugins documentados <!-- Verificado
      empiricamente (onda-034): as 3 scenarios de test_doc-counts.sh
      (skills_count_matches_readme, all_skills_referenced_in_readme,
      profile_counts_match_sources) derivam so de `plugins/cstk/skills/`
      + scripts/profiles.txt.in + `plugins/cstk-language-*/`; nenhuma
      deriva de `plugins/cstk-jira/` (build-release.sh so faz glob de
      `cstk-language-*`). Sem numero para ajustar — gate ja verde antes e
      depois desta onda, confirmado por `sh tests/run.sh test_doc-counts.sh`
      (3 PASS) -->
- [x] 9.1.3 Incluir os 2 hooks novos (`posttooluse-jira-sync.sh`,
      `pretooluse-jira-deny-destructive.sh`) na allowlist de
      `tests/test_state-parity-sweep.sh` <!-- Escopo estatico expandido
      (scenario_estatica_sem_acesso_direto_fora_da_allowlist +
      scenario_estatica_allowlist_sem_entradas_mortas) para cobrir
      `plugins/cstk-jira/hooks/*.sh`. `posttooluse-jira-sync.sh` entrou na
      allowlist como `codigo-real` (le `canonical_project` de
      state.json/state.db sem passar por `_state-read.sh`, fallback
      dual-backend simetrico, mesma classe de bloqueios.sh/
      spawn-tracker.sh). `pretooluse-jira-deny-destructive.sh` NAO entrou
      na allowlist: nao tem nenhum hit de `/state\.json` (so inspeciona o
      tool_input do PreToolUse) — uma entrada sem hit falharia
      scenario_estatica_allowlist_sem_entradas_mortas de proposito (a
      mesma guarda anti-drift). Continua coberto pelo escopo varrido para
      deteccao futura -->
- [x] 9.1.4 Teste: `tests/test_doc-counts.sh` e
      `tests/test_state-parity-sweep.sh` verdes apos as edicoes acima
      <!-- `sh tests/run.sh test_doc-counts.sh`: PASS 3 FAIL 0. `sh
      tests/run.sh test_state-parity-sweep.sh`: PASS 4 FAIL 0 (inclui os 2
      cenarios estaticos alterados). `sh tests/run.sh
      test_posttooluse-jira-sync.sh` (12 PASS) e `sh tests/run.sh
      test_pretooluse-jira-deny-destructive.sh` (5 PASS) tambem
      re-confirmados sem regressao -->

### 9.2 Lockstep de versao (MP-5) e CHANGELOG `[M]`

Ref: plan.md Constitution Check Principio I; `scripts/validate-plugin-manifests.sh`
MP-5.

- [x] 9.2.1 `plugins/cstk-jira/.claude-plugin/plugin.json` `.version` ==
      `.claude-plugin/marketplace.json` `.plugins[cstk-jira].version` no
      momento do release (mesma disciplina ja aplicada a `cstk`/
      `cstk-language-go`) <!-- Verificado empiricamente (onda-034): os 3
      manifests (plugins/cstk, plugins/cstk-language-go, plugins/cstk-jira
      `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`)
      ja estavam em lockstep em 10.7.0 antes desta onda (fato verificado
      pelo pai no bootstrap desta retomada) — sem escrita necessaria,
      so confirmacao via `bash scripts/validate-plugin-manifests.sh
      --version 10.7.0 --strict` (OK, 0 avisos) -->
- [x] 9.2.2 Entrada no `CHANGELOG.md` descrevendo o novo plugin cstk-jira
      <!-- Secao `## [Unreleased]` adicionada no topo (nao existia antes),
      formato Keep a Changelog, descrevendo as 3 skills, os 2 hooks, a
      credencial fora do repo e a distribuicao exclusiva via plugin nativo
      (sem profile `cstk install` equivalente) -->
- [x] 9.2.3 Teste: `bash scripts/validate-plugin-manifests.sh --strict`
      verde com as 3 entradas em lockstep de versao (MP-5) <!-- `bash
      scripts/validate-plugin-manifests.sh --version 10.7.0 --strict`:
      "validate-plugin-manifests: OK (0 aviso(s))", exit 0. MP-2 (.plugins
      length==3) e MP-5 (lockstep de versao) ja cobertos pelo script;
      `sh tests/run.sh test_cstk-jira-plugin-manifest.sh` (3 PASS) e `sh
      tests/run.sh test_validate-plugin-manifests.sh` tambem verificados
      -->

Nao ha bump de versao nesta onda (dec explicita): o bump coordenado
(MP-5 + WL-5 do painel) e feito na release pela skill `release-wave`,
fora desta pipeline SDD — as 3 entradas permanecem em 10.7.0 ate la.

### 9.3 Validacao final do quickstart `[M]`

Ref: quickstart.md (todos os cenarios).

- [x] 9.3.1 Percorrer manualmente os Cenarios 1-5 do `quickstart.md`
      (instalacao, inatividade, setup, idempotencia, conflito/orfao)
      contra o plugin implementado <!-- onda-035. Exercitado DE FATO (execucao
      real, ambiente isolado HOME/XDG_CONFIG_HOME em tmp, sem rede real, sem
      tocar .env): Cenario 2 (posttooluse-jira-sync.sh task sem
      .claude/cstk-jira/config -> exit 0, sem stdout, .claude/ nunca criado
      — Expected batido literalmente); Cenario 3 parte offline
      (jira-credential-setup.sh com email/token FIXTURE nao-reais via stdin
      -> credentials 0600, dir cstk-jira 0700, 3 chaves gravadas; em seguida
      `jira-config.sh credential-check` exit 0 contra o arquivo gravado).
      Validado via as 14 suites-gate da FASE 9 rodadas integralmente nesta
      onda (`sh tests/run.sh <arquivo>` individual, nunca padrao "jira"
      amplo): jira-config 12 PASS, jira-tasks 16 PASS, jira-map 16 PASS,
      jira-io 82 PASS (JIRA_IO_BACKOFF_SECONDS=0), jira-sync+
      posttooluse-jira-sync 49 PASS, jira-setup 10 PASS, jira-title 10 PASS,
      jira-convert-parity 1 PASS, jira-conflict-view 8 PASS, jira-contract 8
      PASS, jira-mutation 5 PASS, cstk-jira-plugin-manifest 3 PASS,
      pretooluse-jira-deny-destructive 5 PASS — 0 FAIL/0 ERROR em todas;
      essas suites exercitam via stub de rede por fila os MESMOS passos do
      Cenario 4 (convert cria Epic/Task/Sub-task; 9 reexecucoes = 0 criacoes
      SY-11; task nova acrescentada = so ela e criada SY-12) e do Cenario 5
      (outcome pass/fail drena para status_pass/status_fail SY-*, conflito
      5a nao sobrescreve SY-19, auth_failed 5b SY-31, deferred/429 5c SY-34,
      orphan 5d via jira-map mark-orphans). Validado ESTATICAMENTE (sem
      execucao — exige o harness real do Claude Code, nao reproduzivel em
      ambiente isolado): Cenario 1 (`/plugin marketplace add` + `/plugin
      install` reais, disparo automatico de hooks pelo harness) — conferido
      via test_cstk-jira-plugin-manifest.sh (plugin.json/marketplace.json
      coerentes) + hooks.json listando os 3 matchers + skills jira-setup/
      jira-convert/jira-sync presentes em plugins/cstk-jira/skills/.
      Exige o OPERADOR (nao simulavel, nao bloqueante para esta tarefa):
      Cenario 3 passos 2-5 (token API real do proprio site Jira, MCP Rovo
      interativo, confirmacao humana do mapeamento de tipos de issue —
      ja documentado como MUST nunca-inferir em quickstart.md); Cenario 5
      passo 2 "observar o board" a olho contra um site Jira Cloud real.
      Nenhuma divergencia entre quickstart.md e o comportamento real do
      codigo foi encontrada — quickstart.md nao precisou de correcao. -->
- [x] 9.3.2 Confirmar que o Cenario 6 (roundtrip real) permanece
      documentado como validacao ja executada na FASE 0, sem
      re-executar contra producao <!-- onda-035. Confirmado por leitura: 0.1
      (Roundtrip real contra Jira Cloud de teste [C]) esta [x] com evidencia
      onda-011 (Epic SCRUM-5 + Story SCRUM-6 no projeto SCRUM) e a FASE 4.2.3
      complementou com roundtrip onda-022 contra R6 (SyncMarker via PUT/GET
      property, resolve dec-079). `contracts/jira-rest.md` secao "Roundtrip
      real onda-011" + linhas R1/R3/R4/R5/R6/R8 citam respostas reais
      literais (ids/keys/timestamps observados). `quickstart.md` Cenario 6
      ja documenta o procedimento sem reivindicar reexecucao. NAO
      re-executado contra producao nesta onda (dado factual — nenhuma nova
      chamada de rede real feita). -->

---

## Matriz de Dependencias

```mermaid
flowchart TD
    F0[FASE 0 - Reconferencia Bloqueante REST]
    F1[FASE 1 - Fundacao do Plugin e Marketplace]
    F2[FASE 2 - Persistencia Local]
    F3[FASE 3 - Cliente REST Seguro]
    F4[FASE 4 - Motor de Sincronizacao]
    F5[FASE 5 - Hooks do Ciclo de Vida]
    F6[FASE 6 - Skills Interativas]
    F7[FASE 7 - Board do CSTK]
    F8[FASE 8 - Testes Cross-Cutting]
    F9[FASE 9 - Release e Documentacao]

    F0 --> F3
    F1 --> F2
    F2 --> F3
    F2 --> F4
    F3 --> F4
    F4 --> F5
    F3 --> F6
    F4 --> F6
    F6 --> F7
    F3 --> F8
    F4 --> F8
    F5 --> F8
    F1 --> F9
    F5 --> F9
    F6 --> F9
    F7 --> F9
    F8 --> F9
```

## Resumo Quantitativo

| Fase | Tarefas | Subtarefas | Criticidade |
|------|---------|------------|-------------|
| 0 - Reconferencia Bloqueante REST | 2 | 9 | C |
| 1 - Fundacao do Plugin e Marketplace | 2 | 8 | A |
| 2 - Persistencia Local | 3 | 17 | A |
| 3 - Cliente REST Seguro | 5 | 33 | C/A |
| 4 - Motor de Sincronizacao | 4 | 32 | C/A |
| 5 - Hooks do Ciclo de Vida | 2 | 16 | C |
| 6 - Skills Interativas | 3 | 24 | A |
| 7 - Board do CSTK | 2 | 8 | M |
| 8 - Testes Cross-Cutting | 4 | 15 | C/A |
| 9 - Release e Documentacao | 3 | 9 | M |
| **Total** | **30** | **171** | - |

## Escopo Coberto

| Item | Descricao | Fase |
|------|-----------|------|
| US1 | Converter feature em Epic/Tasks/Subtasks (FR-001/003/013/014) | 4, 6 |
| US2 | Board dedicado do CSTK no Jira (FR-002) | 7 |
| US3 | Sincronizacao automatica de status via hooks (FR-004/005/018) | 4, 5 |
| US4 | Instalacao e configuracao guiada (FR-007/008/009) | 1, 6 |
| FR-006/FR-010 | Suporte MCP (preferencial) + REST (fallback universal) | 3, 6 |
| FR-011 | Deteccao de conflito, sem sobrescrita silenciosa | 4 |
| FR-012 | Card orfao nunca apagado + deny-list de exclusao | 4, 5 |
| FR-015 | Host unico, sem vazamento de rede | 3 |
| FR-016/FR-019-INFRA-REFRESH | Credencial invalida => `auth_failed` explicito | 3, 4 |
| FR-017 | Plugin inativo = zero mudanca de comportamento | 2, 5 |
| SEC-1..SEC-5 (gate owasp-security) | Path/JQL allowlist, UNTRUSTED, credencial temporaria, TLS/redirect | 3, 6 |
| checklists `[Gap]` (api CHK006/CHK009 ja corrigidos em onda-006; security CHK005; ux CHK004) | Confirmacao de tipo de issue; distincao auth_failed/permission_denied; rotulo UNTRUSTED; diagnostico com status disponiveis | 0, 3, 6 |
| MP-2/MP-5 (gate de plugins) | Marketplace com 3 plugins; lockstep de versao | 1, 9 |

## Escopo Excluido

| Item | Descricao | Motivo |
|------|-----------|--------|
| Jira Data Center/Server | Qualquer suporte fora de Jira Cloud | D1 (dec-023/block-004): ambiente-alvo fechado em Jira Cloud |
| Bulk create (ate 50 issues) | Criacao em lote via endpoint de bulk | research Decision 3: fora do MVP; criacao item a item preserva mapeamento atomico |
| Servidor MCP dedicado ao cstk-jira | MCP proprio empacotado pelo plugin | dec-020/block-001: A1 usa o Rovo MCP oficial (configurado pelo usuario) + REST; sem MCP dedicado (FR-010) |
| Renovacao automatica de credencial | Refresh automatico de API token | FR-019-INFRA-REFRESH ramo "nao for possivel" (research Decision 2): API token sem renovacao automatica |
| Feedback de progresso incremental em `jira-convert` | Contagem "N/M issues criadas" durante lotes grandes | ux CHK013 `{humano}`: decisao de produto pendente, registrada como nota em 6.2.7, nao fechada nesta onda |
| Copy exata do diagnostico de token invalido | Texto literal da mensagem de erro de credencial | ux CHK005 `{humano}`: decisao de copy/produto pendente, registrada como nota em 6.1.8 |
| Elevar CHK011 a FR-012 da spec | Explicitar na spec que a guarda so e ativa com config presente | security CHK011 `{humano}`: decisao de escopo pendente, registrada como nota em 6.1.8 |


## FASE 10 - Convergência

> Fase gerada automaticamente pela skill `converge` (reconciliação
> spec-vs-código). Cada tarefa abaixo corresponde a um achado (`Gap`)
> entre o que `spec.md`/`plan.md`/`tasks.md` descreveram e o estado
> presente do código. Tarefas sem o prefixo `[Revisar]` são acionáveis
> (`missing`/`partial`/`contradicts`); tarefas com `[Revisar]` são item de
> revisão (`unrequested`, FR-013) — nunca "implementar", o código já
> existe. Append-only: esta fase nunca reescreve fases/tarefas anteriores
> do arquivo (FR-009).

### 10.1 Convert nao grava criticidade/dependencias na descricao da Task `[C]`

Ref: FR-001 (US1, P1) · tipo: `partial` · severidade: `HIGH`

FR-001 exige que as Tasks espelhem "fases, dependencias e criticidade
quando existirem"; data-model.md:117-121 e tasks.md 2.2.5 fixam que
dependencias/criticidade entram na DESCRICAO da Task. O codigo presente em
`plugins/cstk-jira/scripts/jira-sync.sh` (`_js_cmd_convert`, linhas
541-548) monta o corpo de R1 so com `--project-id`/`--issuetype-id`/
`--summary`/`--parent-key` — nunca passa `--description`, embora
`jira-io.sh json-build issue` ja aceite `--description` (ADF) e
`jira-tasks.sh items` ja emita a coluna `criticality` (coluna 4, lida e
descartada em convert). Dependencias (Matriz de Dependencias) nao sao
extraidas por nenhum script. O caminho MCP
(`plugins/cstk-jira/skills/jira-convert/SKILL.md` ETAPA 2b) tem a mesma
lacuna. Completar e aditivo: compor a descricao (criticidade + dependencias
da task) e passa-la nos dois caminhos, com teste.

- [x] 10.1.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` (e `skills/jira-convert/SKILL.md` ETAPA 2b) conforme `FR-001`: descricao da Task com criticidade e dependencias, coberta por teste em `tests/cstk/test_jira-sync.sh` — implementado em `_js_build_task_description` (`jira-sync.sh`, chamada so para `kind=task`), com criticidade lida da coluna 4 de `jira-tasks.sh items` e dependencias resolvidas pelo novo subcomando `jira-tasks.sh phase-deps` (unica fonte real e extraivel — a secao "## Matriz de Dependencias", grafo FASE-a-FASE; NUNCA inventada por-task, que o template nao tem). Texto: "Criticidade: X", "Depende de: FASE A; FASE B", ou os dois com " | "; nenhum presente => `--description` omitido (corpo de R1 inalterado). Caminho MCP (`skills/jira-convert/SKILL.md` ETAPA 2b passo 3b) documentado reusando a MESMA formula. Testes: `tests/cstk/test_jira-tasks.sh` JT-17..JT-22 (`phase-deps`, 6 cenarios) + `tests/cstk/test_jira-sync.sh` SY-36/37/38 (composicao em `convert`) — `sh tests/run.sh jira-tasks`: 22/22 PASS; `sh tests/run.sh jira-sync`: 52/52 PASS; `tests/cstk/test_jira-contract.sh` atualizado (`ct_r1_task_fields` agora espera a chave `description`) — `sh tests/run.sh jira-contract`: 8/8 PASS; `tests/cstk/test_jira-convert-parity.sh` inalterado (so compara `summary`) — 1/1 PASS. `shellcheck -s sh` limpo em `jira-tasks.sh`/`jira-sync.sh`. `contracts/plugin-scripts.md` atualizado (`phase-deps` documentado + nota de `description` em `convert`).

<!-- converge-key: 7dadd8bdeb4e -->

### 10.2 Issue ja mapeada nunca e atualizada quando o artefato local muda `[C]`

Ref: FR-003 (US1, P1) · tipo: `partial` · severidade: `HIGH`

FR-003 exige "atualizar os issues Jira ja existentes quando o artefato local
correspondente mudar"; plan.md (fluxo 2 "Convert", FR-001/003/013/014) e
research.md:66 mapeiam FR-003 para editar issue (R2/`editJiraIssue`). O
codigo presente em `plugins/cstk-jira/scripts/jira-sync.sh`
(`_js_cmd_convert`, linhas 508-512) pula todo `local_key` ja mapeado
("NENHUMA chamada de criacao") sem nenhum caminho de atualizacao: renomear
uma tarefa no `tasks.md` nunca chega ao `summary` do Jira. R2 nao tem
consumidor em producao (dec-104; so a allowlist `_ji_op_allowed`,
`jira-io.sh`:415-420). A parte de STATUS (FR-004) existe via drain, a de
conteudo nao. Completar e aditivo: detectar divergencia de summary contra o
SyncMarker (`written_summary_sha256`) e emitir R2 respeitando FR-011
(nunca sobrescrever edicao manual) e regravar o SyncMarker.

- [x] 10.2.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `FR-003`: atualizar summary de issue ja mapeada via R2 quando o titulo local mudar, com checagem de conflito FR-011 e teste — implementado em `_js_maybe_update_mapped_issue` (`jira-sync.sh`, chamada para `active` de qualquer `kind`, nunca `orphan`): le o summary atual (R3); se igual ao composto agora, no-op sem tocar rede de novo; se divergente, le o SyncMarker (R6) e SO escreve quando `sha256(summary atual) == written_summary_sha256` (nenhuma edicao manual desde a ultima sync) — PUT R2 (`jira-io.sh json-build issue-update`, subcomando novo, corpo minimo sem project/issuetype/parent) + regrava o SyncMarker (novo hash, `written_status` PRESERVADO). Marker ausente (`marker_missing`) ou divergente (`manual_edit`) => `ConflictRecord` via `_js_append_conflict` (MESMO arquivo/fluxo de `resolve` da FASE 4.3), NUNCA sobrescreve (FR-011). Falha de rede durante a checagem/escrita: diagnostico em stderr, item pulado sem abortar o `convert` inteiro (itens novos continuam sendo criados). Gap conhecido documentado (nao fechado nesta tarefa, fora do escopo declarado — so `jira-sync.sh` foi pedido): caminho MCP (`skills/jira-convert/SKILL.md` ETAPA 2b) ainda so pula item mapeado, sem checar atualizacao. Testes: `tests/cstk/test_jira-sync.sh` SY-39 (atualiza sem conflito, preserva `written_status`, jira-map.tsv inalterado) + SY-40 (`marker_missing`) + SY-41 (`manual_edit`, mesmo com titulo local tambem mudado) — `sh tests/run.sh jira-sync`: 55/55 PASS (fixturas de idempotencia SY-11/SY-12 atualizadas para as novas chamadas R3 de checagem; corrigido de brinde um bug latente em `_queue_post_issue_calls_count` do proprio harness de teste — `grep -c` sem match imprimia "00" por causa do `||` de fallback, nunca exercitado ate a 1a asserção de "0 criacoes"). `tests/cstk/test_jira-contract.sh`/`test_jira-convert-parity.sh`/`test_jira-io.sh` inalterados — 8/8, 1/1, 82/82 PASS. `shellcheck -s sh` limpo em `jira-sync.sh`/`jira-io.sh`. `contracts/plugin-scripts.md` atualizado (`json-build issue-update` documentado + nota de update/FR-011 em `convert`).

<!-- converge-key: a8482095dfaf -->

### 10.3 Reconciliacao da feature inteira (local_key=*) nunca processada `[C]`

Ref: FR-004 (US3, P1) · tipo: `partial` · severidade: `HIGH`

FR-004 exige refletir "iniciada, concluida com sucesso, concluida com falha"
no card; US3 cenario 1 exige o card em "em andamento" quando a tarefa
comeca; US2 cenario 1 espera Epics na coluna do estagio atual. O unico
gatilho que carrega `in_progress`/estado de Epic/Sub-task e o evento
`reconcile` com `local_key=*` que o hook enfileira no `close_wave`
(`plugins/cstk-jira/hooks/posttooluse-jira-sync.sh`:155-158) —
`record_task` so traz `pass`/`fail`. Em
`plugins/cstk-jira/scripts/jira-sync.sh` (`_js_process_one_event`,
linhas 687-691) esse evento e deixado `queued` com o diagnostico
"reconciliacao de feature inteira (local_key=*) ainda nao implementada"
(limitacao registrada em tasks.md 4.2 sem tarefa de seguimento), e
`desired_state=reconcile` nao tem status alvo (linhas 715-718). Efeitos:
card nunca vai para "em andamento"; Epic/Sub-tasks nunca mudam de coluna;
o outbox acumula 1 evento `queued` por onda, nunca compactado. Completar
e aditivo: expandir `*` em eventos por item a partir de
`jira-tasks.sh items` (local_state ja derivado) e processa-los pelo
caminho existente.

- [x] 10.3.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `FR-004`: processar `reconcile`/`local_key=*` (in_progress, Epic, Sub-tasks) e fechar o evento, com teste em `tests/cstk/test_jira-sync.sh` — implementado em `_js_process_reconcile_event` (`jira-sync.sh`), chamada pelo guard `local_key = "*"` de `_js_process_one_event` (substitui a mensagem "ainda nao implementada"): expande o evento via `jira-tasks.sh items --feature F` (Epic + Tasks + Sub-tasks, `local_state` ja derivado dos checkboxes/agregacao) e processa CADA item ja mapeado (`active` em `jira-map.tsv`) pelo MESMO nucleo R3/R6-GET/conflito/R5/R4/R6-PUT usado por um evento direto — deliberadamente duplicado (prefixo `_jspr_`) em vez de refatorar `_js_process_one_event`, para nao arriscar regressao nos cenarios ja cobertos de evento direto (SY-18..41). Item ainda sem mapeamento (nao convertido) e ignorado silenciosamente; item `orphan` vira `ConflictRecord` (reason=`orphan`) sem interromper os demais. Idempotente: item ja no status alvo (SyncMarker batendo) faz SOMENTE R3+R6-GET, sem R5/R4 (nenhuma chamada de escrita). Conflito (`marker_missing`/`manual_edit`) em um item grava `ConflictRecord` mas NUNCA impede o processamento dos demais itens (FR-011 e por item); SOMENTE `auth_failed` interrompe a reconciliacao inteira (mesmo gate FR-016/`_JSPE_BREAK` de um evento direto), marcando o evento `*` `auth_failed`. Sem `auth_failed`/`deferred` em nenhum item, o evento `*` fecha `done` (compactado no PROXIMO `drain` — a proxima reconciliacao nasce de um NOVO evento `*` enfileirado no proximo `close_wave`, sempre com o estado local mais recente). Testes: `tests/cstk/test_jira-sync.sh` SY-42 (expande Epic+Task+Sub-task, Epic e Sub-task transicionam via R5/R4/R6-PUT, Task ja no alvo fica idempotente SOMENTE R3+R6-GET, evento fecha `done`, 2a chamada de `drain` compacta o evento) + SY-43 (conflito manual_edit no Epic NAO impede a Task de transicionar; evento ainda fecha `done`; ConflictRecord do Epic gravado) + SY-44 (401 no 1o item aborta a reconciliacao inteira, evento vira `auth_failed`, Task nunca e tocada, exatamente 1 chamada) — `sh tests/run.sh jira-sync`: 58/58 PASS. `tests/cstk/test_jira-contract.sh` inalterado (mesmas operacoes R3/R5/R4/R6 ja contratadas) — 8/8 PASS. `shellcheck -s sh` limpo em `jira-sync.sh`/`test_jira-sync.sh`. `contracts/plugin-scripts.md` atualizado (`drain` documenta a expansao de `local_key=*`).

<!-- converge-key: 29ad68918254 -->

## FASE 11 - Convergência

> Fase gerada automaticamente pela skill `converge` (reconciliação
> spec-vs-código). Cada tarefa abaixo corresponde a um achado (`Gap`)
> entre o que `spec.md`/`plan.md`/`tasks.md` descreveram e o estado
> presente do código. Tarefas sem o prefixo `[Revisar]` são acionáveis
> (`missing`/`partial`/`contradicts`); tarefas com `[Revisar]` são item de
> revisão (`unrequested`, FR-013) — nunca "implementar", o código já
> existe. Append-only: esta fase nunca reescreve fases/tarefas anteriores
> do arquivo (FR-009).

### 11.1 Convert nunca grava o SyncMarker das issues que cria `[C]`

Ref: FR-011 / plan.md Fluxo 2 grava SyncMarker (US1+US3, P1) · tipo: `partial` · severidade: `HIGH`

plan.md:116-119 (Fluxo 2 "Convert") fixa "grava `jira-map.tsv` item a item;
grava SyncMarker", e data-model.md:161-165 diz que o SyncMarker e "Gravado
em cada issue sincronizada". O codigo presente em
`plugins/cstk-jira/scripts/jira-sync.sh` (`_js_cmd_convert`, linhas 764-780)
faz so R1 (POST issue) + `jira-map.sh put` — nenhuma chamada R6 PUT apos a
criacao (o unico R6 PUT fora do drain esta em `_js_maybe_update_mapped_issue`,
que so roda para item JA mapeado e divergente). Efeito: o 1o evento de drain
de qualquer issue recem-criada le R6 = 404 e cai em `marker_missing`
(`jira-sync.sh`:1180-1182) -> ConflictRecord, NUNCA transiciona: a
sincronizacao de status da US3 so funciona apos `resolve` manual item a
item. Completar e aditivo: apos cada R1 bem-sucedido (e do `jira-map.sh
put`), gravar o SyncMarker inicial (`written_summary_sha256` do summary
enviado + `written_status` LIDO da issue via R3, nunca suposto) via
`json-build marker` + R6 PUT, com falha de R6 reportada sem desfazer a
criacao; teste cobrindo convert -> drain sem conflito.

- [x] 11.1.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `FR-011 / plan.md Fluxo 2 grava SyncMarker`: gravar o SyncMarker inicial de cada issue criada em `convert`, com teste end-to-end convert -> drain (sem `marker_missing`) em `tests/cstk/test_jira-sync.sh`

<!-- converge-key: 0d757d6034f9 -->

### 11.2 Caminho MCP do jira-convert sem SyncMarker nem atualizacao de item mapeado `[C]`

Ref: FR-003 / CHK012 / task 6.2.3 (US1, P1) · tipo: `partial` · severidade: `HIGH`

tasks.md 6.2.3 e checklists/api.md CHK012 exigem que os caminhos MCP e REST
produzam "o MESMO efeito observavel (mesmo mapeamento, mesmo SyncMarker)";
FR-003 exige atualizar issue ja existente quando o artefato local mudar.
Em `plugins/cstk-jira/skills/jira-convert/SKILL.md` (ETAPA 2b) o passo 1
(linhas 116-123) documenta como "Gap conhecido" que item mapeado e SEMPRE
pulado (sem o equivalente de `_js_maybe_update_mapped_issue`), e os passos
6-7 (linhas 173-188) gravam so `jira-map.sh put` — nenhum SyncMarker. Os
parametros de `editJiraIssue`/`editJiraEntityProperty` seguem `NAO
ENCONTRADO` em `contracts/rovo-mcp.md`:69, entao a paridade NAO pode ser
fechada inventando schema de tool (Principio VI); o caminho sem fabricacao
e delegar ao REST ja exigido na ETAPA 1 (mesmo padrao do passo 2, que ja
usa `jira-io.sh request`): gravar o SyncMarker inicial e checar/atualizar
itens mapeados via os scripts do plugin. Completar e aditivo (passos novos
na ETAPA 2b + subcomando/reuso de script se necessario).

- [x] 11.2.1 Implementar/corrigir `plugins/cstk-jira/skills/jira-convert/SKILL.md` conforme `FR-003 / CHK012 / task 6.2.3`: caminho MCP grava o SyncMarker inicial de cada issue criada e aplica a mesma checagem/atualizacao de item mapeado do caminho REST, delegando ao REST (sem inventar `inputSchema`), removendo a nota de "Gap conhecido"

<!-- converge-key: ee06652ddf72 -->

### 11.3 Update de issue mapeada ignora status na deteccao de conflito `[C]`

Ref: FR-011 / data-model SyncMarker deteccao de conflito / task 10.2.1 (US1, P1) · tipo: `contradicts` · severidade: `HIGH`

data-model.md:181-185 fixa que, "antes de toda escrita numa issue
existente", o plugin le titulo + status atuais e o SyncMarker, e que
`sha256(titulo_atual) != written_summary_sha256` OU `status_atual !=
written_status` => NAO escrever, gerar ConflictRecord. Os dois caminhos de
drain seguem a regra (`jira-sync.sh`:995 e :1186 comparam sha E status),
mas `_js_maybe_update_mapped_issue` em
`plugins/cstk-jira/scripts/jira-sync.sh` le so `?fields=summary` (linha
544) e compara so o hash do titulo (linha 584): um card cujo status foi
movido manualmente no Jira recebe o PUT R2 de summary sem ConflictRecord
naquele momento. Corrigir exige mudar a leitura R3 e a condicao ja
presentes (incluir `status` e `written_status` na comparacao).

- [x] 11.3.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `FR-011 / data-model SyncMarker deteccao de conflito / task 10.2.1`: `_js_maybe_update_mapped_issue` le `summary,status` e trata `status_atual != written_status` como `manual_edit` (sem escrever), com teste em `tests/cstk/test_jira-sync.sh`

<!-- converge-key: ebe0be4d2d21 -->

## FASE 12 - Convergência

> Fase gerada automaticamente pela skill `converge` (reconciliação
> spec-vs-código). Cada tarefa abaixo corresponde a um achado (`Gap`)
> entre o que `spec.md`/`plan.md`/`tasks.md` descreveram e o estado
> presente do código. Tarefas sem o prefixo `[Revisar]` são acionáveis
> (`missing`/`partial`/`contradicts`); tarefas com `[Revisar]` são item de
> revisão (`unrequested`, FR-013) — nunca "implementar", o código já
> existe. Append-only: esta fase nunca reescreve fases/tarefas anteriores
> do arquivo (FR-009).

### 12.1 `resolve overwrite`/`keep_jira` nao destravam o conflito: o drain re-detecta contra o mesmo SyncMarker `[C]`

Ref: FR-011 / task 4.3.2 / task 4.3.4 resolve (US3, P1) · tipo: `contradicts` · severidade: `HIGH`

tasks.md 4.3.4 exige que os 3 `--choice` produzam "mantem estado do Jira /
sobrescreve / apenas fecha o registro"; `skills/jira-sync/SKILL.md`:106-107
promete que `overwrite` "reenfileira o `desired_state` local para
sobrescrever o Jira no proximo drain". Em
`plugins/cstk-jira/scripts/jira-sync.sh`, `_js_cmd_resolve` (linhas
1590-1595) so reenfileira um evento novo, sem tocar o SyncMarker; o proximo
`drain` (`_js_process_one_event`, linhas 1248-1267) repete a MESMA
comparacao contra o marker inalterado (a edicao manual continua no Jira) e
grava um ConflictRecord NOVO (o anterior ja fechado nao casa
`_js_conflict_pending_exists`) — `overwrite` nunca sobrescreve. Idem
`keep_jira`: o marker nao e rebaselinado para o estado atual do Jira, entao
todo evento/reconciliacao posterior daquele item re-abre o conflito (a cada
`close_wave`, via `_js_process_reconcile_event`). Alem disso,
`_js_last_conflict_desired_state` (linhas 357-368) so acha `desired_state`
em evento outbox `conflict` com o MESMO `local_key` — conflitos gerados pela
reconciliacao `local_key=*` ou por `convert` (`_js_maybe_update_mapped_issue`)
nao tem essa linha, e `resolve --choice overwrite` sai exit 1 para eles.
Mensagens que prometem destravamento inexistente: linha 647 ("resolve
--choice keep_jira destrava") e linha 698 ("ate a proxima convert" — convert
nao regrava marker ausente de item ja mapeado). Corrigir exige mudar a
logica de `resolve`/deteccao ja presente (ex.: `keep_jira` regrava o
SyncMarker com o summary-sha/status ATUAIS lidos via R3; `overwrite`
regrava o marker antes de reenfileirar, ou o evento carrega marca de
override aceita pelo drain), com fonte de `desired_state` para conflitos de
reconciliacao/convert — sem inventar campo REST (so R3/R6 de
`contracts/jira-rest.md`).

- [x] 12.1.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `FR-011 / task 4.3.2 / task 4.3.4 resolve`: `resolve --choice keep_jira` e `--choice overwrite` passam a ter efeito duravel (drain seguinte nao re-abre o mesmo conflito; overwrite de fato transiciona), `overwrite` funciona para conflitos vindos de reconcile/convert, mensagens das linhas 647/698 corrigidas, com teste end-to-end resolve -> drain em `tests/cstk/test_jira-sync.sh`

<!-- converge-key: bd4a7d7b55f4 -->

### 12.2 Evento `deferred` nunca volta a ser processado pelo drain `[C]`

Ref: data-model OutboxEvent deferred->queued / task 3.4.4 (US3, P1) · tipo: `contradicts` · severidade: `HIGH`

data-model.md:208-209 fixa `queued --> deferred: 429 / rede / timeout
(respeita Retry-After)` e `deferred --> queued: proximo gatilho de drain`;
contracts/plugin-scripts.md (tabela de status HTTP, linha 429) diz que
"quem decide quando reenviar e o chamador". Em
`plugins/cstk-jira/scripts/jira-sync.sh`, `_js_cmd_drain` (linhas
1422-1423) seleciona SO `$8 == "queued"`; nenhum codigo do plugin move
`deferred` de volta a `queued`, e o `retry_after` emitido por `jira-io.sh`
em stderr e descartado (`2>/dev/null` nas chamadas R3/R5/R4). Efeito: um
unico 429/5xx/timeout deixa o card permanentemente desatualizado (US3
cenarios 2-3 nao se cumprem "ate o fim da mesma onda"). Corrigir exige
mudar o filtro de selecao do drain (incluir `deferred` elegivel, respeitando
o `retry_after` registrado quando houver) — decidir onde persistir o
`retry_after` sem inventar coluna fora do data-model (ou atualizar o
data-model junto).

- [x] 12.2.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `data-model OutboxEvent deferred->queued / task 3.4.4`: `drain` reprocessa eventos `deferred` (respeitando Retry-After), com teste em `tests/cstk/test_jira-sync.sh` (429 -> deferred -> drain seguinte transiciona)

<!-- converge-key: 600a43fbdf2a -->

### 12.3 Drain sem `jq`/cliente HTTP nao sai exit 5 e degrada eventos para `deferred` `[C]`

Ref: contracts/plugin-scripts.md exit 5 carve-out 1.1.0 (a) (US3, P1) · tipo: `contradicts` · severidade: `HIGH`

contracts/plugin-scripts.md:97-99 fixa que, sem `jq`/cliente HTTP, "o que
degrada e o sync AUTONOMO, que sai com exit 5 + diagnostico e mantem os
eventos no outbox para o proximo `jira-sync` interativo"; o proprio help de
`plugins/cstk-jira/scripts/jira-sync.sh` (linhas 202-205) declara "5
dependencia ausente (convert; drain com eventos queued exige jq/cliente
HTTP/sha256sum-shasum)" e `jira-io.sh`:10 diz que o drain trata esse
fallback. O `_js_cmd_drain` nunca roda `jira-io.sh deps-check`: o exit 5 de
`jira-io.sh request` cai no ramo generico e o evento vira `deferred`
(`_js_process_one_event`, linha 1216) e o drain termina `exit 0` (linha
1460) — combinado com 12.2, o evento fica encalhado. Corrigir exige mudar o
fluxo do drain: `deps-check` antes do 1o evento `queued`, saindo exit 5 com
os eventos intocados em `queued`.

- [x] 12.3.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `contracts/plugin-scripts.md exit 5 carve-out 1.1.0 (a)`: `drain` com eventos `queued` e dependencia ausente sai exit 5 com diagnostico e SEM mudar o status dos eventos, com teste em `tests/cstk/test_jira-sync.sh` (PATH sem `jq`)

<!-- converge-key: 5cc05d2d87e6 -->

### 12.4 Outcome de `record_task` nao tem precedencia na reconciliacao: nenhum `--outcomes-file` e produzido `[C]`

Ref: data-model LocalWorkItem outcome precedence / US3 cenarios 2-3 (US3, P1) · tipo: `partial` · severidade: `HIGH`

data-model.md:114 fixa que, para `kind=task`, o "outcome registrado da task
(`record_task`/`record-task`: `pass`/`fail`) tem precedencia" sobre os
checkboxes; contracts/plugin-scripts.md:68 delega a gravacao desse arquivo a
"`jira-sync.sh`/hooks". Nenhum script do plugin grava um outcomes-file nem
passa `--outcomes-file` a `jira-tasks.sh items` (unicas referencias sao em
`plugins/cstk-jira/scripts/jira-tasks.sh`; chamadas em
`plugins/cstk-jira/scripts/jira-sync.sh` linhas 423, 735 e 975 sem a flag;
`hooks/posttooluse-jira-sync.sh` so enfileira). Efeito: o evento direto de
`record_task` leva o card a `pass`/`fail`, mas a reconciliacao `local_key=*`
do `close_wave` seguinte deriva o estado SO dos checkboxes e — sem conflito,
porque o marker foi gravado pelo proprio plugin — pode mover o card de volta
(ex.: `fail` registrado com subtasks `[x]`, ou `pass` com subtask `[ ]`
remanescente). Completar e aditivo: persistir `task_id<TAB>outcome` no
runtime quando o evento de `record_task` e enfileirado/processado e passar
`--outcomes-file` na expansao da reconciliacao.

- [ ] 12.4.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `data-model LocalWorkItem outcome precedence / US3 cenarios 2-3`: outcome de `record_task` persistido e usado via `--outcomes-file` em `_js_process_reconcile_event`, com teste em `tests/cstk/test_jira-sync.sh` (record_task fail + checkboxes `[x]` -> reconcile NAO move para pass)

<!-- converge-key: 41370f6418f8 -->

### 12.5 Descricao (criticidade/dependencias) de item ja mapeado nunca e atualizada sozinha `[C]`

Ref: FR-003 / task 10.2.1 description drift (US1, P1) · tipo: `partial` · severidade: `HIGH`

FR-003 exige atualizar a issue "quando o artefato local correspondente
mudar"; contracts/plugin-scripts.md:85 e `skills/jira-convert/SKILL.md`
(ETAPA 2b passo 8) documentam que a checagem cobre "summary/description
compostos AGORA". Em `plugins/cstk-jira/scripts/jira-sync.sh`,
`_js_maybe_update_mapped_issue` (linha 567) retorna cedo quando o summary
nao mudou — uma mudanca so de criticidade (`[C|A|M]`) ou da Matriz de
Dependencias nunca chega a `fields.description`. O SyncMarker so guarda
`written_summary_sha256`, entao atualizar descricao sem protecao FR-011
arriscaria sobrescrever edicao manual. Completar e aditivo: estender a
deteccao para a descricao (ex.: hash da descricao escrita no SyncMarker,
atualizando data-model.md) OU, se a leitura de `description` via R3 nao
tiver fonte em `contracts/jira-rest.md` (Principio VI), restringir
explicitamente a documentacao (contrato + SKILL.md) a "summary-only".

- [ ] 12.5.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `FR-003 / task 10.2.1 description drift`: mudanca so de criticidade/dependencias propaga para a descricao da Task respeitando FR-011 (ou escopo summary-only documentado com fonte), com teste em `tests/cstk/test_jira-sync.sh`

<!-- converge-key: 3fb17fd6f483 -->

### 12.6 Reconfiguracao nao devolve eventos `auth_failed` a fila: sync fica bloqueado para sempre `[A]`

Ref: FR-016 / data-model OutboxEvent auth_failed->queued (US4, P2) · tipo: `partial` · severidade: `MEDIUM`

data-model.md:212 fixa `auth_failed --> queued: operador reconfigura
(jira-setup)`. `plugins/cstk-jira/scripts/jira-setup.sh` (so
`check-status-mapping`/`write-config`) e `skills/jira-setup/SKILL.md` nunca
tocam o outbox; o gate de `_js_cmd_drain` (`jira-sync.sh` linhas 1414-1420)
continua vendo o `auth_failed` e bloqueia a feature mesmo apos credencial
valida reconfigurada. Completar e aditivo: apos o setup validar a credencial
(`GET /rest/api/3/myself`), reenfileirar (`auth_failed` -> `queued`) os
eventos, via subcomando novo no motor ou passo do setup.

- [ ] 12.6.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-setup.sh` conforme `FR-016 / data-model OutboxEvent auth_failed->queued`: reconfiguracao bem-sucedida devolve eventos `auth_failed` a `queued`, com teste

<!-- converge-key: dfa8fab2ef16 -->

### 12.7 Hook descarta todo diagnostico do drain: `auth_failed`/conflitos nunca sao sinalizados na execucao autonoma `[A]`

Ref: FR-016 / data-model ConflictRecord resumo do hook · tipo: `partial` · severidade: `MEDIUM`

FR-016 exige "solicitar reconfiguracao de forma explicita"; data-model.md
(Entity ConflictRecord) diz que o registro e consumido tambem "pelo resumo
emitido pelo hook no fechamento de onda". Em
`plugins/cstk-jira/hooks/posttooluse-jira-sync.sh` (linhas 188-193) enqueue e
drain rodam com `>/dev/null 2>&1`; nenhum resumo e produzido no
`close_wave` e `runtime/hook.log` so recebe a linha de no-op por
candidatos. Na execucao autonoma o operador so descobre credencial expirada
ou conflito rodando `jira-sync.sh status` manualmente. Completar e aditivo,
sem quebrar o fail-open (exit 0 sempre): anexar stderr do drain e um resumo
(conflitos pendentes/`auth_failed`) em `runtime/hook.log` e/ou emitir o
resumo no fechamento de onda.

- [ ] 12.7.1 Implementar/corrigir `plugins/cstk-jira/hooks/posttooluse-jira-sync.sh` conforme `FR-016 / data-model ConflictRecord resumo do hook`: diagnostico do drain + resumo de conflitos/`auth_failed` persistidos/emitidos no fechamento de onda, mantendo fail-open, com teste

<!-- converge-key: c935b453652f -->

### 12.8 `stage_status.<stage>` nunca e aplicado ao Epic `[A]`

Ref: data-model ProjectConfig stage_status / US2 cenario 1 (US2, P2) · tipo: `partial` · severidade: `MEDIUM`

data-model.md:61 e :115 fixam que o `local_state` do Epic segue
`stage_status.<stage>` da etapa corrente quando configurado (US2 cenario 1:
Epics na coluna do estagio atual). Nenhuma chamada a `jira-tasks.sh items`
em `plugins/cstk-jira/scripts/jira-sync.sh` passa `--stage` (linha 975, na
reconciliacao); e mesmo que passasse, `jira-tasks.sh` (linha ~299) poe o
VALOR do override (nome de status Jira) em `local_state`, que
`_js_process_reconcile_event` descarta no `*) continue` (linhas 1013-1014).
Completar e aditivo: obter a etapa corrente (fonte real, ex.: o state da
execucao ativa lido READ-ONLY, sem inventar) e tratar o override como status
alvo direto na reconciliacao.

- [ ] 12.8.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-sync.sh` conforme `data-model ProjectConfig stage_status / US2 cenario 1`: reconciliacao aplica `stage_status.<stage>` ao Epic quando configurado, com teste em `tests/cstk/test_jira-sync.sh`

<!-- converge-key: 39dbe81777b3 -->

### 12.9 Credencial nao e vinculada ao `site_host`: editar o config versionado desvia o token `[A]`

Ref: FR-015 / plan.md credencial resolvida por site_host · tipo: `partial` · severidade: `MEDIUM`

plan.md:237-238 declara como controle confirmado "credencial resolvida POR
`site_host` (alterar o host no config versionado nao desvia o token para
outro host)"; data-model.md (Entity Credential) define `site_host` como
chave de lookup, e `skills/jira-setup/scripts/jira-credential-setup.sh`
(linha 87) grava `site_host=` no arquivo. `plugins/cstk-jira/scripts/jira-io.sh`
(`_ji_cred_read`, linhas 376-395; `request`, linhas 657-664) le so
`email`/`api_token` e nunca compara o `site_host` da credencial com o de
ProjectConfig (linhas 623-627): trocar `site_host` no config versionado
envia o token para o novo host. Completar e aditivo: exigir igualdade exata
entre os dois antes de montar o header de autenticacao (senao exit 4 sem
requisicao).

- [ ] 12.9.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-io.sh` conforme `FR-015 / plan.md credencial resolvida por site_host`: `request` recusa (exit 4, sem requisicao) quando `site_host` da credencial difere do ProjectConfig, com teste em `tests/cstk/test_jira-io.sh`

<!-- converge-key: 731aea8ed951 -->

### 12.10 `relink` nao cobre renumeracao nem fecha o ConflictRecord `orphan` como `relinked` `[A]`

Ref: FR-012 / data-model SyncMapping orphan->active relinked · tipo: `partial` · severidade: `MEDIUM`

`skills/jira-sync/SKILL.md` (ETAPA 3) promete religar o card orfao "a um
`local_key` novo/existente" (spec.md edge case de tarefa renumerada);
data-model.md lista `resolution=relinked` no ConflictRecord e
`orphan --> active: operador religa`. Em
`plugins/cstk-jira/scripts/jira-map.sh` (`_jm_cmd_relink`, linhas 278-317) so
reativa o MESMO `local_key` orfao (que, se sumiu de `tasks.md`, e remarcado
`orphan` pelo proximo `mark-orphans`) — renumeracao 2.3->2.4 gera card
duplicado no proximo `convert`; e nada fecha o ConflictRecord `orphan`
pendente como `relinked` (nenhum codigo produz esse valor), o que tambem
suprime conflitos futuros do par via `_js_conflict_pending_exists`
(ignora `reason`). Completar e aditivo: relink para `local_key` novo
(mover a linha do mapeamento) e fechamento `relinked` do registro pendente.

- [ ] 12.10.1 Implementar/corrigir `plugins/cstk-jira/scripts/jira-map.sh` conforme `FR-012 / data-model SyncMapping orphan->active relinked`: relink para `local_key` novo (renumeracao) + fechamento do ConflictRecord `orphan` como `relinked`, com teste em `tests/cstk/test_jira-map.sh`

<!-- converge-key: 9f3c0e52b0de -->

### 12.11 Contrato `plugin-scripts.md` desatualizado frente ao codigo `[A]`

Ref: contracts/plugin-scripts.md completeness / tasks 11.1.1 11.3.1 · tipo: `partial` · severidade: `MEDIUM`

`docs/specs/cstk-jira/contracts/plugin-scripts.md` (linha 85, linha
`convert`) ainda descreve a checagem de conflito do update como so
`sha256(summary atual) == written_summary_sha256` (11.3.1 passou a comparar
status tambem) e nao menciona o SyncMarker inicial gravado apos R1
(11.1.1). A tabela de `jira-io.sh` (linhas 28-37) omite `json-build
marker|transition|board` e `sha256-stdin` (`jira-io.sh` linhas 297-331), e
nao ha secao para `jira-title.sh compose`, `jira-conflict-view.sh` e
`jira-setup.sh check-status-mapping|write-config`. Completar e aditivo
(documentacao, sem mudar codigo).

- [ ] 12.11.1 Implementar/corrigir `docs/specs/cstk-jira/contracts/plugin-scripts.md` conforme `contracts/plugin-scripts.md completeness / tasks 11.1.1 11.3.1`: documentar os subcomandos ausentes e atualizar a linha `convert` (marker inicial + comparacao de status)

<!-- converge-key: 25f9d2e1ff46 -->

### 12.12 `jira-setup` nao exibe o lembrete de validade do API token `[A]`

Ref: plan.md risco 5 / FR-019-INFRA-REFRESH lembrete de validade (US4, P2) · tipo: `partial` · severidade: `MEDIUM`

plan.md:187 (ponto 5, FR-019-INFRA-REFRESH) fixa que "`jira-setup` exibe a
data de validade informada pelo operador como lembrete". Nem
`plugins/cstk-jira/skills/jira-setup/SKILL.md` nem
`skills/jira-setup/scripts/jira-credential-setup.sh` coletam ou exibem essa
data (nenhuma ocorrencia de "validade"/"expira"). Completar e aditivo: passo
que coleta a data informada pelo operador (nunca inventada) e a exibe como
lembrete, sem gravar segredo.

- [ ] 12.12.1 Implementar/corrigir `plugins/cstk-jira/skills/jira-setup/SKILL.md` conforme `plan.md risco 5 / FR-019-INFRA-REFRESH lembrete de validade`: coletar/exibir a data de validade do API token informada pelo operador

<!-- converge-key: 56ce1b369eea -->
