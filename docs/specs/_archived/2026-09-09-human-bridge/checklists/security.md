# Security Checklist: Human Bridge (Intervencoes)

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca desta feature —
nao repetir o gate `owasp-security` (que ja rodou sobre `plan.md` e achou 6
itens, todos resolvidos ou corrigidos). Aqui o alvo e: os requisitos e o
desenho ja fechado estao especificados com precisao suficiente para serem
verificados de forma inequivoca na implementacao?
**Created**: 2026-08-29
**Feature**: [`../spec.md`](../spec.md) · [`../plan.md`](../plan.md) ·
[`../contracts/panel-bridge-api.md`](../contracts/panel-bridge-api.md) ·
[`../contracts/mcp-tool-ask-operator.md`](../contracts/mcp-tool-ask-operator.md)

## Superficie de Escrita e Confinamento

- [x] CHK001 - O confinamento de escrita a `bridge.db` (conexao separada, nunca o corpus `knowledge.db`) esta declarado como MUST testavel, nao so como intencao de design? [Completude, Spec FR-017/FR-018; Plan §Constitution Check Principio I do painel] {auto}
- [x] CHK002 - A ausencia de autenticacao nas rotas `/api/v1/bridge/*` esta explicitamente aceita como limite herdado do painel (nao um gap desta feature), com o texto deixando claro que amplia-la exigiria mudanca de escopo do painel inteiro? [Consistencia, Plan §Complexity Tracking; contract §10] {auto}
- [x] CHK003 - Existe um MUST impedindo que o escopo CORS de `/bridge/*` seja alcancado alargando a lista GLOBAL de metodos (isolando o aumento de risco so na superficie nova)? [Consistencia, contract §11.1] {auto}
- [x] CHK004 - O requisito de `origin` allowlist para `/bridge/*` esta formulado como controle de seguranca (MUST NOT `origin:true`/`'*'`/reflexao de header), nao como conveniencia de dev, dado que agora um POST bem-sucedido dirige a decisao de um agente autonomo? [Clareza, contract §11.2] {auto}
- [x] CHK005 - Existe defesa em profundidade contra CSRF (rejeicao `415` de Content-Type != `application/json`) descrita como MUST, cobrindo o cenario em que um parser de corpo futuro reabriria o vetor em silencio? [Cobertura, contract §11.2] {auto}

## Roteamento por Capacidade (session_id)

- [x] CHK006 - Existe um requisito explicito impedindo que `session_id` (token de capacidade) atravesse o payload HTTP, headers, ou qualquer campo exposto pela Ponte — e o mecanismo pelo qual isso e garantido POR CONSTRUCAO (roteamento dentro da chamada MCP, painel como caixa-postal por `questionId`) esta descrito, nao so afirmado? [Seguranca critica, contract §1 item 4; data-model.md §"Achado de seguranca"] {auto}
- [x] CHK007 - SC-005 (0% de respostas aplicadas a sessao errada) e tratado como invariante estrutural do desenho (decorrencia do roteamento acima), nao como meta a validar so por teste de carga? [Mensurabilidade, Plan §"Os tres achados que mudaram o desenho" item 2] {auto}

## Texto Livre e Conteudo UNTRUSTED

- [x] CHK008 - As tres defesas de texto livre (teto de tamanho, filtragem best-effort, tratamento como dado nunca instrucao) estao especificadas com precisao suficiente para verificacao independente (ordem exata das operacoes, unidade do teto)? [Mensurabilidade, Spec FR-006/FR-007/FR-008; contract §7 linha `text`: "strip de controle -> scrub (UMA vez) -> truncamento a 2048 bytes UTF-8, nesta ordem"] {auto}
- [x] CHK009 - A limitacao conhecida da filtragem best-effort (FR-008: "lacunas conhecidas", "nao substitui a responsabilidade do operador") esta redigida como caracteristica aceita do requisito, evitando que uma revisao futura a trate como bug a corrigir silenciosamente? [Clareza, Spec FR-008] {auto}
- [x] CHK010 - A assimetria original entre `question`/`options[]` (sem scrub) e `untrusted_text` (com scrub) foi fechada com um MUST aplicando o MESMO pipeline de entrada aos tres campos, e nao apenas remendada caso a caso? [Consistencia, contract §11.3] {auto}
- [x] CHK011 - O rotulo estrutural que impede texto livre de virar instrucao (R-TEXT-4/FR-006) esta descrito como propriedade do CAMPO (campo proprio no envelope, nunca concatenado em prompt/commit/PR), nao apenas como recomendacao de uso? [Clareza, Spec FR-006; contract §7 "text nunca vira instrucao"] {auto}
- [x] CHK012 - A mitigacao de enquadramento hostil da pergunta (ASI09 — agente sob injecao indireta perguntando algo enganoso) esta especificada como requisito de apresentacao obrigatorio (procedencia + defaultValue visiveis junto de cada pergunta), nao deixada implicita? [Cobertura, contract §11.7; Spec FR-014] {auto}

