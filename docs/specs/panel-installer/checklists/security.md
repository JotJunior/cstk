# Security Checklist: panel-installer

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca — completude, clareza,
mensurabilidade e cobertura de ameacas. Nao testa implementacao.
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)
**Dominios de ameaca**: OWASP Top 10:2025 (A03/A08), Agentic AI 2026 (ASI04/ASI05),
supply-chain, SSRF, command injection, execucao de codigo de terceiros.

---

## S.1 — Supply-chain e Integridade de Download

- [ ] CHK-S01 - O requisito de integridade best-effort (FR-008) especifica o comportamento
  exato quando `.sha256` ESTA presente (verificar + abort em mismatch) E quando ESTA
  AUSENTE (avisar + prosseguir)? Ambos os ramos sao verificaveis por teste automatizado?
  [Completude, Spec §FR-008]

- [ ] CHK-S02 - FR-008 define o texto ou categoria de aviso exibido ao operador quando
  a verificacao de integridade e indisponivel? ("aviso claro" e mensuravel — qual
  nivel: stderr, prefixo `[WARN]`, cor?) [Clareza, Spec §FR-008]

- [ ] CHK-S03 - A spec define quais hosts sao considerados confiavel para o `tarball_url`
  (allowlist GitHub)? O requisito especifica o comportamento ao receber um host fora da
  allowlist (ex: reject com exit 1 vs. aviso)? [Completude, Spec §FR-001, Gap S2 do
  plan.md]

- [ ] CHK-S04 - A spec menciona ou exige que o download seja realizado SOMENTE via HTTPS
  (nunca HTTP plano)? O requisito cobre o comportamento se a URL retornada pela API
  vier com schema `http://`? [Completude, Gap]

- [ ] CHK-S05 - A spec especifica onde e como a `tag_name` instalada e registrada (marker
  `.panel-version`) para permitir auditoria pelo operador? O formato deste marker e
  definido de forma mensuravel? [Clareza, Spec §FR-007, research.md D1]

- [ ] CHK-S06 - Os requisitos de supply-chain (FR-008, FR-010) documentam o TRUST MODEL
  explicitamente: em qual entidade o operador esta confiando ao executar `cstk serve`
  (repositorio `JotJunior/cstk-panel`, CDN GitHub, ou ambos)? [Clareza, Spec §FR-008,
  plan.md §S1/S3]

---

## S.2 — Execucao de Codigo de Terceiros (ASI05 / A03)

- [ ] CHK-S07 - A spec documenta o trust boundary de execucao de codigo de terceiros
  (`npm run start`)? O requisito indica claramente que o operador e responsavel por
  confiar no repositorio upstream? [Completude, Spec §FR-003, plan.md §S3]

- [ ] CHK-S08 - A spec ou contratos definem se `npm install` deve ser executado com
  `--ignore-scripts` (desabilitar lifecycle scripts) ou com scripts habilitados? A
  justificativa (painel precisa de build) esta em artefato de requisito, nao apenas
  no plan? [Completude, Gap — decisao esta so no plan.md §S3, nao na spec]

- [ ] CHK-S09 - FR-003 especifica o que acontece se `npm run start` falhar apos a
  instalacao? Exit code, mensagem e indicacao de como o operador pode diagnosticar
  estao definidos como requisito? [Completude, Spec §FR-003]

- [ ] CHK-S10 - A spec define se ha verificacao de que o diretorio instalado contem
  `package.json` com um `name` esperado (ex: `cstk-panel`) antes de executar `npm run
  start`? Ou o requisito aceita qualquer `package.json`? [Clareza, Spec §FR-002,
  Ambiguity]

---

## S.3 — SSRF e Injecao de URL (S2 do plan)

- [ ] CHK-S11 - A spec lista explicitamente os hosts externos permitidos para download
  (whitelist)? Se a lista esta no state.json mas nao na spec, o requisito e rastreavel
  para o operador sem acesso ao state? [Completude, Gap — whitelist esta no state.json,
  nao em FR-NNN]

- [ ] CHK-S12 - E definido como requisito que `tarball_url` extraida da resposta da API
  DEVE ser validada contra a host-allowlist ANTES de ser passada ao `curl`? O requisito
  especifica o comportamento de rejeicao (exit code, mensagem)? [Completude, Spec
  §FR-001, plan.md §S2 — atualmente descrito como "recomendacao", nao como FR]

- [ ] CHK-S13 - A spec define quais redirects HTTP sao permitidos pelo `curl -L`? Ha
  requisito que limite o numero de redirects ou exija que o destino final esteja na
  allowlist? [Completude, Gap]

---

