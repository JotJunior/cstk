---
name: dotnet-testing
description: |
  Gera testes unitários e de integração para projetos .NET 10 seguindo boas práticas.
  Usa xUnit, NSubstitute, FluentAssertions e padrão Triple A (Arrange, Act, Assert).
  Triggers: "criar teste", "testar", "unit test", "teste unitário",
  "teste de integração", "coverage".
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

# Skill: Testes .NET 10

Esta skill gera testes unitários e de integração para projetos .NET 10 seguindo padrão Triple A e arquitetura hexagonal.

## Quando Usar

Claude deve invocar esta skill automaticamente quando:
- Usuário pedir para criar testes
- Usuário mencionar "unit test", "teste unitário", "integração"
- Após implementar uma feature, para garantir cobertura
- Usuário pedir para validar comportamento de código

## Stack de Testes

| Componente | Tecnologia |
|------------|------------|
| Framework de Testes | xUnit |
| Mocking | NSubstitute |
| Assertions | FluentAssertions |
| Test Data | Bogus |
| Integration Tests | WebApplicationFactory |
| Database Tests | Testcontainers |

## Padrão Triple A (Arrange, Act, Assert)

Todos os testes DEVEM seguir o padrão Triple A:

```csharp
[Fact]
public async Task Method_Scenario_ExpectedBehavior()
{
    // Arrange
    // Configuração de dependências, mocks e dados de entrada

    // Act
    // Execução do método sendo testado

    // Assert
    // Verificação do resultado esperado
}
```

## Convenções de Nomenclatura

### Classe de Teste
```
{ClasseTestada}Tests.cs
```

### Método de Teste
```
{Metodo}_{Cenario}_{ComportamentoEsperado}
```

Exemplos:
- `Handle_ValidCommand_ReturnsSuccess`
- `Handle_InvalidEmail_ReturnsValidationError`
- `GetById_EntityNotFound_ReturnsNull`
- `Create_DuplicateDocument_ThrowsDomainException`

## Estrutura de Testes

```
tests/
├── {Projeto}.Domain.Tests/
│   ├── Entities/
│   │   └── {Entity}Tests.cs
│   ├── ValueObjects/
│   │   └── {ValueObject}Tests.cs
│   └── Specifications/
│       └── {Specification}Tests.cs
│
├── {Projeto}.Application.Tests/
│   ├── Commands/
│   │   └── {Feature}/
│   │       ├── {Feature}CommandHandlerTests.cs
│   │       └── {Feature}CommandValidatorTests.cs
│   ├── Queries/
│   │   └── {Feature}/
│   │       └── {Feature}QueryHandlerTests.cs
│   └── Common/
│       └── Behaviors/
│           └── {Behavior}Tests.cs
│
├── {Projeto}.Infrastructure.Tests/
│   ├── Persistence/
│   │   └── Repositories/
│   │       └── {Entity}RepositoryTests.cs
│   └── Messaging/
│       └── Publishers/
│           └── {Event}PublisherTests.cs
│
└── {Projeto}.API.Tests/
    ├── Controllers/
    │   └── {Controller}Tests.cs
    └── IntegrationTests/
        └── {Feature}IntegrationTests.cs
```

## Templates de Teste

### Teste de Entidade de Domínio

```csharp
namespace {Projeto}.Domain.Tests.Entities;

public sealed class {Entity}Tests
{
    [Fact]
    public void Create_ValidParameters_ReturnsEntity()
    {
        // Arrange
        var name = "Valid Name";
        var email = "valid@email.com";

        // Act
        var entity = {Entity}.Create(name, email);

        // Assert
        entity.Should().NotBeNull();
        entity.Name.Should().Be(name);
        entity.Email.Should().Be(email);
        entity.Id.Should().NotBeEmpty();
    }

    [Fact]
    public void Create_EmptyName_ThrowsDomainException()
    {
        // Arrange
        var name = string.Empty;
        var email = "valid@email.com";

        // Act
        var act = () => {Entity}.Create(name, email);

        // Assert
        act.Should().Throw<DomainException>()
            .WithMessage("*name*required*");
    }

    [Fact]
    public void Create_ValidParameters_RaisesDomainEvent()
    {
        // Arrange
        var name = "Valid Name";
        var email = "valid@email.com";

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
    public void Create_InvalidName_ThrowsDomainException(string? invalidName)
    {
        // Arrange
        var email = "valid@email.com";

        // Act
        var act = () => {Entity}.Create(invalidName!, email);

        // Assert
        act.Should().Throw<DomainException>();
    }
}
```

