FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app

COPY src/ ./

RUN dotnet restore src.sln
RUN dotnet publish Xebia.Monitoring.Entra.ApplicationSecrets.csproj -o out


FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app/out .
ENTRYPOINT ["dotnet", "Xebia.Monitoring.Entra.ApplicationSecrets.dll"]