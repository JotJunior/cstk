# Referencia de fase: constitution (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

   ### 5.b Constitution (pre-flight de conflito raiz-vs-feature)

   ANTES de invocar a skill `constitution`:

   ```bash
   pipeline.sh constitution-conflict \
     --projeto-alvo-path <PAP> \
     --feature-dir <FD>
   ```

   Tabela de tratamento:

   | Exit | Significado | Acao do orquestrador |
   |------|-------------|----------------------|
   | 0 | sem conflito OU coordenado | invoque `Skill(skill="constitution")` normalmente |
   | 1 | conflito real (ambos existem, feature nao referencia raiz) | NAO invoque skill — registre Decisao + tente Edit para adicionar header `Predecessor:` OU emita BloqueioHumano para operador decidir |
   | 2 | alerta pre-skill (raiz existe, feature nao criada) | OBRIGATORIO: emita BloqueioHumano com 3 opcoes (a) atualizar global via bump SemVer (b) criar feature-delta com Sync Impact Report (c) abortar. NAO invoque skill sem resposta humana. |

   Padrao do BloqueioHumano para exit=2 (use `bloqueios.sh register`):

   - **Pergunta**: "Detectei docs/constitution.md global v<X.Y.Z>. Como
     tratar a constitution desta feature?"
   - **Opcoes recomendadas**: `["atualizar-global-via-bump-SemVer",
     "criar-feature-delta-com-sync-impact-report", "abortar-feature-sem-principios-proprios"]`
   - **Contexto para humano**: paths dos 2 candidatos + 3 linhas
     resumindo principios da raiz + lista dos principios candidatos a
     adicionar/especializar.

   Apos resposta humana, registre Decisao + invoque skill (ou nao, se
   `abortar`). **OBRIGATORIO antes de invocar `Skill(constitution)`:**
   confirme que o BloqueioHumano foi respondido com resposta autorizadora
   via primitiva de enforcement:

   ```bash
   pipeline.sh require-blockade-resolved \
     --state-dir <SD> --etapa constitution
   ```

   Exit codes:
   - `0` = bloqueio respondido com `atualizar-global-via-bump-SemVer` ou
     `criar-feature-delta-com-sync-impact-report` — skill pode ser invocada.
   - `1` = ausencia de decisao pre-flight, bloqueio nao registrado, ainda
     aguardando humano, OU humano escolheu `abortar`. **NAO invoque
     `Skill(constitution)`** — registre Decisao informativa explicando o
     bloqueio e siga para a proxima etapa (ou abortar feature).

   Razao (exec-2026-05-19 dec-004 do projeto github-pages-cstk-manual):
   orquestrador detectou exit=2 corretamente, listou as 3 opcoes corretas
   em `--opcoes`, mas decidiu sozinho em "Auto Mode" com `--score 2` e
   invocou a skill sem aguardar resposta humana. As travas em
   `state-decisions.sh register` (rejeita score!=0 quando as 3 opcoes
   canonicas estao presentes) e `pipeline.sh require-blockade-resolved`
   (verifica FK decisao→bloqueio + status respondido + resposta
   autorizadora) fecham esse caminho no runtime.

   Apos invocacao bem-sucedida:

   ```bash
   state-ondas.sh record-skill --state-dir <SD> --skill constitution \
     --decisao-id <dec-NNN>
   ```

<!-- ORCH-REF-END -->
