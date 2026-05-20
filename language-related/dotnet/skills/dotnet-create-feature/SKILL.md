---
name: dotnet-create-feature
description: |
  Cria nova feature .NET 10 seguindo padrao CQRS com Command, Query, Handler e Validator.
  Triggers: "criar feature", "nova feature", "create feature", "novo command", "nova query".
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

# Criar Feature .NET 10

Crie uma nova feature seguindo padrão CQRS com Command, Query, Handler e Validator.

## Argumentos

$ARGUMENTS

## Instruções

Analise o argumento fornecido. Ele deve conter:
1. **Nome da feature**: Nome do caso de uso/funcionalidade
2. **Tipo**: Command (escrita) ou Query (leitura)
3. **Entidade**: Entidade de domínio principal
4. **Descrição**: O que a feature faz

### Passos para criação:

1. **Identifique o tipo de operação**:
   - **Command**: Cria, atualiza ou deleta dados
   - **Query**: Consulta dados sem efeitos colaterais

2. **Crie os arquivos necessários**:

### Para Commands

```
src/{Projeto}.Application/Commands/{Feature}/
├── {Feature}Command.cs
├── {Feature}CommandHandler.cs
└── {Feature}CommandValidator.cs
```

### Para Queries

```
src/{Projeto}.Application/Queries/{Feature}/
├── {Feature}Query.cs
├── {Feature}QueryHandler.cs
└── {Feature}Dto.cs
```

3. **Estrutura dos arquivos**:

### Command

```csharp
namespace {Projeto}.Application.Commands.{Feature};

public sealed record {Feature}Command(
    // Propriedades necessárias para a operação
    string Property1,
    int Property2
) : IRequest<Result<{Response}>>;
```

### Command Handler

```csharp
namespace {Projeto}.Application.Commands.{Feature};

public sealed class {Feature}CommandHandler
    : IRequestHandler<{Feature}Command, Result<{Response}>>
{
    private readonly I{Entity}Repository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<{Feature}CommandHandler> _logger;

    public {Feature}CommandHandler(
        I{Entity}Repository repository,
        IUnitOfWork unitOfWork,
        ILogger<{Feature}CommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    public async Task<Result<{Response}>> Handle(
        {Feature}Command request,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Processing {Feature} command", nameof({Feature}));

        // 1. Validações de negócio
        // 2. Criar/atualizar entidade
        // 3. Persistir
        // 4. Retornar resultado

        try
        {
            var entity = {Entity}.Create(request.Property1, request.Property2);

            await _repository.AddAsync(entity, cancellationToken);
            await _unitOfWork.SaveChangesAsync(cancellationToken);

            _logger.LogInformation("{Feature} completed successfully for {EntityId}",
                nameof({Feature}), entity.Id);

            return Result<{Response}>.Success(new {Response}(entity.Id));
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "{Feature} failed due to domain error", nameof({Feature}));
            return Result<{Response}>.Failure(ex.Message);
        }
    }
}
```

### Command Validator

```csharp
namespace {Projeto}.Application.Commands.{Feature};

public sealed class {Feature}CommandValidator : AbstractValidator<{Feature}Command>
{
    public {Feature}CommandValidator()
    {
        RuleFor(x => x.Property1)
            .NotEmpty()
            .WithMessage("Property1 is required")
            .MaximumLength(200)
            .WithMessage("Property1 must not exceed 200 characters");

        RuleFor(x => x.Property2)
            .GreaterThan(0)
            .WithMessage("Property2 must be greater than 0");
    }
}
```

### Query

```csharp
namespace {Projeto}.Application.Queries.{Feature};

public sealed record {Feature}Query(
    Guid Id
) : IRequest<Result<{Feature}Dto>>;
```

### Query Handler