### Teste de Value Object

```csharp
namespace {Projeto}.Domain.Tests.ValueObjects;

public sealed class EmailTests
{
    [Fact]
    public void Create_ValidEmail_ReturnsEmail()
    {
        // Arrange
        var value = "test@example.com";

        // Act
        var email = Email.Create(value);

        // Assert
        email.Value.Should().Be(value);
    }

    [Theory]
    [InlineData("invalid")]
    [InlineData("invalid@")]
    [InlineData("@invalid.com")]
    [InlineData("")]
    public void Create_InvalidEmail_ThrowsDomainException(string invalidEmail)
    {
        // Arrange & Act
        var act = () => Email.Create(invalidEmail);

        // Assert
        act.Should().Throw<DomainException>()
            .WithMessage("*invalid email*");
    }

    [Fact]
    public void Equals_SameValue_ReturnsTrue()
    {
        // Arrange
        var email1 = Email.Create("test@example.com");
        var email2 = Email.Create("test@example.com");

        // Act
        var result = email1.Equals(email2);

        // Assert
        result.Should().BeTrue();
    }
}
```

### Teste de Command Handler

```csharp
namespace {Projeto}.Application.Tests.Commands.{Feature};

public sealed class {Feature}CommandHandlerTests
{
    private readonly I{Entity}Repository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly {Feature}CommandHandler _handler;

    public {Feature}CommandHandlerTests()
    {
        _repository = Substitute.For<I{Entity}Repository>();
        _unitOfWork = Substitute.For<IUnitOfWork>();
        _handler = new {Feature}CommandHandler(_repository, _unitOfWork);
    }

    [Fact]
    public async Task Handle_ValidCommand_ReturnsSuccess()
    {
        // Arrange
        var command = new {Feature}Command(
            Name: "Valid Name",
            Email: "valid@email.com"
        );

        _unitOfWork.SaveChangesAsync(Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(1));

        // Act
        var result = await _handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeTrue();
        await _repository.Received(1).AddAsync(
            Arg.Is<{Entity}>(e => e.Name == command.Name),
            Arg.Any<CancellationToken>());
        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_DuplicateEntity_ReturnsFailure()
    {
        // Arrange
        var command = new {Feature}Command(
            Name: "Existing Name",
            Email: "existing@email.com"
        );

        _repository.ExistsAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(true);

        // Act
        var result = await _handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsFailure.Should().BeTrue();
        result.Error.Should().Contain("already exists");
        await _repository.DidNotReceive().AddAsync(
            Arg.Any<{Entity}>(),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_RepositoryThrows_PropagatesException()
    {
        // Arrange
        var command = new {Feature}Command(
            Name: "Valid Name",
            Email: "valid@email.com"
        );

        _repository.AddAsync(Arg.Any<{Entity}>(), Arg.Any<CancellationToken>())
            .ThrowsAsync(new InvalidOperationException("Database error"));

        // Act
        var act = async () => await _handler.Handle(command, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("Database error");
    }
}
```

### Teste de Command Validator

```csharp
namespace {Projeto}.Application.Tests.Commands.{Feature};

public sealed class {Feature}CommandValidatorTests
{
    private readonly {Feature}CommandValidator _validator;

    public {Feature}CommandValidatorTests()
    {
        _validator = new {Feature}CommandValidator();
    }

    [Fact]
    public void Validate_ValidCommand_ReturnsNoErrors()
    {
        // Arrange
        var command = new {Feature}Command(
            Name: "Valid Name",
            Email: "valid@email.com"
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeTrue();
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void Validate_EmptyName_ReturnsValidationError()
    {
        // Arrange
        var command = new {Feature}Command(
            Name: "",
            Email: "valid@email.com"
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().ContainSingle()
            .Which.PropertyName.Should().Be("Name");
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData(null)]
    public void Validate_InvalidName_ReturnsValidationError(string? invalidName)
    {
        // Arrange
        var command = new {Feature}Command(
            Name: invalidName!,
            Email: "valid@email.com"
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Name");
    }

    [Fact]
    public void Validate_InvalidEmail_ReturnsValidationError()
    {
        // Arrange
        var command = new {Feature}Command(
            Name: "Valid Name",
            Email: "invalid-email"
        );

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Email");
    }
}
```

