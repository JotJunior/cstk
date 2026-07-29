# Research: validate-docs-sdd-profile

Documento produzido no Phase 0 do `/plan`. Resolve as decisoes tecnicas em
aberto ANTES do design. A spec ja passou por `/clarify` (FR-013 resolvido,
zero `[NEEDS CLARIFICATION]` residuais), portanto nao ha unknowns herdados da
spec — as decisoes abaixo sao escolhas de implementacao que a propria spec
deixou explicitamente para o `/plan` (secao Out of Scope: "Escolha de
implementacao … decisao de /plan" e "Nomeacao exata de flags … decisao de
/plan").

## Decision 1: Motor deterministico via NOVO script POSIX (nao prosa-apenas)

**Decision**: Implementar os dois perfis como um NOVO script POSIX sh
`global/skills/validate-documentation/scripts/validate-sdd.sh` (a skill
`validate-documentation` hoje NAO possui diretorio `scripts/` — foi
verificado por leitura direta: `global/skills/validate-documentation/`
contem apenas `evals/` e `SKILL.md`), com a prosa do `SKILL.md` documentando
o acionamento, os perfis e os gotchas. Os perfis UC e `--runbook` existentes
permanecem prosa-apenas e INALTERADOS (spec, Out of Scope).

**Rationale**:
1. **Determinismo e testabilidade** — os checks desta feature (secoes
   obrigatorias presentes, contagem de `[NEEDS CLARIFICATION]`, IDs
   duplicados, referencia `FR-`/`SC-` inexistente na spec) sao
   estruturalmente decidiveis; um script produz o MESMO veredito toda vez,
   ao contrario de um checklist guiado por prosa que depende do LLM
   "lembrar" de cada criterio.
2. **Convencao ja imposta pelo projeto** — o `CLAUDE.md` (secao "Como testar
   scripts shell") e `tests/README.md` estabelecem: todo `.sh` novo em
   `global/skills/*/scripts/` EXIGE `tests/test_<nome>.sh`, e
   `./tests/run.sh --check-coverage` falha (exit 1) na ausencia. Um motor
   deterministico entra nessa malha de cobertura; prosa nao.
3. **Precedente direto** — `global/skills/create-tasks/scripts/validate-tasks-template.sh`
   e `global/skills/validate-docs-rendered/scripts/validate.sh` sao skills
   que combinam script POSIX determinista + `SKILL.md` em prosa; o padrao
   ja existe no toolkit e este perfil o segue.
4. **Reuso pelos orquestradores como gate** — `agente-00c`/`feature-00c`
   podem invocar o script diretamente como gate pos-artefato (hoje aplicam
   os criterios ad-hoc com grep — gap confirmado pelo read-back loop:
   sugestao de `cstk/enforced-guards` registrada na knowledge.db aponta
   exatamente "validate-documentation nao tem perfil dedicado para
   artefatos de /plan").

**Alternatives considered**:
- **Prosa-apenas (como UC/`--runbook` fazem hoje)** — rejeitado: sem
  cobertura de teste (`--check-coverage` nao alcanca prosa), sem
  determinismo, e mantem os orquestradores presos ao grep ad-hoc que a
  feature existe para eliminar (SC-006).
- **Estender o `validate.sh` de `validate-docs-rendered`** — rejeitado:
  violaria a fronteira de responsabilidade (FR-018); aquele script e o dono
  da validacao de RENDERIZACAO, nao de qualidade estrutural de artefato SDD.

**Nota de conformidade com o Principio III (skill = prosa + progressive
disclosure)**: o script e o MOTOR; o `SKILL.md` continua sendo a interface
em prosa (quando usar, gotchas, exemplos). Isso e exatamente o arranjo de
`create-tasks` e `validate-docs-rendered` — nao ha conflito com o Principio
III.

## Decision 2: Acionamento = deteccao automatica por path + flags explicitas

**Decision**: Suportar AMBOS os mecanismos, espelhando o que a skill ja faz
para os perfis existentes:
- **Deteccao automatica por convencao de path** (FR-015):
  - `docs/specs/<feature>/spec.md` → spec-profile;
  - `docs/specs/<feature>/plan.md`, `.../research.md`, `.../data-model.md`,
    `.../quickstart.md`, `.../contracts/*.md` → plan-profile.
- **Selecao explicita por flag** (FR-014): `--sdd-spec` e `--sdd-plan`,
  aditivas as flags/perfis ja existentes (`--runbook`, perfil UC default).
- **Perfil indeterminado** (FR-016): quando o path nao casa nenhuma
  convencao reconhecida (nem UC `UC-*.md`, nem runbook `RB-\d{3}-*.md`, nem
  spec-profile, nem plan-profile) e nenhuma flag foi passada, reportar erro
  claro "perfil nao determinado" e sair — NUNCA aplicar o perfil UC default
  silenciosamente aos artefatos desta feature.

**Rationale**: e o padrao ESTABELECIDO da propria skill — o perfil UC casa
por glob `UC-*.md`, o `--runbook` casa por filename `RB-\d{3}-*.md` OU pela
flag `--runbook` (verificado no `SKILL.md`, secao "Perfil `--runbook`").
Duplicar esse mecanismo dual (auto por path + flag explicita) mantem
consistencia e satisfaz FR-014 (explicito), FR-015 (auto) e FR-016
(fail-safe) sem inventar convencao nova.

**Alternatives considered**:
- **Somente flag explicita** — rejeitado: falha FR-015 (auto-deteccao) e
  reintroduz atrito de adocao (US3).
- **Somente auto-deteccao por path** — rejeitado: falha FR-014 (override
  explicito) e nao resolve validar um artefato fora da convencao de
  diretorio.
- **Estender o default implicito do perfil UC para spec/plan** — rejeitado
  explicitamente pela spec (US3 Acceptance Scenario 3): aplicar perfil por
  engano e pior que pedir desambiguacao.

## Decision 3: Reuso da taxonomia de severidade + semantica dos exit codes

**Decision**: Reutilizar a taxonomia de severidade JA existente na skill —
**Erro** (bloqueia aprovacao) / **Aviso** (recomenda correcao) / **Info**
(sugestao opcional) — sem introduzir taxonomia divergente (FR-017). No
contrato do script (ver `contracts/validate-sdd-cli.md`):
- stdout: uma linha por achado `FINDING|<severity>|<code>|<msg>` com
  `severity ∈ {error, warning, info}` (mapeando 1:1 para Erro/Aviso/Info) +
  uma linha final `RESULT|<file>|profile=<p>|errors=<N>|warnings=<M>`.
- **exit codes**: `0` = zero achados de severidade `error` (avisos/infos
  podem existir e NAO bloqueiam); `1` = >=1 achado `error`; `2` = uso
  incorreto / arquivo inexistente / perfil indeterminado (FR-016).

**Rationale**: alinhar o exit code a SEMANTICA da severidade da skill — so
**Erro** bloqueia aprovacao, logo so **Erro** deve produzir exit != 0 de
"reprovado". Isso segue a convencao do `validate.sh` de `validate-docs-rendered`
("exit 0 se zero ERROs, 1 se houver ERROs"), e NAO a do
`validate-tasks-template.sh` (que sai 1 em QUALQUER finding, inclusive
warning). A divergencia e deliberada: a taxonomia canonica de
`validate-documentation` distingue Aviso de Erro (Aviso "recomenda", nao
"bloqueia"), enquanto o modelo critical/warning de `validate-tasks-template`
trata ambos como reprovacao. Adotar o exit-por-Erro preserva FR-017.

**Alternatives considered**:
- **exit 1 em qualquer finding (estilo `validate-tasks-template.sh`)** —
  rejeitado: conflitaria Aviso com Erro e violaria a semantica "Aviso nao
  bloqueia" do modelo de severidade que FR-017 manda preservar.

## Decision 4: Fronteira de responsabilidade documentada (nao-duplicacao)

**Decision**: Materializar SC-005 como um **checklist de fronteira**
documentado (neste plano, secao Project Structure/§Fronteira, e reproduzido
no `SKILL.md` na implementacao) declarando, por categoria de check, qual das
tres skills e a dona:

| Categoria de check | Dono | spec/plan-profile faz? |
|--------------------|------|------------------------|
| Secoes obrigatorias presentes num UNICO artefato | validate-documentation (novos perfis) | SIM (FR-001, FR-008) |
| Anti-padroes de conteudo da spec (impl. vazando, SC nao-mensuravel, `[NEEDS CLARIFICATION]` > 3, stories acopladas, adjetivos vagos, N/A residual) | validate-documentation (spec-profile) | SIM (FR-002..FR-007) |
| Placeholder de template residual / rotulo real-vs-proposto / `[NEEDS CLARIFICATION]` residual no plan | validate-documentation (plan-profile) | SIM (FR-009, FR-010, FR-011) |
| ID `FR-`/`SC-` citado em plan.md EXISTE na spec.md (checagem SEMANTICA) | validate-documentation (plan-profile) | SIM (FR-012) |
| Link/anchor entre arquivos RESOLVE no disco (arquivo existe, header casa) | validate-docs-rendered (§2.2) | NAO (FR-013, FR-018) |
| Sintaxe Mermaid, frontmatter YAML, code-block sem linguagem | validate-docs-rendered | NAO (FR-018) |
| Cobertura cross-artifact (tasks vs requisitos, duplicacao, gaps, drift de terminologia, alinhamento com constitution) | analyze | NAO (FR-018) |
| Drift de case-convention entre camadas (snake vs camel) | analyze (Pass G) | NAO (Out of Scope) |

**Rationale**: SC-005 exige "checklist documentado de fronteira de
responsabilidade entre as tres skills". A linha divisoria mais sutil
(referencia cruzada de IDs) foi resolvida na fase clarify (dec-004,
2026-07-10): o plan-profile faz apenas a checagem SEMANTICA (o ID existe na
spec?), NUNCA a resolucao de path/anchor no disco — essa fica 100% com
`validate-docs-rendered` §2.2, verificado por leitura real daquele
`SKILL.md`.

**Alternatives considered**:
- **Deixar a fronteira implicita na prosa dos FRs** — rejeitado: SC-005
  pede um artefato de fronteira explicito e verificavel; prosa dispersa nao
  e auditavel como checklist.

## Decision 5: Estrategia de fixtures e cobertura de teste

**Decision**: O teste `tests/test_validate-sdd.sh` (nome derivado da
convencao `global/skills/<X>/scripts/<n>.sh` → `tests/test_<n>.sh`) usa como
fixture "boa" os artefatos REAIS ja versionados em
`docs/specs/enforced-guards/` — verificado por leitura direta que
`spec.md` contem as 3 secoes obrigatorias (`User Scenarios & Testing`,
`Requirements`, `Success Criteria`) e `plan.md` as 4 (`Summary`,
`Technical Context`, `Constitution Check`, `Project Structure`) — e como
fixtures "ruins" copias deliberadamente quebradas (heredoc ou arquivos sob
`tests/fixtures/`), uma quebra por cenario (secao removida, stack-term
injetado em SC, 4o `[NEEDS CLARIFICATION]`, ID duplicado, placeholder
`[FEATURE]` residual, citacao `FR-099` inexistente, entrada de contrato sem
rotulo real-vs-proposto).

**Rationale**: satisfaz a "Regra de ouro" do `CLAUDE.md` (todo `.sh` novo
tem `test_<nome>.sh`, gateada por `--check-coverage`), reusa artefatos reais
como oraculo de verdade-positiva (0 erros) e isola cada verdade-negativa num
unico defeito para assercao precisa da severidade (SC-001..SC-004).

**Alternatives considered**:
- **Somente fixtures inline (heredoc), sem apontar para artefato real** —
  aceitavel para os casos "ruins", mas para o caso "bom" o artefato real de
  `enforced-guards` da maior confianca de que o perfil nao produz
  falso-positivo contra um artefato de producao. Usar ambos.

## Decision 6: Deteccao heuristica de conteudo — limites e severidade

**Decision**: Os checks de CONTEUDO derivados dos anti-padroes catalogados
em `specify/examples/spec-bad.md` (impl. vazando FR-002, SC nao-mensuravel
FR-003, adjetivos vagos FR-006, stories acopladas FR-007) sao heuristicos
(lista de termos de stack + ausencia de padrao numerico de metrica). Os
puramente estruturais e de baixo risco de falso-positivo sao **Erro**
(FR-002, FR-003, FR-004); os semanticos com risco de falso-positivo sao
**Aviso** (FR-005, FR-006, FR-007, ja assim classificados na spec). A lista
concreta de termos de stack e o conjunto de regex de metrica sao detalhe de
implementacao (marcado `[PROPOSTA — a validar na implementacao]` no
contrato), a ser afinado contra os 6 exemplos de `spec-bad.md` ate atingir
SC-002 (100% dos 6 anti-padroes estruturalmente detectaveis).

**Rationale**: casa exatamente a classificacao de severidade que a spec ja
fixou (FR-002/003/004 = erro; FR-005/006/007 = aviso), e reconhece
honestamente que deteccao semantica tem limite — por isso story-coupling
(FR-007) e aviso, nao erro. A calibragem da wordlist contra `spec-bad.md`
evita afirmar cobertura que ainda nao foi medida (SC-002 e verificado no
teste, nao presumido).

**Alternatives considered**:
- **Tornar todos os checks de conteudo Erro** — rejeitado: falso-positivo
  em check semantico (ex.: "robusto" num contexto legitimo) bloquearia
  aprovacao indevidamente; a spec ja separa erro de aviso justamente por
  isso.
