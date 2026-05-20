---
name: dotnet-infrastructure
description: |
  Configura infraestrutura para projetos .NET 10 com PostgreSQL, RabbitMQ, gRPC e ETCD.
  Use para configurar banco de dados, mensageria, comunicação entre serviços e credenciais.
  Triggers: "configurar banco", "postgresql", "rabbitmq", "grpc",
  "etcd", "docker", "infraestrutura".
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

# Skill: Infraestrutura .NET 10

Esta skill configura a infraestrutura completa para projetos .NET 10.

## Quando Usar

Claude deve invocar esta skill automaticamente quando:
- Usuário pedir para configurar banco de dados PostgreSQL
- Usuário mencionar RabbitMQ, mensageria ou filas
- Houver necessidade de configurar comunicação gRPC
- Usuário pedir para configurar ETCD ou credenciais
- Usuário pedir para criar docker-compose ou containers

## Stack de Infraestrutura

| Componente | Tecnologia | Versão Recomendada |
|------------|------------|-------------------|
| Banco de Dados | PostgreSQL | 16+ |
| Mensageria | RabbitMQ | 3.13+ |
| Comunicação | gRPC | .NET nativo |
| Credenciais | ETCD | v3.5+ |
| Containers | Docker | 24+ |
| Orquestração | Docker Compose | v2+ |

## Docker Compose Completo

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: ${PROJECT_NAME}-postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
      POSTGRES_DB: ${POSTGRES_DB:-appdb}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./scripts/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-app} -d ${POSTGRES_DB:-appdb}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  rabbitmq:
    image: rabbitmq:3.13-management-alpine
    container_name: ${PROJECT_NAME}-rabbitmq
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER:-guest}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASS:-guest}
      RABBITMQ_DEFAULT_VHOST: ${RABBITMQ_VHOST:-/}
    ports:
      - "${RABBITMQ_PORT:-5672}:5672"
      - "${RABBITMQ_MGMT_PORT:-15672}:15672"
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
      - ./rabbitmq/definitions.json:/etc/rabbitmq/definitions.json:ro
      - ./rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_port_connectivity"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  etcd:
    image: quay.io/coreos/etcd:v3.5.12
    container_name: ${PROJECT_NAME}-etcd
    environment:
      ETCD_NAME: etcd0
      ETCD_DATA_DIR: /etcd-data
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd:2379
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_INITIAL_ADVERTISE_PEER_URLS: http://etcd:2380
      ETCD_INITIAL_CLUSTER: etcd0=http://etcd:2380
      ETCD_INITIAL_CLUSTER_STATE: new
      ETCD_INITIAL_CLUSTER_TOKEN: etcd-cluster-1
    ports:
      - "${ETCD_PORT:-2379}:2379"
      - "2380:2380"
    volumes:
      - etcd_data:/etcd-data
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  api:
    build:
      context: .
      dockerfile: src/${PROJECT_NAME}.API/Dockerfile
    container_name: ${PROJECT_NAME}-api
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ASPNETCORE_URLS: http://+:80;https://+:443
      ASPNETCORE_Kestrel__Endpoints__Grpc__Url: http://+:5001
      ASPNETCORE_Kestrel__Endpoints__Grpc__Protocols: Http2
      ConnectionStrings__DefaultConnection: "Host=postgres;Database=${POSTGRES_DB:-appdb};Username=${POSTGRES_USER:-app};Password=${POSTGRES_PASSWORD:-app}"
      RabbitMQ__Host: rabbitmq
      RabbitMQ__Port: 5672
      RabbitMQ__Username: ${RABBITMQ_USER:-guest}
      RabbitMQ__Password: ${RABBITMQ_PASS:-guest}
      Etcd__ConnectionString: http://etcd:2379
    ports:
      - "${API_HTTP_PORT:-8080}:80"
      - "${API_HTTPS_PORT:-8443}:443"
      - "${API_GRPC_PORT:-5001}:5001"
    depends_on:
      postgres:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
      etcd:
        condition: service_healthy
    networks:
      - app-network

volumes:
  postgres_data:
  rabbitmq_data:
  etcd_data:

networks:
  app-network:
    driver: bridge
```

## Configuração PostgreSQL

### appsettings.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=appdb;Username=app;Password=app;Include Error Detail=true"
  },
  "PostgreSQL": {
    "EnableRetryOnFailure": true,
    "MaxRetryCount": 3,
    "MaxRetryDelay": "00:00:30",
    "CommandTimeout": 30,
    "EnableSensitiveDataLogging": false
  }
}
```

