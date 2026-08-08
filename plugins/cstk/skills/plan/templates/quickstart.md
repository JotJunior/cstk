# Quickstart: [FEATURE]

Cenarios de teste que validam a implementacao end-to-end. Um cenario por fluxo
critico (happy path + pelo menos um error case).

## Scenario 1: [Happy Path]

1. [Passo]
2. [Passo]
3. **Expected**: [Resultado]

## Scenario 2: [Error Case]

1. [Passo]
2. **Expected**: [Erro esperado]

## Scenario 3: Roundtrip End-to-End (obrigatorio para features com borda backend↔frontend)

Cenario que valida que o payload REAL do backend casa com o contrato
declarado em `contracts/*.md` e com o tipo consumido pelo frontend.
NAO use mock/fixture — chame o backend de verdade.

1. Subir backend localmente (ex: `npm run dev` ou `make run`)
2. Fazer requisicao real ao endpoint critico (ex: `curl -s
   http://localhost:3000/api/foo`)
3. Capturar payload e comparar shape contra o contrato:
   - Nomes de campo (case style — camelCase? snake_case?)
   - Tipos (string vs number vs boolean — sem coercao silenciosa)
   - Enums (valores literais batem com `z.enum().options` do shared-types?)
4. Frontend consome o mesmo payload e parseia com Zod sem erros
5. **Expected**: zero divergencia entre payload real, contrato declarado
   e tipo TS no frontend. Drift detectado AQUI evita 40 ondas de retrabalho
   tardio.

> **Por que esse cenario e obrigatorio**: a execucao-fonte do agente-00c
> (60 ondas, 224 decisoes) descobriu na onda-040 (FASE 8) uma divergencia
> snake_case vs camelCase que existia desde o contrato inicial (onda-014,
> dec-064). 40 ondas de testes verdes parsearam apenas mocks, mascarando
> o drift real. Roundtrip empirico catch o drift na primeira execucao.
