---
name: dotnet-review-code
description: |
  Review de codigo .NET 10 analisando Clean Code, SOLID, seguranca e performance.
  Triggers: "review code", "revisar codigo", "code review", "analise de codigo".
deprecated: true
deprecated_since: "3.12.0"
remove_in: "4.0.0"
deprecated_reason: "Stack .NET descontinuada pelo mantenedor. Skill sem substituto no toolkit global."
replacement: null
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Review de Código .NET 10

Execute uma revisão de código completa analisando Clean Code, SOLID, segurança e performance.

## Argumentos

$ARGUMENTS

## Instruções

Analise o argumento fornecido. Ele pode ser:
1. **Arquivo específico**: Caminho para um arquivo .cs
2. **Diretório**: Caminho para um diretório a revisar
3. **PR/Branch**: Alterações de uma branch ou PR

### Categorias de Análise

Execute a análise nas seguintes categorias:

#### 1. Clean Code

| Aspecto | Verificar |
|---------|-----------|
| Nomes | Expressivos, sem abreviações obscuras |
| Funções | Pequenas (< 20 linhas), fazem uma coisa |
| Classes | Coesas, uma responsabilidade |
| Comentários | Apenas quando necessário |
| Formatação | Consistente com o projeto |
| DRY | Sem duplicação de lógica |

#### 2. SOLID

| Princípio | Verificar |
|-----------|-----------|
| SRP | Classe/método tem uma única responsabilidade |
| OCP | Extensível via abstrações, não modificações |
| LSP | Subtipos substituem base sem quebrar |
| ISP | Interfaces focadas, segregadas |
| DIP | Depende de abstrações, não implementações |

#### 3. Segurança (OWASP Top 10)

| Vulnerabilidade | Verificar |
|-----------------|-----------|
| Injection | SQL, Command, LDAP injection |
| XSS | Sanitização de output |
| Broken Auth | Validação de autenticação |
| Sensitive Data | Criptografia, não logar secrets |
| XXE | Processamento de XML seguro |
| Broken Access | Autorização adequada |
| Misconfiguration | Configs seguras |
| Insecure Deserialization | Deserialização segura |
| Known Vulnerabilities | Dependências atualizadas |
| Logging | Logs adequados sem dados sensíveis |

#### 4. Performance

| Aspecto | Verificar |
|---------|-----------|
| N+1 | Queries em loop |
| Async | Uso correto de async/await |
| Memory | Alocações desnecessárias, StringBuilder |
| LINQ | Materialização prematura |
| Caching | Oportunidades de cache |
| Indexes | Índices no banco de dados |

#### 5. Arquitetura Hexagonal

| Aspecto | Verificar |
|---------|-----------|
| Camadas | Separação correta |
| Dependências | Fluem para dentro |
| Domain | Sem dependências externas |
| Ports | Interfaces na Application |
| Adapters | Implementações na Infrastructure |

### Formato do Relatório

```markdown
# Code Review Report

## 📊 Summary

| Metric | Value |
|--------|-------|
| Files Reviewed | X |
| Total Issues | Y |
| 🔴 Critical | X |
| 🟠 Major | X |
| 🟡 Minor | X |
| 🔵 Suggestion | X |

---

## 🔴 Critical Issues

### [CR-001] SQL Injection Vulnerability

**File**: `src/Infrastructure/Repositories/CustomerRepository.cs:45`
**Category**: Security
**OWASP**: A03:2021 - Injection

**Problem**:
```csharp
// Linha 45
var query = $"SELECT * FROM customers WHERE name = '{name}'";
await connection.ExecuteAsync(query);
```

**Impact**: Allows attackers to execute arbitrary SQL commands.

**Solution**:
```csharp
var query = "SELECT * FROM customers WHERE name = @Name";
await connection.ExecuteAsync(query, new { Name = name });
```

---

### [CR-002] Hardcoded Credentials

**File**: `src/API/appsettings.json:12`
**Category**: Security
**OWASP**: A07:2021 - Identification and Authentication Failures

**Problem**:
```json
"ConnectionString": "Server=prod;User=admin;Password=P@ssw0rd123"
```

**Impact**: Credentials exposed in source control.

**Solution**:
Use environment variables or secret management (ETCD):
```json
"ConnectionString": "${DATABASE_CONNECTION_STRING}"
```

---

## 🟠 Major Issues

### [CR-003] Violation of DIP

**File**: `src/Application/Services/CustomerService.cs:15`
**Category**: SOLID
**Principle**: Dependency Inversion

**Problem**:
```csharp
public class CustomerService
{
    private readonly CustomerRepository _repository = new();
}
```

**Impact**: Tight coupling, hard to test.

**Solution**:
```csharp
public class CustomerService
{
    private readonly ICustomerRepository _repository;

