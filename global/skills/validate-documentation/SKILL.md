---
name: validate-documentation
description: 'Validate a single existing document''s quality/completeness against structural standards. Triggers: "validar documentacao", "verificar UC", "audit docs". Skip for cross-artifact spec/plan/tasks consistency (use analyze).'
allowed-tools:
  - Read
  - Glob
  - Grep
---

# Skill: Validação de Documentação

Esta skill analisa e valida documentação existente contra padrões de qualidade.

## Quando Usar

Claude deve invocar esta skill automaticamente quando:
- Usuário pedir para validar/verificar documentação
- Usuário mencionar "review", "audit" ou "checar" documentos
- Antes de finalizar criação de documentação (auto-validação)
- Usuário pedir status de qualidade da documentação

## Critérios de Validação

### 1. Validação Estrutural (Documentos UC)

**Seções Obrigatórias:**
```
- [ ] Informações Gerais (tabela com ID, Nome, Domínio)
- [ ] Descrição (mínimo 2 parágrafos)
- [ ] Atores (tabela com tipo e descrição)
- [ ] Pré-condições (lista numerada)
- [ ] Pós-condições (sucesso e falha)
- [ ] Fluxo Principal (diagrama + tabela)
- [ ] Fluxos Alternativos (ao menos 1)
- [ ] Exceções (tabela com códigos)
- [ ] Regras de Negócio (tabela com IDs)
- [ ] Casos de Teste (tabela com cenários)
- [ ] Dependências (relacionamentos)
```

**Padrões de ID:**
```regex
UC-[A-Z]{2,4}-\d{3}     # UC-CAD-001, UC-AUTH-001
RN\d{2}                  # RN01, RN02
CT\d{2}                  # CT01, CT02
E\d{3}                   # E001, E002
FA\d                     # FA1, FA2
RNF\d{2}                 # RNF01, RNF02
```

### 2. Validação de Conteúdo

**Descrição:**
- Mínimo 100 caracteres
- Deve explicar O QUE e POR QUE

**Atores:**
- Pelo menos 1 ator primário
- Tipo deve ser: Primário, Secundário ou Sistema
- Descrição deve ser clara

**Fluxo Principal:**
- Diagrama Mermaid deve ser válido
- Passos devem ser numerados sequencialmente
- Cada passo deve ter descrição clara

**Regras de Negócio:**
- Cada regra deve ser acionável
- Regras complexas devem ter detalhamento

**Casos de Teste:**
- Mínimo 5 casos por UC
- Deve cobrir: sucesso, erro, edge cases
- Cada caso deve ter entrada e saída esperada

### 3. Validação de Consistência

**Cross-references:**
- Dependências devem referenciar UCs existentes
- Links internos devem ser válidos
- IDs não devem ser duplicados

**Nomenclatura:**
- Campos devem seguir padrão (camelCase ou UPPER_CASE)
- Nomes de atores consistentes entre documentos
- Terminologia uniforme

### 4. Validação de Diagramas Mermaid

**sequenceDiagram:**
```
- Participantes definidos
- Mensagens com setas corretas (->>, -->>)
- Alt/else para fluxos condicionais
- Loop para repetições
```

**flowchart:**
```
- Nós com IDs únicos
- Conexões válidas
- Decisões com múltiplas saídas
```

## Relatório de Validação

Formato do relatório gerado:

```markdown
# Relatório de Validação de Documentação

**Data:** YYYY-MM-DD
**Arquivos analisados:** N

## Resumo

| Status | Quantidade |
|--------|------------|
| OK     | X          |
| Aviso  | Y          |
| Erro   | Z          |

## Detalhes por Arquivo

### UC-XXX-NNN.md

**Status:** OK | Aviso | Erro

**Validações:**
- [x] Estrutura completa
- [x] Conteúdo adequado
- [ ] Consistência - Falta detalhar RN03
- [x] Diagramas válidos

**Ações recomendadas:**
1. Adicionar detalhamento para RN03
2. Incluir mais casos de teste de erro

---
```

## Níveis de Severidade

| Nível | Descrição | Ação |
|-------|-----------|------|
| **Erro** | Seção obrigatória ausente | Bloqueia aprovação |
| **Aviso** | Conteúdo insuficiente | Recomenda correção |
| **Info** | Sugestão de melhoria | Opcional |

## Processo de Validação

1. Identificar arquivos a validar (glob `UC-*.md`)
2. Para cada arquivo:
   - Verificar estrutura
   - Validar conteúdo
   - Checar consistência
   - Testar diagramas
3. Gerar relatório consolidado
4. Sugerir correções específicas

## Comandos de Validação

**Validar um arquivo:**
```
Valide o documento UC-CAD-001.md
```

