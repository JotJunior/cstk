# Contract: `cstk` CLI Commands

Comandos expostos pelo binario `cstk`. Cada comando tem subsection com sintaxe,
flags, exit codes e saida esperada.

## Convencoes globais

**Sintaxe comum:**

```
cstk <command> [command-args...] [global-flags...]
```

**Flags globais (aceitas por qualquer command):**

| Flag                        | Descricao                                                                |
|-----------------------------|--------------------------------------------------------------------------|
| `--scope <global\|project>` | Default `global`. `project` usa `./.claude/skills/` relativo ao CWD      |
| `--dry-run`                 | Mostra o que seria feito sem escrever. Exit 0 se acao seria bem-sucedida |
| `--yes`                     | Pula confirmacoes interativas (assume "sim"). Ainda aborta em erros      |
| `--verbose`                 | Loga passos intermediarios em stderr                                     |
| `--help`                    | Imprime help do command e sai                                            |

**Exit codes (convencao POSIX + Principio II):**

| Code | Significado                                                                                              |
|------|----------------------------------------------------------------------------------------------------------|
| 0    | Sucesso                                                                                                  |
| 1    | Erro geral (rede, filesystem, conflito nao resolvido)                                                    |
| 2    | Uso incorreto (flag invalida, arg faltando)                                                              |
| 3    | Lock ja detido por outra instancia                                                                       |
| 4    | Conflito de edicao local detectado e usuario nao passou `--force` / `--keep`                             |
| 10   | `self-update --check`: update disponivel (usado por scripts/automacao)                                   |

**Saida:**
- Dados estruturados em stdout (TSV ou linha-por-item, pensado para pipe)
- Mensagens humanas (progresso, avisos, erros) em stderr
- Summary final em stderr, prefixado com `==>`

---

## Command: `cstk install`

Instala skills no escopo indicado.

**Sintaxe:**

```
cstk install [SKILL...] [--profile NAME] [--interactive] [--scope global|project] [--dry-run] [--yes]
```

**Argumentos:**

- `SKILL...` (opcional, zero ou mais): nomes especificos de skills para cherry-pick.
  Precede `--profile`. Conflito: se ambos informados, usa UNION.

**Flags especificas:**

| Flag                   | Descricao                                                                                                                            |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| `--profile NAME`       | Perfil declarado em catalog: `all`, `sdd`, `complementary`, `language-go`, `language-dotnet`. Default quando nada e informado: `sdd` |
| `--interactive` / `-i` | Abre seletor numerico de perfis e skills                                                                                             |
| `--from RELEASE`       | Instala a partir de uma release especifica (tag). Default = ultima release                                                           |

**Comportamento:**

1. Adquire lock do escopo (exit 3 se ocupado)
2. Valida perfil/selecao
3. Baixa tarball da release alvo para tempdir; valida SHA-256
4. Extrai; resolve set final de skills a instalar
5. Para cada skill alvo:
   - Se ja existe em disco e NAO esta no manifest: preservar (skill de terceiro ou
     instalacao prev. manual). Log de aviso e pular.
   - Se ja existe e esta no manifest: comportamento equivalente a update daquela
     skill (ver `cstk update`)
   - Se nao existe: copiar para destino e adicionar ao manifest
6. Se perfil inclui `language-*` E escopo e `project`: tambem aplicar FR-009d (hooks
   + settings.json merge)
7. Escrever manifest atualizado (temp + mv atomico)
8. Emitir summary

**Summary output (stderr, machine-readable-ish):**

```
==> cstk install summary
  installed: 9
  updated: 0
  preserved (third-party): 1
  skipped: 0
  scope: global
  toolkit version: 3.2.0
```

**Error cases:**

- Skill name nao existe no catalog → exit 2, mensagem lista names validos
- Perfil nao existe → exit 2
- Download falha (rede) → exit 1, nenhuma escrita feita
- Checksum mismatch → exit 1, nenhuma escrita feita

---

## Command: `cstk update`

Atualiza skills ja instaladas no escopo para a versao da release alvo.

