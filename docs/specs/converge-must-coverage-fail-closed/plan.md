# Implementation Plan: Gate de Convergência Recusa Cobertura Zero de MUST

**Feature**: `converge-must-coverage-fail-closed` | **Date**: 2026-08-29 | **Spec**: [spec.md](./spec.md)

## Summary

Requisito primário: a etapa `converge` **MUST NOT** reportar sucesso quando a
verificação de cobertura de `MUST` da constituição do projeto-alvo não rodou de
fato (arquivo declara MUST, parser reconhece zero regras) — issue #173.

Abordagem técnica em duas frentes, ambas mínimas e aditivas:

1. **Fail-closed no gate (US1)**: `extract-must.sh --coverage` ganha um
   **veredito de vocabulário fechado** (`ok` | `zero-reconhecida` |
   `sem-must-declarado`) como 6ª linha de stdout, mais **exit code 3** para o
   caso-alvo. A `converge/SKILL.md` passa a emitir, sobre esse sinal
   determinístico, um `Gap` sintético (`contradicts` / `P1` /
   `must_violated=false` → **HIGH**) que percorre o mesmo pipeline dos demais
   achados — logo conta em `N` e torna `outcome=clean` mecanicamente
   impossível. **Nenhum script novo; `severity.sh` e `converge-status.sh`
   inalterados.**
2. **Causa na origem (US2)**: a skill `constitution` passa a ensinar e
   exemplificar o **formato rotulado** que o parser reconhece, e o texto-semente
   obrigatório de Veracidade de Dados passa a ele próprio segui-lo — saindo do
   blockquote (`> ` **quebra** o reconhecimento, medido) para bloco de código
   cercado. Nenhuma constituição existente é migrada (FR-009).

## Technical Context

**Language/Version**: POSIX `sh` (`#!/bin/sh`, `set -eu`) + `awk`/`grep` POSIX — inferido de `plugins/cstk/skills/converge/scripts/*.sh` e da Constitution II
**Primary Dependencies**: nenhuma além das ferramentas POSIX canônicas (`grep`, `awk`, `sed`, `mktemp`). Zero `jq`/`bats`/`ripgrep` nos scripts de skill (Constitution II)
**Storage**: N/A — nenhuma persistência nova. O único artefato gravado (`converge-report.md`) já existe e não muda de formato
**Testing**: harness próprio `tests/run.sh` (cenários `scenario_*` em `tests/test_*.sh`), com gate `--check-coverage` (nenhum script sem teste)
**Target Platform**: CLI local (macOS/Linux); toolkit `cstk` distribuído como plugin/catálogo — sem runtime de serviço.
Fonte: `docs/constitution.md` Princípio II (NON-NEGOTIABLE) exige `#!/bin/sh` + zero dependência externa para todo script de skill, o que fixa o alvo como shell POSIX local; nenhum `Dockerfile`/manifesto de serviço existe na raiz do repo (verificado por `ls`). Registrado em dec-015.
**Project Type**: cli / toolkit de skills (single-layer)
**Performance Goals**: N/A — o custo adicional é uma comparação inteira já computada; nenhuma leitura de arquivo extra
**Constraints**: mudança em `extract-must.sh` deve ser **estritamente aditiva** em stdout (5 linhas existentes byte-idênticas); `docs/constitution.md` deste repo é **imutável** nesta feature (sha256 gravado no `state.json`, FR-009)
**Scale/Scope**: 5 arquivos de produto + 1 arquivo de teste; nenhum `NEEDS CLARIFICATION` restante

## Constitution Check

*GATE: passou antes do Phase 0; re-checado após Phase 1 (ETAPA 7) — resultado abaixo é o pós-design.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. Spec-Driven Development Aplica-se Recursivamente (NON-NEGOTIABLE) | PASS | Feature nasceu de `spec.md` ratificada; `clarify` rodado (0 perguntas); este plano precede qualquer código |
| II. Scripts POSIX sh Puros, Zero Dependencia Externa (NON-NEGOTIABLE) | PASS *(com nota)* | Mudança usa só comparação inteira em `sh`; sem Bash-ism, sem dep nova. **Nota**: o MUST enumera "exit codes convencionais (0 sucesso, 1 erro geral, 2 uso incorreto)" — o `exit 3` proposto é **sinal de estado**, não erro, e tem precedente vivo no mesmo diretório (`converge-status.sh check`, exit 0/1/3). Registrado em Complexity Tracking |
| III. Formato Canonico de Skill: Progressive Disclosure, Gotchas, Description-como-Trigger | PASS | `converge/SKILL.md` permanece o ponto de entrada enxuto (edição de ~2 blocos, sem colar template); a §Gotchas de ambas as skills ganha entrada nova derivada de armadilha **real medida** (blockquote quebra o rótulo), não hipotética |
| IV. Zero Coleta Remota de Uso ou Dados (NON-NEGOTIABLE) | PASS | Nenhuma rede, telemetria ou envio. Tudo é leitura local de arquivo + stdout |
| V. Profundidade e Reducao de Retrabalho Acima de Metricas de Adocao | PASS | O achado existe justamente para impedir retrabalho tardio: hoje um gate verde esconde que a verificação não rodou |
| VI. Veracidade de Dados — Zero Fabricacao (NON-NEGOTIABLE) | PASS | `must_violated=false` é escolha **direta** deste princípio: afirmar `true` alegaria uma violação MUST específica que o parser não conseguiu ler. Todo número/saída citado neste plano foi medido neste worktree; duas premissas recebidas foram **refutadas** por medição e não propagadas (dec-014) |