### Teste de Query Handler

```csharp
namespace {Projeto}.Application.Tests.Queries.{Feature};

public sealed class {Feature}QueryHandlerTests
{
    private readonly IReadOnlyRepository<{Entity}> _repository;
    private readonly {Feature}QueryHandler _handler;

    public {Feature}QueryHandlerTests()
    {
        _repository = Substitute.For<IReadOnlyRepository<{Entity}>>();
        _handler = new {Feature}QueryHandler(_repository);
    }

    [Fact]
    public async Task Handle_ExistingEntity_ReturnsDto()
    {
        // Arrange
        var entityId = Guid.NewGuid();
        var entity = CreateTestEntity(entityId);
        var query = new {Feature}Query(entityId);

        _repository.GetByIdAsync(entityId, Arg.Any<CancellationToken>())
            .Returns(entity);

        // Act
        var result = await _handler.Handle(query, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeNull();
        result.Value.Id.Should().Be(entityId);
    }

    [Fact]
    public async Task Handle_NonExistingEntity_ReturnsNotFound()
    {
        // Arrange
        var entityId = Guid.NewGuid();
        var query = new {Feature}Query(entityId);

        _repository.GetByIdAsync(entityId, Arg.Any<CancellationToken>())
            .Returns(({Entity}?)null);

        // Act
        var result = await _handler.Handle(query, CancellationToken.None);

        // Assert
        result.IsFailure.Should().BeTrue();
        result.Error.Should().Contain("not found");
    }

    private static {Entity} CreateTestEntity(Guid id)
    {
        // Use reflection ou método interno para criar entidade de teste
        return {Entity}.Create("Test Name", "test@email.com");
    }
}
```

### Teste de Repositório (Integração com PostgreSQL)

```csharp
namespace {Projeto}.Infrastructure.Tests.Persistence.Repositories;

public sealed class {Entity}RepositoryTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres;
    private ApplicationDbContext _context = null!;
    private {Entity}Repository _repository = null!;

    public {Entity}RepositoryTests()
    {
        _postgres = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseNpgsql(_postgres.GetConnectionString())
            .Options;

        _context = new ApplicationDbContext(options);
        await _context.Database.EnsureCreatedAsync();

        _repository = new {Entity}Repository(_context);
    }

    public async Task DisposeAsync()
    {
        await _context.DisposeAsync();
        await _postgres.DisposeAsync();
    }

    [Fact]
    public async Task AddAsync_ValidEntity_PersistsToDatabase()
    {
        // Arrange
        var entity = {Entity}.Create("Test Name", "test@email.com");

        // Act
        await _repository.AddAsync(entity);
        await _context.SaveChangesAsync();

        // Assert
        var persisted = await _context.{Entities}
            .FirstOrDefaultAsync(e => e.Id == entity.Id);
        persisted.Should().NotBeNull();
        persisted!.Name.Should().Be("Test Name");
    }

    [Fact]
    public async Task GetByIdAsync_ExistingEntity_ReturnsEntity()
    {
        // Arrange
        var entity = {Entity}.Create("Test Name", "test@email.com");
        await _context.{Entities}.AddAsync(entity);
        await _context.SaveChangesAsync();
        _context.ChangeTracker.Clear();

        // Act
        var result = await _repository.GetByIdAsync(entity.Id);

        // Assert
        result.Should().NotBeNull();
        result!.Id.Should().Be(entity.Id);
        result.Name.Should().Be("Test Name");
    }

    [Fact]
    public async Task GetByIdAsync_NonExistingEntity_ReturnsNull()
    {
        // Arrange
        var nonExistingId = Guid.NewGuid();

        // Act
        var result = await _repository.GetByIdAsync(nonExistingId);

        // Assert
        result.Should().BeNull();
    }
}
```

### Teste de Integração de API