```csharp
namespace {Projeto}.Application.Queries.{Feature};

public sealed class {Feature}QueryHandler
    : IRequestHandler<{Feature}Query, Result<{Feature}Dto>>
{
    private readonly IReadOnlyRepository<{Entity}> _repository;
    private readonly ILogger<{Feature}QueryHandler> _logger;

    public {Feature}QueryHandler(
        IReadOnlyRepository<{Entity}> repository,
        ILogger<{Feature}QueryHandler> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    public async Task<Result<{Feature}Dto>> Handle(
        {Feature}Query request,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Processing {Feature} query for {Id}",
            nameof({Feature}), request.Id);

        var entity = await _repository.GetByIdAsync(request.Id, cancellationToken);

        if (entity is null)
        {
            _logger.LogWarning("{Entity} not found with Id {Id}",
                nameof({Entity}), request.Id);
            return Result<{Feature}Dto>.Failure($"{nameof({Entity})} not found");
        }

        var dto = new {Feature}Dto(
            entity.Id,
            entity.Property1,
            entity.Property2,
            entity.CreatedAt
        );

        return Result<{Feature}Dto>.Success(dto);
    }
}
```

### DTO

```csharp
namespace {Projeto}.Application.Queries.{Feature};

public sealed record {Feature}Dto(
    Guid Id,
    string Property1,
    int Property2,
    DateTime CreatedAt
);
```

4. **Crie os testes correspondentes**:

### Command Handler Tests

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

    [Fact]
    public async Task Handle_ValidCommand_ReturnsSuccess()
    {
        // Arrange
        var command = new {Feature}Command("ValidValue", 10);

        _unitOfWork.SaveChangesAsync(Arg.Any<CancellationToken>())
            .Returns(1);

        // Act
        var result = await _handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsSuccess.Should().BeTrue();
        await _repository.Received(1).AddAsync(
            Arg.Any<{Entity}>(),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_InvalidData_ReturnsFailure()
    {
        // Arrange
        var command = new {Feature}Command("", 0);

        // Act
        var result = await _handler.Handle(command, CancellationToken.None);

        // Assert
        result.IsFailure.Should().BeTrue();
    }
}
```

### Validator Tests

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
        var command = new {Feature}Command("ValidValue", 10);

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData(null)]
    public void Validate_InvalidProperty1_ReturnsError(string? invalidValue)
    {
        // Arrange
        var command = new {Feature}Command(invalidValue!, 10);

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Property1");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Validate_InvalidProperty2_ReturnsError(int invalidValue)
    {
        // Arrange
        var command = new {Feature}Command("ValidValue", invalidValue);

        // Act
        var result = _validator.Validate(command);

        // Assert
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Property2");
    }
}
```

5. **Crie o endpoint na API** (se necessário):

### Controller

```csharp
namespace {Projeto}.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class {Entities}Controller : ControllerBase
{
    private readonly ISender _sender;

    public {Entities}Controller(ISender sender)
    {
        _sender = sender;
    }

    [HttpPost]
    [ProducesResponseType(typeof({Response}), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Create(
        [{Feature}Request] request,
        CancellationToken cancellationToken)
    {
        var command = new {Feature}Command(request.Property1, request.Property2);
        var result = await _sender.Send(command, cancellationToken);

        if (result.IsFailure)
            return BadRequest(new ProblemDetails { Detail = result.Error });

        return CreatedAtAction(
            nameof(GetById),
            new { id = result.Value.Id },
            result.Value);
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof({Feature}Dto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        var query = new {Feature}Query(id);
        var result = await _sender.Send(query, cancellationToken);

        if (result.IsFailure)
            return NotFound();

        return Ok(result.Value);
    }
}
```

## Checklist

Antes de finalizar, verificar:
- [ ] Command/Query criado com record imutável
- [ ] Handler com injeção de dependência via construtor
- [ ] Validator com todas as regras necessárias
- [ ] Testes seguindo padrão Triple A
- [ ] DTO para queries (nunca expor entidades)
- [ ] Logs informativos no handler
- [ ] Tratamento de erros adequado

## Saída Esperada

Apresente:
1. **Arquivos criados** - Lista com caminho completo
2. **Código gerado** - Conteúdo de cada arquivo
3. **Próximos passos** - O que fazer para integrar a feature
