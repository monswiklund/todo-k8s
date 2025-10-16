using MongoDB.Driver;
using ToDoApp.Models;

namespace ToDoApp.Services;

public class TaskService
{
    private readonly IMongoCollection<TodoTask> _tasks;
    private readonly ILogger<TaskService> _logger;

    public TaskService(IMongoCollection<TodoTask> tasks, ILogger<TaskService> logger)
    {
        _tasks = tasks;
        _logger = logger;
    }

    public async Task<List<TodoTask>> GetAllAsync(int limit = 100)
    {
        _logger.LogInformation("Getting all tasks with limit {Limit}", limit);

        try
        {
            var tasks = await _tasks.Find(Builders<TodoTask>.Filter.Empty)
                .Limit(limit)
                .ToListAsync();

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
            var task = await _tasks.Find(t => t.Id == id).FirstOrDefaultAsync();

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
            await _tasks.InsertOneAsync(newTask);

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
            var result = await _tasks.ReplaceOneAsync(task => task.Id == updatedTasks.Id, updatedTasks);

            if (result.MatchedCount == 0)
            {
                _logger.LogWarning("No task found to update with ID {TaskId}", updatedTasks.Id);
                throw new KeyNotFoundException($"Task with ID '{updatedTasks.Id}' not found.");
            }

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
            var result = await _tasks.DeleteOneAsync(task => task.Id == id);

            if (result.DeletedCount == 0)
                _logger.LogWarning("No task found to delete with ID {TaskId}", id);

            _logger.LogInformation("Successfully deleted task {TaskId}", id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting task {TaskId}", id);
            throw;
        }
    }
}
