# Adaptador Codex — piloto local

Status: controlador supervisionado, seis workflows 00c, respostas humanas,
aborto auditável, transferência explícita e reconciliação implementados.
Autonomia nativa não certificada. As entradas feature-00c/agente-00c e suas
variantes resume/abort reutilizam o mesmo controlador.
Projeto começa em briefing e termina em review-features (11 etapas); o modo
roadmap explícito seleciona briefing, constitution e roadmap.
Plano e critérios: [plan.md](../../docs/specs/codex-feature-00c/plan.md).

## Instalação pelo CSTK

```sh
cstk install --cli=codex
cstk install --cli=codex --dry-run
cstk install --cli=codex --knowledge-db /caminho/compartilhado/knowledge.db
```

No checkout, use `sh cli/cstk install --cli=codex`. A CLI já instalada precisa
ser atualizada a partir de uma release que contenha esta implementação.
O comando usa o checkout quando disponível, ou baixa/verifica a release e
consome catalog/codex. Instala o plugin nativo, MCP e hooks no CODEX_HOME
(default ~/.codex), por comandos oficiais do Codex. Requer shell POSIX e SHA-256; jq/sqlite3 são requisitos do estado canônico e Codex com suporte a plugin add. Aceita --codex-home para instalação
isolada; escopo global e pacote completo das seis entradas, perfil sdd/all.

