# Validation: Pipeline CSTK no Codex

> Histórico da implementação anterior à reescrita POSIX de 2026-10-03.
> Estado atual e novas evidências em [validation-posix.md](validation-posix.md).

**Date**: 2026-10-02 | **Feature**: [spec.md](spec.md)

## Níveis de evidência

- Implementação/testes: contratos determinísticos com fixtures identificadas.
- Descoberta nativa: CLI/app-server em instalação isolada, sem turno de modelo.
- Semântica: modelo conduz entrega funcional, com revisão/testes de negócio.
- Proteção nativa: hooks revisados e observados nas ferramentas de um turno real.

Os dois últimos níveis continuam pendentes. Não preencher com resultados dos
primeiros. As alterações da padronização inicial são documentais; não houve nova
execução da suíte de runtime para declarar aprovação atual do produto.

## Evidência da implementação anterior

| Execução | Resultado observado | Log |
|----------|---------------------|-----|
| Suíte Python completa | 74 casos; 73 passaram, 1 nativo pulado; 358,662 s | /tmp/cstk-codex-v05-full-tests.log |
| Ciclo de vida posterior | 18 passaram; 141,313 s | /tmp/cstk-codex-v05-lifecycle-final.log |
| Instalação final | 6 passaram; 6,449 s | /tmp/cstk-codex-v05-installer-hooks-final.log |
| Contratos nativos finais | 2 passaram; 28,270 s | /tmp/cstk-codex-v05-final-native-r2.log |

União dos IDs nos quatro logs: 81 casos distintos, não uma suíte única de
81 casos aprovada num mesmo snapshot. Cabeçalhos/hash/sumários preservados
em [test-results.txt](evidence/test-results.txt). Históricos completos em
[implementation-history.md](evidence/implementation-history.md).

Grupos shell direcionados anteriores aprovados: install 31, build-release 11,
self-update 19, bootstrap/00c-bootstrap 32, cstk-main 23. A suíte shell completa
histórica teve 4.458 sucessos e 10 falhas; reexecuções/correção são descritas
no histórico. Não declarar repetição completa que não ocorreu.

## Instalação do operador e preflight desta sessão

Inspeção global somente leitura: fonte/cache conferem com SHA-256 do recibo,
plugin habilitado, seis skills e handlers intactos, knowledge.db existente.
Ver [installation-preflight.json](evidence/installation-preflight.json).
Confiança global dos hooks não foi inspecionada nem alterada.

Cópia isolada do pacote efetivamente instalado: CLI 0.160.0, seis skills,
quinze ferramentas, MCP conectado, hooks carregados sem erros/avisos e
untrusted. Ver [native-preflight.json](evidence/native-preflight.json) e
[dogfood-session-2026-10-02.md](dogfood-session-2026-10-02.md).
Nenhum turno de modelo, estado ou onda do piloto foi criado.

## Rastreabilidade de requisitos

| Requisito | Tasks | Evidência/pendência |
|-----------|-------|--------------------|
| FR-001 | 5.1 | dry-run/dependências nos testes de instalação |
| FR-002 | 3.1, 5.2 | seis skills no preflight nativo |
| FR-003 | 5.1, 5.2 | preservação/conflitos e regressões shell |
| FR-004 | 4.2, 5.1, 6.1 | configuração sem confiança; revisão real pendente |
| FR-005 | 2.1, 2.2, 6.1 | oito fases em fixture; semântica pendente |
| FR-006 | 2.1 | onze/três fases em fixture; semântica nativa pendente |
| FR-007 | 2.2, 4.2 | evidências/gates e decisões testados |
| FR-008 | 2.2, 6.1 | I-2 testado; resposta real pendente |
| FR-009 | 3.1, 6.1 | retomada testada; piloto semântico pendente |
| FR-010 | 3.1 | bloqueio/resposta por ID testados |
| FR-011 | 3.1, 6.1 | aborto/idempotência testados; piloto separado pendente |
| FR-012 | 2.2, 3.2, 4.2 | locks e interrupções/processos testados |
| FR-013 | 4.1, 6.1, 8.3 | ingestão/migração/recall testados; cadastro posterior indexado no banco real |
| FR-014 | 2.1, 4.1 | proveniência nullable testada |
| FR-015 | 3.2 | transferência explícita JSON/SQLite e MCP testada |
| FR-016 | 3.2 | drift/reconciliação testados |
| FR-017 | 1.1, 1.2, 6.2 | matriz distingue níveis; aceite completo aberto |
| FR-018 | 1.1, 7.1, 7.2 | governança II/III em conflito; não aprovada |
| FR-019 | 8.1, 8.2, 8.3 | estado SQLite, schema 16, WAL e API do índice real validados |

## Gates documentais da normalização

Executados pelas próprias skills; saída em
[documentation-gates.txt](evidence/documentation-gates.txt): cobertura de
19/19 FRs, template canônico, métricas de tarefas, renderização/links e
extração de intenção/MUST. Revisão cruzada semântica em [review.md](review.md).
Renderização é heurística do script CSTK, não certificação por renderer visual.

## Incremento do painel

SC-007 validado pelo caminho real de leitura da API (Fastify.inject) e por
testes SQLite com escrita WAL antes do checkpoint. Suíte do servidor: 496
passaram e 48 pulados; build/typecheck aprovados. Bootstrap/validação/helpers
canônicos e primeira ingestão no índice compartilhado concluídos. Sem teste
visual de navegador nem turno semântico do Codex. Evidência e limite da
importação retrospectiva em [panel-registration.md](panel-registration.md).

## Critérios finais ainda abertos

SC-002 e cobertura nativa de SC-006: piloto funcional real, retomada, aborto,
proteções em turno real. SC-003: projetos/roadmap possuem evidência de fixture,
não aprovação semântica. SC-004/005: contratos aprovados por testes, observação
no piloto real pendente. SC-006 também requer resolver governança e revisão
Claude; tentativa mais recente retornou ausência de autenticação, sem revisão.

## Verificação para publicação do PR — 2026-10-02

Nova execução sobre as alterações preparadas neste checkout:

- `python3 -m unittest discover -s tests/codex -v`: 81 casos, 79 passaram,
  dois contratos nativos opcionais pulados por falta de instalação isolada
  selecionada; 370,443 s. Nenhuma instalação global foi alterada.
- `sh tests/run.sh`: 4.462 passaram, nove falharam, zero erros e zero órfãos;
  1.205 s. As falhas ocorreram nos grupos que exigem portas locais, tmux
  ou inspeção de processos bloqueados pelo sandbox.
- Reexecuções fora do sandbox: telemetry-env (13), e2e_roadmap_wave (3),
  otel-usage (38) e parallel-launch (96), todos aprovados. A suíte completa
  não foi repetida fora do sandbox; seu resultado original permanece acima.
- Servidor do painel: 496 passaram, 48 pulados; build e typecheck aprovados.
  A tentativa inicial no sandbox falhou na suíte de integração que abre uma
  porta local; a reexecução completa fora dele foi aprovada.
- Cobertura shell com zero órfãos; validadores de manifestos e lockstep do
  painel aprovados (comparação com tag não solicitada, pois não é release).
- Sintaxe Python (23 arquivos), frontmatter das seis skills, sintaxe shell
  dos arquivos alterados e `git diff --cached --check` aprovados.

Sumários, hashes e identificação dos logs em
[pr-test-results.txt](evidence/pr-test-results.txt). Essa verificação não
fecha os conflitos constitucionais nem os critérios de homologação semântica
e de cobertura nativa dos hooks. A publicação é preparada como PR rascunho.
