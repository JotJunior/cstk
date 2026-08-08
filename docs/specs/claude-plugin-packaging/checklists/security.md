# Security Checklist: Empacotamento do cstk como Plugin do Claude Code

**Purpose**: Gate de qualidade de requisitos de seguranca — feature de distribuicao/supply-chain (nao aplicacao web), adaptado do dominio generico `security` (autenticacao/PII/compliance) para o eixo real de risco: integridade de artefato, origem confiavel, transporte, consentimento, dedup de guardas e zero coleta remota.
**Created**: 2026-08-08
**Feature**: [spec.md](../spec.md)

## Verificacao de Integridade

- [x] CHK001 - Ha requisito de verificacao de integridade para AMBOS os caminhos de distribuicao (classico e plugin), nao so para o classico? [Cobertura, Spec §FR-008] {auto} — FR-008 exige checagem de alinhamento (`hash_dir`) entre os dois; o mecanismo de integridade de cada caminho individualmente (sha256 fail-closed vs pin `gitCommitSha`) esta descrito no plan (tabela §"Modelo de integridade por caminho"), nao repetido na spec — ver CHK002.
- [ ] CHK002 - O mecanismo de verificacao de integridade de CADA caminho (sha256 fail-closed do classico vs pin `gitCommitSha` do plugin) esta documentado na propria spec, ou so no plan? [Clareza, Gap] {auto} — **[Gap]**: a spec (FR-008, Delta FR-017) descreve o CRITERIO de alinhamento entre os dois (checksum), mas nao a mecanica de integridade interna de cada caminho — essa informacao vive so em plan.md (linhas 169-176, achado F1 do gate owasp). Consequencia direta do mesmo Gap ja registrado em `checklists/requirements.md` CHK006: a Delta FR-017 precisa da reescrita sugerida pelo plan para a spec deixar de descrever equivalencia e passar a descrever o mecanismo real.
- [x] CHK003 - O comportamento fail-closed (recusar artefato sem `.sha256`, sem bypass silencioso) do caminho classico permanece o padrao apos a introducao do plugin, sem regressao? [Consistencia, Spec §FR-011] {auto} — nenhum FR desta feature altera `serve-integrity`/`bash-guard-enforcement` no caminho classico; FR-004 (Delta, MODIFIED) so ADICIONA o caminho plugin como segunda forma de provisionamento, preservando o existente (`e uma segunda forma OFICIAL... FR-015/FR-016 desta capability permanecem intactas`, spec.md linha 398-401).

## Origem Confiavel

- [x] CHK004 - A allowlist de hosts confiaveis (`CSTK_TRUSTED_RELEASE_HOSTS`) do caminho classico e preservada, nao substituida ou enfraquecida pela introducao do plugin? [Consistencia, Spec §FR-006, FR-011] {auto} — FR-006 mantem o binario cstk (e seu fluxo `install.sh`/`self-update`) inalterado pelo plugin; nenhum FR desta feature toca `trusted-hosts.sh`.
- [x] CHK005 - O requisito "nenhum servico de terceiros operado pelo autor" (FR-011) e objetivamente verificavel (marketplace hospedado no proprio repo git, sem endpoint proprietario)? [Mensurabilidade, Spec §FR-011, FR-003] {auto} — FR-003 exige explicitamente que a listagem de marketplace seja "hospedada no proprio repositorio git do toolkit"; FR-011 reforca "MUST continuar operando exclusivamente a partir do proprio repositorio". Verificavel por inspecao do `source` no `marketplace.json`.

## Transporte

- [ ] CHK006 - Ha requisito explicito de transporte seguro (HTTPS) para o download do conteudo do catalogo pelo caminho plugin? [Completude, Gap] {auto} — **[Gap]**: a tabela do plan (linha 173) registra "HTTPS do provedor git" como a garantia de transporte do caminho plugin, mas isso e um fato observado sobre o MECANISMO DO HARNESS (fora do controle do toolkit), nao um requisito MUST redigido na spec. Diferente do caminho classico, onde FR-011/constitution ja amarram `http://` rejeitado como politica do PROPRIO toolkit (`trusted-hosts.sh`). Aceitavel como Gap de baixo risco (o toolkit nao pode impor politica de transporte sobre um mecanismo que nao controla), mas vale registrar para nao ser lido como omissao silenciosa.