**Sintaxe:**

```
cstk update [SKILL...] [--scope global|project] [--force] [--keep] [--prune] [--from RELEASE] [--dry-run] [--yes]
```

**Argumentos:**

- `SKILL...` (opcional): restringe update a um subset do que esta no manifest.
  Default = todas as skills listadas no manifest do escopo.

**Flags especificas:**

| Flag             | Descricao                                                                                                                   |
|------------------|-----------------------------------------------------------------------------------------------------------------------------|
| `--force`        | Sobrescreve skills com edicao local (hash mismatch). Sem ela, CLI pula skills editadas e retorna exit 4                     |
| `--keep`         | Mantem skills com edicao local silenciosamente (atualiza as outras; nao emite aviso por skill editada)                      |
| `--prune`        | Remove do disco e do manifest skills que nao existem mais no catalog da release alvo. Exige confirmacao a menos que `--yes` |
| `--from RELEASE` | Especifica release alvo (tag). Default = ultima release                                                                     |

**Comportamento:**

1. Adquire lock (exit 3 se ocupado)
2. Baixa tarball + checksum da release alvo
3. Para cada skill no escopo (segundo manifest e args):
   - Calcula hash atual do diretorio instalado
   - Compara com `source_sha256` do manifest
     - Iguais: skill limpa. Se versao difere ou conteudo da release difere, atualiza.
     - Diferentes: edicao local detectada
       - Sem `--force` e sem `--keep`: pula skill e adiciona a lista "edited, skipped"
       - `--force`: sobrescreve e atualiza manifest
       - `--keep`: pula silenciosamente (sem warning por skill)
4. Se `--prune`: detectar skills no manifest que nao existem mais no catalog;
   confirmar; remover
5. Escrever manifest atualizado
6. Emitir summary. Se alguma skill foi skipped por edicao local sem `--force`/`--keep`:
   exit 4 (nao 0) — sinal para CI detectar "update incompleto"

**Summary output:**

```
==> cstk update summary
  updated: 3
  already up-to-date: 6
  skipped (local edits): 1
  removed (pruned): 0
  scope: global
  from: 3.2.0 → 3.3.0
  next: cstk update --force  (to overwrite edited skills)
```

**Error cases:**

- Skills com edicao local sem `--force`/`--keep` → exit 4 apos processar o resto
- Rede/checksum → exit 1 sem escrita

---

## Command: `cstk self-update`

Atualiza o proprio binario `cstk` + `cli/lib/` para a ultima release.

**Sintaxe:**

```
cstk self-update [--check] [--dry-run] [--yes]
```

**Flags especificas:**

| Flag | Descricao |
|------|-----------|
| `--check` | So verifica; imprime `latest:<tag> current:<tag>` em stdout. Exit 0 se ja na ultima, exit 10 se update disponivel, exit 1 em erro de verificacao |

**Comportamento:**

1. NAO adquire lock de skills (lock de skills e por escopo; self-update opera na CLI).
   Adquire lock EXCLUSIVO de self-update em `$CSTK_LIB/../.self-update.lock` (via
   `mkdir`). Exit 3 se ja detido.
2. Consulta ultima release GitHub
3. Se `--check`: imprime e sai
4. Se versao atual = latest: reporta, exit 0 sem escrita
5. Baixa tarball + checksum
6. Verifica SHA-256 contra `.sha256` da release (FR-010a)
7. Stage de arquivos novos em `$CSTK_LIB.new/` e `$CSTK_BIN.new` (diretorios irmaos,
   mesmo filesystem)
8. Sequencia stage-and-rename coordenada (atomicidade par bin+lib — FR-006):
   a. `mv $CSTK_LIB $CSTK_LIB.old` (atomic rename)
   b. `mv $CSTK_LIB.new $CSTK_LIB` (atomic rename)
   c. **Commit point**: `mv -f $CSTK_BIN.new $CSTK_BIN` (atomic rename)
   d. `rm -rf $CSTK_LIB.old` (cleanup; falha aqui nao afeta correcao)
