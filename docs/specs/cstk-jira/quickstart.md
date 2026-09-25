# Quickstart / Cenarios de Teste: cstk-jira

Cenarios de validacao manual e de aceitacao. Placeholders entre `<>` sao
preenchidos pelo operador com os dados do PROPRIO site Jira Cloud — nenhum
valor abaixo e um dado real.

## Pre-requisitos

- Site Jira Cloud `https://<site>.atlassian.net` (D1: Data Center/Server fora
  de escopo) com um projeto dedicado a este projeto-alvo (FR-002).
- API token do Atlassian account (research Decision 2 — expira em ate 1 ano).
- Opcional (uso interativo): Atlassian Rovo MCP configurado na sessao; endpoint
  recomendado `https://mcp.atlassian.com/v2/mcp` (README oficial citado em
  `research.md` Decision 1).
- Opcional (sync autonomo): `jq` e o cliente HTTP de linha de comando no PATH.

## Cenario 1 — Instalacao pelo marketplace (US4 cenario 1, FR-008)

1. Adicionar o marketplace e instalar, como os demais plugins
   (padrao de `README.md` L339-342, que instala `cstk@cstk` e `cstk-language-go@cstk`): `/plugin marketplace add JotJunior/cstk` e
   `/plugin install cstk-jira@cstk` (nome do plugin = DESIGN deste plano).
2. Listar skills disponiveis.

**Expected**: `jira-setup`, `jira-convert`, `jira-sync` visiveis; hooks do
plugin ativos; nenhuma mudanca no comportamento de outras skills.

## Cenario 2 — Plugin instalado e inativo (US4 cenario 3, FR-017, SC-006)

1. Sem `.claude/cstk-jira/config`, rodar uma onda `feature-00c` qualquer que
   registre outcome de task e feche onda.

**Expected**: hooks saem em no-op (exit 0, stdout vazio); nenhum arquivo em
`.claude/cstk-jira/`; nenhuma rede; nenhuma mensagem nova.

## Cenario 3 — Setup guiado (US4 cenario 2, FR-007, SC-004)

1. Invocar a skill `jira-setup`; informar `<site>` e `<PROJECT_KEY>`.
2. Em um terminal PROPRIO (nunca no chat — o token entraria no transcript),
   rodar o comando de credencial que a skill exibe; digitar email e token com
   eco desligado.
3. A skill valida a credencial remotamente, descobre tipos de issue e
   status/transicoes e pede o mapeamento `pending/in_progress/pass/fail`.
4. A skill cria (ou reusa) filtro + board kanban do projeto.

**Expected**: `.claude/cstk-jira/config` valido (`jira-config.sh validate` exit
0); arquivo de credencial com modo `0600` fora do repo; `board_id` gravado;
nenhum segredo em arquivo versionado (`git grep` pelo email/token nao acha
nada).

**Error case 3a**: mapear `fail` para o mesmo status de `pass` => setup recusa
com diagnostico pedindo um status distinto no workflow.

**Error case 3b**: token invalido => diagnostico de credencial rejeitada;
nenhum `config` parcial marcado como valido.

## Cenario 4 — Conversao da feature (US1, FR-001/003/013/014, SC-001/002/005)

1. Com uma feature com `spec.md` + `tasks.md`, invocar `jira-convert <feature>`.
2. Conferir no Jira o Epic, as Tasks filhas e as Sub-tasks.
3. Rodar `jira-convert <feature>` mais 9 vezes seguidas.
4. Acrescentar uma task `### N.M` nova ao `tasks.md` e rodar de novo.

**Expected**: passo 1 cria 1 Epic + 1 issue por task/subtask, todas presentes
em `docs/specs/<feature>/jira-map.tsv` com SyncMarker gravado; passo 3 cria 0
issues (SC-002); passo 4 cria SO a task nova (US1 cenario 2).

**Error case 4a** (US1 cenario 3): credencial ausente => recusa ANTES de
qualquer criacao; `jira-map.tsv` nao e criado.

## Cenario 5 — Sync autonomo durante execucao 00c (US3, FR-004/005/018, SC-003)

1. Feature convertida; rodar `/feature-00c-resume` numa onda de execute-task.
2. Observar o board durante a onda.

**Expected**: task iniciada (`[~]`) aparece em `status_in_progress`; outcome
`pass` vai para `status_pass` e `fail` para `status_fail` ate o fim da mesma
onda (drain obrigatorio no fechamento); o orquestrador nunca espera pelo Jira.

**Error case 5a** (FR-011): mover um card manualmente no Jira e depois
registrar outcome da task => card NAO e sobrescrito; `jira-sync status` lista o
conflito.

**Error case 5b** (FR-016/FR-019): revogar o token no meio da execucao =>
evento `auth_failed`, nenhuma nova chamada ate `jira-setup`; a execucao da
feature segue normalmente.

**Error case 5c** (edge case de indisponibilidade): site inacessivel => eventos
`deferred`, drenados no gatilho seguinte; execucao nao para.

**Error case 5d** (FR-012): remover uma task do `tasks.md` => card permanece no
Jira; linha vira `orphan`; tentativa de `deleteJiraIssue` pela sessao e barrada
pela guarda (exit 2).

## Cenario 6 — Roundtrip End-to-End (conferencia de contrato)

1. Contra um site Jira Cloud de teste, rodar `jira-sync.sh plan` e depois
   `convert` de uma feature de 1 task.
2. Capturar a resposta REAL de criacao, de leitura da issue e da lista de
   transicoes.
3. Comparar metodo, path e nomes de campo contra `contracts/jira-rest.md`.

**Expected**: 100% dos campos usados pelo motor existem na resposta real com o
nome do contrato. Qualquer divergencia => corrigir o CONTRATO com a fonte
observada antes do codigo (Principio VI), nunca ajustar o codigo por
suposicao.

## Cenario 7 — Dependencias ausentes (carve-out 1.1.0, condicao a)

1. Rodar o hook de sync com PATH minimo sem `jq`/cliente HTTP.
2. Rodar `jira-convert` interativo com as tools do Rovo MCP visiveis.

**Expected**: passo 1 => exit 5 + diagnostico com instrucao de instalacao,
eventos preservados no outbox, execucao 00c inalterada; passo 2 => conversao
concluida pelo caminho MCP + scripts POSIX.
