using System.Diagnostics.Metrics;

namespace ToDoApp.Services;

public class MetricsService
{
    private readonly Meter _meter;
    private readonly Histogram<double> _requestDuration;
    private readonly Counter<int> _requestsTotal;
    private readonly Counter<int> _tasksCompleted;
    private readonly Counter<int> _tasksCreated;
    private readonly Counter<int> _tasksDeleted;

    public MetricsService()
    {
        _meter = new Meter("ToDoApp", "1.0.0");

        _tasksCreated = _meter.CreateCounter<int>(
            "todoapp_tasks_created_total",
            description: "Total number of tasks created");

        _tasksCompleted = _meter.CreateCounter<int>(
            "todoapp_tasks_completed_total",
            description: "Total number of tasks marked as completed");

        _tasksDeleted = _meter.CreateCounter<int>(
            "todoapp_tasks_deleted_total",
            description: "Total number of tasks deleted");

        _requestsTotal = _meter.CreateCounter<int>(
            "todoapp_requests_total",
            description: "Total number of HTTP requests");

        _requestDuration = _meter.CreateHistogram<double>(
            "todoapp_request_duration_seconds",
            description: "HTTP request duration in seconds");
    }

    public void IncrementTasksCreated() => _tasksCreated.Add(1);

    public void IncrementTasksCompleted() => _tasksCompleted.Add(1);

    public void IncrementTasksDeleted() => _tasksDeleted.Add(1);

    public void IncrementRequests(string method, string endpoint) =>
        _requestsTotal.Add(1, new KeyValuePair<string, object?>("method", method),
            new KeyValuePair<string, object?>("endpoint", endpoint));

    public void RecordRequestDuration(double duration, string method, string endpoint) =>
        _requestDuration.Record(duration, new KeyValuePair<string, object?>("method", method),
            new KeyValuePair<string, object?>("endpoint", endpoint));
}