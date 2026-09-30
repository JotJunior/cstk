# Contract: marcadores inline de reconciliacao

[PROPOSTA — a validar na implementacao] — contrato novo, fixado por este plan conforme
FR-009 ("tokens exatos definidos no plan"). Nenhum formato pre-existente e afirmado.

## 1. Sintaxe

```
[reconciled:<kind> <date> evidence=<ref>]
```

| Parte | Valores | Regra |
|-------|---------|-------|
| `<kind>` | `removed` \| `updated` \| `added` | minusculo, ingles |
| `<date>` | `YYYY-MM-DD` | data local da execucao que aplicou o marcador |
| `<ref>` | `<path>:<line>` \| `absent:<path>` | `<path>` relativo a raiz do projeto, sem espacos; `<line>` inteiro >= 1 |

Regex de reconhecimento (ERE POSIX, usada por `markers.sh`):

```
\[reconciled:(removed|updated|added) [0-9]{4}-[0-9]{2}-[0-9]{2} evidence=(absent:)?[^] :]+(:[0-9]+)?\]
```

O marcador nunca carrega conteudo do codigo, so a referencia `<ref>` (FR-019: nao-copia de
segredos).

Um marcador por linha/celula. Posicao: FIM da linha (ou da celula de tabela) do trecho
afetado, separado por um espaco.

## 2. Semantica por `kind`

| kind | Quando | Texto do documento | Identificador |
|------|--------|--------------------|---------------|
| `removed` | codigo citado nao existe mais (ancora `absent`) ou comportamento documentado foi retirado | texto original PRESERVADO integralmente | FR-NNN original mantido |
| `updated` | trecho SHOULD/descritivo reescrito para refletir o codigo (FR-005) | so o trecho divergente muda | FR-NNN/SC-NNN mantidos |
| `added` | comportamento do codigo sem cobertura na documentacao | nova linha de requisito | NOVO FR-NNN = maior FR existente no `spec.md` + 1, 3 digitos (`markers.sh next-fr`) |

`removed` exige `evidence=absent:<path>` quando a remocao e de arquivo; quando o arquivo
existe mas o comportamento saiu, usa `<path>:<line>` do trecho que mostra o novo
comportamento.

## 3. O que NAO recebe marcador

- `possible-regression` (FR-007): documento intocado; so relatorio.
- `unverifiable` (FR-008): documento intocado; so relatorio.
- Arquivos fora da allowlist de `doc-guard.sh` (inclui todo `docs/specs/current/`).

## 4. Idempotencia (FR-012, SC-003)

- Trecho que ja possui marcador e esta coerente com o codigo NAO e reescrito — nem a
  data, nem o `<line>` da evidencia (linhas mudam com edicoes nao relacionadas; isso
  nao e divergencia).
- Um trecho `removed` so volta a ser tocado se o codigo reaparecer (vira `updated` sobre
  o mesmo FR-NNN, substituindo o marcador `removed`).
- `markers.sh lint <file>` falha (exit 1) em marcador mal formado, permitindo checar a
  saida da propria skill.

## 5. Exemplos

```markdown
- **FR-004**: O sistema MUST aceitar `--foo`. [reconciled:removed 2026-10-02 evidence=absent:cli/lib/foo.sh]
- **FR-006**: O sistema SHOULD registrar em `a.log`. [reconciled:updated 2026-10-02 evidence=cli/lib/bar.sh:41]
- **FR-019**: O sistema MUST aceitar `--baz`. [reconciled:added 2026-10-02 evidence=cli/lib/bar.sh:88]
```

Os caminhos, flags e linhas acima sao ILUSTRATIVOS da sintaxe (nao existem no
repositorio) e nao devem ser copiados para nenhum documento real.
