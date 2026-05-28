"""
gen_pages.py — Hook MkDocs (mkdocs-gen-files) que enumera fontes canonicas
do toolkit `cstk` e gera shims virtuais "--8<--" para cada
skill/agent/command, SEM duplicar conteudo (alinhado com Principio D-I:
Zero Duplicacao).

Categorias geradas (paths virtuais sob `docs-site/`):

  - `skills/<slug>.md`          <- global/skills/<slug>/SKILL.md
  - `skills/<lang>/<slug>.md`   <- language-related/<lang>/skills/<slug>/SKILL.md
  - `agents/<stem>.md`          <- global/agents/<stem>.md
  - `commands/<stem>.md`        <- global/commands/<stem>.md
  - `skills/index.md`           <- index agrupado (global / go / dotnet)
  - `agents/index.md`           <- index agents
  - `commands/index.md`         <- index commands

Cada pagina gerada e um shim minimo contendo apenas a diretiva snippets
`--8<--` referenciando o arquivo fonte (resolvido a partir da raiz do
repo via `base_path: ['..', 'docs-site']` no `mkdocs.yml`). Isso garante
que QUALQUER edicao em `global/skills/<X>/SKILL.md` se reflete no site
sem mudanca aqui.

Pass-through de frontmatter Claude (FR-024):
  Os arquivos fonte usam frontmatter YAML com chaves Claude-especificas
  (`name`, `description`, `allowed-tools`, `argument-hint`,
  `model`). MkDocs/Material parseia esse YAML como front-matter e
  ignora chaves desconhecidas — sem reescrita aqui. Se YAML estiver
  malformado, o build falha em `--strict` (intencional, conforme
  FR-011).

Edit links (FR-017):
  Para cada pagina virtual, `mkdocs_gen_files.set_edit_path(virtual,
  source)` aponta o botao "Edit this page" para o `.md` fonte no
  GitHub. A API do plugin trata `source` como caminho relativo a raiz
  do repositorio quando combinado com `edit_uri` do mkdocs.yml.

Extensibilidade (D-I, FR-016):
  Para adicionar uma linguagem nova (ex: `language-related/python/`),
  basta colocar os SKILL.md no path canonico. Este hook descobre via
  glob — zero edits aqui.

Restricoes:
  - FR-018: este hook NAO instala dependencias nem faz chamadas de
    rede. Apenas le filesystem e emite paginas via mkdocs_gen_files.
  - Sem efeitos colaterais fora de `mkdocs_gen_files.open(...)`.

Execucao:
  MkDocs invoca este hook automaticamente quando o plugin `gen-files`
  esta configurado (ver `mkdocs.yml`). Nao deve ser executado
  diretamente — `python gen_pages.py` falha por falta de contexto
  MkDocs (esperado).

Referencias:
  - spec.md FR-003, FR-004, FR-010, FR-016, FR-017, FR-024
  - plan.md Decision 1 (mkdocs-gen-files), Decision 4 (pass-through)
  - tasks.md FASE 2 (T-2.1 a T-2.5)
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterator

import mkdocs_gen_files

# ---------------------------------------------------------------------------
# Constantes de caminho
# ---------------------------------------------------------------------------

# Este arquivo vive em <REPO_ROOT>/docs-site/hooks/gen_pages.py.
# parents[0] = hooks/, parents[1] = docs-site/, parents[2] = repo root.
REPO_ROOT: Path = Path(__file__).resolve().parents[2]

GLOBAL_SKILLS_DIR: Path = REPO_ROOT / "global" / "skills"
GLOBAL_AGENTS_DIR: Path = REPO_ROOT / "global" / "agents"
GLOBAL_COMMANDS_DIR: Path = REPO_ROOT / "global" / "commands"
LANG_RELATED_DIR: Path = REPO_ROOT / "language-related"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _rel_to_repo(path: Path) -> str:
    """Retorna `path` relativo a REPO_ROOT como string POSIX."""
    return path.relative_to(REPO_ROOT).as_posix()


def _emit_passthrough_page(virtual_path: str, source_md: Path) -> None:
    """Gera uma pagina virtual `virtual_path` em docs-site/ contendo apenas
    a diretiva snippets `--8<--` que inclui o `source_md` literalmente.

    O `source_md` e referenciado por caminho relativo a raiz do repo
    porque `mkdocs.yml` configura `pymdownx.snippets.base_path` com a
    raiz do repositorio (alem de docs-site/).

    Tambem registra o edit-path (FR-017) para que o botao "Edit this
    page" no tema Material aponte para o arquivo fonte no GitHub.
    """
    source_rel = _rel_to_repo(source_md)

    # Conteudo do shim: apenas a diretiva snippets, sem narrativa.
    # Principio D-I: zero duplicacao. A pagina renderizada e exatamente
    # o conteudo de source_md, processado pela toolchain MkDocs.
    shim_body = f'--8<-- "{source_rel}"\n'

    with mkdocs_gen_files.open(virtual_path, "w") as fd:
        fd.write(shim_body)

    # set_edit_path aceita o caminho relativo ao repo root quando
    # combinado com edit_uri do mkdocs.yml.
    mkdocs_gen_files.set_edit_path(virtual_path, source_rel)


_DESCRIPTION_MAX_CHARS: int = 200


def _extract_description(md_path: Path) -> str:
    """Extrai descricao curta de um arquivo Markdown com frontmatter YAML
    Claude-especifico.

    Estrategia (alinhada com spec §Key Entities — Page.descricao_curta):

    1. Se houver frontmatter YAML delimitado por `---`, procurar chave
       `description:` (single ou multi-line dobrado).
    2. Fallback: primeira frase do body apos h1 ou apos frontmatter,
       cortada em `_DESCRIPTION_MAX_CHARS`.
    3. Robusto a YAML malformado — captura excecoes e retorna fallback
       vazio sem quebrar build (FR-018: pass-through nao bloqueia).

    Esta funcao NAO usa o modulo `yaml` (evita dependencia opcional do
    PyYAML — `mkdocs` ja o traz, mas mantemos parser simples e robusto).
    """
    try:
        text = md_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""

    lines = text.splitlines()
    body_start = 0

    # Tentar extrair frontmatter
    if lines and lines[0].strip() == "---":
        # Procurar fechamento
        for idx in range(1, len(lines)):
            if lines[idx].strip() == "---":
                # Parse simples chave: valor dentro do frontmatter
                fm_lines = lines[1:idx]
                body_start = idx + 1
                desc = _parse_description_from_frontmatter(fm_lines)
                if desc:
                    return _truncate(desc, _DESCRIPTION_MAX_CHARS)
                break

    # Fallback: primeira frase nao-vazia do body apos h1
    for raw in lines[body_start:]:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            continue
        # Primeira frase: cortar em ponto-final ou na linha inteira
        candidate = line.split(". ")[0]
        return _truncate(candidate, _DESCRIPTION_MAX_CHARS)

    return ""


def _parse_description_from_frontmatter(fm_lines: list[str]) -> str:
    """Parse minimalista de `description:` em YAML frontmatter.

    Suporta:
      - `description: texto inline`
      - `description: "texto com aspas duplas"`
      - `description: 'texto com aspas simples'`
      - `description: |` ou `description: >` seguido de indentado (multi-line)
    """
    in_block = False
    block_indent = -1
    block_buf: list[str] = []
    for raw in fm_lines:
        if not in_block:
            stripped = raw.strip()
            if not stripped.lower().startswith("description:"):
                continue
            value = stripped[len("description:"):].strip()
            # Multi-line scalar?
            if value in ("|", ">", "|-", ">-", "|+", ">+"):
                in_block = True
                block_indent = -1
                continue
            # Single-line: remover aspas se presente
            return _strip_quotes(value)
        else:
            # Bloco multi-line: linhas com indent maior que zero
            if not raw.strip():
                if block_buf:
                    block_buf.append("")
                continue
            # Calcular indent da primeira linha do bloco
            stripped = raw.lstrip()
            indent = len(raw) - len(stripped)
            if block_indent < 0:
                block_indent = indent
            if indent < block_indent:
                # Saiu do bloco
                break
            block_buf.append(stripped)
    if block_buf:
        return " ".join(b for b in block_buf if b)
    return ""


def _strip_quotes(s: str) -> str:
    """Remove aspas duplas/simples envolventes de um valor YAML inline."""
    if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
        return s[1:-1]
    return s


def _truncate(s: str, max_chars: int) -> str:
    """Trunca string com reticencias unicode se exceder max_chars."""
    s = s.strip()
    if len(s) <= max_chars:
        return s
    return s[: max_chars - 1].rstrip() + "..."


def _iter_skill_dirs(base_dir: Path) -> Iterator[Path]:
    """Itera diretorios filhos de `base_dir` que contem `SKILL.md`.

    Edge case (spec §Edge Cases): diretorios sem SKILL.md sao
    silenciosamente pulados (ex: skill em scaffolding, dir vazio).
    """
    if not base_dir.is_dir():
        return
    for child in sorted(base_dir.iterdir()):
        if not child.is_dir():
            continue
        skill_md = child / "SKILL.md"
        if skill_md.is_file():
            yield skill_md


# ---------------------------------------------------------------------------
# Geradores por categoria
# ---------------------------------------------------------------------------


def gen_skill_pages_global() -> int:
    """Gera paginas virtuais para skills globais.

    Fonte: `global/skills/<slug>/SKILL.md`
    Destino: `skills/<slug>.md` (sob docs-site/)
    """
    count = 0
    for skill_md in _iter_skill_dirs(GLOBAL_SKILLS_DIR):
        slug = skill_md.parent.name
        virtual_path = f"skills/{slug}.md"
        _emit_passthrough_page(virtual_path, skill_md)
        count += 1
    return count


def gen_skill_pages_lang() -> dict[str, int]:
    """Gera paginas virtuais para skills por linguagem.

    Fonte: `language-related/<lang>/skills/<slug>/SKILL.md`
    Destino: `skills/<lang>/<slug>.md`

    Descoberto via glob — adicionar `language-related/python/skills/`
    funciona sem edits aqui (FR-016, D-I).
    """
    counts: dict[str, int] = {}
    if not LANG_RELATED_DIR.is_dir():
        return counts

    for lang_dir in sorted(LANG_RELATED_DIR.iterdir()):
        if not lang_dir.is_dir():
            continue
        lang = lang_dir.name
        skills_base = lang_dir / "skills"
        if not skills_base.is_dir():
            continue

        lang_count = 0
        for skill_md in _iter_skill_dirs(skills_base):
            slug = skill_md.parent.name
            virtual_path = f"skills/{lang}/{slug}.md"
            _emit_passthrough_page(virtual_path, skill_md)
            lang_count += 1
        if lang_count > 0:
            counts[lang] = lang_count
    return counts


def gen_agent_pages() -> int:
    """Gera paginas virtuais para agents.

    Fonte: `global/agents/<stem>.md`
    Destino: `agents/<stem>.md`
    """
    if not GLOBAL_AGENTS_DIR.is_dir():
        return 0

    count = 0
    for md_file in sorted(GLOBAL_AGENTS_DIR.glob("*.md")):
        if not md_file.is_file():
            continue
        stem = md_file.stem
        virtual_path = f"agents/{stem}.md"
        _emit_passthrough_page(virtual_path, md_file)
        count += 1
    return count


def gen_command_pages() -> int:
    """Gera paginas virtuais para slash commands.

    Fonte: `global/commands/<stem>.md`
    Destino: `commands/<stem>.md`
    """
    if not GLOBAL_COMMANDS_DIR.is_dir():
        return 0

    count = 0
    for md_file in sorted(GLOBAL_COMMANDS_DIR.glob("*.md")):
        if not md_file.is_file():
            continue
        stem = md_file.stem
        virtual_path = f"commands/{stem}.md"
        _emit_passthrough_page(virtual_path, md_file)
        count += 1
    return count


# ---------------------------------------------------------------------------
# Geradores de paginas-index (catalogos)
# ---------------------------------------------------------------------------


def _format_index_item(name: str, link: str, description: str) -> str:
    """Formata uma linha de item de index como `- [nome](link) — descricao`.

    Se a descricao estiver vazia, omite o em-dash (sem linha tracejada
    pendurada — limpa visualmente).
    """
    if description:
        return f"- [`{name}`]({link}) — {description}"
    return f"- [`{name}`]({link})"


def gen_skill_index() -> int:
    """Gera `skills/index.md` virtual agrupado por origem.

    Secoes:
      - Skills Globais (global/skills/<slug>/SKILL.md)
      - Skills Go (language-related/go/skills/<slug>/SKILL.md)
      - Skills Dotnet (language-related/dotnet/skills/<slug>/SKILL.md)
      - (descobre dinamicamente novas linguagens via iterdir)

    Cada item linka para a pagina-detalhe correspondente (`/skills/<slug>/`
    ou `/skills/<lang>/<slug>/`) e mostra descricao curta extraida do
    frontmatter `description:`.

    Retorna numero total de itens listados (auditavel em CI).
    """
    sections: list[tuple[str, list[tuple[str, str, str]]]] = []

    # Skills globais
    global_items: list[tuple[str, str, str]] = []
    for skill_md in _iter_skill_dirs(GLOBAL_SKILLS_DIR):
        slug = skill_md.parent.name
        link = f"./{slug}.md"  # link relativo dentro de skills/
        desc = _extract_description(skill_md)
        global_items.append((slug, link, desc))
    if global_items:
        sections.append(("Skills Globais", global_items))

    # Skills por linguagem (descoberta dinamica)
    if LANG_RELATED_DIR.is_dir():
        for lang_dir in sorted(LANG_RELATED_DIR.iterdir()):
            if not lang_dir.is_dir():
                continue
            skills_base = lang_dir / "skills"
            if not skills_base.is_dir():
                continue
            lang_items: list[tuple[str, str, str]] = []
            for skill_md in _iter_skill_dirs(skills_base):
                slug = skill_md.parent.name
                link = f"./{lang_dir.name}/{slug}.md"
                desc = _extract_description(skill_md)
                lang_items.append((slug, link, desc))
            if lang_items:
                # Titulo capitalizado: "Skills Go", "Skills Dotnet"
                title = f"Skills {lang_dir.name.capitalize()}"
                sections.append((title, lang_items))

    # Renderizar markdown
    lines: list[str] = [
        "---",
        'title: "Skills"',
        'description: "Catalogo de skills disponiveis no toolkit."',
        "---",
        "",
        "# Skills",
        "",
        (
            "Lista de **skills** que voce pode invocar via tool Skill ou citar "
            "explicitamente no contexto do Claude Code. Cada skill encapsula um "
            "padrao operacional reutilizavel — workflow, validador, gerador."
        ),
        "",
    ]

    total = 0
    for title, items in sections:
        items_sorted = sorted(items, key=lambda x: x[0].lower())
        lines.append(f"## {title} ({len(items_sorted)})")
        lines.append("")
        for name, link, desc in items_sorted:
            lines.append(_format_index_item(name, link, desc))
        lines.append("")
        total += len(items_sorted)

    body = "\n".join(lines)
    with mkdocs_gen_files.open("skills/index.md", "w") as fd:
        fd.write(body)
    return total


def gen_agent_index() -> int:
    """Gera `agents/index.md` virtual com listagem alfabetica.

    Lista todos os arquivos `global/agents/*.md`, com descricao curta
    extraida do frontmatter `description:`.

    Retorna numero de itens listados.
    """
    items: list[tuple[str, str, str]] = []
    if GLOBAL_AGENTS_DIR.is_dir():
        for md_file in sorted(GLOBAL_AGENTS_DIR.glob("*.md")):
            if not md_file.is_file():
                continue
            stem = md_file.stem
            link = f"./{stem}.md"
            desc = _extract_description(md_file)
            items.append((stem, link, desc))

    lines: list[str] = [
        "---",
        'title: "Agents"',
        'description: "Catalogo de agentes customizados (sub-agents)."',
        "---",
        "",
        "# Agents",
        "",
        (
            "Lista de **agents** (sub-agents) customizados — invocados via tool "
            "Agent com `subagent_type` correspondente. Cada agent tem um perfil "
            "proprio de tools, contexto e responsabilidades."
        ),
        "",
        f"## Disponiveis ({len(items)})",
        "",
    ]
    items_sorted = sorted(items, key=lambda x: x[0].lower())
    for name, link, desc in items_sorted:
        lines.append(_format_index_item(name, link, desc))
    lines.append("")

    body = "\n".join(lines)
    with mkdocs_gen_files.open("agents/index.md", "w") as fd:
        fd.write(body)
    return len(items_sorted)


def gen_command_index() -> int:
    """Gera `commands/index.md` virtual com listagem alfabetica.

    Lista todos os arquivos `global/commands/*.md`, com descricao curta
    extraida do frontmatter `description:`.

    Retorna numero de itens listados.
    """
    items: list[tuple[str, str, str]] = []
    if GLOBAL_COMMANDS_DIR.is_dir():
        for md_file in sorted(GLOBAL_COMMANDS_DIR.glob("*.md")):
            if not md_file.is_file():
                continue
            stem = md_file.stem
            link = f"./{stem}.md"
            desc = _extract_description(md_file)
            items.append((stem, link, desc))

    lines: list[str] = [
        "---",
        'title: "Commands"',
        'description: "Catalogo de slash commands disponiveis."',
        "---",
        "",
        "# Commands",
        "",
        (
            "Lista de **slash commands** (`/comando`) disponiveis. Cada comando "
            "instala-se em `~/.claude/commands/` e expoe um fluxo nomeado para "
            "uso direto no Claude Code."
        ),
        "",
        f"## Disponiveis ({len(items)})",
        "",
    ]
    items_sorted = sorted(items, key=lambda x: x[0].lower())
    for name, link, desc in items_sorted:
        lines.append(_format_index_item(name, link, desc))
    lines.append("")

    body = "\n".join(lines)
    with mkdocs_gen_files.open("commands/index.md", "w") as fd:
        fd.write(body)
    return len(items_sorted)


# ---------------------------------------------------------------------------
# Entry point (executado pelo plugin mkdocs-gen-files em build time)
# ---------------------------------------------------------------------------


def main() -> None:
    """Orquestra a geracao de todas as categorias.

    Imprime um resumo em stdout que aparece no log do `mkdocs build`
    (util para auditoria do que foi gerado em CI).

    Ordem: paginas-detalhe primeiro (FASE 2), depois index pages (FASE 3).
    """
    # FASE 2 — paginas-detalhe (passthrough)
    n_global = gen_skill_pages_global()
    n_lang = gen_skill_pages_lang()
    n_agents = gen_agent_pages()
    n_commands = gen_command_pages()

    total_lang = sum(n_lang.values())
    detail_total = n_global + total_lang + n_agents + n_commands

    # FASE 3 — paginas-index (catalogos)
    n_skill_idx = gen_skill_index()
    n_agent_idx = gen_agent_index()
    n_cmd_idx = gen_command_index()

    # Log resumo (visivel em mkdocs build verbose).
    lang_summary = ", ".join(f"{k}={v}" for k, v in sorted(n_lang.items())) or "(none)"
    print(
        f"[gen_pages] generated {detail_total} detail pages + 3 indexes: "
        f"skills_global={n_global}, skills_lang=[{lang_summary}], "
        f"agents={n_agents}, commands={n_commands}; "
        f"index_items: skills={n_skill_idx}, agents={n_agent_idx}, commands={n_cmd_idx}"
    )


# mkdocs-gen-files executa o modulo top-level a cada build.
main()
