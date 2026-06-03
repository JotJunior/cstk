# Third-Party Notices & Acknowledgments

`cstk` é distribuído sob a licença MIT (ver [LICENSE](./LICENSE)). Este arquivo
reconhece trabalhos de terceiros que inspiraram ou foram parcialmente adaptados
neste toolkit, e reproduz os avisos de licença exigidos.

O agrupamento abaixo é por **nível de obrigação**: obrigatório (a licença exige
preservar o aviso), cortesia (inspiração conceitual, sem exigência legal) e
referências factuais (padrões públicos citados, sem reprodução de texto
protegido).

---

## 1. Obrigatório — código/templates adaptados

### GitHub Spec Kit

Partes do pipeline de Spec-Driven Development deste toolkit — o vocabulário de
etapas (`constitution` → `specify` → `clarify` → `plan` → `tasks` → `analyze`) e,
em particular, o **template de constituição** em
`global/skills/constitution/templates/constitution.md` (estrutura
`## Core Principles` / `### [PRINCIPLE_N_NAME]`, rodapé
`**Version** | **Ratified** | **Last Amended**`, marcadores `[NEEDS CLARIFICATION]`
e "Sync Impact Report") — são **adaptados** do projeto **GitHub Spec Kit**.

- Projeto: <https://github.com/github/spec-kit>
- Licença: MIT

```
MIT License

Copyright (c) GitHub, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

> **Nota de manutenção:** o bloco acima é o texto MIT padrão com o titular
> ("GitHub, Inc.") — confirme o ano e o texto exato no arquivo `LICENSE` do
> repositório upstream e cole-o aqui literalmente se divergir.

---

## 2. Cortesia — inspiração conceitual (sem exigência legal)

Estes projetos influenciaram o **design** de skills/convenções, sem reprodução
de código ou texto. O reconhecimento é por boa-fé, não por obrigação de licença.

- **obra/superpowers** (Jesse Vincent) — <https://github.com/obra/superpowers> —
  inspirou padrões de `description`/anti-atalho e estrutura de skills. Licença MIT.
- **Anthropic Claude Code** — convenções de scaffolding de skills, commands e
  agents (formato `SKILL.md`, frontmatter, triggers). Documentação pública.
- O framework de prompt "Subject-Context-Style" da skill `image-generation`
  segue o guia público de prompting do Google Imagen.

---

## 3. Referências factuais — padrões públicos citados

A skill `owasp-security` **não reproduz texto protegido** desses padrões: usa
nomes de categorias e rankings (fatos) com prosa e exemplos de código próprios,
e já cita cada fonte nas seções `## Sources` dos arquivos de referência. Listados
aqui por transparência:

- OWASP Top 10:2025, API Security Top 10:2023, CI/CD Top 10, ASVS 5.0, Top 10 for
  LLM Applications 2025, Top 10 for Agentic Applications 2026, Mobile/Kubernetes/
  Docker Top 10 — © OWASP Foundation (conteúdo original sob CC BY-SA; aqui apenas
  taxonomias factuais são referenciadas).
- MITRE CWE Top 25:2025 · NIST SP 800-63B-4, FIPS 203/204/205, IR 8547 ·
  IETF OAuth 2.1, RFC 9449/9126/9101 · W3C WebAuthn L3 · OpenID FAPI 2.0 ·
  Cloud Security Alliance MAESTRO · EU AI Act.

---

*Encontrou uma atribuição faltante ou incorreta? Abra uma issue — corrigimos.*