### DbContext Configuration

```csharp
namespace {Projeto}.Infrastructure.Persistence;

public sealed class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<{Entity}> {Entities} => Set<{Entity}>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(
            typeof(ApplicationDbContext).Assembly);

        // Convenções globais
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            // snake_case para nomes de tabelas
            entityType.SetTableName(
                entityType.GetTableName()?.ToSnakeCase());

            // snake_case para nomes de colunas
            foreach (var property in entityType.GetProperties())
            {
                property.SetColumnName(
                    property.GetColumnName()?.ToSnakeCase());
            }
        }
    }
}
```

### DI Registration

```csharp
namespace {Projeto}.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // PostgreSQL
        services.AddDbContext<ApplicationDbContext>((sp, options) =>
        {
            var connectionString = configuration.GetConnectionString("DefaultConnection");

            options.UseNpgsql(connectionString, npgsqlOptions =>
            {
                npgsqlOptions.MigrationsAssembly(
                    typeof(ApplicationDbContext).Assembly.FullName);

                npgsqlOptions.EnableRetryOnFailure(
                    maxRetryCount: configuration.GetValue<int>("PostgreSQL:MaxRetryCount"),
                    maxRetryDelay: configuration.GetValue<TimeSpan>("PostgreSQL:MaxRetryDelay"),
                    errorCodesToAdd: null);

                npgsqlOptions.CommandTimeout(
                    configuration.GetValue<int>("PostgreSQL:CommandTimeout"));
            });

            if (configuration.GetValue<bool>("PostgreSQL:EnableSensitiveDataLogging"))
            {
                options.EnableSensitiveDataLogging();
            }
        });

        // Repositórios
        services.AddScoped<I{Entity}Repository, {Entity}Repository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        return services;
    }
}
```

### Health Check

```csharp
services.AddHealthChecks()
    .AddNpgSql(
        connectionString: configuration.GetConnectionString("DefaultConnection")!,
        name: "postgresql",
        tags: ["db", "sql", "postgresql"]);
```

## Configuração RabbitMQ

### appsettings.json

```json
{
  "RabbitMQ": {
    "Host": "localhost",
    "Port": 5672,
    "Username": "guest",
    "Password": "guest",
    "VirtualHost": "/",
    "RetryCount": 5,
    "RetryInterval": "00:00:05",
    "Exchanges": {
      "Default": "{projeto}.exchange",
      "DeadLetter": "{projeto}.dlx"
    },
    "Queues": {
      "Default": "{projeto}.queue",
      "DeadLetter": "{projeto}.dlq"
    }
  }
}
```

### Connection Factory

```csharp
namespace {Projeto}.Infrastructure.Messaging;

public static class RabbitMQExtensions
{
    public static IServiceCollection AddRabbitMQ(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var rabbitConfig = configuration.GetSection("RabbitMQ");

        services.AddSingleton<IConnection>(sp =>
        {
            var factory = new ConnectionFactory
            {
                HostName = rabbitConfig["Host"],
                Port = rabbitConfig.GetValue<int>("Port"),
                UserName = rabbitConfig["Username"],
                Password = rabbitConfig["Password"],
                VirtualHost = rabbitConfig["VirtualHost"],
                DispatchConsumersAsync = true,
                AutomaticRecoveryEnabled = true,
                NetworkRecoveryInterval = TimeSpan.FromSeconds(10)
            };

            var retryCount = rabbitConfig.GetValue<int>("RetryCount");
            var retryInterval = rabbitConfig.GetValue<TimeSpan>("RetryInterval");

            return Policy
                .Handle<BrokerUnreachableException>()
                .WaitAndRetry(
                    retryCount,
                    _ => retryInterval,
                    (ex, time) =>
                    {
                        var logger = sp.GetRequiredService<ILogger<IConnection>>();
                        logger.LogWarning(ex,
                            "RabbitMQ connection failed. Retrying in {Delay}...",
                            time);
                    })
                .Execute(() => factory.CreateConnectionAsync().GetAwaiter().GetResult());
        });

        // Publishers
        services.AddSingleton<IEventPublisher<{Event}>, {Event}Publisher>();

        // Consumers
        services.AddHostedService<{Event}Consumer>();

        return services;
    }
}
```

### definitions.json (RabbitMQ)

