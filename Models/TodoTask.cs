using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ToDoApp.Models;

[BsonIgnoreExtraElements]
public class TodoTask
{
    // Identifier saved as string to keep compatibility with existing clients
    [BsonId]
    [BsonRepresentation(BsonType.String)]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsCompleted { get; set; }
}
