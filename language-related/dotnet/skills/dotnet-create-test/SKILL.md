---
name: dotnet-create-test
description: |
  Cria testes unitarios e de integracao .NET 10 seguindo padrao Triple A (Arrange, Act, Assert) com xUnit, NSubstitute e FluentAssertions.
  Triggers: "criar teste", "novo teste", "create test", "unit test", "teste de integracao".
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

# Criar Testes .NET 10

Crie testes unitários ou de integração seguindo padrão Triple A (Arrange, Act, Assert).

## Argumentos

$ARGUMENTS

## Instruções

Analise o argumento fornecido. Ele deve conter:
1. **Tipo de teste**: Unit (unitário) ou Integration (integração)
2. **Classe a testar**: Classe/Handler/Repositório a ser testado
3. **Cenários**: Cenários específicos a cobrir (opcional)

### Passos para criação:

1. **Identifique o tipo de classe a testar**:

| Tipo | Localização do Teste |
|------|---------------------|
| Entity | tests/{Projeto}.Domain.Tests/Entities/ |
| ValueObject | tests/{Projeto}.Domain.Tests/ValueObjects/ |
| Command Handler | tests/{Projeto}.Application.Tests/Commands/ |
| Query Handler | tests/{Projeto}.Application.Tests/Queries/ |
| Validator | tests/{Projeto}.Application.Tests/Commands/ |
| Repository | tests/{Projeto}.Infrastructure.Tests/Persistence/ |
| Controller | tests/{Projeto}.API.Tests/Controllers/ |

2. **Siga a convenção de nomenclatura**:

**Classe de teste**: `{ClasseTestada}Tests.cs`

**Método de teste**: `{Metodo}_{Cenario}_{ComportamentoEsperado}`

Exemplos:
- `Create_ValidParameters_ReturnsEntity`
- `Handle_DuplicateEmail_ReturnsFailure`
- `Validate_EmptyName_ReturnsValidationError`
- `GetByIdAsync_NonExistingEntity_ReturnsNull`

3. **Estrutura do teste Triple A**:

```csharp
[Fact]
public async Task Method_Scenario_ExpectedBehavior()
{
    // Arrange
    // Configurar mocks, dados de entrada e estado inicial

    // Act
    // Executar o método sendo testado

    // Assert
    // Verificar o resultado esperado
}
```

### Templates por Tipo

#### Teste de Entidade de Domínio

```csharp
namespace {Projeto}.Domain.Tests.Entities;

public sealed class {Entity}Tests
{
    #region Create

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
        entity.Id.Should().NotBeEmpty();
        entity.Name.Should().Be(name);
        entity.Status.Should().Be({Entity}Status.Active);
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
    public void Create_InvalidName_ThrowsArgumentException(string? invalidName)
    {
        // Arrange
        var email = "valid@email.com";

        // Act
        var act = () => {Entity}.Create(invalidName!, email);

        // Assert
        act.Should().Throw<ArgumentException>();
    }

    #endregion

    #region Behavior Methods

    [Fact]
    public void UpdateName_ValidName_UpdatesProperty()
    {
        // Arrange
        var entity = {Entity}.Create("Original", "test@email.com");
        var newName = "Updated Name";
        entity.ClearDomainEvents();

        // Act
        entity.UpdateName(newName);

        // Assert
        entity.Name.Should().Be(newName);
        entity.UpdatedAt.Should().NotBeNull();
        entity.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<{Entity}UpdatedEvent>();
    }

    [Fact]
    public void UpdateName_InactiveEntity_ThrowsDomainException()
    {
        // Arrange
        var entity = {Entity}.Create("Original", "test@email.com");
        entity.Deactivate();

        // Act
        var act = () => entity.UpdateName("New Name");

        // Assert
        act.Should().Throw<{Entity}Exception>()
            .WithMessage("*Cannot update inactive*");
    }

    #endregion
}
```

#### Teste de Command Handler