**Nenhum FAIL em princípio MUST — gate liberado.**

## Project Structure

### Documentation (this feature)

```
docs/specs/converge-must-coverage-fail-closed/
├── spec.md                              # existente (commit 3a3091d)
├── plan.md                              # este arquivo
├── research.md                          # Phase 0 (10 decisions)
├── data-model.md                        # Phase 1
├── quickstart.md                        # Phase 1 (9 cenários)
└── contracts/
    └── must-coverage-finding.md         # Phase 1
```

### Source Code (repository root)

Árvore real, restrita aos paths tocados (verificados por `ls`):

```
plugins/cstk/skills/
├── converge/
│   ├── SKILL.md                         # [EDITADO] ETAPA 3, §5.2, ETAPA 7, §Gotchas, §Scripts auxiliares
│   ├── scripts/
│   │   ├── extract-must.sh              # [EDITADO] veredito + exit 3 + cabeçalho de contrato
│   │   ├── severity.sh                  # [INTOCADO] tabela vigente já entrega HIGH
│   │   ├── converge-status.sh           # [INTOCADO] `record` já recusa clean com actionable != 0
│   │   ├── converge-tasks.sh            # [INTOCADO] gap-key/existing-keys/append-phase reusados
│   │   ├── extract-intent.sh            # [INTOCADO]
│   │   └── path-contains.sh             # [INTOCADO]
│   └── templates/
│       └── convergence-phase.md         # [INTOCADO] mapa HIGH -> [C] já cobre o achado
└── constitution/
    ├── SKILL.md                         # [EDITADO] §3.2 regra de formato + texto-semente + §Gotchas
    └── templates/
        └── constitution.md              # [EDITADO] esqueleto rotulado sob cada princípio

tests/
├── test_extract-must.sh                 # [EDITADO] +5 cenários (veredito, exits, aditividade, semente)
├── test_severity.sh                     # [INTOCADO] tripla já coberta por scenario_tabela_completa_*
└── run.sh                               # [INTOCADO]

docs/constitution.md                     # [IMUTÁVEL] FR-009 + sha256 no state.json
```

