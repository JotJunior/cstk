# Registro SQLite e painel — 2026-10-02

> Histórico da implementação anterior à reescrita POSIX de 2026-10-03.
> Estado atual e novas evidências em [validation-posix.md](validation-posix.md).

Pedido do operador: tornar esta feature visível no painel. Registro retroativo,
separado do piloto temporário de dogfood, usando o runtime deste checkout.

## Estado canônico

- Local: `.claude/feature-00c-state/codex-feature-00c/state.db` neste projeto.
- Execução: `feat-codex-2aff8813b29343d9b20a93baab6da5a5`; projeto `cstk`.
- Status: `aguardando_humano`; fase: `converge`; duas decisões, um bloqueio.
- Proveniência: runtime `codex`, modelo `null`, toolkit `0.0.0-dev` (checkout).
- Nenhuma onda histórica reconstruída, opt-in respondido ou confiança concedida.

Criado com `adapters/codex/skills/feature-00c/scripts/session.py bootstrap`.
Mutações posteriores sob `Session.locked()` usam state-rw.sh, state-decisions.sh
e bloqueios.sh. Integridade e hashes verificados por Session.validate;
lock liberado. report.sh emit gerou relatório parcial no mesmo diretório.
Ver [state-registration.json](evidence/state-registration.json) para integridade,
contagens e hash do backlog.

`block-001` registra CHK016: decidir entre a emenda delimitada documentada e
o redesenho POSIX. A constitution não foi alterada. A retomada precisa resolver
governança, Gotchas, opt-ins e homologação das fases 6/7.

O schema SQLite exige `task_outcome.wave_id NOT NULL REFERENCES wave(id)`.
A tentativa de reconcile-tasks sem onda foi recusada e não importou outcomes.
Backlog documental preservado em `retrospective_registration.documented_subtasks`,
com SHA-256 de tasks.md. A aba de documentos contém as tarefas concluídas e
pendentes; a timeline/tasks operacionais permanece vazia até haver ondas reais.

## Compatibilidade e validação do painel

config.ts aceita schema 16 aditivo e preserva restrições explícitas do operador.
ingest-watcher.ts descobre state.db ou state.json; SQLite usa assinatura por
stat do banco e WAL para acompanhar commits antes do checkpoint. Não escreve
nos bancos; a ingestão continua delegada ao recall canônico.

Testes direcionados: 54 passaram. Suíte completa do servidor: 496 passaram,
48 pulados, 40 arquivos aprovados e quatro pulados. O primeiro ensaio exigiu
build de shared-types; o segundo foi impedido pelo sandbox no teste com porta
local. A execução final autorizada passou. Build de shared-types/servidor e
typecheck do servidor aprovados. Log completo: `/tmp/cstk-codex-panel-tests.log`.
Hash e sumário preservados em [panel-test-results.txt](evidence/panel-test-results.txt).

Ingestão ensaiada em `/tmp/cstk-codex-panel-stage.db`, depois executada com
autorização de escrita no índice compartilhado `~/.claude/cstk/knowledge.db`
por `sh cli/cstk recall --ingest --state-dir <diretório acima> --db <índice>`.
Resultado: 1 execução, 2 decisões, 1 bloqueio, 1 evento; 0 ondas/tasks operacionais.

Rotas reais compiladas registradas com Fastify.inject no índice real:
`/api/v1/features/cstk/codex-feature-00c`, subrecurso de bloqueios da execução
e `/api/v1/features/cstk/codex-feature-00c/docs/tasks`. Conferidos schema 16,
ausência de degradação, status, fase, contagens e conteúdo do backlog.
Saída filtrada em [panel-api.json](evidence/panel-api.json).

Nenhum teste visual de navegador ou pipeline semântica completa foi realizado.
Painel já iniciado precisa carregar o build atualizado para aceitar schema 16
e acompanhar SQLite. O cadastro não aprova as pendências de homologação.