## Politica de Autonomia (timeout / default value)

- [x] CHK013 - O piso `ASK_MIN_TIMEOUT_MS` (janela minima antes de um agente poder aplicar o proprio default) esta justificado como constante PROPRIA, com a coincidencia numerica com a folga da R-CLOCK-2 explicitamente desqualificada como fonte de derivacao (para nao acoplar por engano num ajuste futuro)? [Clareza, Plan §"Resolucao de F1" — "Acoplar os dois por coincidencia numerica seria pior que ter duas constantes"; contract R-CLOCK-7] {auto}
- [x] CHK014 - O requisito de auditoria da janela efetiva (persistir `effective_timeout_ms`, gerar finding no `review-task` para `outcome=timeout` com janela `< 60000` ms) e mensuravel o bastante para ser verificado mecanicamente, sem julgamento humano? [Mensurabilidade, Plan §"Resolucao de F1" item 2; contract R-AUDIT-1] {auto}
- [x] CHK015 - Existe um MUST NOT explicito impedindo o painel de re-derivar, re-clampar ou "corrigir" `timeoutMs` recebido — preservando a politica de relogio como responsabilidade exclusiva do servidor MCP? [Consistencia, contract §4 "O painel MUST NOT re-derivar..."] {auto}

## Armazenamento e Transporte

- [x] CHK016 - As permissoes de arquivo do `bridge.db` (diretorio `700`, arquivo `600`, best-effort) estao especificadas seguindo o MESMO precedente ja usado para o corpus, evitando um segundo padrao de permissao no mesmo processo? [Consistencia, contract §11.4] {auto}
- [x] CHK017 - Existe um MUST NOT explicito para transporte nao-loopback sem opt-in (recusa de host != `127.0.0.1`/`::1`/`localhost` a menos que uma segunda variavel de ambiente seja setada), cobrindo o caso de erro de configuracao (typo/copy-paste de outro ambiente)? [Cobertura, contract §11.5] {auto}
- [x] CHK018 - O formato de `:questionId` na URL esta especificado com um charset/tamanho concreto (nao apenas "sera validado"), fechando tanto a superficie de SQL quanto a de roteamento HTTP? [Mensurabilidade, contract §11.6] {auto}

## Idempotencia e Concorrencia

- [x] CHK019 - O requisito de idempotencia de resposta (FR-016/SC-006) esta especificado como invariante de banco (condicao atomica `resolution IS NULL AND expires_at > ?`), em vez de depender de uma checagem `SELECT`-then-`UPDATE` com janela de corrida? [Mensurabilidade, Spec FR-016; contract §7 "FR-016/SC-006 — idempotencia por invariante de banco"] {auto}
- [x] CHK020 - O Edge Case de duas respostas concorrentes tem um desfecho deterministico e unico (primeira vence, segunda recebe aviso) sem depender de ordenacao de rede ou timing de aplicacao? [Cobertura, Spec Edge Cases; contract §7] {auto}

## Escopo Aceito e Nao Coberto

- [ ] CHK021 - O crescimento ilimitado de `bridge.db` ao longo do tempo (FR-020, sem expurgo na v1) e um caracteristica operacional aceitavel a longo prazo para o volume esperado do operador, ou um follow-up de purge deveria ser pre-comprometido antes do lancamento? [Risco de produto] {humano}
- [ ] CHK022 - O limite de confianca herdado (sem auth, sem rate-limit, confianca total em qualquer processo local que alcance a porta) permanece aceitavel agora que a superficie ganhou o PRIMEIRO endpoint capaz de dirigir a decisao de um agente autonomo, ou isso justifica reabrir a discussao de autenticacao do painel como um todo (fora do escopo desta feature)? [Risco de produto, Plan §"Mudanca de postura que a feature introduz"] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao); nenhum
  `[Gap]`/`[Ambiguity]`/`[Conflict]` foi encontrado neste dominio — o gate
  `owasp-security` ja rodou sobre o `plan.md` e os 6 achados (F1-F6) foram
  todos corrigidos no proprio contrato ou escalados e resolvidos (F1 via
  `block-005`/`dec-031`).
- CHK021/CHK022 sao decisoes de apetite de risco do dono do produto, nao
  lacunas de especificacao — a spec/plan ja documentam a postura atual com
  precisao; a pergunta e se ela CONTINUA sendo a postura desejada.