```csharp
namespace {Projeto}.Application.Tests.Commands.{Feature};

public sealed class {Feature}CommandHandlerTests
{
    private readonly I{Entity}Repository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<{Feature}CommandHandler> _logger;
    private readonly {Feature}CommandHandler _handler;

    public {Feature}CommandHandlerTests()
    {
        _repository = Substitute.For<I{Entity}Repository>();
        _unitOfWork = Substitute.For<IUnitOfWork>();
        _logger = Substitute.For<ILogger<{Feature}CommandHandler>>();
        _handler = new {Feature}CommandHandler(_repository, _unitOfWork, _logger);
    }

    #region Success Cases

    [Fact]
    public async Task Handle_ValidCommand_ReturnsSuccess()
    {
        // Arrange
        var command = new {Feature}Command("ValidName", "valid@email.com");

        _repository.ExistsByEmailAsync(command.Email, Arg.Any<CancellationToken>())
            .Returns(false);

        _unitOfWork.SaveChangesAsync(Arg.Any<CancellationToken>())
            .Returns(1);

        // Act
        var result = await _handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();

        await _repository.Received(1).AddAsync(
            Arg.Is<{Entity}>(e => e.Name == command.Name),
            Arg.Any<CancellationToken>());

        await _unitOfWork.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    #endregion

    #region Failure Cases

    [Fact]
    public async Task Handle_DuplicateEmail_ReturnsFailure()
    {
        // Arrange
        var command = new {Feature}Command("ValidName", "existing@email.com");

        _repository.ExistsByEmailAsync(command.Email, Arg.Any<CancellationToken>())
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
        var command = new {Feature}Command("ValidName", "valid@email.com");

        _repository.ExistsByEmailAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(false);

        _repository.AddAsync(Arg.Any<{Entity}>(), Arg.Any<CancellationToken>())
            .ThrowsAsync(new InvalidOperationException("Database error"));

        // Act
        var act = async () => await _handler.Handle(command, CancellationToken.None);

        // Assert
        await act.Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("Database error");
    }

    #endregion
}
```

#### Teste de Validator

```csharp
namespace {Projeto}.Application.Tests.Commands.{Feature};

public sealed class {Feature}CommandValidatorTests
{
    private readonly {Feature}CommandValidator _validator;

    public {Feature}CommandValidatorTests()
    {
        _validator = new {Feature}CommandValidator();
    }

    #region Valid Commands

    [Fact]
    public void Validate_ValidCommand_ReturnsNoErrors()
    {
        // Arrange
        var command = new {Feature}Command("Valid Name", "valid@email.com");

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeTrue();
        result.Errors.Should().BeEmpty();
    }

    #endregion

    #region Name Validation

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData(null)]
    public void Validate_EmptyName_ReturnsValidationError(string? invalidName)
    {
        // Arrange
        var command = new {Feature}Command(invalidName!, "valid@email.com");

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().ContainSingle()
            .Which.PropertyName.Should().Be("Name");
    }

    [Fact]
    public void Validate_NameTooLong_ReturnsValidationError()
    {
        // Arrange
        var longName = new string('A', 201);
        var command = new {Feature}Command(longName, "valid@email.com");

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Name");
    }

    #endregion

    #region Email Validation

    [Theory]
    [InlineData("")]
    [InlineData("invalid")]
    [InlineData("@invalid.com")]
    [InlineData("test@")]
    public void Validate_InvalidEmail_ReturnsValidationError(string invalidEmail)
    {
        // Arrange
        var command = new {Feature}Command("Valid Name", invalidEmail);

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Email");
    }

    #endregion
}
```

#### Teste de Query Handler

```csharp
namespace {Projeto}.Application.Tests.Queries.{Feature};

public sealed class {Feature}QueryHandlerTests
{
    private readonly IReadOnlyRepository<{Entity}> _repository;
    private readonly ILogger<{Feature}QueryHandler> _logger;
    private readonly {Feature}QueryHandler _handler;

    public {Feature}QueryHandlerTests()
    {
        _repository = Substitute.For<IReadOnlyRepository<{Entity}>>();
        _logger = Substitute.For<ILogger<{Feature}QueryHandler>>();
        _handler = new {Feature}QueryHandler(_repository, _logger);
    }

    [Fact]
    public async Task Handle_ExistingEntity_ReturnsDto()
    {
        // Arrange
        var entityId = Guid.NewGuid();
        var entity = CreateTestEntity(entityId, "Test Name", "test@email.com");
        var query = new {Feature}Query(entityId);

        _repository.GetByIdAsync(entityId, Arg.Any<CancellationToken>())
            .Returns(entity);

        // Act
        var result = await _handler.Handle(query, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeNull();
        result.Value.Id.Should().Be(entityId);
        result.Value.Name.Should().Be("Test Name");
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

    private static {Entity} CreateTestEntity(Guid id, string name, string email)
    {
        // Usar reflection ou builder para criar entidade de teste
        return {Entity}.Create(name, email);
    }
}
```