```json
{
  "rabbit_version": "3.13.0",
  "users": [
    {
      "name": "guest",
      "password_hash": "guest",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["administrator"]
    }
  ],
  "vhosts": [
    { "name": "/" }
  ],
  "permissions": [
    {
      "user": "guest",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    }
  ],
  "exchanges": [
    {
      "name": "{projeto}.exchange",
      "vhost": "/",
      "type": "topic",
      "durable": true,
      "auto_delete": false
    },
    {
      "name": "{projeto}.dlx",
      "vhost": "/",
      "type": "fanout",
      "durable": true,
      "auto_delete": false
    }
  ],
  "queues": [
    {
      "name": "{projeto}.queue",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-dead-letter-exchange": "{projeto}.dlx"
      }
    },
    {
      "name": "{projeto}.dlq",
      "vhost": "/",
      "durable": true,
      "auto_delete": false
    }
  ],
  "bindings": [
    {
      "source": "{projeto}.exchange",
      "vhost": "/",
      "destination": "{projeto}.queue",
      "destination_type": "queue",
      "routing_key": "#"
    },
    {
      "source": "{projeto}.dlx",
      "vhost": "/",
      "destination": "{projeto}.dlq",
      "destination_type": "queue",
      "routing_key": ""
    }
  ]
}
```

### Health Check

```csharp
services.AddHealthChecks()
    .AddRabbitMQ(
        rabbitConnectionString: $"amqp://{config["Username"]}:{config["Password"]}@{config["Host"]}:{config["Port"]}/{config["VirtualHost"]}",
        name: "rabbitmq",
        tags: ["messaging", "rabbitmq"]);
```

## Configuração gRPC

### appsettings.json

```json
{
  "Grpc": {
    "Services": {
      "{Service}": {
        "Address": "https://localhost:5001",
        "Timeout": "00:00:30",
        "RetryCount": 3
      }
    },
    "Server": {
      "MaxReceiveMessageSize": 16777216,
      "MaxSendMessageSize": 16777216
    }
  }
}
```

### Proto File

```protobuf
syntax = "proto3";

option csharp_namespace = "{Projeto}.Grpc";

package {projeto};

service {Service}Service {
  rpc Get{Entity} (Get{Entity}Request) returns (Get{Entity}Response);
  rpc Create{Entity} (Create{Entity}Request) returns (Create{Entity}Response);
  rpc Update{Entity} (Update{Entity}Request) returns (Update{Entity}Response);
  rpc Delete{Entity} (Delete{Entity}Request) returns (Delete{Entity}Response);
  rpc List{Entities} (List{Entities}Request) returns (stream {Entity}Item);
}

message Get{Entity}Request {
  string id = 1;
}

message Get{Entity}Response {
  {Entity}Item item = 1;
}

message {Entity}Item {
  string id = 1;
  string name = 2;
  string email = 3;
  google.protobuf.Timestamp created_at = 4;
}

message Create{Entity}Request {
  string name = 1;
  string email = 2;
}

message Create{Entity}Response {
  string id = 1;
  bool success = 2;
  string message = 3;
}

message Update{Entity}Request {
  string id = 1;
  string name = 2;
  string email = 3;
}

message Update{Entity}Response {
  bool success = 1;
  string message = 2;
}

message Delete{Entity}Request {
  string id = 1;
}

message Delete{Entity}Response {
  bool success = 1;
  string message = 2;
}

message List{Entities}Request {
  int32 page_size = 1;
  string page_token = 2;
}
```

### gRPC Client Registration

```csharp
namespace {Projeto}.Infrastructure.Grpc;

public static class GrpcExtensions
{
    public static IServiceCollection AddGrpcClients(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var grpcConfig = configuration.GetSection("Grpc:Services");

        services.AddGrpcClient<{Service}.{Service}Client>(options =>
        {
            options.Address = new Uri(grpcConfig["{Service}:Address"]!);
        })
        .ConfigurePrimaryHttpMessageHandler(() =>
        {
            var handler = new HttpClientHandler();
            // Para desenvolvimento, aceitar certificados auto-assinados
            if (Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") == "Development")
            {
                handler.ServerCertificateCustomValidationCallback =
                    HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
            }
            return handler;
        })
        .AddPolicyHandler(GetRetryPolicy(grpcConfig.GetValue<int>("{Service}:RetryCount")));

        services.AddScoped<I{Service}Client, {Service}GrpcClient>();

        return services;
    }

    private static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy(int retryCount)
    {
        return HttpPolicyExtensions
            .HandleTransientHttpError()
            .OrResult(msg => msg.StatusCode == System.Net.HttpStatusCode.NotFound)
            .WaitAndRetryAsync(
                retryCount,
                retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)));
    }
}
```

