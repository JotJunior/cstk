# Capability: delivery-tier

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-001

O inicio de `/agente-00c` MUST exibir, antes da inicializacao do estado, uma pergunta unica de finalidade com exatamente 4 opcoes canonicas, mapeadas aos tokens estaveis `local`, `internal-network`, `cloud-internal` e `cloud-public`.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-002

A escolha MUST persistir em campo proprio do estado da execucao (`delivery_tier`) gravado no init; retomadas (`/agente-00c-resume`) MUST reler o campo sem re-promptar — mesmo padrao do opt-in atomic-commit.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-003

Ausencia de resposta, entrada invalida ou execucao nao-interativa MUST resultar no default `cloud-public` (profundidade plena), preservando o comportamento atual da pipeline como caso base (zero regressao).

*Introduzida por: delivery-tier (2026-09-09)*

### FR-004

O orquestrador MUST propagar o tier vigente no contexto das etapas briefing, specify e plan, com instrucao explicita de calibrar escopo e profundidade de arquitetura a finalidade declarada. A leitura do tier propagado MUST vir de fonte coagida ao enum fechado de 4 tokens — nunca texto livre interpolado diretamente no prompt da skill.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-005

Os quality gates complementares MUST ser resolvidos por uma matriz tier×gate versionada no toolkit; gate ausente da matriz para um tier MUST rodar completo (fail-safe na direcao da profundidade). O mesmo fail-safe MUST cobrir o caso de uma linha PRESENTE na matriz com modo malformado, corrompido ou vazio — nao apenas o caso de par ausente: qualquer modo lido fora do enum fechado `completo|leve|skip` MUST ser coagido a `completo`, nunca propagado verbatim. A matriz cobre EXCLUSIVAMENTE o gate `owasp-security` (revisao de seguranca) — matriz default: completa nos tiers `cloud-internal` e `cloud-public`, versao leve (checagens essenciais: auth, secrets, input) em `internal-network`, skip com Decisao em `local`. Os demais gates complementares (`checklist`, `validate-documentation`, `validate-docs-rendered`, `analyze`) NAO tem celula na matriz e MUST rodar completos nos 4 tiers, sob o mesmo fail-safe. Skip ou versao leve de gate MUST gerar Decisao auditavel citando o tier — nunca skip silencioso.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-006

create-tasks MUST receber o tier e aplicar uma divisao BINARIA nuvem/nao-nuvem: os tiers `local` e `internal-network` MUST omitir do backlog as fases de infraestrutura de producao (deploy em nuvem, escalabilidade e observabilidade de producao — entendida aqui como dashboards, SLO/SLI, APM/tracing, alertas e autoescala/ multi-regiao/CDN de escala operacional; log de autenticacao/ autorizacao e trilha de auditoria NUNCA entram nessa omissao, em qualquer tier); os tiers `cloud-internal` e `cloud-public` MUST gerar backlog completo com essas fases. Nao ha lista de fases distinta por tier alem dessa divisao binaria. create-tasks MUST registrar no proprio tasks.md o tier usado na geracao.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-007

O tier MUST calibrar somente profundidade e escopo; MUST NOT alterar, relaxar ou desativar o Principio VI (zero fabricacao de dados), as guardas enforced (bash-guard, path-guard, secrets-filter) nem qualquer invariante de seguranca do runtime — em TODOS os tiers.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-008

A escolha do tier MUST ser registrada como Decisao auditavel (5 campos) na execucao, e o tier + consequencias aplicadas (gates pulados/versao leve) MUST constar no relatorio final e no review-task. O review-task MUST detectar e reportar como finding qualquer mudanca do tier vigente sem Decisao de operador correspondente na trilha de auditoria (`delivery-tier-unattended-change`).

*Introduzida por: delivery-tier (2026-09-09)*

### FR-009

Elevacao de tier mid-execucao MUST ser suportada via decisao manual do operador entre ondas, valendo das ondas seguintes em diante; rebaixamento mid-execucao MUST NOT ser aplicado sem decisao manual explicita **do operador** e MUST NOT reduzir retroativamente artefatos ja gerados.

*Introduzida por: delivery-tier (2026-09-09)*

### FR-010

Estado legado sem o campo `delivery_tier` MUST ser tratado como `cloud-public` em qualquer leitor (orquestrador, resume, report) — sem re-prompt, sem erro de validacao.

*Introduzida por: delivery-tier (2026-09-09)*

