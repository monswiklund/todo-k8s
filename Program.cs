using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
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
builder.Services.AddSwaggerGen();

// AWS services setup
builder.Services.AddAWSService<IAmazonDynamoDB>();
builder.Services.AddSingleton<IDynamoDBContext>(provider =>
{
    var client = provider.GetRequiredService<IAmazonDynamoDB>();
    var config = new DynamoDBContextConfig
    {
        // Fick problem med att containers kraschade pga DescribeTable-anrop så skippar metadata loading
        DisableFetchingTableMetadata = true
    };
    return new DynamoDBContext(client, config);
});

builder.Services.AddScoped<TaskService>();

var app = builder.Build();

// Serilog request logging
app.UseSerilogRequestLogging();

app.MapOpenApi();
app.UseSwaggerUI(options => { options.SwaggerEndpoint("/openapi/v1.json", "v1"); });

// Serve static files från wwwroot
app.UseStaticFiles();

// Serve startpage istället för redirect
app.MapGet("/", () => Results.File("~/index.html", "text/html"));

// Hämta alla todos
app.MapGet("/todos", async (TaskService taskService) =>
    Results.Ok(await taskService.GetAllAsync())
);

// Hämta en specifik todo
app.MapGet("/todos/{id}", async (string id, TaskService service) =>
{
    var todo = await service.GetByIdAsync(id);
    return todo != null ? Results.Ok(todo) : Results.NotFound();
});

// Skapa ny todo
app.MapPost("/todos", async (TaskModels newTask, TaskService service) =>
{
    newTask.Id = Guid.NewGuid().ToString(); // Genererar nytt ID
    await service.CreateAsync(newTask);
    return Results.Created($"/todos/{newTask.Id}", newTask);
});

// Uppdatera todo
app.MapPut("/todos/{id}", async (string id, TaskModels updatedTask, TaskService service) =>
{
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

// Health check endpoint för ALB med Docker Swarm status
app.MapGet("/health", async () =>
{
    try
    {
        var healthData = new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow,
            version = "3.0",
            environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"),
            aws_region = Environment.GetEnvironmentVariable("AWS_REGION"),
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
            version = "3.0"
        };

        return Results.Json(errorData, statusCode: 503);
    }
});

// Explicit IPv4 binding för ALB health checks
app.Run();