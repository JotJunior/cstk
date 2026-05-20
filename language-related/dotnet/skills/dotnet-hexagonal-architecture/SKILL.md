---
name: dotnet-hexagonal-architecture
description: |
  Gera estrutura de projeto .NET 10 seguindo arquitetura hexagonal, CQRS, Clean Code e SOLID.
  Use quando precisar criar novos projetos, módulos ou camadas seguindo os padrões arquiteturais.
  Triggers: "criar projeto dotnet", "nova feature", "hexagonal", "arquitetura",
  "criar módulo", "estrutura de projeto".
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

# Skill: Arquitetura Hexagonal .NET 10

Esta skill gera estrutura de projetos .NET 10 seguindo Arquitetura Hexagonal, CQRS, Clean Code e princípios SOLID.

## Quando Usar

Claude deve invocar esta skill automaticamente quando:
- Usuário pedir para criar um novo projeto .NET
- Usuário mencionar "hexagonal", "ports and adapters", "clean architecture"
- Houver necessidade de criar nova feature ou módulo
- Usuário pedir para estruturar código seguindo SOLID/Clean Code

## Stack Tecnológica

| Componente                   | Tecnologia                             |
|------------------------------|----------------------------------------|
| Framework                    | .NET 10                                |
| Banco de Dados               | PostgreSQL                             |
| Mensageria                   | RabbitMQ                               |
| Comunicação entre Serviços   | gRPC                                   |
| Gerenciamento de Credenciais | ETCD                                   |
| ORM                          | Entity Framework Core / Dapper         |
| Validação                    | FluentValidation                       |
| Mapeamento                   | Mapster                                |
| Testes                       | xUnit + NSubstitute + FluentAssertions |
| Logs                         | Serilog                                |
| Health Checks                | AspNetCore.HealthChecks                |

## Estrutura de Projeto

```
src/
├── {Projeto}.Domain/                    # Camada de Domínio (Core)
│   ├── Entities/                        # Entidades de domínio
│   ├── ValueObjects/                    # Objetos de valor
│   ├── Enums/                           # Enumeradores
│   ├── Exceptions/                      # Exceções de domínio
│   ├── Events/                          # Eventos de domínio
│   └── Specifications/                  # Especificações de domínio
│
├── {Projeto}.Application/               # Camada de Aplicação
│   ├── Common/
│   │   ├── Behaviors/                   # Pipeline behaviors (validation, logging)
│   │   ├── Interfaces/                  # Interfaces de serviços
│   │   └── Mappings/                    # Configurações de mapeamento
│   ├── Commands/                        # CQRS - Commands
│   │   └── {Feature}/
│   │       ├── {Feature}Command.cs
│   │       ├── {Feature}CommandHandler.cs
│   │       └── {Feature}CommandValidator.cs
│   ├── Queries/                         # CQRS - Queries
│   │   └── {Feature}/
│   │       ├── {Feature}Query.cs
│   │       ├── {Feature}QueryHandler.cs
│   │       └── {Feature}Dto.cs
│   └── EventHandlers/                   # Handlers de eventos de domínio
│
├── {Projeto}.Infrastructure/            # Camada de Infraestrutura
│   ├── Persistence/
│   │   ├── Configurations/              # Configurações EF Core
│   │   ├── Repositories/                # Implementações de repositórios
│   │   ├── Migrations/                  # Migrações do banco
│   │   └── ApplicationDbContext.cs
│   ├── Messaging/
│   │   ├── Publishers/                  # Publicadores RabbitMQ
│   │   └── Consumers/                   # Consumidores RabbitMQ
│   ├── Grpc/
│   │   ├── Clients/                     # Clientes gRPC
│   │   └── Services/                    # Serviços gRPC
│   ├── Configuration/
│   │   └── EtcdConfigurationProvider.cs # Provider ETCD
│   └── DependencyInjection.cs           # Registro de dependências
│
├── {Projeto}.API/                       # Camada de Apresentação (API)
│   ├── Controllers/                     # Controllers REST
│   ├── Grpc/                            # Serviços gRPC expostos
│   ├── Middleware/                      # Middlewares customizados
│   ├── Filters/                         # Filtros de exceção
│   └── Program.cs
│
tests/
├── {Projeto}.Domain.Tests/              # Testes de domínio
├── {Projeto}.Application.Tests/         # Testes de aplicação
├── {Projeto}.Infrastructure.Tests/      # Testes de infraestrutura
└── {Projeto}.API.Tests/                 # Testes de API (integração)
```

## Padrões de Código

### Entidade de Domínio