### gRPC Server Configuration

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddGrpc(options =>
{
    options.MaxReceiveMessageSize = builder.Configuration.GetValue<int>("Grpc:Server:MaxReceiveMessageSize");
    options.MaxSendMessageSize = builder.Configuration.GetValue<int>("Grpc:Server:MaxSendMessageSize");
    options.EnableDetailedErrors = builder.Environment.IsDevelopment();
    options.Interceptors.Add<LoggingInterceptor>();
    options.Interceptors.Add<ExceptionInterceptor>();
});

var app = builder.Build();

app.MapGrpcService<{Service}GrpcService>();
app.MapGrpcReflectionService(); // Para desenvolvimento

app.Run();
```

### Health Check

```csharp
services.AddHealthChecks()
    .AddCheck<GrpcHealthCheck>(
        "{Service}Grpc",
        tags: ["grpc", "services"]);
```

## Configuração ETCD

### appsettings.json

```json
{
  "Etcd": {
    "ConnectionString": "http://localhost:2379",
    "Prefix": "/config/{projeto}/",
    "Username": "",
    "Password": "",
    "WatchEnabled": true,
    "CacheTimeout": "00:05:00"
  }
}
```

### ETCD Configuration Provider

```csharp
namespace {Projeto}.Infrastructure.Configuration;

public sealed class EtcdConfigurationProvider : ConfigurationProvider, IDisposable
{
    private readonly EtcdClient _client;
    private readonly string _prefix;
    private readonly bool _watchEnabled;
    private readonly ILogger<EtcdConfigurationProvider> _logger;
    private CancellationTokenSource? _watchCts;

    public EtcdConfigurationProvider(
        string connectionString,
        string prefix,
        bool watchEnabled,
        ILoggerFactory loggerFactory)
    {
        _client = new EtcdClient(connectionString);
        _prefix = prefix;
        _watchEnabled = watchEnabled;
        _logger = loggerFactory.CreateLogger<EtcdConfigurationProvider>();
    }

    public override void Load()
    {
        LoadAsync().GetAwaiter().GetResult();

        if (_watchEnabled)
        {
            StartWatching();
        }
    }

    private async Task LoadAsync()
    {
        try
        {
            var response = await _client.GetRangeAsync(_prefix);

            Data = response.Kvs.ToDictionary(
                kv => ConvertKeyToConfigPath(kv.Key.ToStringUtf8()),
                kv => kv.Value.ToStringUtf8());

            _logger.LogInformation(
                "Loaded {Count} configuration values from ETCD with prefix {Prefix}",
                Data.Count, _prefix);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load configuration from ETCD");
            throw;
        }
    }

    private void StartWatching()
    {
        _watchCts = new CancellationTokenSource();

        Task.Run(async () =>
        {
            try
            {
                await foreach (var response in _client.WatchRangeAsync(
                    _prefix,
                    cancellationToken: _watchCts.Token))
                {
                    foreach (var @event in response.Events)
                    {
                        var key = ConvertKeyToConfigPath(@event.Kv.Key.ToStringUtf8());

                        if (@event.Type == Mvccpb.Event.Types.EventType.Put)
                        {
                            Data[key] = @event.Kv.Value.ToStringUtf8();
                            _logger.LogInformation("Configuration updated: {Key}", key);
                        }
                        else if (@event.Type == Mvccpb.Event.Types.EventType.Delete)
                        {
                            Data.Remove(key);
                            _logger.LogInformation("Configuration removed: {Key}", key);
                        }
                    }

                    OnReload();
                }
            }
            catch (OperationCanceledException)
            {
                // Expected when disposing
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error watching ETCD configuration");
            }
        }, _watchCts.Token);
    }

    private string ConvertKeyToConfigPath(string etcdKey)
    {
        return etcdKey
            .Replace(_prefix, "")
            .Replace("/", ":");
    }

    public void Dispose()
    {
        _watchCts?.Cancel();
        _watchCts?.Dispose();
        _client?.Dispose();
    }
}

public sealed class EtcdConfigurationSource : IConfigurationSource
{
    public string ConnectionString { get; set; } = default!;
    public string Prefix { get; set; } = default!;
    public bool WatchEnabled { get; set; } = true;
    public ILoggerFactory LoggerFactory { get; set; } = default!;