## Consentimento

- [x] CHK007 - O requisito de consentimento no caminho plugin (trust dialog / tela "Will install") e tratado como assumption a validar, sem afirmar timing exato como fato? [Clareza, Constitution VI, Spec §Clarifications A1/A2] {auto} — spec.md linhas 34-45 e FR-004 marcam explicitamente `[ASSUMPTION a validar empiricamente]` para o timing e a ausencia/presenca de gate extra de hooks; nenhuma afirmacao de fato nao verificada (Principio VI respeitado).

## Dedup / Duplicacao de Guarda

- [x] CHK008 - FR-005 define de forma inequivoca qual caminho vence quando ambos coexistem (plugin vence), sem ambiguidade de precedencia? [Clareza, Spec §FR-005] {auto} — "dedup em tempo de instalacao, plugin vence" e a redacao literal tanto em FR-005 quanto no Edge Case correspondente (linhas 255-266, 190-198).
- [x] CHK009 - O requisito cobre tanto DETECCAO quanto REMEDIACAO da duplicacao (nao so deteccao muda)? [Completude, Spec §FR-005] {auto} — FR-005: "`cstk doctor` MUST reportar a duplicacao... com remediacao acionavel" — deteccao + remediacao explicitas, nao so alerta passivo.
- [x] CHK010 - O gate owasp do plan (F3: shadowing por precedencia de `CLAUDE_PLUGIN_ROOT`) foi corrigido no desenho antes de virar task, ou ficou pendente sem decisao registrada? [Traceability, dec-027] {auto} — dec-027 (plan, score 2) registra a correcao aplicada: "`resolve_runtime_root` ganha Ordem B (sibling antes de `CLAUDE_PLUGIN_ROOT`) para o consumidor fail-closed" — corrigido no proprio desenho, nao adiado.
- [x] CHK011 - O gate owasp do plan (F4: plugin habilitado mas nao-funcional deixaria o projeto sem guarda silenciosamente) foi corrigido no desenho? [Traceability, dec-027] {auto} — dec-027: "skip do provisionamento classico passa a exigir 3a condicao (`hooks.json` presente no `installPath`)" — fecha o cenario de "plugin declarado habilitado mas hooks de fato ausentes" antes de desligar o caminho classico.

## Falha Diagnostica (Nunca Silenciosa)

- [x] CHK012 - FR-012 (falha diagnostica quando script de runtime nao resolve localizacao) cobre TODOS os scripts afetados pela relocacao, ou so um subconjunto? [Completude, Spec §FR-012] {auto} — FR-012 e redigido em termos gerais ("um script de runtime", sem lista fechada), aplicando-se por construcao a qualquer um dos scripts tocados por `_resolve-root.sh` (plan.md linha 153: "adocao nos 6 arquivos").
- [x] CHK013 - A tensao entre "falha diagnostica sempre" (FR-012) e a politica fail-OPEN documentada dos hooks de metrica (`posttooluse-tool-call-tick.sh`, `posttooluse-loose-usage.sh`) esta resolvida com decisao auditavel, sem contradizer FR-012? [Consistencia, dec-024] {auto} — dec-024 (score 3, evidencia citada do cabecalho do proprio hook) resolve a tensao: FR-012 e satisfeito pelo canal de diagnostico (sidecar) mantendo `exit 0`; hooks de guarda (`bash-guard`) permanecem fail-closed — polaridades distintas por desenho, nao um requisito violado.

## Secrets, Credenciais e Zero Coleta Remota

- [x] CHK014 - Nenhum FR desta feature introduz necessidade de armazenar credencial/secret novo para o caminho plugin funcionar? [Completude] {auto} — nenhum dos 13 FRs menciona autenticacao, API key ou token; a distribuicao via plugin usa o proprio mecanismo publico do harness (marketplace em repo git publico), sem segredo novo.
- [x] CHK015 - FR-011 (zero coleta remota) e redigido de forma absoluta (MUST NOT), sem excecao condicional que abra brecha? [Clareza, Spec §FR-011] {auto} — "MUST NOT introduzir nenhum endpoint de telemetria, analytics ou coleta remota administrado pelo autor do toolkit" — sem clausula de excecao.
- [x] CHK016 - A decisao de manter `posttooluse-loose-usage.sh` (captura de consumo, hoje opt-in) FORA do `hooks.json` do plugin esta registrada com justificativa, para nao virar opt-in default so por habilitar o plugin? [Consistencia, Constitution IV, research.md D2] {auto} — research.md linhas 128-137 documenta a decisao com o motivo explicito ("registrar loose-usage junto — rejeitado: muda default de privacidade"); plan.md linha 214-216 reconfirma no Re-check pos-Phase 1: "fortalece o Principio IV... sem ela, habilitar o plugin ligaria captura de consumo por default".

