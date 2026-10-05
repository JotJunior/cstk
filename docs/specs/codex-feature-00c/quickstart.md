# Quickstart: Pipeline CSTK no Codex

Cenários de validação; não são registros de aprovação. Código do checkout e
limites atuais em [validation.md](validation.md). A primeira onda real exige
resposta humana e a conformidade aberta no Constitution Check.

## Scenario 1: Instalação e descoberta isoladas

1. Criar um CODEX_HOME e projeto temporários; confirmar caminho absoluto do índice isolado.
2. Executar o instalador apontando para os caminhos escolhidos:

```sh
sh cli/cstk install --cli=codex --codex-home "$CSTK_PILOT_HOME" --knowledge-db "$CSTK_PILOT_DB"
```

3. Iniciar nova sessão no projeto com essa instalação; consultar skills/MCP.
4. **Expected**: seis skills cstk-codex-pilot e quinze ferramentas cstk_pipeline. Nenhuma confiança de hooks ou resposta de opt-in criada automaticamente. SC-001.

As variáveis representam caminhos escolhidos pelo operador, não fixtures de
resposta. Evidência já observada em dogfood-session-2026-10-02.md.

## Scenario 2: Erro sem escolhas ou governança

1. Selecionar feature em projeto sem briefing/constitution; solicitar bootstrap.
2. **Expected**: diagnóstico de pré-requisitos, sem onda.
3. Preparar documentos válidos e bootstrap; não registrar resposta de opt-in.
4. Solicitar primeira onda.
5. **Expected**: guarda I-2 recusa sem avanço; silêncio não preenche atomic_commit. FR-005, FR-008.

## Scenario 3: Feature funcional com retomada

1. Em nova sessão com plugin carregado, selecionar projeto/feature/banco explicitamente e conferir contexto.
2. Obter resposta real sobre commits; registrar com cstk_optin e referência à mensagem recebida. Revisar hooks em /hooks; confirmar diagnóstico.
3. Abrir onda, ler skill_path/phase_reference e executar a etapa na própria sessão.
4. Persistir artefatos/revisão/testes e concluir com cstk_complete; continuar até impedimento real ou término.
5. Pausar em uma etapa com cstk_pause; invocar a skill feature-00c-resume; conferir mesma execução/etapa e continuidade.
6. **Expected**: oito etapas, entrega funcional testada, decisões justificadas e conclusão terminal observada. SC-002. Ainda pendente.

## Scenario 4: Aborto e concorrência

1. Criar execução separada autorizada e registrar suas escolhas reais.
2. Com onda própria aberta, solicitar abort; não solicitar purge de backups.
3. Repetir abort e resume sobre o estado terminal.
4. **Expected**: abortada, artefatos/histórico/relatório preservados; operação repetida não reabre execução. Outra conexão não toma proprietário vivo. SC-004.

## Scenario 5: Conhecimento compartilhado e origem

1. Confirmar índice antes da onda; consultar precedentes em specify/plan.
2. Aplicar somente fontes retornadas e justificadas; concluir etapa.
3. Conferir eventos de consulta/uso e execução derivada; repetir ingestão.
4. **Expected**: IDs de origem auditados, ingestão sem duplicação e modelo desconhecido null. Índice indisponível degrada sem perda do estado. SC-005.

## Scenario 6: Proteções num turno nativo real

1. Operador revisa definições exatas em /hooks; nova sessão expõe o MCP instalado.
2. Durante onda ativa, observar comando permitido, tentativa negada, apply_patch confinado e contagem PostToolUse.
3. Observar pausa/retomada sem proprietário órfão; persistir trace/status e limites do ambiente.
4. **Expected**: proteção demonstrada no ambiente alvo. RPC direto de app-server não substitui esse cenário. SC-006. Ainda pendente.

Sem frontend nesta feature; roundtrip aplicável é host -> MCP -> runtime ->
estado, já exercitado por RPC sem modelo. O uso semântico do modelo/proteções
permanece separado. Projeto completo/roadmap usam onze/três etapas e os três
opt-ins reais; evidência atual desses caminhos é fixture, não homologação.
