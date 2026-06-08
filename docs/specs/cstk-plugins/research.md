# Research: cstk-plugins

Phase 0 do `/plan`. Resolve as unknowns tecnicas antes do design. A spec ja
passou por `/clarify` (dec-005 FR-001, dec-006 FR-007), entao nao restam
`NEEDS CLARIFICATION` no Technical Context. As decisoes abaixo registram
escolhas de implementacao ancoradas na realidade do toolkit (POSIX sh,
catalogo `~/.claude`, runtime via self-update) e na constitution v1.1.0.

## Decision 1: Localizacao do plugin store

**Decision**: Plugins instalados vivem em **`~/.claude/cstk/plugins/<name>/`**
(namespace dedicado do cstk), NAO em `~/.claude/plugins/<name>/` como o
default literal da spec FR-007.

**Rationale**: `~/.claude/plugins/` JA e propriedade do sistema NATIVO de
plugins do Claude Code. Inspecao empirica:

```
$ ls -d ~/.claude/plugins/*/
~/.claude/plugins/cache/  ~/.claude/plugins/data/
~/.claude/plugins/marketplaces/  ~/.claude/plugins/repos/
$ jq keys ~/.claude/plugins/installed_plugins.json
["plugins", "version"]
```

O Claude Code mantem `installed_plugins.json`, `known_marketplaces.json`,
`blocklist.json` e os subdiretorios `cache/ data/ marketplaces/ repos/`
nesse caminho. Escrever `~/.claude/plugins/codex/` arrisca: (a) colisao se
o CC reservar mais subdirs; (b) o CC clobberar/limpar nossos arquivos em uma
operacao de manutencao do proprio store; (c) `cstk plugin-list` confundir
plugins nativos do CC com plugins cstk. Um namespace dedicado
`~/.claude/cstk/plugins/` elimina os tres riscos e ainda satisfaz a intencao
de FR-007 (user-local; FORA de `~/.claude/skills/`).

