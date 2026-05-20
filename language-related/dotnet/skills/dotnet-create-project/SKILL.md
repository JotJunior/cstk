---
name: dotnet-create-project
description: |
  Cria novo projeto .NET 10 com arquitetura hexagonal, CQRS, Clean Code e SOLID.
  Triggers: "criar projeto dotnet", "new dotnet project", "novo projeto .NET".
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

# Criar Projeto .NET 10

Crie um novo projeto .NET 10 seguindo arquitetura hexagonal, CQRS, Clean Code e SOLID.

## Argumentos

$ARGUMENTS

## Instruções

Analise o argumento fornecido. Ele deve conter:
1. **Nome do projeto**: Nome da solução/projeto
2. **Descrição**: Breve descrição do domínio/funcionalidade

### Passos para criação:

1. **Crie a estrutura de diretórios**:

```
{NomeProjeto}/
├── src/
│   ├── {NomeProjeto}.Domain/
│   │   ├── Entities/
│   │   ├── ValueObjects/
│   │   ├── Enums/
│   │   ├── Exceptions/
│   │   ├── Events/
│   │   └── Specifications/
│   ├── {NomeProjeto}.Application/
│   │   ├── Common/
│   │   │   ├── Behaviors/
│   │   │   ├── Interfaces/
│   │   │   └── Mappings/
│   │   ├── Commands/
│   │   ├── Queries/
│   │   └── EventHandlers/
│   ├── {NomeProjeto}.Infrastructure/
│   │   ├── Persistence/
│   │   │   ├── Configurations/
│   │   │   ├── Repositories/
│   │   │   └── Migrations/
│   │   ├── Messaging/
│   │   │   ├── Publishers/
│   │   │   └── Consumers/
│   │   ├── Grpc/
│   │   │   ├── Clients/
│   │   │   └── Services/
│   │   └── Configuration/
│   └── {NomeProjeto}.API/
│       ├── Controllers/
│       ├── Grpc/
│       ├── Middleware/
│       └── Filters/
├── tests/
│   ├── {NomeProjeto}.Domain.Tests/
│   ├── {NomeProjeto}.Application.Tests/
│   ├── {NomeProjeto}.Infrastructure.Tests/
│   └── {NomeProjeto}.API.Tests/
├── docker/
│   ├── docker-compose.yml
│   └── docker-compose.override.yml
├── scripts/
│   ├── init.sql
│   └── seed-etcd.sh
└── docs/
```

2. **Crie os arquivos de projeto (.csproj)**:

### Domain

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
```

### Application

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="FluentValidation" Version="11.*" />
    <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.*" />
    <PackageReference Include="Mapster" Version="7.*" />
    <PackageReference Include="MediatR" Version="12.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\{NomeProjeto}.Domain\{NomeProjeto}.Domain.csproj" />
  </ItemGroup>
</Project>
```

### Infrastructure

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.*" />
    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.*" />
    <PackageReference Include="RabbitMQ.Client" Version="7.*" />
    <PackageReference Include="Grpc.Net.Client" Version="2.*" />
    <PackageReference Include="Grpc.Net.ClientFactory" Version="2.*" />
    <PackageReference Include="dotnet-etcd" Version="7.*" />
    <PackageReference Include="Polly" Version="8.*" />
    <PackageReference Include="Serilog" Version="4.*" />
    <PackageReference Include="Serilog.Sinks.Console" Version="6.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\{NomeProjeto}.Domain\{NomeProjeto}.Domain.csproj" />
    <ProjectReference Include="..\{NomeProjeto}.Application\{NomeProjeto}.Application.csproj" />
  </ItemGroup>
</Project>
```

### API

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Grpc.AspNetCore" Version="2.*" />
    <PackageReference Include="AspNetCore.HealthChecks.NpgSql" Version="8.*" />
    <PackageReference Include="AspNetCore.HealthChecks.Rabbitmq" Version="8.*" />
    <PackageReference Include="Serilog.AspNetCore" Version="8.*" />
    <PackageReference Include="Swashbuckle.AspNetCore" Version="6.*" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\{NomeProjeto}.Application\{NomeProjeto}.Application.csproj" />
    <ProjectReference Include="..\{NomeProjeto}.Infrastructure\{NomeProjeto}.Infrastructure.csproj" />
  </ItemGroup>
</Project>
```

3. **Crie os arquivos base**:

### BaseEntity.cs (Domain)

```csharp
namespace {NomeProjeto}.Domain.Entities;

public abstract class BaseEntity
{
    public Guid Id { get; protected set; }
    public DateTime CreatedAt { get; protected set; }
    public DateTime? UpdatedAt { get; protected set; }

    private readonly List<IDomainEvent> _domainEvents = [];

    public IReadOnlyCollection<IDomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    protected void RaiseDomainEvent(IDomainEvent domainEvent)
    {
        _domainEvents.Add(domainEvent);
    }

    public void ClearDomainEvents()
    {
        _domainEvents.Clear();
    }
}
```

### Result.cs (Domain)

