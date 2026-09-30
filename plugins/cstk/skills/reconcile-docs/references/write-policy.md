# Politica de escrita (reconcile-docs)

Regras de gravacao da skill. Carregar antes do primeiro passo de escrita (passo 6 do
`SKILL.md`). Direcao da skill: a documentacao segue o codigo; **so documentacao da feature
e gravada, nunca codigo**.

## 1. Allowlist de documentos (FR-005, FR-006, FR-017)

Gravaveis, dentro do diretorio da feature (ativa ou arquivada), no maximo um nivel:
`spec.md`, `plan.md`, `data-model.md`, `quickstart.md`, `contracts/*.md` e
`reconciliation.md` (este so via `reconciliation-log.sh`).

NUNCA gravaveis: `research.md`, `checklists/`, `tasks.md` (registro historico;
divergencias com `tasks.md` so aparecem no relatorio), o corpus canonico
`docs/specs/current/` (gerado por delta-merge) e qualquer arquivo de codigo, teste, script
ou configuracao. A allowlist e imposta por `scripts/doc-guard.sh`, nao por convencao.

## 2. Sequencia de escrita (por alteracao)

1. `scripts/doc-guard.sh check --root . --feature-dir <dir> <doc>` — fail-closed: exit != 0
   (inclusive script ausente ou erro) = negado; a acao vira `ignored` com motivo
   `write-denied` e nada e gravado.
2. `Edit` somente do trecho divergente, preservando o restante do texto, a estrutura e os
   identificadores (FR-NNN, SC-NNN).
3. Marcador inline `[reconciled:<kind> <date> evidence=<ref>]` (novo FR via
   `markers.sh next-fr`), depois `markers.sh lint <doc>` e `markers.sh verify --root . <doc>`
   (ambos devem passar; falha = desfaca a edicao daquele trecho e reporte).
4. So se algum documento mudou: `reconciliation-log.sh append` (entrada datada, sem copiar o
   relatorio). Sem alteracao, nao grava nada (FR-012, FR-018).

## 3. Pre-condicao de gravacao: precisa de git (FR-016, dec-035)

Antes de qualquer escrita, rode `scripts/git-probe.sh can-write --root .`.

| Resultado | Consequencia |
|-----------|--------------|
| `WRITE<TAB>allowed` (exit 0) | gravacao permitida |
| qualquer outro (`WRITE<TAB>denied-no-git` com exit 3, exit != 0, script ausente) | RECUSA: execute como `--dry-run` forcado |

Sem git a unica rede de seguranca (reversao pelo VCS) nao existe, por isso a skill nunca
grava: analisa, classifica e reporta as alteracoes como `proposed-*`, com o aviso
`no-git-write-refused` no relatorio, e diz que a gravacao exige um projeto versionado. Nada
e criado ou alterado, inclusive `reconciliation.md`. A analise segue valida (a leitura do
codigo atual nao depende de git).

## 4. Modo padrao e confirmacao no `--all` (FR-020, dec-035)

- **Uma feature (sem `--all`), com git**: grava direto, sem confirmacao por alteracao; o VCS
  e a rede de seguranca.
- **`--all` sem `--dry-run`, com git**: nao grava na primeira passada. Analise todas as
  features como `--dry-run` (uma por vez, retendo so a linha-resumo e as acoes propostas em
  forma enxuta), exiba o resumo do que mudara em TODAS as features (ativas e arquivadas) e
  peca UMA confirmacao unica para o lote. So com confirmacao afirmativa explicita do
  operador execute a passada de gravacao (sequencia da secao 2, feature por feature;
  releia a linha citada antes de gravar, pois o codigo pode ter mudado). Sem confirmacao, nada
  e gravado.
- **Sem operador presente** (execucao nao interativa, sem como perguntar): nao assuma
  consentimento; caia em `--dry-run` e diga isso no relatorio.
- `--dry-run` explicito nunca pede confirmacao e nunca grava.

## 5. Auditoria pos-execucao (SC-001)

Depois das escritas, rode `git-probe.sh status --root .` e compare com o snapshot do passo 2
do `SKILL.md`: toda entrada nova fora da allowlist (ou em `docs/specs/current/`) e
`audit: violation` no relatorio. Sem git a skill nao grava (secao 3); a auditoria fica
`skipped-no-git`.