**Structure Decision**: nenhum arquivo novo. A feature é implementada como
extensão aditiva de um script existente + prosa normativa nas duas `SKILL.md`
afetadas. Criar um `must-coverage-gate.sh` dedicado foi rejeitado no Phase 0
(Decision 1): duplicaria a gramática de contagem, exatamente o risco que o
próprio `extract-must.sh` documenta ("duas copias driftariam e a metrica de
cobertura mediria um parser diferente do que roda", linhas 174-175).

## Convenções de Borda

**N/A — single-layer.** Não há fronteira backend↔frontend, DB↔backend ou
broker↔consumer nesta feature. As únicas fronteiras são:

| Fronteira | Convenção | Fonte da verdade |
|-----------|-----------|------------------|
| `extract-must.sh` → agente (stdout) | texto `chave: valor`, uma métrica por linha, ASCII sem acento | `contracts/must-coverage-finding.md` §1 |
| `extract-must.sh` → chamador (exit code) | `0` sucesso · `1` fonte ausente · `2` uso · `3` cobertura zero | `contracts/must-coverage-finding.md` §1 |
| agente → `severity.sh` (argv) | enums fechados, validados pelo próprio script | `severity.sh` linhas 115-128 |
| agente → `converge-status.sh record` (argv) | `--outcome`/`--actionable` com invariante `clean ⇒ 0` | `converge-status.sh` linhas 362-363 |

Identificadores/enums em **inglês** (`ok` é o único valor do veredito que
coincide com português); mensagens e comentários em pt-BR, conforme a
convenção já vigente nos scripts desta skill.

## Ordem de implementação sugerida

Deriva das prioridades da spec (US1 = P1, US2 = P2) e do gate de cobertura de
testes do repo:

1. **US1-a** `extract-must.sh`: veredito + exit 3 + atualização do cabeçalho de
   contrato do script (§"Relatorio de cobertura").
2. **US1-b** `tests/test_extract-must.sh`: cenários 1-5 do `quickstart.md`
   (incluindo o de aditividade, que é a rede contra regressão de formato).
3. **US1-c** `converge/SKILL.md`: ETAPA 3 (3 ramos), §5.2 (carve-out `P1`),
   ETAPA 7 (contagem), §Scripts auxiliares (novo exit code), §Gotchas.
4. **US2-a** `constitution/SKILL.md` §3.2: regra de formato + texto-semente em
   bloco cercado com linha `**MUST:**` + §Gotchas (armadilha do `> `).
5. **US2-b** `constitution/templates/constitution.md`: esqueleto rotulado.
6. **US2-c** cenário 7 do `quickstart.md` como verificação (transcrição verbatim
   do texto-semente → `cobertura de MUST: ok`).
7. **Verificação final**: suite completa (`LC_ALL=C ./tests/run.sh`, ~12min, em
   background com log) + `./tests/run.sh --check-coverage` + cenários 8 e 9
   (imutabilidade de `docs/constitution.md`, dogfooding).

## Riscos e mitigações

| Risco | Probabilidade | Mitigação |
|-------|---------------|-----------|
| Regressão de formato do `--coverage` (linha nova no lugar errado, acento, ordem) | Média | Cenário 5 do `quickstart.md` compara as 5 linhas existentes byte-a-byte; elas são asserção de teste |
| `exit 3` quebrar um caller sob `set -e` | **Baixa (medida)** | `grep -rn 'extract-must'` não encontrou nenhum caller programático fora de `tests/` — só prosa de SKILL.md e CHANGELOG |
| Carve-out da §5.2 esquecido ⇒ SKILL.md autocontraditória | Média | É item explícito da ordem de implementação (3) e do contrato §3.3; uma execução futura de `converge` a pegaria como `contradicts` |
| Texto-semente regredir para blockquote em edição futura | Média | Cenário 7 do `quickstart.md` + entrada dedicada em §Gotchas da skill `constitution` |
| Escopo vazar para a 3ª sugestão da issue #173 (alargar o parser) | Baixa | `research.md` Decision 8 mostra que FR-006/SC-002 empurram na direção **oposta**; `_EM_MUST_RE` está marcada `[INTOCADO]` no contrato |
| **Fail-open por contador não-numérico** (gate de segurança, MEDIUM): `grep` falhando por IO deixa `N`/`M` vazios e `[ "" -gt 0 ]` avalia como falso sem abortar (medido) ⇒ veredito `sem-must-declarado` com exit 0 | Baixa · impacto alto | Guarda numérica obrigatória antes de derivar o veredito; não-inteiro ⇒ `exit 1` (`contracts/...` §1 Guarda de integridade) |
| **Constituição ilegível lida como "erro de uso"** (gate de segurança, MEDIUM): arquivo existente com `chmod 000` sai `exit 2` e stdout vazio; a `SKILL.md` descreve `exit 2` como bug de invocação | Baixa · impacto alto | Regra da ETAPA 3 vira **allowlist**: suprime o achado só com veredito literal `ok`/`sem-must-declarado`; todo o resto é cobertura indisponível (`contracts/...` §3.1) |
| **Diretiva hostil na constitution auditada tenta suprimir o achado** (LLM01/ASI09) | Baixa | Achado nasce do sinal do script, não de julgamento sobre o texto; conteúdo do arquivo **não** é ecoado no stdout do `--coverage` (medido, forja falhou); regra explícita de não-supressão (`contracts/...` §3.3-bis) |
| **Bypass de 1 linha**: `**MUST:** n/a` faz `M=1` e silencia o gate mesmo com MUST em prosa | Média | **Risco residual aceito**: é o comportamento que FR-006 exige preservar (cobertura parcial = 3ª sugestão da issue #173, deferida). Quem escreve a `constitution.md` já detém a governança do projeto — não há elevação de privilégio |

## Fora de escopo (explícito)

- **3ª sugestão da issue #173** (parser aceitar prosa em bullet): deferida pela
  spec; `research.md` Decision 8 confirma que **nenhum** FR/SC a exige — logo
  **nenhum bloqueio humano é aberto** por este eixo.
- **Cobertura parcial** (`M > 0` porém menor que as obrigações pretendidas):
  FR-006 exige preservar o comportamento atual.
- **Migração de constituições existentes**: proibida por FR-009.

## Complexity Tracking

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| `exit 3` além do conjunto `0/1/2` enumerado na Constitution II | Um gate **fail-closed** não pode depender de o chamador parsear prosa: um consumidor que ignore stdout ainda assim não deve receber `0` silencioso — é literalmente a classe de defeito que a issue #173 relata. Precedente vivo sob a mesma constituição: `converge-status.sh check` já usa `exit 0/1/3` para veredito consumível | *Só a linha de veredito, sem exit code*: funciona para o agente (que lê stdout), mas deixa testes e qualquer futuro caller dependentes de parsing textual, e mantém o `0` silencioso como resposta ao caso-alvo — estritamente mais fraco pelo custo de 1 linha. *Reciclar `exit 1`*: colidiria com "constituição ausente", que a spec exige manter como estado **distinto** (Edge Case, `data-model.md` INV-3) |

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/converge-must-coverage-fail-closed/plan.md | Criado |
| docs/specs/converge-must-coverage-fail-closed/research.md | Criado |
| docs/specs/converge-must-coverage-fail-closed/data-model.md | Criado |
| docs/specs/converge-must-coverage-fail-closed/contracts/must-coverage-finding.md | Criado |
| docs/specs/converge-must-coverage-fail-closed/quickstart.md | Criado |
