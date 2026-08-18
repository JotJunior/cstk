# Implementation Plan: Lançamento Paralelo de Features do Roadmap

**Feature**: `roadmap-parallel-launch`
**Spec**: [spec.md](./spec.md)
**Research**: [research.md](./research.md)
**Created**: 2026-08-17
**Status**: Draft

## Summary

Ao término do modo roadmap (`termination_reason = concluido_roadmap`), o
**command pai** `/agente-00c` calcula a fronteira de features elegíveis do
DAG, oferece ao operador uma leva paralela (teto default **2**), e lança cada
feature escolhida numa worktree isolada rodando `/feature-00c <short>` num
pane tmux próprio. Ao terminar, cada sessão-filha notifica a coordenadora
(best-effort), que recalcula a fronteira e oferece a próxima leva.

Abordagem técnica escolhida (detalhe e fontes em `research.md`):

- Status/fronteira derivados **exclusivamente** de `roadmap-status.sh --json`
  (helper já existente, fail-closed) — nunca de leitura própria do roadmap.
- Lançamento composto por `cstk session start` (worktree) + `tmux new-window`
  (pane executando `claude --name ... "/feature-00c <short>"`) — **zero
  alteração em `cli/lib/`**, porque `cstk session start --claude` termina em
  `exec claude` sem argumentos e não serve para este caso.
- Notificação via cross-session messaging (`SendMessage`), com o
  comportamento de wake-up tratado como **hipótese a comprovar**, não como
  fato — é a primeira task do plano.

## Technical Context

| Campo | Valor | Fonte |
|---|---|---|
| Linguagem | POSIX `sh` puro (scripts) + Markdown (prosa de command/skill) | `docs/constitution.md` Princípio II |
| Dependências obrigatórias | `git` (já exigida), `sh`, `sed`/`awk` POSIX | precedente `roadmap-status.sh`, `session.sh` |
| Dependências opcionais (com fallback) | `tmux` (FR-007 degrada), `claude` CLI, `gh` (não usada aqui) | Princípio II §exceção com fallback coberto por teste |
| Plataforma alvo | macOS / Linux (mesma do toolkit) | `CLAUDE.md`, doc de cross-session messaging |
| Testes | harness POSIX `tests/run.sh` | `CLAUDE.md` §Como testar scripts shell |
| Estado persistido novo | **nenhum** | spec §Requirements, nota de infraestrutura |
| Metade da instalação afetada | **catálogo apenas** (`cstk install`/`cstk update`) | `research.md` Decision 9 |

Nenhum `NEEDS CLARIFICATION` remanescente: as 5 ambiguidades foram resolvidas
na etapa `clarify` (ver §Clarifications da spec) e as 9 unknowns técnicas
foram fechadas em `research.md` com fonte real.

## Constitution Check

*GATE: passou antes do Phase 0; re-checado após Phase 1 (§Re-check).*

| Princípio | Status | Notas |
|---|---|---|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | feature nasceu de `spec.md` clarificada; plan/contracts/tasks seguem o pipeline |
| II. Scripts POSIX puros, zero dep externa (NON-NEGOTIABLE) | PASS | ambos os helpers novos são `sh` puro sem `jq`; `tmux` é dep **opcional** com fallback funcional (FR-007) e teste dedicado, satisfazendo as condições cumulativas da exceção |
| III. Formato canônico de skill | PASS | nenhuma skill nova; alterações são prosa de command + 2 scripts, ambos com `-h/--help` e gotchas |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | tudo local: git worktree, tmux, sessões do próprio operador; nenhuma telemetria |
| V. Profundidade acima de métricas | PASS | US1/US2 atacam retrabalho real (lançar features uma a uma); US3/US4 reduzem falha silenciosa e conflito |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | todo contrato novo rotulado `[PROPOSTA — a validar na implementação]`; wake-up de sessão ociosa marcado **NÃO COMPROVADO** e promovido a primeira task |

Nenhum FAIL. `Complexity Tracking` fica vazio (§adiante).

## Convencoes de Borda

**Sem camada de dados — mas com 2 fronteiras de processo.** A feature não
atravessa fronteira backend↔frontend,
DB↔backend ou broker↔consumer: é composta de scripts POSIX locais, prosa de
command e invocação de CLIs (`git`, `tmux`, `claude`, `cstk`). Não há DTO,
schema de banco, nem payload de API.