**Constitution note**: FR-007 diz "default: `~/.claude/plugins/<name>/`" — o
plano DESVIA do default literal por seguranca de integridade. Isso e uma
mudanca de contrato menor dentro da MESMA feature (a spec ainda em Draft);
sera refletida na proxima revisao da spec. O proibitivo MUST de FR-007 ("MUST
NOT write into `~/.claude/skills/`") permanece integralmente respeitado.

**Alternatives considered**:
- `~/.claude/plugins/<name>/` (literal da spec) — REJEITADA: colisao com CC
  native (evidencia acima).
- `~/.cstk/plugins/` (irmao de `~/.cstk/config` de FR-001) — viavel, mas
  fragmenta o estado do cstk em dois roots (`~/.claude/` para catalogo +
  `~/.cstk/` para plugins). Manter tudo sob `~/.claude/cstk/` agrupa o estado
  do toolkit. `~/.cstk/config` permanece como override de FR-001 (ja na spec).
- Symlink farm em `~/.claude/skills/` — REJEITADA: viola FR-007 explicitamente
  e dec-006 (path-prepending only, score 3).

## Decision 2: Metodo de checksum/integridade do bundle

**Decision**: Reusar **`hash_dir`** de `cli/lib/hash.sh` para computar o
checksum canonico do bundle (campo `sha256` do manifest). `hash_dir`
ja faz: `find . -type f -print | sort` → `sha256_file` por arquivo →
linha `<hash>  <relpath>` → `sha256_stdin` do agregado. O `sha256_file`
de `compat.sh` detecta `sha256sum` (coreutils) com fallback `shasum -a 256`
(macOS), exatamente o que FR-017 autoriza sob o carve-out 1.1.0.

**Rationale**: Zero dependencia nova (Principio II NON-NEGOTIABLE). O hash
e deterministico e independente de ordem de `find` (o `sort` canonicaliza).
A exclusao do proprio manifest do bundle (FR-003: "excluding the manifest
itself") e feita removendo `./plugin-manifest.json` antes de chamar
`hash_dir`, ou hasheando um subdiretorio `skills/` que nao contem o manifest.

**Evidencia empirica**:
```
$ command -v shasum sha256sum
/usr/bin/shasum
/sbin/sha256sum
$ grep -n hash_dir cli/lib/hash.sh
45:hash_dir() {  # find . -type f | sort; sha256_file por arquivo; sha256_stdin
```

**Alternatives considered**:
- `tar` do bundle + `sha256` do tarball — REJEITADA: `tar` adiciona
  metadados (mtime, uid/gid, ordem) nao-deterministicos; exigiria flags de
  normalizacao nao-portaveis (`--sort`, `--mtime`, `--owner`) que GNU tar tem
  mas BSD tar (macOS) nao. `hash_dir` ja resolve isso de forma portavel.
- Assinatura GPG/minisign — fora de escopo MVP; adiciona dep externa
  obrigatoria (viola Principio II). O manifest+checksum cobre integridade
  (A08); confianca de ORIGEM e delegada ao trust model do GitHub namespace
  (FR-001 default `JotJunior/`, mesmo trust do toolkit). Anotado como
  extensao futura (campo `signature` opcional no schema, ignorado no MVP).

## Decision 3: Download remoto e conformidade com Principio IV

**Decision**: `plugin-add` baixa via `http_download` (`cli/lib/http.sh`,
wrapper `curl -fsSL`). O download e **fetch de artefato** sob comando
explicito do usuario, NAO telemetria — explicitamente conforme Principio IV.

**Rationale**: Principio IV proibe "coleta remota de uso ou dados" e
"endpoint de telemetria/analytics". Baixar um plugin que o usuario PEDIU
(`cstk plugin-add codex`) e o caso permitido pela propria constitution:
"Fetches HTTP sao permitidos apenas quando o proposito da skill e
inerentemente de rede ... e o fetch e do dominio-alvo da pergunta, nao de um
endpoint do autor". A URL e derivada do nome do plugin (FR-001), nao de um
endpoint do mantenedor. FR-006 e FR-018 cravam: nenhuma rede em
`plugin-list`/`plugin-remove`/ativacao; rede SO no `plugin-add` disparado
pelo usuario.

**Evidencia empirica**:
```
$ grep -n "curl" cli/lib/http.sh
50: curl -fsSL --connect-timeout 10 --max-time 300 -o "$_http_dest" -- "$_http_url"
```
O `http_download` mapeia exit codes de curl (6 host, 7 conn, 22 HTTP, 28
timeout) → mensagens claras (cobre Edge Case "offline", FR US1-AS4).

**Alternatives considered**:
- `git clone` do repo do plugin — viavel (git esta no stack), porem traz a
  arvore `.git` inteira (peso) e exige checkout/tag resolution. `curl` de um
  tarball de release (`/archive/refs/tags/<ver>.tar.gz` ou release asset) e
  mais enxuto e ja tem wrapper (`http_download` + `download_and_verify` em
  `tarball.sh`). Decisao: tarball via http_download (reaproveita
  `tarball.sh:download_and_verify`).
- Mirror/cache local obrigatorio — fora de MVP; Edge Case "sem rede e sem
  cache" resolve com erro claro (nao exige cache).

## Decision 4: Mecanismo de path-prepending para `--llm`

**Decision**: O dispatcher de skills resolve cada lookup consultando
**primeiro** `~/.claude/cstk/plugins/<name>/skills/<skill>/`, com fallback
para `~/.claude/skills/<skill>/`. Implementado como uma funcao de resolucao
`plugin_resolve_skill_dir <skill>` em `cli/lib/plugin-common.sh`, exportada
para os entrypoints 00c. Nenhum arquivo e copiado/symlinkado (dec-006,
score 3).

**Rationale**: dec-006 (clarify, score 3) fixou path-prepending como UNICO
modelo consistente com a proibicao de FR-007. O catalogo core permanece
imutavel durante ativacao. A resolucao e puramente de leitura
(stat de diretorio), sem efeito colateral no filesystem — compativel com
Edge Case "plugin-remove durante pipeline rodando" (skills ja resolvidas
em contexto nao sao interrompidas).

**Evidencia empirica** (padrao de resolucao de helper ja existe no toolkit):
o read-back loop recuperou `_st_resolve_repo_root` usando `CSTK_LIB` quando
sourced (cstk/show-tips/onda-008) — mesmo padrao de "resolver caminho de
recurso por variavel/ordem de busca". Reaproveitamos a convencao.

**Alternatives considered**:
- Variavel `CSTK_SKILLS_PATH` estilo `$PATH` (lista `:`-separada) — mais
  generico mas over-engineering para MVP (um unico plugin ativo por
  invocacao via `--llm`). Anotado como extensao futura se houver demanda por
  multiplos plugins simultaneos.
- Override por env apenas — REJEITADA: a resolucao precisa de fallback
  granular POR SKILL (plugin cobre `specify`, mas nao `plan` → plan vem do
  core). Uma unica env de path raiz nao da fallback granular.

## Decision 5: Registry de plugins instalados

**Decision**: `~/.claude/cstk/plugins/registry.json` — indice leve JSON
mantido por `plugin-common.sh`. Um objeto por plugin: `name`, `version`,
`type`, `installed_at`, `bundle_sha256` (o checksum verificado no install).
`plugin-list` le o registry (rapido, SC-004 <2s) e SO re-verifica integridade
on-demand (`--verify` flag). `jq` e a dep para manipular o registry, sob o
carve-out 1.1.0 (confinado a `plugin-common.sh`, fallback documentado).

**Rationale**: SC-004 exige `plugin-list` <2s independente do numero de
plugins — re-hashear todos os bundles a cada list violaria isso. O registry
cacheia o `bundle_sha256` verificado; `plugin-list` mostra `ok` do cache e
`tampered` so quando `--verify` re-hashea e diverge. SC-006 (offline list)
satisfeito: ler registry.json e re-hashear sao ambos locais.

**Constitution note (carve-out jq, condicoes a/b/c)**:
- (a) **Opcional + fallback graceful**: se `jq` ausente, `plugin-common.sh`
  cai num parser POSIX `sh`+`grep`/`sed` minimo para os 5 campos do registry
  (formato JSON flat, sem aninhamento profundo). O fallback e testado.
- (b) **Confinado a UM arquivo**: todas as chamadas `jq` vivem em
  `cli/lib/plugin-common.sh`. `grep -n jq cli/lib/plugin-*.sh` casa so esse
  arquivo. Precedente: `cli/lib/hooks.sh` (carve-out original 1.1.0).
- (c) **Declarada na doc da feature**: este research.md + plan.md §Constitution
  Check documentam a dep, o arquivo confinado e o fallback.

**Evidencia empirica** (precedente do carve-out):
```
$ grep -rn "jq" docs/constitution.md
102: Primeiro caso concreto: dep opcional em jq em cli/lib/hooks.sh ... amendment 1.1.0
```

**Alternatives considered**:
- Registry em formato POSIX key=value (sem jq) — viavel e seria zero-dep, mas
  representar a lista `skills[]` do manifest em key=value flat e desajeitado.
  Manter o REGISTRY em key=value e o MANIFEST em JSON (o manifest e produzido
  pelo autor do plugin, fora do nosso controle de formato) bifurca formatos.
  Decisao: JSON em ambos, com jq sob carve-out + fallback POSIX.
- Sem registry (re-scan de diretorios a cada list) — REJEITADA: viola SC-004
  quando ha muitos plugins e re-hash for default.

## Decision 6: Schema versioning e forward-compat do manifest

**Decision**: `schema_version` inteiro (comeca em `1`). O toolkit declara o
maior `schema_version` que entende (constante `PLUGIN_SCHEMA_MAX=1`). Manifest
com `schema_version > PLUGIN_SCHEMA_MAX` → rejeitado com "unsupported manifest
version, update the toolkit" (Edge Case). `schema_version` MENOR e aceito
(retro-compat).

**Rationale**: Cobre o Edge Case "manifest declara schema que o toolkit nao
entende". Inteiro monotonico e mais simples que SemVer para schema interno;
a regra "maior que o que entendo = rejeita" e deterministica.

**Alternatives considered**:
- SemVer no schema_version — over-engineering; o schema do manifest evolui
  raramente e linearmente.
- Sem schema_version — REJEITADA: FR-003 lista `schema_version` como campo
  obrigatorio; sem ele nao ha forward-compat e o Edge Case fica sem solucao.
