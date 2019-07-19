FROM {{.Values.acr.name}}.azurecr.io/aspnetcore-runtime:latest AS base
WORKDIR /app
EXPOSE 80

FROM {{.Values.acr.name}}.azurecr.io/dotnetcore-sdk:latest AS build
COPY --chown=dotnet . ./app/
WORKDIR /app

### RUN echo "{{.Values.nugetConfig}}" > nuget.config

RUN dotnet restore "{{.Values.service.solutionFile}}"
RUN dotnet build "{{.Values.service.solutionFile}}" -c {{.Values.service.buildConfiguration}}

FROM build AS publish
RUN dotnet publish "{{.Values.service.projectFile}}" -c {{.Values.service.buildConfiguration}} -o /app
### TODO: COPY space app setting file

RUN rm -f ./nuget.config

FROM base AS final
WORKDIR /app
COPY --from=publish --chown=dotnet /app .
ENTRYPOINT ["dotnet", "{{.Values.service.assemblyName}}.dll"]