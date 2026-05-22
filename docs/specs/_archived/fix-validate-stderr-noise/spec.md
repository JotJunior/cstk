# Feature Specification: Limpar stderr ruidoso em validate.sh

**Feature**: `fix-validate-stderr-noise`
**Created**: 2026-04-20
**Status**: Draft

## Contexto

O script `global/skills/validate-docs-rendered/scripts/validate.sh` emite
mensagens tecnicas em stderr quando processa arquivos que nao casam com
algum contador interno (`[: 0\n0: integer expression expected`). Essas
mensagens aparecem em TODA execucao, mesmo quando o validador encontra
zero erros reais — confundindo o mantenedor sobre se o script esta ou
nao operando corretamente.

A causa raiz e conhecida: o script usa o mesmo padrao `grep -c || printf '0'`
que gerou o bug historico em `metrics.sh` (corrigido em ead1b68). O padrao
concatena `"0\n0"` quando `grep -c` nao acha matches, e a aritmetica
posterior falha silenciosamente.

**Impacto observado**:

- stderr poluido em todas as execucoes — ruido constante.
- Exit code continua correto (0 em sucesso, 1 em presenca de ERROs).
- stdout continua correto (mensagens de ERRO aparecem quando devem).
- Contagem de ERRO/AVISO no sumario pode estar sendo silenciosamente
  zerada — a aritmetica quebrada "mostra" sempre 0. Suspeita: a tabela
  de resumo `| ERRO | 0\n0 |` no stdout e consequencia direta disso.

A feature atual e **cirurgica**: um unico alvo, um unico padrao, fix
mecanico analogo ao do `metrics.sh`.

## Clarifications

### Session 2026-04-20

- Q: Onde exatamente vive o padrao defeituoso em `validate.sh`? → A: Linhas 244-245 (duas ocorrencias, para `ERRORS` e `WARNINGS`). O sintoma e observavel nas linhas 273-284 (comparacoes aritmeticas `[ "$VAR" -gt 0 ]` que consomem os contadores corrompidos). A causa e isolada; o sintoma e distribuido — esta distincao e relevante porque o executor deve tocar apenas as linhas 244-245.
- Q: O fix pode alterar os valores numericos que aparecem na tabela Resumo do stdout? → A: Sim. FR-007 preserva estrutura/contrato (colunas, ordem, severidades, exit codes), **nao** os valores numericos. Se a aritmetica quebrada estava silenciosamente zerando contagens de ERRO/AVISO, o fix vai revelar os numeros corretos — e melhoria esperada, nao regressao. Atualizacao dos tests ja e coberta por FR-006.
- Q: Remover as linhas 246-247 (`ERRORS=${ERRORS:-0}` / `WARNINGS=${WARNINGS:-0}`) apos o fix? → A: Nao. Preservar como defesa-em-profundidade + adicionar comentario curto acima explicando que permanece deliberadamente como seguranca adicional apos o fix da causa raiz. Remocao ampliaria diff sem ganho operacional.

## User Scenarios & Testing

### User Story 1 — Mantenedor ve stderr limpo (Priority: P1)

Quando o mantenedor roda `validate.sh` em um diretorio de documentacao
qualquer, o stderr mostra apenas mensagens de diagnostico intencionais
(warnings reais sobre o conteudo) — nunca mensagens sobre o funcionamento
interno do proprio script.

**Why this priority**: o proposito do script e reportar problemas na
documentacao alheia. stderr ruidoso sobre mecanica interna treina o
mantenedor a ignorar stderr, o que eventualmente mascara um problema
real.

**Independent Test**: rodar `validate.sh` contra qualquer um dos 4
fixtures existentes em `tests/fixtures/docs-site/` e confirmar que stderr
nao contem a string "integer expression expected" nem "[:".

**Acceptance Scenarios**:

1. **Given** o fixture `tests/fixtures/docs-site/valid/`, **When** o
   mantenedor roda `validate.sh` nele, **Then** stderr e vazio (ou contem
   apenas mensagens originadas de logica intencional do script, nao de
   comparacoes aritmeticas defeituosas).
2. **Given** o fixture `tests/fixtures/docs-site/broken-mermaid/`,
   **When** o mantenedor roda `validate.sh`, **Then** stdout reporta o
   erro de Mermaid e stderr permanece livre de ruido mecanico.
3. **Given** qualquer markdown de conteudo real do repositorio (ex:
   `docs/`), **When** validate.sh e invocado, **Then** stderr nao
   confunde o mantenedor com mensagens sobre `[:` ou `integer expression`.

---

### User Story 2 — Suite protege contra regressao futura (Priority: P1)

Qualquer refatoracao futura do `validate.sh` que acidentalmente reintroduza
o padrao defeituoso e imediatamente detectada pela suite existente, sem
exigir inspecao manual de stderr.

**Why this priority**: sem a regressao automatizada, o bug volta na
proxima refatoracao e o ciclo recomeca. P1 ao lado da Story 1 porque a
correcao so e durável se houver guardrail.

**Independent Test**: apos o fix, reverter temporariamente UMA linha do
padrao de volta ao defeituoso. Rodar a suite. Deve falhar em um scenario
dedicado de `test_validate.sh`. Restaurar o fix. Suite volta a 44/44.

**Acceptance Scenarios**:

1. **Given** `test_validate.sh` apos esta feature, **When** a suite roda,
   **Then** existe ao menos um scenario que captura especificamente stderr
   e verifica ausencia de "integer expression expected".