As duas **fronteiras de processo** existentes estão contratadas em
`contracts/parallel-launch.md`:

| Fronteira | Formato | Fonte da verdade |
|---|---|---|
| `roadmap-status.sh` → `roadmap-frontier.sh` | JSON-lines `{"ordem","short_name","status","depende_de"}` | `roadmap-status.sh:200-201` (**real**) |
| sessão-filha → coordenadora | texto plano `[cstk-parallel] feature=… outcome=… repo=…` | `contracts/parallel-launch.md` §6 (**proposta**) |

## Project Structure

### Documentação (feature dir) — paths reais

```
docs/specs/roadmap-parallel-launch/
├── spec.md                          (existente)
├── plan.md                          (este arquivo)
├── research.md                      (novo)
├── data-model.md                    (novo)
├── quickstart.md                    (novo)
└── contracts/
    ├── roadmap-frontier.md          (novo)
    └── parallel-launch.md           (novo)
```

### Código — árvore real do repo, com os pontos de toque

```
plugins/cstk/
├── commands/
│   ├── agente-00c.md                (ALTERADO — oferta da leva pós-terminal)
│   ├── agente-00c-resume.md         (ALTERADO — mesmo gatilho no resume)
│   ├── feature-00c.md               (ALTERADO — notificação terminal)
│   └── feature-00c-resume.md        (ALTERADO — idem)
├── agents/
│   └── agente-00c-orchestrator.md   (INALTERADO — §9.quater intacta)
└── skills/
    ├── review-features/scripts/
    │   ├── roadmap-status.sh        (INALTERADO — reusado)
    │   └── roadmap-frontier.sh      (NOVO)
    └── agente-00c-runtime/scripts/
        └── parallel-launch.sh       (NOVO)

cli/lib/session.sh                   (INALTERADO — ver research.md Decision 3)

tests/
├── test_roadmap-frontier.sh         (NOVO — obrigatório, --check-coverage)
├── test_parallel-launch.sh          (NOVO — obrigatório, --check-coverage)
└── test_command-spawn-parallel-launch.sh (NOVO — prosa dos commands)
```

Precedente do teste de prosa: `tests/test_command-spawn-roadmap-mode.sh`, já
existente no repo para o bloco de opt-in do modo roadmap.

## Alocação de responsabilidades

Detalhe normativo em `contracts/parallel-launch.md` §1. Resumo:

| Ator | Faz | Não faz |
|---|---|---|
| Command pai `/agente-00c(-resume)` | pergunta, decide, lança, recebe notificação, oferece próxima leva | executar a pipeline da feature |
| Subagente `agente-00c-orchestrator` | nada desta feature | qualquer coisa desta feature (FR-012) |
| `roadmap-frontier.sh` | calcula fronteira + avisos, read-only | lançar, perguntar, escrever |
| `parallel-launch.sh` | compõe/emite comandos exatos, detecta tmux, guarda anti-duplicidade | executar o lançamento, perguntar |
| Sessão-filha `/feature-00c` | executa sua feature, notifica ao terminar | calcular fronteira, oferecer leva, lançar sessão |

O motivo de `parallel-launch.sh` **emitir** em vez de **executar** está em
`contracts/parallel-launch.md` §4: torna o caminho automático (US1) e o
degradado (US3) o mesmo texto, o que transforma o AC2 da US3 em asserção
comparável byte a byte.

## Fases de implementação

Ordenadas por prioridade das User Stories, com a validação empírica de FR-013
como **primeira task**, antes de qualquer implementação que dependa dela.

### FASE 0 — Validação empírica do mecanismo de notificação (bloqueante para US2)

| # | Task | Critério de aceite |
|---|---|---|
| 0.1 | **Experimento de wake-up**: abrir 2 sessões `claude --name`, deixar a coordenadora ociosa, disparar `SendMessage` da filha e observar se a coordenadora retoma processamento sem intervenção | resultado registrado como **funciona / não funciona / parcialmente**, com transcrição literal do observado (SC-005) |
| 0.2 | Registrar o resultado de 0.1 em `research.md` (nova Decision) e propagar para `contracts/parallel-launch.md` §6 | se refutado, §8 (próxima leva) passa a depender da via manual — e a prosa MUST dizer isso |
| 0.3 | Implementar a **via manual** de checagem (`contracts/parallel-launch.md` §7) | documentada no command pai; funciona independentemente do resultado de 0.1 (FR-013) |

