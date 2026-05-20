---
name: dotnet-create-entity
description: |
  Cria entidade de dominio .NET 10 seguindo DDD com Value Objects, eventos de dominio e configuracao EF Core.
  Triggers: "criar entidade", "nova entidade", "create entity", "novo agregado".
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

# Criar Entidade de Domínio .NET 10

Crie uma nova entidade de domínio seguindo DDD, com Value Objects, eventos de domínio e configuração EF Core.

## Argumentos

$ARGUMENTS

## Instruções

Analise o argumento fornecido. Ele deve conter:
1. **Nome da entidade**: Nome do agregado/entidade
2. **Propriedades**: Lista de propriedades com tipos
3. **Regras de negócio**: Validações e comportamentos

### Passos para criação:

1. **Crie a entidade de domínio**:

```
src/{Projeto}.Domain/
├── Entities/
│   └── {Entity}.cs
├── ValueObjects/
│   └── {ValueObject}.cs (se necessário)
├── Events/
│   └── {Entity}CreatedEvent.cs
│   └── {Entity}UpdatedEvent.cs
└── Exceptions/
    └── {Entity}Exception.cs
```

2. **Estrutura da entidade**:

### Entidade Principal

```csharp
namespace {Projeto}.Domain.Entities;

public sealed class {Entity} : AggregateRoot
{
    // Construtor privado para EF Core
    private {Entity}() { }

    // Propriedades com setters privados
    public string Name { get; private set; } = default!;
    public Email Email { get; private set; } = default!;
    public {Entity}Status Status { get; private set; }
    public DateTime? DeactivatedAt { get; private set; }

    // Coleções como IReadOnlyCollection
    private readonly List<{ChildEntity}> _children = [];
    public IReadOnlyCollection<{ChildEntity}> Children => _children.AsReadOnly();

    // Factory method estático
    public static {Entity} Create(string name, string email)
    {
        Guard.Against.NullOrWhiteSpace(name, nameof(name));
        Guard.Against.NullOrWhiteSpace(email, nameof(email));

        var entity = new {Entity}
        {
            Id = Guid.NewGuid(),
            Name = name,
            Email = Email.Create(email),
            Status = {Entity}Status.Active,
            CreatedAt = DateTime.UtcNow
        };

        entity.RaiseDomainEvent(new {Entity}CreatedEvent(entity.Id, entity.Name));

        return entity;
    }

    // Métodos de comportamento
    public void UpdateName(string name)
    {
        Guard.Against.NullOrWhiteSpace(name, nameof(name));

        if (Status == {Entity}Status.Inactive)
            throw new {Entity}Exception("Cannot update inactive {entity}");

        Name = name;
        UpdatedAt = DateTime.UtcNow;

        RaiseDomainEvent(new {Entity}UpdatedEvent(Id, nameof(Name), name));
    }

    public void UpdateEmail(string email)
    {
        Guard.Against.NullOrWhiteSpace(email, nameof(email));

        if (Status == {Entity}Status.Inactive)
            throw new {Entity}Exception("Cannot update inactive {entity}");

        Email = Email.Create(email);
        UpdatedAt = DateTime.UtcNow;

        RaiseDomainEvent(new {Entity}UpdatedEvent(Id, nameof(Email), email));
    }

    public void Deactivate()
    {
        if (Status == {Entity}Status.Inactive)
            throw new {Entity}Exception("{Entity} is already inactive");

        Status = {Entity}Status.Inactive;
        DeactivatedAt = DateTime.UtcNow;
        UpdatedAt = DateTime.UtcNow;

        RaiseDomainEvent(new {Entity}DeactivatedEvent(Id));
    }

    public void Activate()
    {
        if (Status == {Entity}Status.Active)
            throw new {Entity}Exception("{Entity} is already active");

        Status = {Entity}Status.Active;
        DeactivatedAt = null;
        UpdatedAt = DateTime.UtcNow;

        RaiseDomainEvent(new {Entity}ActivatedEvent(Id));
    }

    // Método para adicionar filho
    public void Add{ChildEntity}({ChildEntity} child)
    {
        Guard.Against.Null(child, nameof(child));

        if (_children.Any(c => c.Id == child.Id))
            throw new {Entity}Exception("{ChildEntity} already exists");

        _children.Add(child);
        UpdatedAt = DateTime.UtcNow;
    }

    public void Remove{ChildEntity}(Guid childId)
    {
        var child = _children.FirstOrDefault(c => c.Id == childId);

        if (child is null)
            throw new {Entity}Exception("{ChildEntity} not found");

        _children.Remove(child);
        UpdatedAt = DateTime.UtcNow;
    }
}
```

### Value Object