**Validar todos os UCs:**
```
Valide toda a documentação de casos de uso
```

**Validar com auto-correção:**
```
Valide e corrija os problemas encontrados em UC-CAD-001.md
```

**Validar runbook (perfil --runbook):**
```
Valide o runbook RB-001-restore-drill.md com perfil --runbook
```

**Validar spec.md de uma feature SDD (perfil spec-profile):**
```
global/skills/validate-documentation/scripts/validate-sdd.sh docs/specs/minha-feature/spec.md
```

**Validar plan.md de uma feature SDD (perfil plan-profile, com referencia cruzada de IDs):**
```
global/skills/validate-documentation/scripts/validate-sdd.sh docs/specs/minha-feature/plan.md --spec docs/specs/minha-feature/spec.md
```

---

## Perfil `--runbook` (RB-NNN)

Runbooks operacionais (`docs/08-operacoes/RB-*.md`) tem padrao
estrutural diferente de UCs e exigem perfil dedicado. Acionar via
flag `--runbook` ou quando o filename casa `RB-\d{3}-*.md`.

### Frontmatter YAML obrigatorio

Todo runbook DEVE ter frontmatter YAML com pelo menos:

```yaml
---
title: "RB-001: Restore Drill PostgreSQL"
versao: 1.0
severidade: critica  # critica | alta | media | baixa
tempo-estimado: 45min
pre-requisitos:
  - acesso-ssh-droplet-prod
  - backup-recente-em-s3
---
```

Campos obrigatorios:
- `title` casa regex `^RB-\d{3}: .+`
- `versao` (semver ou inteiro)
- `severidade` (enum acima)
- `tempo-estimado` (string com unidade — `min`, `h`)
- `pre-requisitos` (array de strings)

### Secoes obrigatorias

Cada runbook DEVE ter (na ordem):

1. **Descricao** — 2-5 paragrafos explicando quando rodar
2. **Pre-requisitos** — checklist de itens necessarios
3. **Procedimento** — passos numerados com comandos literais
4. **Verificacao / Validacao** — como saber se o RB rodou OK
5. **Rollback** — passos reversos (OBRIGATORIO se `severidade=critica`)
6. **Contatos** — quem chamar em caso de problema

Ausencia de qualquer secao acima e Erro (nao Aviso). Para
`severidade=critica` sem secao Rollback, erro adicional CRITICO.

### Checks adicionais

- **Sem placeholders residuais**: rejeitar se conteudo contem
  `TODO:`/`TODO(`, `XXX`, `FIXME`, `<placeholder>`, `lorem ipsum`,
  `TBD`, `[FILL ME]`. Runbook e operacional — placeholder e divida
  tecnica que vira incidente. NOTA (corpus pt-br): exigir o marcador
  DELIMITADO — `TODO:` (dois-pontos) ou `TODO(` (estilo comentario de
  codigo) — e NAO o token solto `TODO`. Em prosa pt-br, "TODO/TODA" em
  enfase CAIXA-ALTA (ex: "para TODO comando") e legitimo e NAO deve
  disparar falso-positivo.
- **Cross-refs validos**: paths relativos em links Markdown
  (`[texto](../path)`) devem existir no disco. Reportar
  link quebrado como Erro.
- **Comandos sem variavel de ambiente nao-documentada**: se
  procedimento usa `$VAR`, `VAR` deve estar listado em
  Pre-requisitos OU em frontmatter `env-vars: [...]`. Caso
  contrario, Aviso (operador pode esquecer de exportar).

### Criterio de aceitacao

Novo `RB-NNN` e REJEITADO por `validate-documentation --runbook` se
faltar qualquer:
- Campo obrigatorio do frontmatter
- Secao obrigatoria
- Rollback (quando severidade=critica)
- Cross-ref valido em link interno

Razao para rigor extra: runbooks rodam em incidente, com operador
sob pressao. Placeholder = pessoa errada lendo o passo errado em
2h da manha.

---

## Perfil `spec-profile` (SDD)

Valida `spec.md` de uma feature SDD (`docs/specs/<feature>/spec.md`)
contra os criterios ja documentados na skill `specify`. Motor
deterministico: `global/skills/validate-documentation/scripts/validate-sdd.sh`
(POSIX sh, mesmo padrao de `create-tasks/scripts/validate-tasks-template.sh`
e `validate-docs-rendered/scripts/validate.sh`).

**Quando usar**: apos `specify` (ou apos `clarify`), antes de avancar para
`plan` — gate de qualidade da spec antes de investir em desenho tecnico.

**Acionamento**: flag `--sdd-spec` (forca o perfil, ignora deteccao por
path) OU deteccao automatica quando `FILE` casa a convencao
`docs/specs/<feature>/spec.md`.

