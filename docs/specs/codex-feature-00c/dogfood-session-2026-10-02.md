# Dogfood após instalação — 2026-10-02

## Resultado até o preflight

A instalação real do operador foi inspecionada somente por leitura. Fonte e cache conferem com os SHA-256 do recibo; o plugin está habilitado, as seis skills estão presentes e os dois handlers gerenciados correspondem ao hooks.json. O knowledge.db configurado existe. Não foram modificadas instalações globais nem concedida confiança aos hooks.

Uma instalação temporária, criada a partir do pacote efetivamente instalado pelo operador, foi consultada com Codex CLI 0.160.0/app-server: seis skills habilitadas, servidor cstk_pipeline conectado e 15 ferramentas disponíveis. PreToolUse e PostToolUse carregaram sem erros; nessa instalação isolada estão sem confiança. Isso não determina a confiança dos hooks da instalação global.

O catálogo de ferramentas desta conversa não expõe o MCP CSTK. A documentação oficial exige nova sessão após instalar para usar as skills/ferramentas empacotadas: https://learn.chatgpt.com/docs/plugins. A revisão de confiança é feita pelo operador em /hooks: https://learn.chatgpt.com/docs/hooks.

## Piloto preparado

Projeto temporário: `/var/folders/37/03qyt93s4rb25rffgyp5194w0000gp/T/cstk-dogfood-20261002-hk4v4ub3/project`.
Instalação temporária: `/var/folders/37/03qyt93s4rb25rffgyp5194w0000gp/T/cstk-dogfood-20261002-hk4v4ub3/codex-home`.
Evidência nativa: `/var/folders/37/03qyt93s4rb25rffgyp5194w0000gp/T/cstk-dogfood-20261002-hk4v4ub3/native-preflight.json`.
Inspeção global filtrada: `/tmp/cstk-dogfood-global-install-readonly.json`.
Localizador do piloto: `/tmp/cstk-dogfood-latest.json`.

Entrega proposta: CLI local de validação de documentos de governança, com saída JSON, casos válidos/negativos e execução somente leitura. Briefing e constitution 1.0.0 foram preparados. O context.py do pacote instalado confirmou prerequisites_ready=true, nenhuma pendência de preparação e state_exists=false; nenhum estado/onda foi criado.

## Pendências reais

- Resposta do operador sobre commits automáticos e escolha do banco antes da primeira onda. Pergunta enviada na sessão, ainda sem resposta no momento deste registro; não substituir por resposta de fixture.
- Executar as oito etapas semânticas, testar pausa/retomada, aborto em execução separada e confirmar ingestão/proveniência.
- Em nova sessão que exponha o MCP instalado, revisar hooks e observar chamadas de ferramentas de um turno de modelo real.

## Limite da evidência

O preflight confirma instalação e descoberta nativa. Não houve turno de modelo no app-server, execução semântica da feature, revisão/confiança global de hooks ou certificação de cobertura. Chamadas diretas ao app-server não disparam hooks de ferramentas de um turno de modelo. A aprovação completa permanece pendente.

## Cadastro posterior da feature do toolkit

Após este preflight, o operador solicitou visibilidade da feature no painel.
Foi criado estado SQLite no projeto CSTK e indexado no banco compartilhado,
com pendências reais, zero ondas e opt-ins não respondidos. Esse registro não
é a execução do piloto temporário acima. Ver [panel-registration.md](panel-registration.md).