```csharp
namespace {Projeto}.Domain.Entities;

public sealed class {Entidade} : BaseEntity
{
    private {Entidade}() { } // EF Core

    public static {Entidade} Create(/* params */)
    {
        var entity = new {Entidade}
        {
            // propriedades
        };

        entity.RaiseDomainEvent(new {Entidade}CreatedEvent(entity.Id));
        return entity;
    }

    // Comportamentos de domínio como métodos
    public void Update(/* params */)
    {
        // validações de domínio
        // atualização
        RaiseDomainEvent(new {Entidade}UpdatedEvent(Id));
    }
}
```

### Command (CQRS)

```csharp
namespace {Projeto}.Application.Commands.{Feature};

public sealed record {Feature}Command(
    // propriedades imutáveis
) : IRequest<Result<{Response}>>;

public sealed class {Feature}CommandHandler
    : IRequestHandler<{Feature}Command, Result<{Response}>>
{
    private readonly I{Repository} _repository;
    private readonly IUnitOfWork _unitOfWork;

    public {Feature}CommandHandler(
        I{Repository} repository,
        IUnitOfWork unitOfWork)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
    }

    public async Task<Result<{Response}>> Handle(
        {Feature}Command request,
        CancellationToken cancellationToken)
    {
        // 1. Validações de negócio
        // 2. Criar/atualizar entidade
        // 3. Persistir
        // 4. Retornar resultado
    }
}

public sealed class {Feature}CommandValidator
    : AbstractValidator<{Feature}Command>
{
    public {Feature}CommandValidator()
    {
        RuleFor(x => x.Property)
            .NotEmpty()
            .WithMessage("Property is required");
    }
}
```

### Query (CQRS)

```csharp
namespace {Projeto}.Application.Queries.{Feature};

public sealed record {Feature}Query(
    // filtros e paginação
) : IRequest<Result<{Feature}Dto>>;

public sealed class {Feature}QueryHandler
    : IRequestHandler<{Feature}Query, Result<{Feature}Dto>>
{
    private readonly IReadOnlyRepository<{Entity}> _repository;

    public {Feature}QueryHandler(IReadOnlyRepository<{Entity}> repository)
    {
        _repository = repository;
    }

    public async Task<Result<{Feature}Dto>> Handle(
        {Feature}Query request,
        CancellationToken cancellationToken)
    {
        // Usar projeção direta para DTO
        // Evitar carregar entidades completas
    }
}

public sealed record {Feature}Dto(
    // propriedades do DTO
);
```

### Interface de Repositório (Port)

```csharp
namespace {Projeto}.Application.Common.Interfaces;

public interface I{Entity}Repository
{
    Task<{Entity}?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<{Entity}>> GetAllAsync(CancellationToken cancellationToken = default);
    Task AddAsync({Entity} entity, CancellationToken cancellationToken = default);
    void Update({Entity} entity);
    void Delete({Entity} entity);
}
```

### Implementação de Repositório (Adapter)

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
            .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    }

    // ... outras implementações
}
```

### Configuração PostgreSQL

```csharp
namespace {Projeto}.Infrastructure.Persistence.Configurations;

