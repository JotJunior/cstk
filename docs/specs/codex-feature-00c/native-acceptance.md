# Native Acceptance: Pipeline CSTK no Codex

**Feature**: [spec.md](spec.md) | **Adapter**: 0.5.0 | **Date**: 2026-10-02
**Status**: discovery aprovado; homologação de uso real pendente.

## Preparação

1. Resolver Constitution Check aberto conforme tasks 7.1/7.2.
2. Usar projeto e CODEX_HOME temporários; confirmar banco antes de abrir onda.
3. Instalar com cstk install --cli=codex. Nova sessão deve expor as seis skills e o MCP.
4. Revisar definições exatas no menu /hooks; instalador não concede confiança.
5. Registrar os opt-ins reais aplicáveis e a fonte da resposta.

Fluxos e cenários em [quickstart.md](quickstart.md); schemas em
[contracts/workflows.md](contracts/workflows.md). Fonte oficial:
[Plugins](https://learn.chatgpt.com/docs/plugins) e
[Hooks](https://learn.chatgpt.com/docs/hooks).

## Definições para revisão

[PreToolUse](../../../adapters/codex/hooks/pretooluse.py),
[PostToolUse](../../../adapters/codex/hooks/posttooluse.py) e
[configuração](../../../adapters/codex/hooks/hooks.json).
Instalador 0.5.0 registra handlers na camada user com comandos do pacote por
hash e desativa declarações redundantes no manifest instalado.
No CLI 0.160.0, hooks somente pelo manifest não foram listados; afirmações
antigas de descoberta desse caminho estão corrigidas no histórico.

## Evidências requeridas para fechar o aceite

| Critério | Evidência exigida | Estado atual |
|----------|-------------------|--------------|
| Instalação/descoberta | Seis skills habilitadas, quinze ferramentas e MCP conectado | Observado em instalação isolada |
| Confiança | Definições revisadas pelo operador e status correspondente | Pendente; confiança global não inferida |
| Cobertura de ferramentas | Trace real de comando permitido/negado, patch e contagem durante onda | Pendente |
| Pipeline semântica | Feature funcional testada, oito etapas e evidências de avanço | Pendente |
| Retomada | Pausa e continuação da mesma execução/etapa | Contrato testado; piloto real pendente |
| Aborto | Execução separada, histórico e relatório preservados | Contrato testado; piloto real pendente |
| Conhecimento | Consulta/uso e proveniência conferidos no índice escolhido | Contrato testado; piloto real pendente |
| Governança/revisão | Constitution Check resolvido e revisão externa produzida | Pendente |

## Limites de interpretação

Chamadas diretas ao app-server usam o MCP real, mas não são turno de modelo
nem disparo de hooks desse turno. Ferramentas hospedadas, write_stdin e
wrappers têm limites próprios; confiança não equivale a cobertura completa.
Não conceder confiança por API/backdoor ou usar bypass como evidência de aceite.

A instalação do operador foi apenas inspecionada por leitura; preflight do
pacote copiado para ambiente isolado está em
[validation.md](validation.md). O procedimento 0.4.0 foi preservado como
histórico e não é instrução vigente. App/IDE/cloud exigem avaliação separada.
