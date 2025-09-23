using Amazon.DynamoDBv2.DataModel;
using ToDoApp.Models;

namespace ToDoApp.Services;

public class TaskService
{
    private readonly IDynamoDBContext _context;

    public TaskService(IDynamoDBContext context)
    {
        _context = context;
    }

    public async Task<List<TaskModels>> GetAllAsync()
    {
        // Måste override table name eftersom DynamoDBContext inte hittar det automatisk när metadata loading är disabled (som jag hade problem med)
        var config = new DynamoDBOperationConfig
        {
            OverrideTableName = "Tasks"
        };
        
        var scan = _context.ScanAsync<TaskModels>(new List<ScanCondition>(), config);
        return await scan.GetRemainingAsync();
    }

    public async Task<TaskModels?> GetByIdAsync(string id)
    {
        var config = new DynamoDBOperationConfig
        {
            OverrideTableName = "Tasks" 
        };
        return await _context.LoadAsync<TaskModels>(id, config);
    }

    public async Task CreateAsync(TaskModels newTask)
    {
        var config = new DynamoDBOperationConfig
        {
            OverrideTableName = "Tasks"
        };
        await _context.SaveAsync(newTask, config);
    }

    public async Task UpdateAsync(TaskModels updatedTasks)
    {
        var config = new DynamoDBOperationConfig
        {
            OverrideTableName = "Tasks"
        };
        // SaveAsync fungerar som både insert och update i DynamoDB
        await _context.SaveAsync(updatedTasks, config);
    }

    public async Task DeleteAsync(string id)
    {
        var config = new DynamoDBOperationConfig
        {
            OverrideTableName = "Tasks"
        };
        await _context.DeleteAsync<TaskModels>(id, config);
    }
}