    public IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        return new EtcdConfigurationProvider(
            ConnectionString,
            Prefix,
            WatchEnabled,
            LoggerFactory);
    }
}

public static class EtcdConfigurationExtensions
{
    public static IConfigurationBuilder AddEtcd(
        this IConfigurationBuilder builder,
        Action<EtcdConfigurationSource> configure)
    {
        var source = new EtcdConfigurationSource();
        configure(source);
        return builder.Add(source);
    }
}
```

### Program.cs Integration

```csharp
var builder = WebApplication.CreateBuilder(args);

// Adicionar ETCD como fonte de configuração
var etcdConfig = builder.Configuration.GetSection("Etcd");
if (!string.IsNullOrEmpty(etcdConfig["ConnectionString"]))
{
    builder.Configuration.AddEtcd(options =>
    {
        options.ConnectionString = etcdConfig["ConnectionString"]!;
        options.Prefix = etcdConfig["Prefix"] ?? "/config/";
        options.WatchEnabled = etcdConfig.GetValue<bool>("WatchEnabled");
        options.LoggerFactory = LoggerFactory.Create(logging =>
        {
            logging.AddConsole();
            logging.SetMinimumLevel(LogLevel.Information);
        });
    });
}
```

### Seeding Initial Configuration

```bash
#!/bin/bash
# scripts/seed-etcd.sh

ETCD_HOST=${ETCD_HOST:-localhost:2379}
PREFIX="/config/{projeto}/"

# Database
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}ConnectionStrings/DefaultConnection" "Host=postgres;Database=appdb;Username=app;Password=app"

# RabbitMQ
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}RabbitMQ/Host" "rabbitmq"
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}RabbitMQ/Port" "5672"
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}RabbitMQ/Username" "guest"
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}RabbitMQ/Password" "guest"

# Feature Flags
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}Features/NewFeatureEnabled" "true"
etcdctl --endpoints=$ETCD_HOST put "${PREFIX}Features/MaxRetryCount" "3"

echo "Configuration seeded successfully!"
```

### Health Check

```csharp
services.AddHealthChecks()
    .AddCheck<EtcdHealthCheck>(
        "etcd",
        tags: ["configuration", "etcd"]);

public sealed class EtcdHealthCheck : IHealthCheck
{
    private readonly EtcdClient _client;

    public EtcdHealthCheck(IConfiguration configuration)
    {
        var connectionString = configuration["Etcd:ConnectionString"];
        _client = new EtcdClient(connectionString);
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await _client.StatusAsync(new StatusRequest());
            return HealthCheckResult.Healthy("ETCD is healthy");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy(
                "ETCD is unhealthy",
                exception: ex);
        }
    }
}
```

## Dockerfile Otimizado

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

# Copiar arquivos de projeto e restaurar dependências
COPY ["src/{Projeto}.API/{Projeto}.API.csproj", "src/{Projeto}.API/"]
COPY ["src/{Projeto}.Application/{Projeto}.Application.csproj", "src/{Projeto}.Application/"]
COPY ["src/{Projeto}.Domain/{Projeto}.Domain.csproj", "src/{Projeto}.Domain/"]
COPY ["src/{Projeto}.Infrastructure/{Projeto}.Infrastructure.csproj", "src/{Projeto}.Infrastructure/"]

RUN dotnet restore "src/{Projeto}.API/{Projeto}.API.csproj"

# Copiar código fonte
COPY src/ src/

# Build e publish
WORKDIR "/src/src/{Projeto}.API"
RUN dotnet publish "{Projeto}.API.csproj" -c Release -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app

# Criar usuário não-root
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# Copiar aplicação
COPY --from=build /app/publish .

# Configurar permissões
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 80 443 5001

ENTRYPOINT ["dotnet", "{Projeto}.API.dll"]
```

## Checklist de Infraestrutura

Antes de finalizar, verificar:
- [ ] docker-compose.yml com todos os serviços
- [ ] Health checks configurados para cada serviço
- [ ] Variáveis de ambiente documentadas
- [ ] Scripts de inicialização (init.sql, seed-etcd.sh)
- [ ] Retry policies configuradas
- [ ] Logging configurado corretamente
- [ ] Secrets não expostos em código
- [ ] Dockerfile multi-stage otimizado
- [ ] Volumes persistentes configurados
