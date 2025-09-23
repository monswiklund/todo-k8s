using Amazon.DynamoDBv2.DataModel;

namespace ToDoApp.Models;

[DynamoDBTable("Tasks")]
public class TaskModels
{
    // Primary key i DynamoDB - genererar automatiskt nytt GUID
    [DynamoDBHashKey]
    public string  Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsCompleted { get; set; }
}