## Threat Modeling

- [x] CHK017 - O gate `owasp-security` foi executado sobre o plano tecnico (nao so sobre a spec em linguagem natural)? [Traceability, dec-026] {auto} — dec-026 (plan, score 3) registra a execucao do gate sobre o desenho completo (`plan.md` + contratos), nao apenas sobre `spec.md`.
- [x] CHK018 - Todos os achados do gate (F1/F3/F4 MEDIUM, 2 LOW) tiveram disposicao auditavel (corrigido, aceito com justificativa, ou escalado), nenhum ficou sem decisao registrada? [Traceability, dec-026, dec-027] {auto} — F3 e F4 corrigidos no desenho (dec-027); F1 registrado como MEDIUM aceito com plano de correcao textual na spec (nao aplicado por `plan` por desenho — vira Gap CHK006/CHK002, com destino explicito em `create-tasks`); os 2 LOW nao tem correcao dedicada registrada nesta onda — ver CHK019.
- [ ] CHK019 - Os 2 achados LOW do gate owasp (mencionados em dec-026 mas nao detalhados por decisao propria) tem descricao rastreavel em algum artefato do plan, ou ficaram so no numero agregado "2 LOW"? [Traceability, Gap] {auto} — **[Gap]**: dec-026 registra a contagem "0 CRITICAL, 0 HIGH, 3 MEDIUM... 2 LOW" e cita evidencia so para os MEDIUM (F1/F3/F4); os 2 LOW nao aparecem nomeados em plan.md nem em decisao dedicada — nao ha como auditar OS QUE SAO sem re-rodar o gate ou consultar log bruto da skill. Risco baixo (LOW por definicao), mas quebra a cadeia de auditoria completa exigida pelo Principio I (auditabilidade total).

## Compliance

- [x] CHK020 - Ha algum requisito de compliance (LGPD/GDPR/PCI/HIPAA) aplicavel a esta feature? [Compliance] {auto} — Nao aplicavel: a feature nao processa dado pessoal, financeiro ou de saude; e puramente empacotamento/distribuicao de codigo publico do proprio toolkit. Nenhum FR toca dado de usuario final. Confirmado por ausencia de qualquer mencao a PII/dado sensivel em spec.md e pela nota explicita em spec.md linha 314-318 ("Decisoes de infraestrutura: N/A").

## Notas

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]` quando a evidencia mostra ausencia real).
- Nenhum item `{humano}` foi necessario neste dominio: as perguntas de seguranca aqui sao verificaveis contra spec.md/plan.md/research.md/decisions do state, sem depender de apetite de risco do dono do produto alem do que o gate owasp ja formalizou.
- **Gaps abertos (3)**: CHK002/CHK006 (mecanismo de integridade por caminho e transporte nao descritos na propria spec, so no plan — mesma raiz do CHK006 de `requirements.md`, resolve-se junto com a reescrita da Delta FR-017), CHK019 (2 achados LOW do gate owasp sem descricao rastreavel individual).
- Este checklist NAO cobre autenticacao/autorizacao/PII (dominio generico `security.md` do catalogo) porque a feature nao tem superficie desse tipo — adaptado ao eixo real de risco (supply-chain/distribuicao), conforme instrucao da propria skill ("references/ sao ponto de partida — nao copiar sem adaptar ao contexto da feature").

## Proximos Passos

- `/create-tasks` — CHK002/CHK006 (integridade+transporte por caminho na spec) resolve-se junto com a task de reescrita da Delta FR-017 (mesmo gap de `requirements.md`); CHK019 (2 LOW sem descricao) vira task leve de auditoria: re-rodar `owasp-security` sobre o plan final e anexar os 2 achados nomeados a uma Decisao dedicada antes de `execute-task` fechar a fase de seguranca.
