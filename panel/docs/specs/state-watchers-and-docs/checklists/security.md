# Security Checklist: Watchers de Execução em Andamento e Visualização de Documentação

**Purpose**: Quality gate da qualidade dos requisitos de SEGURANÇA — postura
JÁ RATIFICADA pelo operador (block-001 → dec-021). Confirma que os requisitos
que mitigam os 2 findings HIGH (XSS por esquema de URL; escape por symlink) e os
4 medium do gate `owasp-security` estão bem especificados na spec/plan/contratos.
Valida qualidade de requisito, não a implementação.
**Created**: 2026-07-15
**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md) | **Research**: [research.md](../research.md) (Decisions 6, 7, 9)
**Domínios irmãos**: [requirements.md](./requirements.md) · [performance.md](./performance.md)

> Postura ratificada: os 2 HIGH foram **corrigidos no plano** (Decisions 6 e 7);
> os medium consolidados na Decision 9. Modelo de ameaça: local / single-operator
> / bind `127.0.0.1` / sem auth (blast radius contido). IDs `CHK027`–`CHK043`.

## Modelo de Ameaça e Superfície

- [x] CHK027 - O modelo de ameaça (local, single-operator, bind `127.0.0.1`, sem autenticação) está documentado e os requisitos alinhados a ele? [Traceability, research Decision 9 §Rationale, plan §Constraints/Scale] {auto}
- [x] CHK028 - A superfície nova é especificada como somente-leitura (`GET`), sem endpoint de mutação, alinhada ao Princípio I (Read-Only Absoluto)? [Cobertura, contract docs-api Invariante 1, plan §Constitution Check I] {auto}

## Conteúdo UNTRUSTED — Render de Markdown (FR-010, Decision 6)

- [x] CHK029 - O requisito de desabilitar/sanitizar HTML ativo (raw HTML OFF; nunca `dangerouslySetInnerHTML` com HTML não sanitizado) está especificado? [Completude, Spec §FR-010, research Decision 6, contract docs-api Invariante 3] {auto}
- [x] CHK030 - O requisito de allowlist de esquema de URL (permitir `http`/`https`/`mailto`/relativo; descartar `javascript:`/`data:`/`vbscript:`) em links/imagens está especificado? [Completude, research Decision 6 (finding HIGH), contract docs-api Invariante 3] {auto}
- [x] CHK031 - Está explícito que "raw HTML OFF" sozinho NÃO basta — os esquemas perigosos vêm do AST do markdown (`[x](javascript:…)`, `![x](data:…)`), não do raw HTML? [Clareza, research Decision 6] {auto}
- [x] CHK032 - O requisito de que o SERVIDOR entrega markdown bruto e NUNCA executa/entrega HTML sanitizado (a sanitização/render seguro acontece no cliente) está especificado? [Consistência, contract docs-api Invariante 3, research Decision 6] {auto}

## Path Traversal / Confinamento de Leitura (FR-009, Decision 7)

- [x] CHK033 - O requisito de confinar toda leitura de artefato à subárvore `<projectPath>/docs/specs/<feature>/` está especificado? [Cobertura, Spec §FR-009, research Decision 7] {auto}
- [x] CHK034 - O requisito de resolver symlinks (`fs.realpath`) e rejeitar `.md` symlinkado (`lstat`), ALÉM da regex de param, está especificado? [Completude, research Decision 7 (finding HIGH), contract docs-api Invariante 2] {auto}
- [x] CHK035 - O requisito de comparação de prefixo na fronteira `path.sep` (evitando o falso-positivo `/root` casar `/root-evil`) está especificado? [Clareza, research Decision 7] {auto}
- [x] CHK036 - A validação anti-traversal (regex `/^[^/\\.<>]+$/`) dos path params (`:project`/`:feature`/`:artifact`) está especificada? [Cobertura, contract docs-api §Path params, research Decision 7] {auto}
- [x] CHK037 - O requisito de cap de tamanho na leitura do `.md` (anti-exaustão de memória) está especificado? [Completude, research Decision 7, contract docs-api Invariante 2] {auto}

## Subprocesso Seguro — Delegação a `cstk` (Decisions 2 e 9)

- [x] CHK038 - O requisito de `execFile` com argumentos em array (sem shell-string interpolada; nunca `exec('cstk ' + var)`) está especificado? [Completude, research Decision 2, contract watchers §2] {auto}
- [x] CHK039 - O requisito de resolver o binário `cstk` de forma confiável (anti PATH hijack; `env`/`cwd` mínimos ao subprocesso) está especificado? [Completude, research Decision 9.1, contract watchers §2] {auto}
- [x] CHK040 - O requisito de confinar `feature`/`session` (UNTRUSTED, vindos da knowledge.db) com canonicalização + regex anti-traversal + confinamento ANTES de montar o state-dir — não só checar existência — está especificado? [Completude, research Decision 9.2, contract watchers §2] {auto}
- [x] CHK041 - O requisito de timeout explícito + captura de `stderr`/`stdout` no subprocesso está especificado? [Completude, contract watchers §2, research Decision 2] {auto}

## Invariantes Read-Only

- [x] CHK042 - Está explícito que nenhum caminho de código escreve na knowledge.db, toca `state.json` ou roda `cstk recall --reindex`? [Consistência, Spec §FR-004, contract watchers §4 Invariantes, plan §Constitution Check I/IV] {auto}

## Julgamento de Risco (Dono do Produto)

- [ ] CHK043 - A decisão de aceitar os 4 findings `medium` / 3 `low` do gate `owasp-security` (sem corrigi-los antes de `/create-tasks`) reflete o apetite de risco do produto para release? [Risco, research Decision 9 §Low] {humano}
  - Nota: a postura de segurança GLOBAL (incl. os 2 HIGH corrigidos no plano) já foi **ratificada** pelo operador em `block-001` → `dec-021`. Este item preserva a granularidade medium/low visível para uma decisão explícita do dono; não reabre a ratificação.

## Notes

- Items `{auto}` já vêm resolvidos: `[x]` com citação (Spec/research/contract).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto.
- **Resolução**: 16 `{auto}` verificados `[x]`; 1 item `{humano}` em aberto (CHK043, já coberto pela ratificação dec-021). 0 gaps auto em aberto. Rastreabilidade: 100%.
- **Follow-up**: CHK043 é decisão do dono do produto; a postura já foi ratificada (dec-021), então serve de registro auditável, não de bloqueio.
