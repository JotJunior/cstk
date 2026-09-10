# SECURITY Checklist: structural-decision-human-gate

**Purpose**: Validar os requisitos de governanca/consentimento como controle de seguranca — a feature e, na essencia, um controle de autorizacao (consentimento humano rastreavel) contra decisao autonoma de alto impacto.
**Created**: 2026-08-19
**Feature**: [spec.md](../spec.md)

## Autenticacao/Autorizacao (consentimento como token de autoridade)

- [x] CHK001 - O "consentimento humano rastreavel" e definido como token verificavel contra estado (bloqueio `respondido`), nunca como afirmacao em texto livre do agente? [AuthZ, Spec §FR-003, Key Entities "Consentimento humano"] {auto}
- [x] CHK002 - O campo de agente decisor esta explicitamente excluido de qualquer papel na determinacao de consentimento (evita "self-authorization" por um agente que se auto-rotule humano)? [AuthZ, Spec §FR-003 "O campo que identifica o agente decisor MUST NOT ter qualquer papel"] {auto}
- [x] CHK003 - Existe vinculo obrigatorio de assunto (mesmo eixo) entre o BloqueioHumano e a Decisao, prevenindo "confused deputy" (consentimento de um eixo autorizando outro)? [AuthZ, Spec §FR-003 "O vinculo de assunto e obrigatorio"] {auto}
- [x] CHK004 - A referencia ao BloqueioHumano e verificada contra o estado NO MOMENTO DO REGISTRO (nao contra um cache/snapshot potencialmente obsoleto)? [AuthZ, Spec §FR-003 "verificada contra o estado no momento do registro"] {auto}
- [x] CHK005 - Um bloqueio de OUTRA execucao e explicitamente rejeitado como consentimento (escopo de execucao respeitado)? [AuthZ, Spec §FR-003, Edge Cases "Agente tenta forjar consentimento"] {auto}

## Protecao contra Injecao / Conteudo Nao-Confiavel

- [x] CHK006 - Texto lido de artefatos (briefing, plan) pelos gates e tratado estritamente como CONTEUDO, nunca como instrucao que altere classe/score/decisao de pausar? [Injection, Spec §FR-014] {auto}
- [ ] CHK007 - O texto do item Alto do briefing, ao virar a pergunta do BloqueioHumano, passa por algum saneamento contra conteudo adversarial embutido (ex.: instrucoes disfarcadas de "item a definir")? `data-model.md` §"Qualidade da pergunta" reconhece que a qualidade da pergunta e "tao informada quanto a `question` que o agente escreveu" e delega o contrapeso ao operador lendo antes de responder — isso mitiga julgamento indevido do agente, mas nao e saneamento contra conteudo adversarial embutido no texto propagado. [Gap, data-model.md linha 126] {humano}
- [x] CHK008 - A chave de assunto e derivada por funcao PURA do texto (determinismo), fechando a porta a manipulacao de correspondencia por "similaridade" ou "julgamento"? [Injection, Spec §FR-008 "casamento MUST ser igualdade exata de string"] {auto}

## Auditoria e Logging

- [x] CHK009 - Toda Decisao de classe estrutural e persistida com o eixo e a referencia ao bloqueio que a autorizou (rastro auditavel completo)? [Audit, Spec §FR-012] {auto}
- [x] CHK010 - O relatorio/`review-task` reporta contagem de anomalias de governanca (esperado 0), tornando desvios visiveis sem exigir grep manual? [Audit, Spec §FR-012, §US4 Acceptance Scenario 3] {auto}
- [x] CHK011 - Uma anomalia de governanca (estrutural sem consentimento valido) e DERIVADA e reportada, nunca silenciosamente aceita ou corrigida automaticamente? [Audit, Spec §Key Entities "Anomalia de governanca"] {auto}

## Modelo de Ameaca / Limitacoes Declaradas

- [x] CHK012 - A limitacao L1 (cobertura deterministica parcial — eixos stack-frameworks/arquitetura/persistencia sem detector proprio) esta declarada como fraqueza conhecida, nao omitida? [ThreatModel, Spec §"Limitacoes declaradas" L1] {auto}
- [x] CHK013 - A limitacao L2 (escrita direta em arquivo/SQL bypassa o guard) esta declarada, deixando claro que a trava protege o CAMINHO NORMAL, nao todo vetor de escrita? [ThreatModel, Spec §"Limitacoes declaradas" L2] {auto}
- [x] CHK014 - A spec evita alegar que o contorno se torna "impossivel" — usa linguagem calibrada ("eleva o custo", "residual declarado")? [ThreatModel, Spec §"Limitacoes declaradas" paragrafo final] {auto}
- [x] CHK015 - Ha nota sobre o que acontece se o proprio `subject_key` for adversarialmente colidido (dois itens Alto distintos produzindo a mesma chave por funcao pura)? Sim: `data-model.md` declara colisao adversarial via `cksum` (CRC, nao hash criptografico) como aceita, com efeito fail-open documentado e justificado (briefing e artefato humano ratificado, chave e dedup nao fronteira de autorizacao). [Data-model.md §"Derivacao da chave (funcao pura, FR-008)"] {auto}

## Paridade de Portas de Escrita (CLI x MCP)

- [x] CHK016 - A regra de recusa (R1/R2/R3/R6) e exigida como identica nos dois caminhos de escrita (helper POSIX e tool MCP), fechando bypass via MCP? [Parity, Spec §FR-004] {auto}
- [x] CHK017 - O erro tipado do caminho MCP (Edge Cases "Modo MCP") preserva a mesma semantica de recusa do helper CLI, nao apenas o mesmo texto? [Parity, Spec §Edge Cases "Modo MCP"] {auto}

## Regressao / Blast Radius

- [x] CHK018 - Decisoes de classe `operacional` (a maioria do trafego hoje) MUST manter comportamento identico — nenhuma trava nova se aplica a elas? [Regression, Spec §FR-005] {auto}
- [x] CHK019 - Decisoes legadas sem classe continuam legiveis sem exigir migracao (evita quebrar auditoria retroativa)? [Regression, Spec §FR-013] {auto}
- [x] CHK020 - SC-006 garante que o numero de bloqueios humanos para decisoes operacionais nao aumenta (a feature nao pode virar fricção difusa fora do escopo estrutural)? [Regression, Spec §SC-006] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`)
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
- CHK007 e CHK015 sao gaps de dominio de seguranca genuinos: nenhuma fonte no
  corpus atual (spec/plan/contracts) resolve saneamento de texto de item ou
  colisao de chave — nao ha evidencia de que tenham sido considerados.