```csharp
namespace {Projeto}.API.Tests.IntegrationTests;

public sealed class {Feature}IntegrationTests
    : IClassFixture<WebApplicationFactory<Program>>, IAsyncLifetime
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;
    private readonly PostgreSqlContainer _postgres;

    public {Feature}IntegrationTests(WebApplicationFactory<Program> factory)
    {
        _postgres = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .Build();

        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                // Substituir DbContext por container de teste
                var descriptor = services.SingleOrDefault(
                    d => d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>));

                if (descriptor != null)
                    services.Remove(descriptor);

                services.AddDbContext<ApplicationDbContext>(options =>
                    options.UseNpgsql(_postgres.GetConnectionString()));
            });
        });

        _client = _factory.CreateClient();
    }

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        using var scope = _factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        await context.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        await _postgres.DisposeAsync();
    }

    [Fact]
    public async Task Create{Entity}_ValidRequest_ReturnsCreated()
    {
        // Arrange
        var request = new
        {
            Name = "Test Name",
            Email = "test@email.com"
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/{entities}", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var content = await response.Content.ReadFromJsonAsync<{Entity}Response>();
        content.Should().NotBeNull();
        content!.Id.Should().NotBeEmpty();
        content.Name.Should().Be("Test Name");
    }

    [Fact]
    public async Task Create{Entity}_InvalidRequest_ReturnsBadRequest()
    {
        // Arrange
        var request = new
        {
            Name = "",
            Email = "invalid"
        };

        // Act
        var response = await _client.PostAsJsonAsync("/api/{entities}", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Get{Entity}ById_ExistingEntity_ReturnsOk()
    {
        // Arrange
        var createRequest = new { Name = "Test Name", Email = "test@email.com" };
        var createResponse = await _client.PostAsJsonAsync("/api/{entities}", createRequest);
        var created = await createResponse.Content.ReadFromJsonAsync<{Entity}Response>();

        // Act
        var response = await _client.GetAsync($"/api/{{entities}}/{created!.Id}");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var content = await response.Content.ReadFromJsonAsync<{Entity}Response>();
        content!.Id.Should().Be(created.Id);
    }

    [Fact]
    public async Task Get{Entity}ById_NonExistingEntity_ReturnsNotFound()
    {
        // Arrange
        var nonExistingId = Guid.NewGuid();

        // Act
        var response = await _client.GetAsync($"/api/{{entities}}/{nonExistingId}");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

### Teste com Bogus (Dados Fake)

```csharp
namespace {Projeto}.Application.Tests.Common;

public static class {Entity}Faker
{
    private static readonly Faker<{Feature}Command> _commandFaker = new Faker<{Feature}Command>()
        .CustomInstantiator(f => new {Feature}Command(
            Name: f.Company.CompanyName(),
            Email: f.Internet.Email(),
            Document: f.Random.Replace("##.###.###/####-##")
        ));

    public static {Feature}Command GenerateValidCommand()
        => _commandFaker.Generate();

    public static IEnumerable<{Feature}Command> GenerateValidCommands(int count)
        => _commandFaker.Generate(count);
}
```

## Arquitetura Hexagonal nos Testes

### Testar Interfaces, Não Implementações

```csharp
// BOM: Testa comportamento via interface
public sealed class CreateCustomerCommandHandlerTests
{
    private readonly ICustomerRepository _repository; // Interface!
    private readonly CreateCustomerCommandHandler _handler;

    public CreateCustomerCommandHandlerTests()
    {
        _repository = Substitute.For<ICustomerRepository>();
        _handler = new CreateCustomerCommandHandler(_repository);
    }
}

// RUIM: Testa implementação concreta
public sealed class CustomerRepositoryDirectTests
{
    private readonly CustomerRepository _repository; // Implementação!
}
```

### Mocks para Ports de Saída

```csharp
// Mock de repositório (Port de saída)
_repository.GetByIdAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>())
    .Returns(expectedEntity);

// Mock de serviço externo (Port de saída)
_paymentGateway.ProcessPaymentAsync(Arg.Any<PaymentRequest>())
    .Returns(new PaymentResult { Success = true });

// Mock de mensageria (Port de saída)
_eventPublisher.PublishAsync(Arg.Any<CustomerCreatedEvent>())
    .Returns(Task.CompletedTask);
```

## Checklist de Qualidade

Antes de finalizar os testes, verificar:
- [ ] Todos os testes seguem padrão Triple A
- [ ] Nomenclatura segue convenção Method_Scenario_ExpectedBehavior
- [ ] Testes de domínio validam regras de negócio
- [ ] Testes de handler usam mocks para dependências
- [ ] Testes de validador cobrem todos os campos
- [ ] Testes de integração usam containers
- [ ] Cobertura de cenários de sucesso, erro e edge cases
- [ ] Assertions usam FluentAssertions
- [ ] Annotations do xUnit ao invés de docblocks
