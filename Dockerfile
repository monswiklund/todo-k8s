# ---- Build stage ----
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ToDoApp.csproj ./
RUN dotnet restore ToDoApp.csproj
COPY . .
RUN dotnet publish ToDoApp.csproj -c Release -o /app

# ---- Runtime stage ----
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "ToDoApp.dll"]