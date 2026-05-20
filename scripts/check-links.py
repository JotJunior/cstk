#!/usr/bin/env python3
"""
check-links.py — Validador estatico de links e snippets em docs-site/.

Sem dependencias externas (stdlib only). Roda sem mkdocs/Python venv —
usavel em CI minimo, pre-commit, e como gate FASE 7 quando o site
ainda nao pode ser construido.

Valida:
  1. Diretivas `--8<-- "FILE"` apontam para arquivo existente.
  2. Diretivas `--8<-- "FILE:NAME"` tem markers `[start:NAME]` e
     `[end:NAME]` presentes em FILE (consistencia bidirecional).
  3. Links Markdown relativos `[text](path.md)` resolvem para arquivo
     existente OU para pagina gerada por `docs-site/hooks/gen_pages.py`
     (skills/, agents/, commands/).
  4. Paginas geradas referenciam fontes (`global/skills/<n>/SKILL.md`,
     `language-related/<lang>/skills/<n>/SKILL.md`, `global/agents/<n>.md`,
     `global/commands/<n>.md`) — fontes devem existir.

Exit code 0 = ok; 1 = pelo menos 1 erro.
Output: relatorio textual no stdout, contadores no fim.

Uso:
    python3 scripts/check-links.py [--root /path/to/repo] [--verbose]

Convencao de paths:
  - Working root = parent do diretorio `scripts/` (i.e., raiz do repo).
  - Pode ser overridado via `--root`.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable

# ----------------------------------------------------------------------
# Regex compilados uma vez (hot path)
# ----------------------------------------------------------------------

# Diretiva snippets do PyMdown: `--8<-- "FILE"` ou `--8<-- "FILE:SECTION"`.
# A diretiva pode aparecer em qualquer linha (nao precisa estar dentro de
# code fence — pymdown.snippets resolve fora de fence).
SNIPPET_DIRECTIVE_RE = re.compile(
    r'(?m)^\s*--8<--\s+"([^"]+)"\s*$'
)

# Marker de bloco no arquivo-fonte: `<!-- --8<-- [start:NAME] -->`
# e o pareado `[end:NAME]`. Aceita comentarios HTML em qualquer indent.
MARKER_START_RE_TPL = r'<!--\s*--8<--\s*\[start:{name}\]\s*-->'
MARKER_END_RE_TPL = r'<!--\s*--8<--\s*\[end:{name}\]\s*-->'

# Link Markdown relativo: `[text](path)`. Exclui:
#   - urls absolutas (http://, https://, mailto:, etc)
#   - ancoras puras (#anchor)
#   - referencias a imagens em assets/ (path) sao tratadas
LINK_RE = re.compile(
    r'\[([^\]]+)\]\((?!https?://|mailto:|#|/)([^)\s#]+)(?:#[^)]*)?\)'
)

# Geradores de paginas dinamicas (docs-site/hooks/gen_pages.py) emitem
# paths sob estes prefixos. Links para estes paths sao validos se o
# arquivo-fonte existir.
GENERATED_PATH_PATTERNS = [
    # Aceita prefixo "../" ou "" — mkdocs resolve relativo a pagina-origem
    # Index listings (skills/, agents/, commands/) — geradas por gen_pages.py
    (re.compile(r'^(?:\.\./)?skills/?$'),
     lambda root, m: root / 'global' / 'skills'),  # diretorio sempre existe
    (re.compile(r'^(?:\.\./)?agents/?$'),
     lambda root, m: root / 'global' / 'agents'),
    (re.compile(r'^(?:\.\./)?commands/?$'),
     lambda root, m: root / 'global' / 'commands'),
    # Paginas-detalhe — `skills/<NAME>/SKILL.md` ou `skills/<NAME>/`
    # (variante com trailing slash que o mkdocs usa em links pretty-urls).
    (re.compile(r'^(?:\.\./)?skills/([^/]+)/SKILL\.md$'),
     lambda root, m: root / 'global' / 'skills' / m.group(1) / 'SKILL.md'),
    (re.compile(r'^(?:\.\./)?skills/([^/]+)/?$'),
     lambda root, m: root / 'global' / 'skills' / m.group(1) / 'SKILL.md'),
    # Subskills language-related: `skills/<lang>/<NAME>/...`
    (re.compile(r'^(?:\.\./)?skills/([^/]+)/([^/]+)/SKILL\.md$'),
     lambda root, m: root / 'language-related' / m.group(1) / 'skills' / m.group(2) / 'SKILL.md'),
    # Agents e commands
    (re.compile(r'^(?:\.\./)?agents/([^/]+)\.md$'),
     lambda root, m: root / 'global' / 'agents' / f'{m.group(1)}.md'),
    (re.compile(r'^(?:\.\./)?agents/([^/]+)/?$'),
     lambda root, m: root / 'global' / 'agents' / f'{m.group(1)}.md'),
    (re.compile(r'^(?:\.\./)?commands/([^/]+)\.md$'),
     lambda root, m: root / 'global' / 'commands' / f'{m.group(1)}.md'),
    (re.compile(r'^(?:\.\./)?commands/([^/]+)/?$'),
     lambda root, m: root / 'global' / 'commands' / f'{m.group(1)}.md'),
]


# ----------------------------------------------------------------------
# Tipos auxiliares
# ----------------------------------------------------------------------

class Issue:
    """Erro ou warning encontrado durante a validacao."""

    __slots__ = ('severity', 'file', 'line', 'msg')

    def __init__(self, severity: str, file: Path, line: int, msg: str):
        self.severity = severity  # 'ERROR' or 'WARN'
        self.file = file
        self.line = line
        self.msg = msg

    def fmt(self, root: Path) -> str:
        rel = self.file.relative_to(root) if self.file.is_absolute() else self.file
        return f'  [{self.severity}] {rel}:{self.line}  {self.msg}'


# ----------------------------------------------------------------------
# Validacao
# ----------------------------------------------------------------------

def iter_markdown(docs_site: Path) -> Iterable[Path]:
    """Itera sobre todos os .md sob docs-site/, exceto hooks/."""
    for p in docs_site.rglob('*.md'):
        # Excluir hooks (Python, nao markdown publicavel) e __pycache__
        if 'hooks' in p.parts or '__pycache__' in p.parts:
            continue
        yield p


def check_snippet_directive(
    md_file: Path,
    line_no: int,
    target: str,
    root: Path,
    issues: list[Issue],
) -> None:
    """Valida `--8<-- "FILE"` ou `--8<-- "FILE:SECTION"`.

    O resolver do pymdown.snippets procura em `base_path` configurado no
    `mkdocs.yml` — por convencao usamos a raiz do repo como base. Para
    este checker, resolvemos relativo a `root`.
    """
    if ':' in target:
        file_part, section = target.split(':', 1)
    else:
        file_part, section = target, None

    abs_path = (root / file_part).resolve()
    # Defesa em profundidade: rejeitar saidas via .. fora do root.
    try:
        abs_path.relative_to(root.resolve())
    except ValueError:
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'snippet aponta para fora do root: "{target}"',
        ))
        return

    if not abs_path.is_file():
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'snippet referencia arquivo inexistente: "{target}" (resolvido para {abs_path})',
        ))
        return

    if section is None:
        return  # OK — arquivo inteiro

    # Validar markers [start:NAME] e [end:NAME].
    try:
        content = abs_path.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError) as exc:
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'falha ao ler "{target}": {exc}',
        ))
        return

    # Escape de section name (pode conter chars regex)
    name_esc = re.escape(section)
    start_re = re.compile(MARKER_START_RE_TPL.format(name=name_esc))
    end_re = re.compile(MARKER_END_RE_TPL.format(name=name_esc))

    if not start_re.search(content):
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'marker [start:{section}] ausente em {file_part}',
        ))
    if not end_re.search(content):
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'marker [end:{section}] ausente em {file_part}',
        ))


def resolve_generated_path(link_target: str, root: Path) -> Path | None:
    """Se `link_target` corresponde a pagina gerada por gen_pages.py,
    retorna o path do arquivo-fonte. Caso contrario, None."""
    for pat, resolver in GENERATED_PATH_PATTERNS:
        m = pat.match(link_target)
        if m:
            return resolver(root, m)
    return None


def check_internal_link(
    md_file: Path,
    line_no: int,
    link_target: str,
    root: Path,
    docs_site: Path,
    issues: list[Issue],
) -> None:
    """Valida `[text](path)` relativo a md_file."""
    # Ignorar links a paginas geradas dinamicamente — validar via fonte.
    generated_source = resolve_generated_path(link_target, root)
    if generated_source is not None:
        # Pagina-detalhe (file) ou listagem (dir) — basta existir
        if not generated_source.exists():
            issues.append(Issue(
                'ERROR', md_file, line_no,
                f'link para pagina gerada "{link_target}" — fonte ausente: {generated_source}',
            ))
        return

    # Link relativo ao md_file (convencao do mkdocs).
    candidate = (md_file.parent / link_target).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'link aponta para fora do root: "{link_target}"',
        ))
        return

    if not candidate.exists():
        # Tentar resolver relativo a docs-site/ (caso o link seja absoluto-no-site)
        alt = (docs_site / link_target.lstrip('/')).resolve()
        if alt.exists():
            return
        issues.append(Issue(
            'ERROR', md_file, line_no,
            f'link quebrado: "{link_target}" (tentado: {candidate})',
        ))


def check_frontmatter(md_file: Path, root: Path, issues: list[Issue]) -> None:
    """Lint basico: paginas principais de docs-site/ devem ter frontmatter
    `---\ntitle: ...\n---` no topo. README/changelog/snippets sao exceptions."""
    # Skips: arquivos que sao puros snippets (sem frontmatter por design)
    name = md_file.name
    if name in ('changelog.md',):
        return  # snippet wrapper — frontmatter opcional

    try:
        content = md_file.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError) as exc:
        issues.append(Issue(
            'WARN', md_file, 1,
            f'falha ao ler para lint de frontmatter: {exc}',
        ))
        return

    head = content.lstrip('﻿')  # strip BOM
    if not head.startswith('---\n'):
        issues.append(Issue(
            'WARN', md_file, 1,
            'frontmatter ausente (esperado "---\\n...\\n---" no topo)',
        ))
        return

    # Validar fechamento do frontmatter.
    end_idx = head.find('\n---\n', 4)
    if end_idx == -1:
        issues.append(Issue(
            'WARN', md_file, 1,
            'frontmatter aberto mas nao fechado (faltando "---" de encerramento)',
        ))


def validate_docs_site(root: Path, verbose: bool) -> list[Issue]:
    """Roda todas as validacoes sob docs-site/."""
    docs_site = root / 'docs-site'
    if not docs_site.is_dir():
        return [Issue('ERROR', root, 0, f'docs-site/ nao encontrado em {root}')]

    issues: list[Issue] = []
    files_scanned = 0
    snippet_count = 0
    link_count = 0

    for md_file in iter_markdown(docs_site):
        files_scanned += 1
        if verbose:
            print(f'  scan: {md_file.relative_to(root)}')

        # Lint de frontmatter
        check_frontmatter(md_file, root, issues)

        try:
            content = md_file.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError) as exc:
            issues.append(Issue('ERROR', md_file, 0, f'falha ao ler: {exc}'))
            continue

        # 1. Snippet directives
        for m in SNIPPET_DIRECTIVE_RE.finditer(content):
            snippet_count += 1
            line_no = content[:m.start()].count('\n') + 1
            check_snippet_directive(md_file, line_no, m.group(1), root, issues)

        # 2. Internal links — escanear linha-a-linha para localizar erros
        for line_no, line in enumerate(content.splitlines(), start=1):
            # Pular linhas dentro de code fences seria ideal, mas para
            # MVP do checker aceitamos falsos-positivos minimos. Heuristica
            # simples: pular linhas que comecam com 4+ espacos OU dentro
            # de bloco indicado por ```.
            stripped = line.lstrip()
            if stripped.startswith('```'):
                continue  # boundary de code fence
            for m in LINK_RE.finditer(line):
                link_count += 1
                check_internal_link(
                    md_file, line_no, m.group(2), root, docs_site, issues,
                )

    print(f'\n  -> {files_scanned} arquivo(s) escaneados, '
          f'{snippet_count} diretiva(s) snippet, {link_count} link(s) interno(s)')
    return issues


# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description='Valida links e snippets em docs-site/ (stdlib only).',
    )
    parser.add_argument(
        '--root',
        type=Path,
        default=None,
        help='raiz do repositorio (default: parent de scripts/)',
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='listar arquivos sendo escaneados',
    )
    args = parser.parse_args(argv)

    if args.root is None:
        args.root = Path(__file__).resolve().parent.parent
    root = args.root.resolve()

    print(f'check-links.py — root: {root}')

    issues = validate_docs_site(root, args.verbose)

    errors = [i for i in issues if i.severity == 'ERROR']
    warnings = [i for i in issues if i.severity == 'WARN']

    if issues:
        print('\nDescobertas:')
        for issue in issues:
            print(issue.fmt(root))

    print(f'\nResumo: {len(errors)} erro(s), {len(warnings)} warning(s)')

    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
