using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using ToDoApp.Models;
using ToDoApp.Services;

var builder = WebApplication.CreateBuilder(args);

// Swagger för API-dokumentation
builder.Services.AddOpenApi();
builder.Services.AddSwaggerGen();

// AWS DynamoDB setup
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

app.MapOpenApi();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/openapi/v1.json", "v1");
});

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

// Lyssna på alla interfaces för Docker
app.Run("http://*:8080");