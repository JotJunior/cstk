# Quickstart: enforced-guards

Cenarios de validacao end-to-end para as tres frentes (US1/US2/US3). Feature
e single-layer (scripts CLI + hook do harness, sem borda backend↔frontend) —
o cenario "Roundtrip End-to-End" do template nao se aplica; ver nota ao final.

## Scenario 0: Spike de propagacao do hook a subagentes (BLOQUEANTE — roda antes de tudo)

> Resolve a Decision 4 (risco aberto) de `research.md`. Nenhum outro cenario
> de US1 deve ser considerado validado antes deste responder a pergunta.

1. Provisionar o hook `PreToolUse`/`Bash` (Decision 1/9) num projeto de teste
   descartavel, com `.claude/feature-00c-state/<x>/state.json` presente e
   `.execution.status = "em_andamento"` (simulando execucao ativa).
2. A partir da sessao raiz desse projeto, spawnar um subagente (tool Agent,
   qualquer `subagent_type` que tenha Bash nos allowed-tools) com um prompt
   que instrui explicitamente rodar um comando bloqueavel conhecido (ex:
   `git push origin main` sem remote real, ou `rm -rf /tmp/spike-test` —
   escolher um que bash-guard.sh de fato bloqueia).
3. Observar se o comando e interceptado (aparece no `enforcement-log.jsonl`
   e o subagente recebe negacao) ou se executa livremente.
4. **Expected (bifurcacao, ambas sao resultado valido — o que importa e
   *saber*, nao um resultado especifico)**:
   - Se interceptado: US1 cobre subagentes tambem; demais cenarios abaixo
     valem como escritos.
   - Se NAO interceptado: registrar como constraint conhecida (Decision 4,
     mitigacao 2) — SC-001 passa a ser lido como "cobre comandos da sessao
     raiz"; camada advisory (FR-005) permanece a garantia real para comandos
     emitidos de dentro de subagentes. Nenhum cenario abaixo que dependa de
     bloqueio-dentro-de-subagente pode ser declarado passante nesse caso.

---

## Scenario 1: Comando Bash perigoso e barrado sem a instrucao pedir a checagem (US1, happy path do bloqueio)

1. Provisionar o hook (Decision 9) e iniciar uma execucao `feature-00c` real
   (state presente, status `em_andamento`).
2. Emitir, dentro dessa execucao, uma instrucao que NAO menciona rodar
   `bash-guard.sh` e que leva a um `git push origin main`.
3. **Expected**: o comando nao chega a executar (harness recebe
   `permissionDecision: deny`); `enforcement-log.jsonl` ganha uma linha
   `outcome:"blocked-by-rule"`, `category:"git-push"`.

## Scenario 2: Comando Bash legitimo passa sem atraso perceptivel (US1)

1. Mesma execucao ativa do Scenario 1.
2. Emitir um comando Bash inocuo (ex: `ls -la`).
3. **Expected**: executa normalmente; nenhuma entrada `blocked-*` no log
   (pode ou nao gerar entrada `outcome` de sucesso conforme decisao de
   volume — ver `contracts/enforcement-log.md`); sem prompt/passo manual
   extra.

## Scenario 3: Sessao interativa comum do operador NAO e afetada (US1, FR-006/dec-012)

1. Fora de qualquer execucao `agente-00c`/`feature-00c` (nenhum `state.json`
   com status `em_andamento` presente), rodar `git push` manualmente no
   mesmo projeto onde o hook esta provisionado.
2. **Expected**: comando roda exatamente como antes desta feature — hook
   emite `exit 0` sem decisao (Decision 3), zero interferencia no fluxo
   manual do operador.

## Scenario 4: Mecanismo de checagem falha internamente → fail-closed (US1, FR-007)

1. Mesma execucao ativa do Scenario 1, mas com `jq` deliberadamente ausente
   do PATH usado pelo hook (ou `bash-guard.sh` temporariamente sem permissao
   de execucao).
2. Emitir qualquer comando Bash, inclusive um inocuo.
3. **Expected**: comando e bloqueado (nao apenas os perigosos) com
   `permissionDecisionReason` prefixado `MECANISMO_FALHOU` — distinguivel de
   `REGRA_VIOLADA` no log e na mensagem ao orquestrador.

## Scenario 5: Painel recusa iniciar sem integridade confirmada, por padrao (US2)

1. Simular um release do cstk-panel sem `.sha256` disponivel (fixture local,
   analogo ao estado real hoje do repositorio do painel).
2. Rodar `cstk serve`.
3. **Expected**: `cstk serve` NAO inicia a partir do pacote baixado; mensagem
   clara indicando integridade nao confirmada e como prosseguir
   conscientemente (flag/env de Decision 6).

## Scenario 6: Operador aceita o risco explicitamente (US2, FR-009/FR-011)

1. Mesmo fixture do Scenario 5.
2. Rodar `cstk serve --allow-unverified` (ou com
   `CSTK_SERVE_ALLOW_UNVERIFIED=1`).
3. **Expected**: prossegue; `enforcement-log.jsonl` ganha linha
   `source:"serve-integrity"`, `outcome:"unverifiable-bypassed"`,
   `bypass_method:"flag"` (ou `"env"`).

## Scenario 7: Divergencia de checksum continua bloqueando sem bypass (US2, FR-010 — regressao)

1. Fixture com `.sha256` disponivel mas adulterado/nao-correspondente ao
   tarball.
2. Rodar `cstk serve` (com ou sem `--allow-unverified` — bypass NAO se aplica
   a mismatch, so a "nao-verificavel").
3. **Expected**: recusa preservada (comportamento ja existente hoje,
   `serve.sh:206-210`), nenhum bypass silencioso possivel.

## Scenario 8: Host fora da allowlist e rejeitado antes do download (US3)

1. Rodar `cstk install --from https://evil.example.com/release.tar.gz`.
2. **Expected**: rejeitado imediatamente (`exit` nao-zero), mensagem citando
   host nao-confiavel, ZERO bytes transferidos (verificavel por ausencia de
   qualquer arquivo temporario de download criado).

## Scenario 9: Host confiavel continua funcionando sem passo novo (US3, regressao)

1. Rodar `cstk install --from https://github.com/JotJunior/cstk/releases/download/vX.Y.Z/cstk-X.Y.Z.tar.gz`
   (fluxo padrao real).
2. **Expected**: prossegue exatamente como hoje, nenhuma acao manual nova.

## Scenario 10: `file://` continua sem exigir allowlist (US3, FR-014 — regressao)

1. Rodar `cstk install --from file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz` (fluxo
   de dev documentado em `CLAUDE.md`).
2. **Expected**: comportamento identico ao atual, sem checagem de host.

---

> **Nota sobre "Roundtrip End-to-End"**: o template de quickstart exige esse
> cenario para features com borda backend↔frontend (contrato de payload
> HTTP consumido por um SPA). `enforced-guards` nao tem essa borda — e
> enforcement local via hook de CLI + scripts shell, sem API HTTP nem
> frontend. N/A, registrado explicitamente em vez de omitido silenciosamente.