```csharp
namespace {Projeto}.Domain.ValueObjects;

public sealed class Email : ValueObject
{
    public string Value { get; }

    private Email(string value)
    {
        Value = value;
    }

    public static Email Create(string value)
    {
        Guard.Against.NullOrWhiteSpace(value, nameof(value));

        if (!IsValidEmail(value))
            throw new DomainException("Invalid email format");

        return new Email(value.ToLowerInvariant());
    }

    private static bool IsValidEmail(string email)
    {
        try
        {
            var addr = new System.Net.Mail.MailAddress(email);
            return addr.Address == email;
        }
        catch
        {
            return false;
        }
    }

    protected override IEnumerable<object> GetEqualityComponents()
    {
        yield return Value;
    }

    public override string ToString() => Value;

    public static implicit operator string(Email email) => email.Value;
}
```

### Enum de Status

```csharp
namespace {Projeto}.Domain.Enums;

public enum {Entity}Status
{
    Active = 1,
    Inactive = 2,
    Pending = 3,
    Blocked = 4
}
```

### Eventos de Domínio

```csharp
namespace {Projeto}.Domain.Events;

public sealed record {Entity}CreatedEvent(
    Guid {Entity}Id,
    string Name
) : IDomainEvent;

public sealed record {Entity}UpdatedEvent(
    Guid {Entity}Id,
    string PropertyName,
    string NewValue
) : IDomainEvent;

public sealed record {Entity}DeactivatedEvent(
    Guid {Entity}Id
) : IDomainEvent;

public sealed record {Entity}ActivatedEvent(
    Guid {Entity}Id
) : IDomainEvent;
```

### Exceção de Domínio

```csharp
namespace {Projeto}.Domain.Exceptions;

public sealed class {Entity}Exception : DomainException
{
    public {Entity}Exception(string message) : base(message)
    {
    }

    public {Entity}Exception(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
```

3. **Crie a interface do repositório** (Application):

```csharp
namespace {Projeto}.Application.Common.Interfaces;

public interface I{Entity}Repository
{
    Task<{Entity}?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);
    Task<{Entity}?> GetByEmailAsync(string email, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<{Entity}>> GetAllAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<{Entity}>> GetActiveAsync(CancellationToken cancellationToken = default);
    Task<bool> ExistsAsync(Guid id, CancellationToken cancellationToken = default);
    Task<bool> ExistsByEmailAsync(string email, CancellationToken cancellationToken = default);
    Task AddAsync({Entity} entity, CancellationToken cancellationToken = default);
    void Update({Entity} entity);
    void Delete({Entity} entity);
}
```

4. **Crie a implementação do repositório** (Infrastructure):

```csharp
namespace {Projeto}.Infrastructure.Persistence.Repositories;

internal sealed class {Entity}Repository : I{Entity}Repository
{
    private readonly ApplicationDbContext _context;

    public {Entity}Repository(ApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<{Entity}?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        return await _context.{Entities}
            .Include(e => e.Children)
            .FirstOrDefaultAsync(e => e.Id == id, cancellationToken);
    }

    public async Task<{Entity}?> GetByEmailAsync(
        string email,
        CancellationToken cancellationToken = default)
    {
        return await _context.{Entities}
            .FirstOrDefaultAsync(e => e.Email.Value == email.ToLowerInvariant(), cancellationToken);
    }

    public async Task<IReadOnlyList<{Entity}>> GetAllAsync(
        CancellationToken cancellationToken = default)
    {
        return await _context.{Entities}
            .OrderBy(e => e.Name)
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<{Entity}>> GetActiveAsync(
        CancellationToken cancellationToken = default)
    {
        return await _context.{Entities}
            .Where(e => e.Status == {Entity}Status.Active)
            .OrderBy(e => e.Name)
            .ToListAsync(cancellationToken);
    }

    public async Task<bool> ExistsAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        return await _context.{Entities}
            .AnyAsync(e => e.Id == id, cancellationToken);
    }

    public async Task<bool> ExistsByEmailAsync(
        string email,
        CancellationToken cancellationToken = default)
    {
        return await _context.{Entities}
            .AnyAsync(e => e.Email.Value == email.ToLowerInvariant(), cancellationToken);
    }

    public async Task AddAsync(
        {Entity} entity,
        CancellationToken cancellationToken = default)
    {
        await _context.{Entities}.AddAsync(entity, cancellationToken);
    }

    public void Update({Entity} entity)
    {
        _context.{Entities}.Update(entity);
    }

    public void Delete({Entity} entity)
    {
        _context.{Entities}.Remove(entity);
    }
}
```

5. **Crie a configuração EF Core**:

```csharp
namespace {Projeto}.Infrastructure.Persistence.Configurations;

internal sealed class {Entity}Configuration : IEntityTypeConfiguration<{Entity}>
{
    public void Configure(EntityTypeBuilder<{Entity}> builder)
    {
        builder.ToTable("{entities}");

        builder.HasKey(e => e.Id);

        builder.Property(e => e.Id)
            .ValueGeneratedNever();

        builder.Property(e => e.Name)
            .HasMaxLength(200)
            .IsRequired();

        // Value Object como Owned Type
        builder.OwnsOne(e => e.Email, email =>
        {
            email.Property(e => e.Value)
                .HasColumnName("email")
                .HasMaxLength(255)
                .IsRequired();

            email.HasIndex(e => e.Value)
                .IsUnique();
        });

        builder.Property(e => e.Status)
            .HasConversion<int>()
            .IsRequired();

        builder.Property(e => e.CreatedAt)
            .IsRequired();

        builder.Property(e => e.UpdatedAt);

        builder.Property(e => e.DeactivatedAt);

        // Relacionamento com filhos
        builder.HasMany(e => e.Children)
            .WithOne()
            .HasForeignKey("{Entity}Id")
            .OnDelete(DeleteBehavior.Cascade);

        // Índices
        builder.HasIndex(e => e.Status);
        builder.HasIndex(e => e.CreatedAt);

        // Ignorar eventos de domínio
        builder.Ignore(e => e.DomainEvents);
    }
}
```

6. **Adicione ao DbContext**:

```csharp
public DbSet<{Entity}> {Entities} => Set<{Entity}>();
```

7. **Registre o repositório no DI**:

```csharp
services.AddScoped<I{Entity}Repository, {Entity}Repository>();
```

8. **Crie os testes da entidade**:

```csharp
namespace {Projeto}.Domain.Tests.Entities;

public sealed class {Entity}Tests
{
    [Fact]
    public void Create_ValidParameters_ReturnsEntity()
    {
        // Arrange
        var name = "Test Name";
        var email = "test@example.com";

        // Act
        var entity = {Entity}.Create(name, email);

        // Assert
        entity.Should().NotBeNull();
        entity.Id.Should().NotBeEmpty();
        entity.Name.Should().Be(name);
        entity.Email.Value.Should().Be(email.ToLowerInvariant());
        entity.Status.Should().Be({Entity}Status.Active);
        entity.CreatedAt.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromSeconds(1));
    }

    [Fact]
    public void Create_ValidParameters_RaisesCreatedEvent()
    {
        // Arrange
        var name = "Test Name";
        var email = "test@example.com";

        // Act
        var entity = {Entity}.Create(name, email);

        // Assert
        entity.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<{Entity}CreatedEvent>();
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData(null)]
    public void Create_InvalidName_ThrowsArgumentException(string? invalidName)
    {
        // Arrange
        var email = "test@example.com";

        // Act
        var act = () => {Entity}.Create(invalidName!, email);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    [Theory]
    [InlineData("invalid")]
    [InlineData("@invalid.com")]
    [InlineData("test@")]
    public void Create_InvalidEmail_ThrowsDomainException(string invalidEmail)
    {
        // Arrange
        var name = "Test Name";

        // Act
        var act = () => {Entity}.Create(name, invalidEmail);

        // Assert
        act.Should().Throw<DomainException>();
    }

    [Fact]
    public void Deactivate_ActiveEntity_SetsStatusToInactive()
    {
        // Arrange
        var entity = {Entity}.Create("Test", "test@example.com");
        entity.ClearDomainEvents();

        // Act
        entity.Deactivate();

        // Assert
        entity.Status.Should().Be({Entity}Status.Inactive);
        entity.DeactivatedAt.Should().NotBeNull();
        entity.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<{Entity}DeactivatedEvent>();
    }

    [Fact]
    public void Deactivate_InactiveEntity_ThrowsException()
    {
        // Arrange
        var entity = {Entity}.Create("Test", "test@example.com");
        entity.Deactivate();

        // Act
        var act = () => entity.Deactivate();

        // Assert
        act.Should().Throw<{Entity}Exception>()
            .WithMessage("*already inactive*");
    }

    [Fact]
    public void UpdateName_InactiveEntity_ThrowsException()
    {
        // Arrange
        var entity = {Entity}.Create("Test", "test@example.com");
        entity.Deactivate();

        // Act
        var act = () => entity.UpdateName("New Name");

        // Assert
        act.Should().Throw<{Entity}Exception>()
            .WithMessage("*Cannot update inactive*");
    }
}
```

## Checklist

Antes de finalizar, verificar:
- [ ] Entidade com construtor privado
- [ ] Factory method estático para criação
- [ ] Propriedades com setters privados
- [ ] Value Objects para tipos complexos
- [ ] Eventos de domínio em operações relevantes
- [ ] Exceção de domínio específica
- [ ] Métodos de comportamento validam regras
- [ ] Configuração EF Core completa
- [ ] Interface de repositório na Application
- [ ] Implementação de repositório na Infrastructure
- [ ] Testes unitários cobrindo casos de sucesso e erro

## Saída Esperada

Apresente:
1. **Arquivos criados** - Lista com caminho completo
2. **Migração necessária** - Comando para criar migração
3. **Registro no DI** - Código para registrar no container
4. **Próximos passos** - Commands/Queries a criar
