using Amazon.DynamoDBv2.DataModel;
using ToDoApp.Models;

namespace ToDoApp.Services;

public class TaskService
{
    private readonly IDynamoDBContext _context;
    private readonly ILogger<TaskService> _logger;

    public TaskService(IDynamoDBContext context, ILogger<TaskService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<List<TodoTask>> GetAllAsync(int limit = 100)
    {
        _logger.LogInformation("Getting all tasks with limit {Limit}", limit);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };

            var scan = _context.ScanAsync<TodoTask>(new List<ScanCondition>(), config);
            var tasks = await scan.GetNextSetAsync();

            _logger.LogInformation("Retrieved {TaskCount} tasks", tasks.Count);
            return tasks;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving tasks");
            throw;
        }
    }

    public async Task<TodoTask?> GetByIdAsync(string id)
    {
        _logger.LogInformation("Getting task with ID: {TaskId}", id);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };
            var task = await _context.LoadAsync<TodoTask>(id, config);

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

    public async Task CreateAsync(TodoTask newTask)
    {
        _logger.LogInformation("Creating new task: {TaskTitle} with ID: {TaskId}", newTask.Title, newTask.Id);

        try
        {
            var config = new DynamoDBOperationConfig
            {
                OverrideTableName = "Tasks"
            };
            await _context.SaveAsync(newTask, config);

            _logger.LogInformation("Successfully created task {TaskId}: {TaskTitle}", newTask.Id, newTask.Title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating task {TaskId}: {TaskTitle}", newTask.Id, newTask.Title);
            throw;
        }
    }

    public async Task UpdateAsync(TodoTask updatedTasks)
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
            await _context.DeleteAsync<TodoTask>(id, config);

            _logger.LogInformation("Successfully deleted task {TaskId}", id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting task {TaskId}", id);
            throw;
        }
    }
}