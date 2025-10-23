using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Mvc;
using MongoDB.Bson;
using MongoDB.Driver;
using ToDoApp.Models;
using ToDoApp.Services;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Konfigurera Serilog för console logging
builder.Host.UseSerilog((context, services, configuration) =>
{
    configuration
        .ReadFrom.Configuration(context.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .WriteTo.Console();
});

// Swagger för API-dokumentation
builder.Services.AddOpenApi();

// Rate limiting - 100 requests per minut per IP
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                Window = TimeSpan.FromMinutes(1),
                PermitLimit = 100,
                QueueProcessingOrder = System.Threading.RateLimiting.QueueProcessingOrder.OldestFirst,
                QueueLimit = 10
            }));

    options.OnRejected = async (context, token) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            error = "Rate limit exceeded. Please try again later.",
            retryAfter = "60 seconds"
        }, cancellationToken: token);
    };
});

// Läs in MongoDB-connectionstring från miljövariabler eller appsettings
var mongoConn = Environment.GetEnvironmentVariable("MONGO_URI");

if (string.IsNullOrEmpty(mongoConn))
{
    mongoConn = Environment.GetEnvironmentVariable("MONGO_CONNECTION_STRING");
}

if (string.IsNullOrEmpty(mongoConn))
{
    mongoConn = builder.Configuration["Mongo:ConnectionString"];
}

if (string.IsNullOrEmpty(mongoConn))
{
    Console.WriteLine("MongoDB-connection saknas i miljövariabler eller konfiguration.");
    throw new InvalidOperationException("MONGO_URI or MONGO_CONNECTION_STRING environment variable is required.");
}

Console.WriteLine($"Using MongoDB connection: {mongoConn}");

var mongoUrl = MongoUrl.Create(mongoConn);
var databaseName = mongoUrl.DatabaseName ?? builder.Configuration["Mongo:DatabaseName"] ?? "ToDoAppDb";

builder.Services.AddSingleton(mongoUrl);
builder.Services.AddSingleton<IMongoClient>(_ => new MongoClient(mongoUrl));
builder.Services.AddSingleton<IMongoDatabase>(sp =>
{
    var client = sp.GetRequiredService<IMongoClient>();
    return client.GetDatabase(databaseName);
});
builder.Services.AddSingleton<IMongoCollection<TodoTask>>(sp =>
{
    var database = sp.GetRequiredService<IMongoDatabase>();
    return database.GetCollection<TodoTask>("Todos");
});
builder.Services.AddControllers();

builder.Services.AddScoped<TaskService>();

var app = builder.Build();

// Serilog request logging
app.UseSerilogRequestLogging();

// Aktivera rate limiting
app.UseRateLimiter();

app.MapOpenApi();
app.UseSwaggerUI(options => { options.SwaggerEndpoint("/openapi/v1.json", "v1"); });

// Serve static files från wwwroot
app.UseStaticFiles();

// Serve startpage istället för redirect
app.MapGet("/", () => Results.File("~/index.html", "text/html"));

// Hämta alla todos med optional pagination
app.MapGet("/todos", async (TaskService taskService, int? limit) =>
    Results.Ok(await taskService.GetAllAsync(limit ?? 100))
);

// Hämta en specifik todo
app.MapGet("/todos/{id}", async (string id, TaskService service) =>
{
    var todo = await service.GetByIdAsync(id);
    return todo != null ? Results.Ok(todo) : Results.NotFound();
});

// Skapa ny todo
app.MapPost("/todos", async (TodoTask newTask, TaskService service) =>
{
    // Validera input
    if (string.IsNullOrWhiteSpace(newTask.Title))
        return Results.BadRequest(new { error = "Title is required and cannot be empty" });

    if (newTask.Title.Length > 200)
        return Results.BadRequest(new { error = "Title cannot exceed 200 characters" });

    newTask.Id = Guid.NewGuid().ToString(); // Genererar nytt ID
    await service.CreateAsync(newTask);
    return Results.Created($"/todos/{newTask.Id}", newTask);
});

// Uppdatera todo
app.MapPut("/todos/{id}", async (string id, TodoTask updatedTask, TaskService service) =>
{
    // Validera input
    if (string.IsNullOrWhiteSpace(updatedTask.Title))
        return Results.BadRequest(new { error = "Title is required and cannot be empty" });

    if (updatedTask.Title.Length > 200)
        return Results.BadRequest(new { error = "Title cannot exceed 200 characters" });

    // Verifiera att task existerar
    var existing = await service.GetByIdAsync(id);
    if (existing == null)
        return Results.NotFound(new { error = $"Task with ID '{id}' not found" });

    updatedTask.Id = id; // Använder ID från URL
    await service.UpdateAsync(updatedTask);
    return Results.Ok(updatedTask);
});

// Ta bort todo
app.MapDelete("/todos/{id}", async (string id, TaskService service) =>
{
    await service.DeleteAsync(id);
    return Results.NoContent();
});

// Health check endpoint that verifies MongoDB connectivity
app.MapGet("/health", async ([FromServices] IMongoDatabase database) =>
{
    try
    {
        await database.RunCommandAsync<BsonDocument>(new BsonDocument("ping", 1));

        var healthData = new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow,
            version = "3.0",
            environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"),
            database = database.DatabaseNamespace.DatabaseName,
            hostname = Environment.MachineName
        };

        return Results.Ok(healthData);
    }
    catch (Exception ex)
    {
        var errorData = new
        {
            status = "unhealthy",
            timestamp = DateTime.UtcNow,
            error = ex.Message,
            database = database.DatabaseNamespace.DatabaseName,
            version = "3.0"
        };

        return Results.Json(errorData, statusCode: 503);
    }
});

// Explicit IPv4 binding för ALB health checks
app.Run();