```csharp
namespace {NomeProjeto}.Domain;

public class Result<T>
{
    public bool IsSuccess { get; }
    public bool IsFailure => !IsSuccess;
    public T? Value { get; }
    public string? Error { get; }

    private Result(bool isSuccess, T? value, string? error)
    {
        IsSuccess = isSuccess;
        Value = value;
        Error = error;
    }

    public static Result<T> Success(T value) => new(true, value, null);
    public static Result<T> Failure(string error) => new(false, default, error);
}
```

### IUnitOfWork.cs (Application)

```csharp
namespace {NomeProjeto}.Application.Common.Interfaces;

public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

### DependencyInjection.cs (Application)

```csharp
namespace {NomeProjeto}.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = typeof(DependencyInjection).Assembly;

        services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));

        services.AddValidatorsFromAssembly(assembly);

        services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));

        return services;
    }
}
```

### DependencyInjection.cs (Infrastructure)

```csharp
namespace {NomeProjeto}.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // PostgreSQL
        services.AddDbContext<ApplicationDbContext>(options =>
            options.UseNpgsql(
                configuration.GetConnectionString("DefaultConnection"),
                b => b.MigrationsAssembly(typeof(ApplicationDbContext).Assembly.FullName)));

        services.AddScoped<IUnitOfWork, UnitOfWork>();

        // Repositórios
        // services.AddScoped<I{Entity}Repository, {Entity}Repository>();

        return services;
    }
}
```

### Program.cs (API)

```csharp
using {NomeProjeto}.Application;
using {NomeProjeto}.Infrastructure;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Serilog
builder.Host.UseSerilog((context, configuration) =>
    configuration.ReadFrom.Configuration(context.Configuration));

// Services
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddGrpc();

builder.Services.AddHealthChecks()
    .AddNpgSql(builder.Configuration.GetConnectionString("DefaultConnection")!);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseSerilogRequestLogging();

app.UseHttpsRedirection();
app.UseAuthorization();

app.MapControllers();
app.MapHealthChecks("/health");

app.Run();

public partial class Program { }
```

4. **Crie o docker-compose.yml**:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: {nomeprojeto}db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  rabbitmq:
    image: rabbitmq:3.13-management-alpine
    ports:
      - "5672:5672"
      - "15672:15672"
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq

  etcd:
    image: quay.io/coreos/etcd:v3.5.12
    environment:
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd:2379
    ports:
      - "2379:2379"

volumes:
  postgres_data:
  rabbitmq_data:
```

5. **Crie os arquivos de configuração**:

### appsettings.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database={nomeprojeto}db;Username=app;Password=app"
  },
  "RabbitMQ": {
    "Host": "localhost",
    "Port": 5672,
    "Username": "guest",
    "Password": "guest"
  },
  "Etcd": {
    "ConnectionString": "http://localhost:2379",
    "Prefix": "/config/{nomeprojeto}/"
  },
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "System": "Warning"
      }
    },
    "WriteTo": [
      { "Name": "Console" }
    ]
  }
}
```

6. **Execute os comandos para criar a solução**:

```bash
dotnet new sln -n {NomeProjeto}
dotnet new classlib -n {NomeProjeto}.Domain -o src/{NomeProjeto}.Domain
dotnet new classlib -n {NomeProjeto}.Application -o src/{NomeProjeto}.Application
dotnet new classlib -n {NomeProjeto}.Infrastructure -o src/{NomeProjeto}.Infrastructure
dotnet new webapi -n {NomeProjeto}.API -o src/{NomeProjeto}.API
dotnet new xunit -n {NomeProjeto}.Domain.Tests -o tests/{NomeProjeto}.Domain.Tests
dotnet new xunit -n {NomeProjeto}.Application.Tests -o tests/{NomeProjeto}.Application.Tests
dotnet new xunit -n {NomeProjeto}.Infrastructure.Tests -o tests/{NomeProjeto}.Infrastructure.Tests
dotnet new xunit -n {NomeProjeto}.API.Tests -o tests/{NomeProjeto}.API.Tests

dotnet sln add src/{NomeProjeto}.Domain
dotnet sln add src/{NomeProjeto}.Application
dotnet sln add src/{NomeProjeto}.Infrastructure
dotnet sln add src/{NomeProjeto}.API
dotnet sln add tests/{NomeProjeto}.Domain.Tests
dotnet sln add tests/{NomeProjeto}.Application.Tests
dotnet sln add tests/{NomeProjeto}.Infrastructure.Tests
dotnet sln add tests/{NomeProjeto}.API.Tests
```

## Saída Esperada

Após criar o projeto, apresente:

1. **Estrutura criada** - Listagem dos diretórios e arquivos
2. **Próximos passos** - O que o usuário deve fazer a seguir
3. **Comandos úteis**:
   - `docker-compose up -d` - Subir infraestrutura
   - `dotnet ef migrations add Initial` - Criar primeira migração
   - `dotnet ef database update` - Aplicar migração
   - `dotnet run --project src/{NomeProjeto}.API` - Executar API