internal sealed class {Entity}Configuration : IEntityTypeConfiguration<{Entity}>
{
    public void Configure(EntityTypeBuilder<{Entity}> builder)
    {
        builder.ToTable("{entities}");

        builder.HasKey(x => x.Id);

        builder.Property(x => x.Name)
            .HasMaxLength(200)
            .IsRequired();

        // Índices
        builder.HasIndex(x => x.Name);

        // Relacionamentos
        builder.HasMany(x => x.Children)
            .WithOne(x => x.Parent)
            .HasForeignKey(x => x.ParentId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
```

### Publisher RabbitMQ

```csharp
namespace {Projeto}.Infrastructure.Messaging.Publishers;

internal sealed class {Event}Publisher : IEventPublisher<{Event}>
{
    private readonly IConnection _connection;
    private readonly ILogger<{Event}Publisher> _logger;

    public async Task PublishAsync({Event} @event, CancellationToken cancellationToken)
    {
        using var channel = await _connection.CreateChannelAsync();

        await channel.ExchangeDeclareAsync(
            exchange: "{exchange-name}",
            type: ExchangeType.Topic,
            durable: true);

        var body = JsonSerializer.SerializeToUtf8Bytes(@event);

        await channel.BasicPublishAsync(
            exchange: "{exchange-name}",
            routingKey: "{routing-key}",
            mandatory: true,
            body: body);

        _logger.LogInformation("Published {EventType} with Id {EventId}",
            typeof({Event}).Name, @event.Id);
    }
}
```

### Consumer RabbitMQ

```csharp
namespace {Projeto}.Infrastructure.Messaging.Consumers;

internal sealed class {Event}Consumer : BackgroundService
{
    private readonly IConnection _connection;
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<{Event}Consumer> _logger;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var channel = await _connection.CreateChannelAsync();

        await channel.QueueDeclareAsync(
            queue: "{queue-name}",
            durable: true,
            exclusive: false,
            autoDelete: false);

        await channel.QueueBindAsync(
            queue: "{queue-name}",
            exchange: "{exchange-name}",
            routingKey: "{routing-key}");

        var consumer = new AsyncEventingBasicConsumer(channel);
        consumer.ReceivedAsync += async (_, ea) =>
        {
            try
            {
                var @event = JsonSerializer.Deserialize<{Event}>(ea.Body.Span);

                using var scope = _serviceProvider.CreateScope();
                var handler = scope.ServiceProvider.GetRequiredService<I{Event}Handler>();

                await handler.HandleAsync(@event!, stoppingToken);
                await channel.BasicAckAsync(ea.DeliveryTag, false);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing message");
                await channel.BasicNackAsync(ea.DeliveryTag, false, true);
            }
        };

        await channel.BasicConsumeAsync(
            queue: "{queue-name}",
            autoAck: false,
            consumer: consumer);

        await Task.Delay(Timeout.Infinite, stoppingToken);
    }
}
```

### Cliente gRPC

```csharp
namespace {Projeto}.Infrastructure.Grpc.Clients;

internal sealed class {Service}GrpcClient : I{Service}Client
{
    private readonly {Service}.{Service}Client _client;
    private readonly ILogger<{Service}GrpcClient> _logger;

    public {Service}GrpcClient(
        {Service}.{Service}Client client,
        ILogger<{Service}GrpcClient> logger)
    {
        _client = client;
        _logger = logger;
    }

    public async Task<{Response}> {Method}Async(
        {Request} request,
        CancellationToken cancellationToken)
    {
        try
        {
            var grpcRequest = new {GrpcRequest}
            {
                // mapeamento
            };

            var response = await _client.{Method}Async(
                grpcRequest,
                cancellationToken: cancellationToken);

            return new {Response}
            {
                // mapeamento
            };
        }
        catch (RpcException ex)
        {
            _logger.LogError(ex, "gRPC call failed: {Status}", ex.Status);
            throw;
        }
    }
}
```

### Provider ETCD

```csharp
namespace {Projeto}.Infrastructure.Configuration;

public sealed class EtcdConfigurationProvider : ConfigurationProvider
{
    private readonly EtcdClient _client;
    private readonly string _prefix;

    public EtcdConfigurationProvider(string connectionString, string prefix)
    {
        _client = new EtcdClient(connectionString);
        _prefix = prefix;
    }

    public override void Load()
    {
        var response = _client.GetRangeAsync(_prefix).GetAwaiter().GetResult();

        Data = response.Kvs
            .ToDictionary(
                kv => kv.Key.ToStringUtf8().Replace(_prefix, "").Replace("/", ":"),
                kv => kv.Value.ToStringUtf8());
    }
}

public sealed class EtcdConfigurationSource : IConfigurationSource
{
    public string ConnectionString { get; set; } = default!;
    public string Prefix { get; set; } = default!;

    public IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        return new EtcdConfigurationProvider(ConnectionString, Prefix);
    }
}

public static class EtcdConfigurationExtensions
{
    public static IConfigurationBuilder AddEtcd(
        this IConfigurationBuilder builder,
        string connectionString,
        string prefix)
    {
        return builder.Add(new EtcdConfigurationSource
        {
            ConnectionString = connectionString,
            Prefix = prefix
        });
    }
}
```

## Princípios SOLID Aplicados

### Single Responsibility Principle (SRP)
- Cada handler trata apenas um command/query
- Repositórios focam apenas em persistência
- Validadores separados dos handlers

### Open/Closed Principle (OCP)
- Behaviors do MediatR permitem extensão sem modificação
- Strategy pattern para diferentes implementações

### Liskov Substitution Principle (LSP)
- Interfaces de repositório garantem substituibilidade
- Abstrações de infraestrutura podem ser trocadas

### Interface Segregation Principle (ISP)
- Interfaces específicas por contexto (IReadOnlyRepository, IRepository)
- Ports pequenos e focados

### Dependency Inversion Principle (DIP)
- Application depende apenas de interfaces (Ports)
- Infrastructure implementa as interfaces (Adapters)
- Injeção de dependência via construtor

## Checklist de Criação

Antes de finalizar, verificar:
- [ ] Estrutura de pastas criada corretamente
- [ ] Interfaces definidas na camada Application
- [ ] Implementações na camada Infrastructure
- [ ] Entidades com factory methods e eventos de domínio
- [ ] Commands e Queries com validators
- [ ] Configurações de EF Core para PostgreSQL
- [ ] Registro de DI completo
- [ ] Testes unitários estruturados