#### Teste de Repositório (Integração)

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

    [Fact]
    public async Task ExistsByEmailAsync_ExistingEmail_ReturnsTrue()
    {
        // Arrange
        var entity = {Entity}.Create("Test Name", "existing@email.com");
        await _context.{Entities}.AddAsync(entity);
        await _context.SaveChangesAsync();

        // Act
        var result = await _repository.ExistsByEmailAsync("existing@email.com");

        // Assert
        result.Should().BeTrue();
    }

    [Fact]
    public async Task ExistsByEmailAsync_NonExistingEmail_ReturnsFalse()
    {
        // Arrange & Act
        var result = await _repository.ExistsByEmailAsync("nonexisting@email.com");

        // Assert
        result.Should().BeFalse();
    }
}
```

#### Teste de Integração de API

```csharp
namespace {Projeto}.API.Tests.IntegrationTests;

public sealed class {Entity}IntegrationTests
    : IClassFixture<WebApplicationFactory<Program>>, IAsyncLifetime
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;
    private readonly PostgreSqlContainer _postgres;

    public {Entity}IntegrationTests(WebApplicationFactory<Program> factory)
    {
        _postgres = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .Build();

        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
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
    public async Task Post_{Entity}_ValidRequest_ReturnsCreated()
    {
        // Arrange
        var request = new { Name = "Test Name", Email = "test@email.com" };

        // Act
        var response = await _client.PostAsJsonAsync("/api/{entities}", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);

        var content = await response.Content.ReadFromJsonAsync<{Entity}Response>();
        content.Should().NotBeNull();
        content!.Id.Should().NotBeEmpty();
    }

    [Fact]
    public async Task Post_{Entity}_InvalidRequest_ReturnsBadRequest()
    {
        // Arrange
        var request = new { Name = "", Email = "invalid" };

        // Act
        var response = await _client.PostAsJsonAsync("/api/{entities}", request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Get_{Entity}ById_ExistingEntity_ReturnsOk()
    {
        // Arrange
        var createRequest = new { Name = "Test", Email = "test@email.com" };
        var createResponse = await _client.PostAsJsonAsync("/api/{entities}", createRequest);
        var created = await createResponse.Content.ReadFromJsonAsync<{Entity}Response>();

        // Act
        var response = await _client.GetAsync($"/api/{{entities}}/{created!.Id}");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Get_{Entity}ById_NonExisting_ReturnsNotFound()
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

## Pacotes Necessários

```xml
<!-- Testes Unitários -->
<PackageReference Include="xunit" Version="2.*" />
<PackageReference Include="xunit.runner.visualstudio" Version="2.*" />
<PackageReference Include="NSubstitute" Version="5.*" />
<PackageReference Include="FluentAssertions" Version="6.*" />
<PackageReference Include="Bogus" Version="35.*" />

<!-- Testes de Integração -->
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.*" />
<PackageReference Include="Testcontainers.PostgreSql" Version="3.*" />
```

## Checklist

Antes de finalizar, verificar:
- [ ] Padrão Triple A aplicado em todos os testes
- [ ] Nomenclatura Method_Scenario_ExpectedBehavior
- [ ] Mocks usando NSubstitute
- [ ] Assertions usando FluentAssertions
- [ ] Cenários de sucesso, falha e edge cases
- [ ] Testes de integração com Testcontainers
- [ ] Sem lógica de negócio nos testes
- [ ] Annotations [Fact] e [Theory] usadas corretamente

## Saída Esperada

Apresente:
1. **Arquivo de teste criado** - Caminho completo
2. **Cenários cobertos** - Lista de testes criados
3. **Cobertura** - Quais casos estão cobertos
4. **Sugestões** - Cenários adicionais a considerar