FASE 0 é a única que **não pode** ser reordenada: US2 inteira depende do
resultado, e afirmar o comportamento antes de medi-lo violaria o Princípio VI.

### FASE 1 — US1 (P1): fronteira + oferta + lançamento

| # | Task | Cobre |
|---|---|---|
| 1.1 | `roadmap-frontier.sh`: parse da saída de `roadmap-status.sh --json`, regra de elegibilidade (§4 do contrato), saídas markdown/`--json`, exit codes propagados | FR-001, FR-010, SC-004 |
| 1.2 | `tests/test_roadmap-frontier.sh` com fixtures de roadmap (o repo **não tem** `docs/roadmap.md` — fixtures são obrigatórias) | SC-004 |
| 1.3 | `parallel-launch.sh`: `check-tmux` + `emit` (composição dos 2 comandos por feature) | FR-005, FR-006 |
| 1.4 | Guarda anti-duplicidade via `git worktree list --porcelain` (`--exclude-active-from-repo`) | FR-011 |
| 1.5 | `tests/test_parallel-launch.sh` | FR-005, FR-006, FR-011 |
| 1.5a | **Hardening do gate de segurança**: quoting + allowlist de `<WORKTREE>`/`<CHILD_NAME>`, revalidação do short-name no `emit`, log em `enforcement-log.jsonl`, recomputação da guarda anti-duplicidade imediatamente antes do lançamento | `contracts/parallel-launch.md` §4.1/§4.2 |
| 1.5b | Testes adversariais: nome de repo com espaço/aspa; short-name malicioso; path com `..` nas 3 flags de `roadmap-frontier.sh` | §3.1 do contrato de frontier |
| 1.6 | Prosa em `agente-00c.md`/`agente-00c-resume.md`: gatilho pós-`concluido_roadmap`, pergunta de teto (**default 2**), seleção quando candidatas > teto, recusa preserva fluxo atual | FR-002, FR-003, FR-004, FR-012, SC-001 |
| 1.7 | `tests/test_command-spawn-parallel-launch.sh` (prosa) | FR-002..FR-004, FR-012 |

### FASE 2 — US2 (P2): notificação e próxima leva

| # | Task | Cobre |
|---|---|---|
| 2.1 | Prosa da notificação terminal em `feature-00c.md`/`feature-00c-resume.md`, best-effort, com os 3 desfechos reais (`concluida`, `abortada`, `aguardando_humano`) | FR-008, FR-015, SC-002 |
| 2.1a | **Parse fail-closed da notificação recebida** (regex ancorada, sobra descartada, gatilho opaco) — finding HIGH do gate de segurança | `contracts/parallel-launch.md` §6 |
| 2.2 | Prosa do recálculo da fronteira ao receber notificação, no command pai | FR-009 |
| 2.3 | Cenário de teste do não-liberamento de dependentes por término não-concluído | FR-010 |

Pré-requisito duro: FASE 0 concluída e registrada.

### FASE 3 — US3 (P3): degradação sem tmux

| # | Task | Cobre |
|---|---|---|
| 3.1 | Caminho degradado de `emit` (forma `cd <worktree> && claude …`) | FR-007 |
| 3.2 | Teste de paridade: comandos do caminho degradado equivalem aos do automático | SC-003, AC2 da US3 |
| 3.3 | Teste de ausência de tmux: nenhuma falha silenciosa, nenhum bloqueio à espera | SC-003 |

### FASE 4 — US4 (P4): aviso de sobreposição

| # | Task | Cobre |
|---|---|---|
| 4.1 | Heurística de tokens de artefato sobre o bloco de prosa das entradas | FR-014 |
| 4.2 | Redação como **indício**, nunca como afirmação de conflito | Princípio VI |
| 4.3 | Teste: informação insuficiente ⇒ segue oferecendo sem bloquear | AC2/AC3 da US4 |
| 4.4 | **Sanitização da prosa** (allowlist de token, truncamento, escaping JSON/markdown, rótulo de não-confiável) — finding HIGH do gate de segurança | `contracts/roadmap-frontier.md` §6/§7.1 |

## Cenários de teste mapeados aos Success Criteria