### Catalogo de findings (spec-profile)

| code | severidade | Condicao |
|------|------------|----------|
| `missing-section` | Erro | Falta uma das 3 secoes obrigatorias (`User Scenarios & Testing`, `Requirements`, `Success Criteria`). |
| `impl-detail-in-spec` | Erro | Termo de stack/linguagem/framework/lib especifica no corpo da spec (ex.: `bcrypt`, `PostgreSQL`, `React`). |
| `sc-not-measurable` | Erro | Success Criterion sem metrica quantificavel OU com jargao tecnico (ex.: `API`, `TPS`, `paint time`). |
| `too-many-clarifications` | Erro | Mais de 3 marcadores `[NEEDS CLARIFICATION]` no total. |
| `duplicate-id` | Erro | ID `FR-`/`SC-` repetido no mesmo documento (reusa a convencao do Gotcha abaixo). |
| `na-placeholder-section` | Aviso | Secao deixada com placeholder `N/A` em vez de removida. |
| `vague-adjective` | Aviso | Adjetivo vago sem quantificacao em Requirements/Success Criteria (ex.: "MUST be fast", "deve ser robusto"). |
| `coupled-user-story` | Aviso | User story que depende de outra para ser testada isoladamente. |

Wordlists/regex de `impl-detail-in-spec`/`sc-not-measurable`/`vague-adjective`
sao calibradas contra os 6 anti-padroes de `specify/examples/spec-bad.md`
(deliberadamente restritas a termos concretos de stack — nao termos
genericos de dominio como "API"/"CLI"/"JSON" que aparecem legitimamente em
specs de ferramentas de dev, o que geraria falso-positivo).

## Perfil `plan-profile` (SDD)

Valida os artefatos de `/plan` de uma feature SDD — `plan.md`,
`research.md`, `data-model.md`, `quickstart.md`, `contracts/*.md` — contra
os criterios ja documentados na skill `plan`. Mesmo motor
`scripts/validate-sdd.sh`.

**Quando usar**: apos `plan`, antes de `checklist`/`create-tasks` — gate de
qualidade do desenho tecnico.

**Acionamento**: flag `--sdd-plan` OU deteccao automatica quando `FILE`
casa `docs/specs/<feature>/{plan,research,data-model,quickstart}.md` ou
`docs/specs/<feature>/contracts/*.md`.

**Flag `--spec SPEC_MD`**: caminho explicito da `spec.md` correspondente,
usado pelo check `dangling-fr-sc-ref`. Default: `<dir-de-FILE>/spec.md`
resolvido pela convencao `docs/specs/<feature>/` — **so quando `FILE`
segue essa convencao**. A flag explicita `--spec` aceita QUALQUER path
(inclusive fixtures de teste fora de `docs/specs/`); a restricao de
convencao se aplica somente ao default automatico.

### Catalogo de findings (plan-profile)

| code | severidade | Escopo | Condicao |
|------|------------|--------|----------|
| `missing-section` | Erro | `plan.md` | Falta uma das 4 secoes obrigatorias (`Summary`, `Technical Context`, `Constitution Check`, `Project Structure`). |
| `template-placeholder` | Erro | qualquer artefato `/plan` | Token de template nao preenchido (`[FEATURE]`, `[DATE]`, `[short-name]`, `[Topico]`, `[Endpoint/Command/Event]`). |
| `unlabeled-contract` | Erro | `contracts/*.md` | Entrada que documenta um Command/Endpoint/Event sem rotulo inequivoco real-vs-proposto (`[PROPOSTA — a validar na implementacao]` ou `[EXISTENTE]`). |
| `residual-clarification` | Erro | `plan.md` | `[NEEDS CLARIFICATION]` remanescente. |
| `dangling-fr-sc-ref` | Erro | `plan.md` | ID `FR-`/`SC-` citado que NAO existe na `spec.md` correspondente — checagem SEMANTICA apenas, nunca resolucao de link/anchor no disco. |

### Precedencia de selecao de perfil

1. **Flag explicita** (`--sdd-spec`/`--sdd-plan`/`--runbook`) vence tudo.
2. **Deteccao automatica por path**: `UC-*.md` → perfil UC; `RB-\d{3}-*.md`
   → `--runbook`; `docs/specs/<feature>/spec.md` → spec-profile;
   `docs/specs/<feature>/{plan,research,data-model,quickstart}.md` ou
   `docs/specs/<feature>/contracts/*.md` → plan-profile.
3. **Nem flag nem convencao reconhecida** → perfil indeterminado, mensagem
   clara em stderr, exit 2 — NUNCA aplica um perfil por engano.

Exemplos (espelham `contracts/validate-sdd-cli.md` §Exemplos de saida):