    public CustomerService(ICustomerRepository repository)
    {
        _repository = repository;
    }
}
```

---

### [CR-004] N+1 Query Problem

**File**: `src/Infrastructure/Repositories/OrderRepository.cs:32`
**Category**: Performance

**Problem**:
```csharp
var orders = await _context.Orders.ToListAsync();
foreach (var order in orders)
{
    order.Items = await _context.OrderItems
        .Where(i => i.OrderId == order.Id)
        .ToListAsync();
}
```

**Impact**: 1 + N database queries instead of 1.

**Solution**:
```csharp
var orders = await _context.Orders
    .Include(o => o.Items)
    .ToListAsync();
```

---

## 🟡 Minor Issues

### [CR-005] Magic Number

**File**: `src/Domain/Entities/Customer.cs:28`
**Category**: Clean Code

**Problem**:
```csharp
if (name.Length > 200)
    throw new DomainException("Name too long");
```

**Solution**:
```csharp
private const int MaxNameLength = 200;

if (name.Length > MaxNameLength)
    throw new DomainException($"Name must not exceed {MaxNameLength} characters");
```

---

### [CR-006] Inconsistent Naming

**File**: `src/Application/Commands/CreateCustomer/CreateCustomerCommand.cs:8`
**Category**: Clean Code

**Problem**:
```csharp
public record CreateCustomerCommand(
    string customer_name,  // snake_case
    string Email           // PascalCase
)
```

**Solution**:
Use consistent PascalCase:
```csharp
public record CreateCustomerCommand(
    string CustomerName,
    string Email
)
```

---

## 🔵 Suggestions

### [CR-007] Consider Using Record

**File**: `src/Application/DTOs/CustomerDto.cs`
**Category**: Best Practice

**Current**:
```csharp
public class CustomerDto
{
    public Guid Id { get; set; }
    public string Name { get; set; }
}
```

**Suggested**:
```csharp
public sealed record CustomerDto(
    Guid Id,
    string Name
);
```

**Benefits**: Immutability, value equality, less boilerplate.

---

## ✅ Good Practices Found

- Proper use of async/await throughout
- Domain events for cross-cutting concerns
- Validators separated from handlers
- Comprehensive logging

---

## 📋 Action Items

### High Priority (Fix before merge)
1. [ ] Fix SQL injection in CustomerRepository.cs:45
2. [ ] Remove hardcoded credentials from appsettings.json
3. [ ] Fix DIP violation in CustomerService.cs

### Medium Priority (Fix soon)
4. [ ] Resolve N+1 query in OrderRepository.cs
5. [ ] Extract magic numbers to constants

### Low Priority (Consider for future)
6. [ ] Standardize naming conventions
7. [ ] Convert DTOs to records
```

### Níveis de Severidade

| Nível | Descrição | Ação |
|-------|-----------|------|
| 🔴 Critical | Vulnerabilidades, bugs que causam crash | Bloqueia merge |
| 🟠 Major | Violações de SOLID, performance grave | Deve corrigir |
| 🟡 Minor | Clean Code, inconsistências | Deveria corrigir |
| 🔵 Suggestion | Melhorias opcionais | Considerar |

### Comandos para Execução

```bash
# Verificar estilo de código
dotnet format --verify-no-changes

# Analisar código estático
dotnet build /p:TreatWarningsAsErrors=true

# Verificar vulnerabilidades em pacotes
dotnet list package --vulnerable

# Rodar testes
dotnet test --collect:"XPlat Code Coverage"
```

## Saída Esperada

Após a revisão, apresente:

1. **Relatório estruturado** - Seguindo o formato acima
2. **Lista de ações** - Priorizadas por severidade
3. **Estatísticas** - Contagem por categoria
4. **Recomendações** - Próximos passos sugeridos

## Checklist do Revisor

Antes de finalizar, verificar:
- [ ] Todos os arquivos foram analisados
- [ ] Issues categorizadas corretamente
- [ ] Exemplos de código correto fornecidos
- [ ] Severidades atribuídas adequadamente
- [ ] Ações priorizadas
- [ ] Boas práticas reconhecidas