Configura knowledge.db no env explícito do MCP. Não cria nem migra o banco
durante instalação. Os defaults preservam o índice compartilhado legado.
Configurações de outros plugins e arquivos Claude são preservados. O instalador
mescla seus dois handlers em CODEX_HOME/hooks.json, preservando handlers
existentes e protegendo alterações locais nos registros CSTK. Os comandos
apontam para o pacote imutável identificado por hash, para que alterações de
pacote mudem a definição sujeita à revisão. Na cópia instalada, hooks de
plugin ficam explicitamente desativados para evitar execução/contagem dupla.
O pacote de autoria mantém a declaração de hooks para distribuição manual.
Reinstalação protege alterações locais no pacote/cache com exit 4; contenção
de instalação retorna exit 3. Configuração/instalação usam o Codex CLI,
conforme [a documentação oficial](https://developers.openai.com/plugins/build/plugins).
Nenhuma confiança de hook é concedida: inicie nova sessão e revise /hooks.
Codex 0.160.0 listou esses handlers na camada user, habilitados/untrusted,
com zero erros/avisos. A mesma instalação não listou os hooks somente pelo
manifest do plugin; por isso o instalador registra a configuração explícita.

## Entradas e ciclo de vida

| Feature | Projeto | Operação |
| --- | --- | --- |
| feature-00c | agente-00c | Criar e conduzir a pipeline |
| feature-00c-resume | agente-00c-resume | Retomar etapa persistida e responder bloqueios |
| feature-00c-abort | agente-00c-abort | Abortar preservando artefatos e auditoria |

As seis são skills nativas, descobertas pelo Codex com prefixo
cstk-codex-pilot:. O contrato detalhado está em
[lifecycle.md](skills/feature-00c/references/lifecycle.md).
cstk_resume abre e mantém a onda na mesma conexão MCP; um bloqueio devolve
as perguntas sem abrir onda. cstk_abort encerra onda própria, grava estado
terminal JSON/SQLite, backup/relatório filtrados e ingestão best-effort.
purge_backups só se solicitado. Opt-ins anteriores não são repetidos.
cstk_handoff guarda a proveniência anterior quando o operador autoriza
continuar uma execução Claude no Codex. cstk_reconcile_governance exige
hashes atuais revisados e justificativa, mantendo snapshots anteriores.

Execute o preflight sem instalar nem alterar o projeto-alvo:

```sh
sh adapters/codex/skills/feature-00c/scripts/context.sh --project /caminho/projeto --short-name minha-feature
```

Para projeto novo, acrescente `--kind project` e use a identidade canônica do
projeto como `--short-name` em todos os comandos. Não exige governança prévia.
Após bootstrap, registre as três respostas reais usando optins.sh com
`--field atomic_commit --value false`, `--field roadmap_mode --value false`
e `--field delivery_tier --value local` (valores escolhidos pelo operador),
sempre com `--channel` e `--response-source`. A skill
[agente-00c](skills/agente-00c/SKILL.md) detalha os contratos.

O transporte `sh mcp-bridge.sh`, selecionado por cstk_select_execution, expõe initialize, tools/list e tools/call por stdio JSON-RPC,
conforme a [especificação MCP](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).
Preserva um único proprietário entre chamadas e fecha a onda no EOF/SIGTERM.
O manifest portátil plugin.json e o mcp.json registram `cstk_pipeline`.
O app-server nativo conectou e exercitou o ciclo de vida pelas quinze ferramentas; isso não comprova
cobertura dos hooks em um turno de modelo.

O servidor nativo começa sem projeto selecionado, pois o Codex inicia MCPs
portáteis no diretório instalado do plugin. cstk_select_execution vincula
`project` absoluto, `kind` e `short_name`; uma onda aberta impede troca da
execução, e outro projeto exige reiniciar o servidor. Informe `knowledge_db`
absoluto quando configurado: o host não repassou CSTK_KNOWLEDGE_DB nos testes.
Sem override, o default legado permanece. Confirme cstk_context antes de abrir
uma onda. Nenhum estado é criado apenas ao conectar o servidor.

O comando retorna JSON, exit 0 quando os pré-requisitos locais existem,
exit 1 quando faltam, exit 2 para argumentos inválidos. `autonomous_ready`
continua false: este diagnóstico não verifica enforcement no Codex.

A skill pode ser lida diretamente deste checkout durante desenvolvimento.
O pacote tem instalação local validada com Codex CLI em CODEX_HOME isolado.
O harness 0.160.0 descobriu as entradas como
as seis skills com prefixo `cstk-codex-pilot:` via skills/list.
Use essas skills pela seleção nativa do Codex; os arquivos não registram
aliases de commands do Claude no Codex.

O banco é compartilhado usando `CSTK_KNOWLEDGE_DB`; sem override, segue o
default legado `~/.claude/cstk/knowledge.db`. Não é criado pelo preflight.
Estado continua em `.claude/feature-00c-state/<short-name>` para reutilizar
as primitivas e descoberta existentes. `execution_provenance` registra
runtime, modelo observado (nullable) e versão do toolkit. O nome do diretório
não deve ser usado para inferi-los. A projeção `executions.execution_provenance`
no knowledge.db usa schema 16, migrado aditivamente de 15, com NULL no legado.
O subprocesso usa a CLI/runtime do pacote e desativa a captura do exporter
Claude; custo e tokens do Codex permanecem sem medição até integração própria.

Preparação de uma execução (não abre onda):

```sh
sh adapters/codex/skills/feature-00c/scripts/session.sh bootstrap \
  --project /caminho/projeto --short-name minha-feature \
  --description 'Descrição concreta da feature' --canonical-project meu-projeto
sh adapters/codex/skills/feature-00c/scripts/session.sh resume \
  --project /caminho/projeto --short-name minha-feature
sh adapters/codex/skills/feature-00c/scripts/phase.sh \
  --project /caminho/projeto --short-name minha-feature
```

Resume valida integridade, identidade e hashes; handoff e recuperação são
operações explícitas. O lock cobre cada operação de preparação;
o controlador supervisionado mantém o lock pela onda inteira.

## Hooks locais

O manifest portátil `plugin.json` expõe skills, `mcp.json` e `hooks/hooks.json`.
`.codex-plugin/plugin.json` mantém o fallback de skills/hooks. O caminho do MCP
usa `${PLUGIN_ROOT}` no formato portátil: o formato legado não resolveu esse
caminho no Codex 0.160.0 e não é distribuído como fallback MCP.
Para gerar o pacote com as dependências compartilhadas:

```sh
sh scripts/build-codex-plugin.sh --out dist/cstk-codex-pilot
```

O builder copia CLI, skills, agentes de referência e runtime para um diretório
novo; não sobrescreve saídas existentes nem modifica instalações. Os helpers
resolvem assets pelo próprio caminho tanto no checkout quanto no pacote.
Registra o servidor MCP local no pacote; não altera instalações globais.
No pacote gerado, os scripts da entrada ficam em `skills/feature-00c/scripts/`.
O builder inclui um marketplace local no próprio pacote. Para instalação nativa, os comandos são:

```sh
codex plugin marketplace add ./dist/cstk-codex-pilot
codex plugin add cstk-codex-pilot@cstk-codex-pilot-local
```

Esses comandos modificam a instalação do Codex; o builder não os executa.
Depois de instalar, revise a definição em `/hooks` antes de confiar nela.
Não use bypass de confiança para declarar o piloto validado.

`PreToolUse` reutiliza a política Bash, confina paths de apply_patch e
recusa ferramentas locais ainda não validadas durante execução ativa.
O guard permite apenas as quinze ferramentas de `mcp__cstk_pipeline__cstk_*`,
valida seus schemas e exige que a seleção de projeto corresponda à sessão.
O servidor revalida propriedade, identidade, opt-ins, evidências e gates.
`PostToolUse` reutiliza o sidecar de contagem de tool calls do runtime;
essa contagem não equivale a custo/tokens nem confirma cobertura nativa.
Requer sandbox workspace-write, sessão na raiz do projeto e revisão/confiança
do hook dentro do Codex. A confiança não é inferida da existência do arquivo.

Limites conhecidos: ferramentas hospedadas não passam pelo hook; erros ou
timeouts no harness podem continuar a ferramenta; write_stdin não passa por
novo PreToolUse. O piloto recusa `tty`/`interactive` quando presentes, mas
isso não garante cobertura de toda interação com processos. São guardrails,
não uma fronteira completa de enforcement. Validação nativa permanece aberta.
Fonte: https://learn.chatgpt.com/docs/hooks

O diagnóstico MCP nativo não executa turno de modelo nem concede confiança:

```sh
sh adapters/codex/skills/feature-00c/scripts/native-mcp.sh --project /caminho/projeto --codex-home /caminho/instalacao-temporaria
```

Para o teste opcional de contrato pelo app-server, use
`CSTK_NATIVE_TEST_HOME=/caminho/instalacao-temporaria sh tests/codex/test_native-mcp.sh`.
Ele usa projeto/banco temporários e respostas de fixture identificadas como
teste. Chamadas MCP por RPC não certificam execução semântica nem hooks.

Validação desta fundação (shell/awk POSIX, com helpers canônicos existentes):

```sh
sh tests/run.sh codex
sh tests/run.sh pipeline
sh tests/run.sh --check-coverage
```

Os testes POSIX do adaptador são descobertos por `tests/run.sh`, inclusive no check de cobertura.

## Controle das ondas e opt-ins

Os helpers `optins.sh`, `controller.sh` e `native-status.sh` ficam ao lado de
`session.sh`. A skill descreve o transporte JSONL e as ações de decisão,
contagem, bloqueio, pausa e conclusão. O controlador despacha uma fase para a
sessão atual, sem abrir outro modelo. EOF/SIGTERM fecha sem avançar; recuperação
após SIGKILL exige ação explícita e PID morto igual ao dono registrado do lock.
O runner precisa de stdin persistente (pipe ou terminal externo); nenhuma
interface é considerada compatível por apenas exibir a skill.

Registre somente resposta real de opt-in. A coleta é idempotente e preserva
I-2; testes usam respostas explicitamente identificadas como fixtures.
A conclusão registra hashes de evidências e verifica a pipeline canônica,
backlog, bloqueios e orçamento. Qualidade semântica continua responsabilidade
do orquestrador, conforme as referências compartilhadas. Commit por etapa,
quando autorizado, segue os hooks canônicos da skill; nenhum push/PR é implícito.

O recall aceita `--include-source-ids` no modo `--context`, sem alterar o
output legado quando omitido. Consultas/IDs utilizados são auditados em
`.events[]` e nas decisões, preservando o projeto/feature/onda/source_id de
origem. Compartilhar memória não autoriza assumir a execução de outro runtime.

Diagnóstico nativo, sem conceder confiança:

```sh
sh adapters/codex/skills/feature-00c/scripts/native-status.sh --project /caminho/projeto
```

Veja [a matriz de suporte](../../docs/specs/codex-feature-00c/support-matrix.md)
e [as tarefas/evidências](../../docs/specs/codex-feature-00c/tasks.md).