```console
$ validate-sdd.sh docs/specs/enforced-guards/spec.md
RESULT|docs/specs/enforced-guards/spec.md|profile=spec|errors=0|warnings=0
# exit 0

$ validate-sdd.sh docs/specs/x/plan.md
FINDING|error|template-placeholder|Token de template nao preenchido: [FEATURE]
FINDING|error|dangling-fr-sc-ref|plan.md cita FR-099, ausente na spec.md correspondente
RESULT|docs/specs/x/plan.md|profile=plan|errors=2|warnings=0
# exit 1

$ validate-sdd.sh /tmp/qualquer/spec.md
Perfil nao determinado para '/tmp/qualquer/spec.md': path fora da convencao docs/specs/<feature>/ e nenhuma flag informada. Use --sdd-spec ou --sdd-plan.
# exit 2
```

## Fronteira de nao-duplicacao (`spec-profile`/`plan-profile` vs `analyze` vs `validate-docs-rendered`)

Tres skills tocam artefatos SDD; cada categoria de check tem UM dono, sem
sobreposicao (SC-005 da feature `validate-docs-sdd-profile`):

| Categoria de check | Dono | spec/plan-profile faz? |
|--------------------|------|------------------------|
| Secoes obrigatorias presentes num UNICO artefato | `validate-documentation` (spec/plan-profile) | SIM |
| Anti-padroes de conteudo da spec (impl. vazando, SC nao-mensuravel, `[NEEDS CLARIFICATION]` > 3, stories acopladas, adjetivos vagos, N/A residual) | `validate-documentation` (spec-profile) | SIM |
| Placeholder de template residual / rotulo real-vs-proposto / `[NEEDS CLARIFICATION]` residual no plan | `validate-documentation` (plan-profile) | SIM |
| ID `FR-`/`SC-` citado em `plan.md` EXISTE na `spec.md` (checagem SEMANTICA) | `validate-documentation` (plan-profile) | SIM |
| Link/anchor entre arquivos RESOLVE no disco (arquivo existe, header casa) | `validate-docs-rendered` | NAO |
| Sintaxe Mermaid, frontmatter YAML, code-block sem linguagem | `validate-docs-rendered` | NAO |
| Cobertura cross-artifact (tasks vs requisitos, duplicacao, gaps, drift de terminologia, alinhamento com constitution) | `analyze` | NAO |
| Drift de case-convention entre camadas (snake vs camel) | `analyze` (Pass G) | NAO |

A linha mais sutil e a de referencia cruzada de IDs: `plan-profile` faz
APENAS a checagem semantica (o ID existe na spec?), NUNCA a resolucao de
path/anchor no disco — essa fica 100% com `validate-docs-rendered`.

---

## Gotchas

### Valida DOCUMENTO INDIVIDUAL, nao relacionamento entre artefatos

Para verificar se o `tasks.md` cobre os requisitos do `spec.md`, ou se `plan.md` viola `constitution.md`, use a skill `analyze`. Esta skill valida UM documento contra padroes estruturais — UC tem todas as secoes, diagramas parseaveis, IDs nao-duplicados, etc.

### Diagrama Mermaid com erro de sintaxe nao e cosmetico

Um `sequenceDiagram` sem `participant` declarado, ou setas fora do padrao (`-->` ao inves de `->>`), quebra o render em GitHub/viewers. Sempre validar que o diagrama parseia — idealmente via script.

### IDs duplicados dentro do mesmo documento sao erro, nao aviso

RN01 aparecendo duas vezes, ou CT03 com dois cenarios distintos, quebra rastreabilidade. Detectar e reportar como Erro, nao Aviso.

### `duplicate-id` do spec-profile reusa esta convencao, nao inventa criterio novo

O check `duplicate-id` de `spec-profile` (perfil SDD, acima) aplica a MESMA
regra deste Gotcha a `FR-`/`SC-` em `spec.md` — nao ha FR proprio na spec
da feature `validate-docs-sdd-profile` cobrindo esse check porque ele reusa
uma convencao ja estabelecida aqui, e nao introduz criterio novo. Fecha
CHK004/CHK013 (checklist da feature): a citacao a este Gotcha, e nao a um
FR-NNN inexistente, e a rastreabilidade correta.

### Minimo 5 casos de teste (sucesso + erro + edge) — abaixo disso reprova

UC com 2 CTs e incompleto. A cobertura minima e: 1-2 cenarios de sucesso + 1-2 de erro + 1 edge case. Menos que isso, o UC nao esta pronto para implementacao.

### Auto-correcao pede confirmacao — nao aplicar direto

Mesmo quando o usuario pediu "valide e corrija", apresentar o que sera mudado antes de escrever. Correcao automatica em documento humano sem review gera desconfianca do sistema.