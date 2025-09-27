using Amazon.DynamoDBv2.DataModel;
using ToDoApp.Models;

namespace ToDoApp.Services;

public class TaskService
{
    private readonly IDynamoDBContext _context;
    private readonly ILogger<TaskService> _logger;
    private readonly MetricsService _metrics;

    public TaskService(IDynamoDBContext context, ILogger<TaskService> logger, MetricsService metrics)
    {
        _context = context;
        _logger = logger;
        _metrics = metrics;
    }

    public async Task<List<TaskModels>> GetAllAsync()
    {
        _logger.LogInformation("Getting all tasks");

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };

            var scan = _context.ScanAsync<TaskModels>(new List<ScanCondition>(), config);
            var tasks = await scan.GetRemainingAsync();

            _logger.LogInformation("Retrieved {TaskCount} tasks", tasks.Count);
            return tasks;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving tasks");
            throw;
        }
    }

    public async Task<TaskModels?> GetByIdAsync(string id)
    {
        _logger.LogInformation("Getting task with ID: {TaskId}", id);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };
            var task = await _context.LoadAsync<TaskModels>(id, config);

            if (task != null)
                _logger.LogInformation("Found task {TaskId}: {TaskTitle}", id, task.Title);
            else
                _logger.LogWarning("Task with ID {TaskId} not found", id);

            return task;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving task {TaskId}", id);
            throw;
        }
    }

    public async Task CreateAsync(TaskModels newTask)
    {
        _logger.LogInformation("Creating new task: {TaskTitle} with ID: {TaskId}", newTask.Title, newTask.Id);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };
            await _context.SaveAsync(newTask, config);
            _metrics.IncrementTasksCreated();

            _logger.LogInformation("Successfully created task {TaskId}: {TaskTitle}", newTask.Id, newTask.Title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating task {TaskId}: {TaskTitle}", newTask.Id, newTask.Title);
            throw;
        }
    }

    public async Task UpdateAsync(TaskModels updatedTasks)
    {
        _logger.LogInformation("Updating task {TaskId}: {TaskTitle}, Completed: {IsCompleted}",
            updatedTasks.Id, updatedTasks.Title, updatedTasks.IsCompleted);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };
            await _context.SaveAsync(updatedTasks, config);

            if (updatedTasks.IsCompleted)
                _metrics.IncrementTasksCompleted();

            _logger.LogInformation("Successfully updated task {TaskId}", updatedTasks.Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating task {TaskId}", updatedTasks.Id);
            throw;
        }
    }

    public async Task DeleteAsync(string id)
    {
        _logger.LogInformation("Deleting task with ID: {TaskId}", id);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };
            await _context.DeleteAsync<TaskModels>(id, config);
            _metrics.IncrementTasksDeleted();

            _logger.LogInformation("Successfully deleted task {TaskId}", id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting task {TaskId}", id);
            throw;
        }
    }
}