2. **Given** uma reintroducao deliberada do padrao defeituoso em validate.sh,
   **When** a suite roda, **Then** o scenario de regressao falha com
   mensagem clara apontando o sintoma exato.

---

### Edge Cases

- O que acontece com arquivos markdown que nao tem NENHUM code block nem
  Mermaid nem links — ou seja, aquele que zera todos os contadores
  internos do validate.sh? (E o caso que mais reproduz o sintoma hoje.)
- O que acontece se o fix for aplicado incompletamente — uma ocorrencia
  corrigida, outra nao? A feature exige auditoria EXAUSTIVA.
- Se a aritmetica quebrada estava silenciosamente zerando a contagem
  de ERRO/AVISO no sumario, o fix pode ALTERAR numeros ja observados
  (de "0\n0" para valores reais). A suite atual tolera esse delta?

## Requirements

### Functional Requirements

- **FR-001**: O script `global/skills/validate-docs-rendered/scripts/validate.sh`
  DEVE ser auditado exaustivamente para identificar TODAS as ocorrencias
  do padrao `VAR=$(grep -c ... || printf '0')` ou equivalentes que
  emitem concatenacoes defeituosas quando `grep -c` nao encontra matches.
- **FR-002**: Cada ocorrencia identificada em FR-001 DEVE ser corrigida
  para o padrao seguro `VAR=$(grep -c ...) || VAR=0`. A correcao deve
  preservar comportamento funcional nos casos de acerto (o grep encontrou
  matches) — so muda o caminho de fallback.
- **FR-003**: Apos o fix, nenhuma invocacao de `validate.sh` nos fixtures
  existentes de `tests/fixtures/docs-site/` (valid, broken-mermaid,
  broken-link, broken-frontmatter) DEVE emitir em stderr mensagens
  contendo "integer expression expected" ou "`[: `" seguido de multiplas
  linhas de "0".
- **FR-004**: A suite em `tests/test_validate.sh` DEVE incluir ao menos
  um scenario dedicado de regressao que verifique ausencia da string
  "integer expression expected" em stderr apos invocar validate.sh contra
  um fixture que reproduzia o sintoma.
- **FR-005**: A suite completa (`./tests/run.sh`) DEVE continuar
  reportando zero FAIL e zero ERROR apos a feature ser aplicada.
- **FR-006**: Se o fix alterar numeros observaveis (ex: contagem de ERRO
  no sumario impresso por validate.sh), os scenarios existentes em
  `test_validate.sh` DEVEM ser atualizados para refletir os novos valores
  corretos — preservando a intencao de cada assercao.
- **FR-008**: A feature DEVE preservar as linhas 246-247 de `validate.sh`
  (`ERRORS=${ERRORS:-0}` / `WARNINGS=${WARNINGS:-0}`) como defesa-em-profundidade
  e adicionar um comentario curto acima explicando que, apos o fix da
  causa raiz nas linhas 244-245, essas atribuicoes permanecem
  deliberadamente como seguranca adicional caso a substituicao venha
  a ser alterada no futuro.

- **FR-007**: A feature NAO DEVE alterar o contrato externo de
  `validate.sh`: exit codes, **estrutura** de stdout (colunas, ordem,
  secoes), lista de checagens realizadas e severidades (ERRO vs AVISO)
  permanecem inalterados. Explicitamente **fora** da garantia de FR-007:
  os VALORES numericos das contagens de ERRO/AVISO na tabela Resumo —
  se a aritmetica quebrada estava ocultando contagens reais, o fix pode
  revelar numeros diferentes dos observados antes. Atualizacao dos
  scenarios de teste para refletir valores corretos e coberta por FR-006.

### Key Entities

- **Padrao defeituoso**: expressao shell `VAR=$(grep -c ... || printf '0')`
  que, por contrato do `grep -c`, concatena "0" duas vezes quando o grep
  nao acha matches. Unidade de analise para a auditoria.
- **Padrao seguro**: expressao shell `VAR=$(grep -c ...) || VAR=0` que
  captura a saida do grep (sempre "0" em no-match) e ativa o `||` apenas
  quando o exit code do grep e nao-zero. Unidade de substituicao.
- **Fixture de regressao**: dado de entrada minimo que reproduzia o
  sintoma original (stderr "integer expression expected"). Provavelmente
  o markdown em `tests/fixtures/docs-site/valid/` ou equivalente —
  sera escolhido no plan.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Apos a feature, `./tests/run.sh` mostra `PASS: X  FAIL: 0
  ERROR: 0` onde X e o numero atual de scenarios mais os novos
  adicionados para regressao.
- **SC-002**: Invocar `validate.sh` contra os 4 fixtures de
  `tests/fixtures/docs-site/` e capturar stderr produz, em 100% dos
  casos, saida sem a string "integer expression expected".
- **SC-003**: `grep -cE "grep -c.*printf '0'" global/skills/validate-docs-rendered/scripts/validate.sh`
  retorna 0 — evidencia direta de que nenhuma ocorrencia do padrao
  defeituoso permanece.
- **SC-004**: Se o fix for deliberadamente revertido em UMA linha
  qualquer, o novo scenario de regressao em `test_validate.sh` falha
  com mensagem identificavel — validado manualmente uma unica vez
  durante a entrega.
- **SC-005**: Tempo total da suite `./tests/run.sh` permanece abaixo
  do limite de 30s ja estabelecido em `shell-scripts-tests` (SC-003
  daquela spec).
