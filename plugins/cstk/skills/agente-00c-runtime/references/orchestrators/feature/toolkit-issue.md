# Referencia de fase: toolkit-issue (feature)

> Conteudo movido do prompt-base `agente-00c-feature-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

## Gh issue exclusivo (FR-035 + task 4.1.11)

Quando uma sugestao para skill global e classificada como
**severidade=impeditiva**, e SOMENTE nesse caso:

1. Validar repo destino: HARDCODE `JotJunior/cstk`. Outro
   repo = registrar decisao "violacao blast radius" + abortar.

2. Filtrar conteudo: corpo da issue passa por `secrets-filter.sh scrub`
   (o `issue.sh` faz isso internamente, 2x). Por default (issue #143 /
   Principio IV) o corpo e REDIGIDO — inclui apenas:
   - skill afetada
   - diagnostico / reproducao / por-que-impeditivo / proposta (filtrados)
   - link LOCAL ao relatorio com path GENERICO `<projeto-alvo>/...` (NAO
     upload do relatorio; NAO descricao do projeto-alvo, NAO ID da
     execucao, NAO trechos de Decisoes, NAO paths da maquina)

3. RASCUNHAR, nunca publicar:
   `issue.sh create --state-dir $STATE_DIR --suggestion-id <SUG>
   --skill <SKILL> --diagnostico "<...>" --proposta "<...>"
   --por-que-impeditivo "<...>" --reproducao "<...>" --env-file <PAP>/.env
   --draft <PAP>/.claude/agente-00c-issues/<SUG>.md`. Voce NUNCA passa
   `--include-project-context` nem chama `issue.sh publish` — sao acoes
   do operador.

4. Registrar Decisao informativa com o path do rascunho e cita-lo no
   sumario de retorno ("Rascunhos de issue aguardando o operador"). O
   operador revisa e publica com `issue.sh publish --from <arquivo>
   --state-dir $STATE_DIR --suggestion-id <SUG>` (dedup por hash,
   secrets-filter de novo, `mark-issue` no state).

Severidade `informativa` ou `aviso` NAO abre issue — apenas
registrada via `suggestions.sh register` (ver "## Sugestoes para skills
globais (FR-020)" acima).

<!-- ORCH-REF-END -->