| SC | Cenário | Onde |
|---|---|---|
| SC-001 (< 1 min de interação) | fixture com 3 entradas ⇒ oferta apresenta candidatas + teto default 2 numa única rodada de perguntas; nenhum comando montado à mão pelo operador | `test_command-spawn-parallel-launch.sh` + `quickstart.md` C1 |
| SC-002 (100% dos términos tentam notificar) | os 3 desfechos terminais (`concluida`, `abortada`, `aguardando_humano`) disparam tentativa de notificação; falha de envio não altera o ciclo da filha | `quickstart.md` C4/C5 |
| SC-003 (sem multiplexador: 0 falha silenciosa, 0 travamento) | `PATH` sem `tmux` ⇒ `emit` retorna comandos completos, exit 0, sem prompt pendente | `test_parallel-launch.sh` + `quickstart.md` C6 |
| SC-004 (fronteira reflete exatamente as dependências) | matriz de fixtures: dep concluída ⇒ elegível; dep `em-andamento` ⇒ não; dep inexistente ⇒ não; sem deps ⇒ elegível | `test_roadmap-frontier.sh` + `quickstart.md` C2/C3 |
| SC-005 (registro comprovado/refutado do wake-up) | experimento da FASE 0 com resultado literal registrado em `research.md` | `quickstart.md` C7 (task 0.1) |
| (transversal — gate `owasp-security`) | notificação forjada + prosa hostil no roadmap não produzem lançamento fora da fronteira nem injeção em linha de comando | `quickstart.md` C7b + `test_parallel-launch.sh` (1.5b) |

## Re-check de constitution (pós-design)

| Princípio | Status | Verificação pós-design |
|---|---|---|
| II. POSIX puro | PASS | design não introduziu `jq` nem dep obrigatória nova; `tmux` permanece opcional com fallback testado (FASE 3) |
| IV. Zero coleta remota | PASS | nenhum componente novo faz rede; `SendMessage` é local ao harness do operador |
| VI. Veracidade | PASS | FASE 0 impede que o comportamento não comprovado vire premissa; todos os contratos novos rotulados como proposta |
| — Complexidade | PASS | 2 scripts novos, 0 arquivo de `cli/lib/` tocado, 0 estado persistido novo, 0 comando de CLI novo |

Nenhuma violação a justificar.

## Complexity Tracking

*Vazio — nenhuma violação de constitution exigiu justificativa.*

## Riscos conhecidos

| Risco | Impacto | Mitigação no plano |
|---|---|---|
| Wake-up da coordenadora ociosa pode não existir | US2 perde automação | FASE 0 mede antes de depender; via manual (FR-013) é entregue de qualquer forma |
| Guarda de Bash inativa no instante da oferta (status já `concluida`) | comandos da leva rodam sem decisão do hook | short-names só vêm da saída fail-closed de `roadmap-status.sh`; documentado em `contracts/parallel-launch.md` §2 |
| Coordenadora sem `--name` | endereçamento da notificação falha | detectado e informado no lançamento, não descoberto depois (`contracts/parallel-launch.md` §5) |
| Heurística de sobreposição gera falso positivo | ruído para o operador | saída redigida como indício; nunca bloqueia (AC3 da US4) |
| **Prosa de `docs/roadmap.md` é conteúdo não-confiável** que chega ao command pai no instante em que ele pode executar shell (LLM01/ASI01) | injeção de prompt indireta | allowlist de token + truncamento + rótulo de não-confiável (`contracts/roadmap-frontier.md` §6); INV-4 reconciliado |
| **Notificação `SendMessage` não autentica remetente** (ASI07) | leva forjada | payload casado por regex ancorada, tratado como gatilho opaco, e nada é lançado sem reconfirmação pela fronteira recalculada (`contracts/parallel-launch.md` §6) |
| **Worktree não é fronteira de segurança** (ASI03/ASI08) | filha comprometida alcança coordenadora e host (`.git` common-dir, `$HOME`, `~/.claude`, credenciais) | declarado explicitamente em `contracts/parallel-launch.md` §8.bis; teto de concorrência também limita blast radius; kill switch documentado |
| Interpolação de `<WORKTREE>`/`<CHILD_NAME>` em linha de comando | argument injection (nome de repo com espaço/aspa) | quoting obrigatório + allowlist no ponto de uso (`contracts/parallel-launch.md` §4.1) + revalidação no `emit` (§4.2) |

## Próximos passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor as FASES 0-4 em backlog executável
3. `/analyze` — consistência cross-artifact após as tasks existirem