9. Em qualquer falha antes de (c): rollback (restaurar `$CSTK_LIB.old` → `$CSTK_LIB`)
   + abort. Sistema fica 100% na versao antiga.
10. Imprime summary
11. Libera lock (via trap em EXIT/INT/TERM)

**Summary output:**

```
==> cstk self-update summary
  from: 3.2.0 → 3.3.0
  binary: ~/.local/bin/cstk
  library: ~/.local/share/cstk/lib/
  next: cstk update  (to bring installed skills to 3.3.0)
```

**Error cases:**

- Download falha → exit 1, CLI antigo permanece funcional
- Checksum mismatch → exit 1, idem (zero escrita no destino)
- Falta permissao de escrita no destino → exit 1 com instrucao
- Lock ja detido por outro self-update → exit 3
- Falha em rename (a), (b) ou (c) → rollback automatico + exit 1 + mensagem indicando
  que sistema permanece na versao antiga
- CLI nao instalada (`$CSTK_BIN` nao existe) → exit 1 apontando o one-liner de
  bootstrap (FR-005a)

---

## Command: `cstk list`

Lista skills instaladas no escopo.

**Sintaxe:**

```
cstk list [--scope global|project] [--format tsv|pretty] [--available]
```

**Flags especificas:**

| Flag          | Descricao                                                                                                         |
|---------------|-------------------------------------------------------------------------------------------------------------------|
| `--format`    | `tsv` (stdin-pipe friendly) ou `pretty` (tabela colorida default em TTY). Default: `pretty` em TTY, `tsv` em pipe |
| `--available` | Lista skills do catalog da ULTIMA release em vez do manifest local. Nao exige lock nem escrita                    |

**Saida (format tsv):**

```
specify	3.2.0	clean	2026-04-22T14:30:00Z
plan	3.2.0	edited	2026-04-22T14:30:00Z
```

Colunas: skill, version, status (`clean`/`edited`/`missing-from-catalog`), installed_at

**Saida (format pretty):**

```
SKILL             VERSION   STATUS    INSTALLED
specify           3.2.0     clean     2026-04-22
plan              3.2.0     edited    2026-04-22
```

**Exit codes:**
- 0 sempre, exceto se escopo inexistente (1) ou manifest corrompido (1)

---

## Command: `cstk doctor`

Verifica integridade da instalacao: drift, manifest vs disco, hash mismatch.

**Sintaxe:**

```
cstk doctor [--scope global|project] [--fix]
```

**Flags especificas:**

| Flag    | Descricao                                                                                            |
|---------|------------------------------------------------------------------------------------------------------|
| `--fix` | Tenta reconciliar: reconstroi manifest inspecionando disco; remove entradas orfas; re-calcula hashes |

**Comportamento:**

1. Le manifest
2. Para cada entry: verifica diretorio existe, calcula hash, compara
3. Para cada diretorio nao listado: classifica como "third-party" (ausente do
   catalog da release do manifest) ou "suspected toolkit skill sem manifest entry"
4. Reporta achados
5. Com `--fix`: aplica reparos seguros (nao sobrescreve conteudo, apenas manifest)

**Output (pretty):**

```
==> cstk doctor (scope: global, toolkit: 3.2.0)
  [OK]        specify      clean
  [EDITED]    plan         local edits detected
  [MISSING]   checklist    in manifest, not on disk
  [ORPHAN]    my-custom    on disk, not in manifest (third-party)
  [DRIFT]     3 issues found. Run with --fix to reconcile manifest.
```

**Exit codes:**
- 0 se tudo clean
- 1 se algum drift detectado (sem `--fix`)

---

## Command: `cstk --version`

Imprime versao instalada do CLI em stdout.

**Saida:**

```
cstk 3.2.0
```

**Exit code:** 0

---

## Command: `cstk --help` (ou `cstk help`)

Imprime help geral ou de um subcommand.

**Sintaxe:**

```
cstk help [COMMAND]
cstk --help
cstk <command> --help
```

**Exit code:** 0