## S.4 — Command Injection e Quoting (S5 do plan)

- [ ] CHK-S14 - FR-004 especifica que o valor de `--port` deve ser validado como inteiro
  no intervalo 1-65535 ANTES de ser exportado como `PORT=<valor>`? O requisito define
  exit code e mensagem de erro para valor invalido (indica exit 2 — e consistente com
  P3 AC)? [Clareza, Spec §FR-004, Spec §P3]

- [ ] CHK-S15 - A spec define explicitamente que ZERO uso de `eval` e permitido no
  helper `serve.sh`? Ou e apenas uma restricao de implementacao no plan sem correspondente
  em FR? [Completude, Gap — restricao esta so no plan.md §S5]

- [ ] CHK-S16 - Ha requisito que proiba interpolar valores de flags do operador
  (`--port`, `--host`, `--reinstall`) no corpo de comandos shell (vs. argumentos
  posicionais entre aspas)? [Completude, Gap]

- [ ] CHK-S17 - O requisito FR-004 para `--host` especifica quais caracteres sao aceitos
  no valor (ex: apenas alfanumerico + ponto + dois-pontos)? Ou o host e repassado
  sem sanitizacao para o terminal (aviso apenas)? [Clareza, Spec §FR-004, Ambiguity]

---

## S.5 — Prerequisitos e Degradacao Graceful

- [ ] CHK-S18 - FR-006 define a mensagem de erro exata (ou o nivel de especificidade
  requerido) quando `curl` esta ausente? E quando `npm` esta ausente? "Mensagem clara
  pedindo instalacao" e mensuravel? [Clareza, Spec §FR-006]

- [ ] CHK-S19 - A spec define o comportamento se `curl` esta presente mas sem permissao
  de execucao, ou se esta em PATH mas e uma versao incompativel (ex: muito antiga, sem
  suporte a TLS 1.2)? [Cobertura de Edge Cases, Gap]

- [ ] CHK-S20 - FR-006 abrange `node` (runtime) alem de `npm`? Um ambiente com `npm`
  mas sem `node` executavel geraria erro compreensivel? [Cobertura de Edge Cases,
  Spec §FR-006, Ambiguity]

---

## S.6 — Isolamento e Zero Coleta Remota (Principio IV)

- [ ] CHK-S21 - FR-012 (zero coleta remota) e especifico o suficiente para ser testavel?
  O requisito define quais URLs SAO permitidas (allowlist positiva) alem de proibir
  coleta? [Clareza, Spec §FR-012]

- [ ] CHK-S22 - A spec define que o `cstk serve` NAO transmite a `tag_name` instalada,
  PATH do usuario, sistema operacional ou qualquer metadado do ambiente para endpoints
  externos durante a execucao normal (pos-instalacao)? [Completude, Spec §FR-012, Gap]

- [ ] CHK-S23 - Ha requisito que cubra o comportamento de `npm run start` em relacao a
  conexoes de rede que o PAINEL (nao o serve.sh) pode fazer? O trust boundary e claro:
  `cstk serve` controla apenas o processo, nao o comportamento de rede do Node.js?
  [Clareza, Spec §FR-003, Assumption]

---

## S.7 — Instalacao e Sistema de Arquivos

- [ ] CHK-S24 - FR-007 especifica as permissoes esperadas do diretorio de instalacao
  (`~/.local/share/cstk/panel/`)? E um requisito que o diretorio seja criado com permissoes
  restritivas (ex: `0700` ou `0755`)? [Completude, Gap]

- [ ] CHK-S25 - A spec define o comportamento de `--reinstall` se a remocao do diretorio
  existente falhar (ex: processo npm ainda rodando, permissao negada)? Exit code e
  mensagem estao especificados? [Completude, Spec §FR-005, Cobertura de Edge Cases]

- [ ] CHK-S26 - FR-007 define que a extracao do tarball ocorre em diretorio temporario
  privado antes do move atomico para o destino? Ou e apenas um detalhe de implementacao
  sem requisito correspondente? [Completude, Gap — atualmente so no research.md D2]

---

## Notes

- Marcar items concluidos com `[x]`
- Items numerados por CHK-S01..CHK-S26 para referencia cruzada com tasks
- Findings marcados `[Gap]` indicam requisitos ausentes na spec que precisam de FR dedicado
- Findings marcados `[Ambiguity]` indicam requisitos presentes mas insuficientemente precisos
- Items CHK-S03, CHK-S12, CHK-S15, CHK-S16 referem-se a items atualmente descritos como
  "recomendacoes" no plan.md mas sem FR correspondente na spec — candidatos a promover
  para FR antes de create-tasks
