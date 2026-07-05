# UX Checklist: Show Tips

**Purpose**: Quality gate de UX/apresentacao — valida clareza, completude e consistencia
dos requisitos de experiencia do usuario e formato visual da feature `show-tips`.
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md)

---

## Hierarquia Visual e Formatacao

- [ ] CHK039 - Os requisitos de destaque visual do tip block (FR-004) definem o tipo concreto de delimitador (linha `---`, prefixo `> `, caixa com `#`, ANSI escape)? [Clareza, Spec §FR-004]
- [ ] CHK040 - Ha requisito especificando o que aparece quando o bloco e renderizado em terminal sem suporte a Markdown (ex: plain text sem formatacao)? [Clareza, Gap]
- [ ] CHK041 - O formato do cabecalho do tip block esta definido? (ex: "TIP [skill-name]:", "Dica sobre skill X:", nenhum cabecalho?) [Completude, Spec §FR-004, §Key Entities - Tip Block]
- [ ] CHK042 - A ordem dos elementos no bloco (nome da skill, categoria, texto, exemplo) esta especificada? [Completude, Spec §FR-001, §US1 cenario 1]

---

## Interacao e Invocacao

- [ ] CHK043 - O fluxo de "sob demanda" (US3) esta descrito do ponto de vista do usuario: onde e como ele aciona? (linha de comando `cstk show-tip <skill>`, slash command, outro?) [Completude, Spec §US3, §FR-009]
- [ ] CHK044 - Ha requisito definindo o comportamento quando o usuario invoca `cstk show-tip` sem argumentos: qual e a UX esperada (dica aleatoria conforme FR-010, ou help/usage)? [Clareza, Spec §FR-010, §US3 cenario 3]
- [ ] CHK045 - O feedback ao usuario quando a skill nao tem dicas (US3 cenario 2) esta descrito com o texto exato ou pelo menos com os elementos obrigatorios da mensagem? [Clareza, Spec §US3 cenario 2]

---

## Acessibilidade e Portabilidade de Terminal

- [ ] CHK046 - Os requisitos de destaque visual funcionam em terminais monocromaticos (sem ANSI colors)? Ha fallback especificado? [Acessibilidade, Gap]
- [ ] CHK047 - O comprimento maximo do bloco de exibicao esta definido? (Terminais de 80 colunas — linhas longas em exemplos podem quebrar a leitura) [Acessibilidade, Gap]
- [ ] CHK048 - Caracteres especiais no `text` e nos `examples` do catalogo (backticks, asteriscos, pipes) estao cobertos por requisito de escape/renderizacao? [Acessibilidade, Spec §Edge Cases]

---

## Consistencia de UX entre Modos

- [ ] CHK049 - O bloco de tip exibido automaticamente (US1) e o exibido sob demanda (US3) tem o mesmo formato visual? Ou ha diferenca intencional? Isso esta especificado? [Consistencia, Spec §US1, §US3]
- [ ] CHK050 - A "mensagem amigavel" de skill-nao-encontrada (US3 cenario 2) esta definida no mesmo nivel de detalhe do bloco de tip valido? [Consistencia, Spec §US3 cenario 2]

---

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente (continua de CHK038 do requirements.md)
- `[Gap]` = aspecto nao coberto pela spec atual
- Rastreabilidade: 12/12 items (100%) referenciam spec ou marcador de qualidade
