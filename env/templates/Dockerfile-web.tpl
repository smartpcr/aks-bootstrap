FROM {{.Values.acr.name}}.azurecr.io/aspnetcore-runtime:latest AS base
WORKDIR /app
EXPOSE 80

FROM {{.Values.acr.name}}.azurecr.io/dotnetcore-sdk:latest AS build

# install nodejs
USER root
ENV NODE_VERSION 8.11.3
ENV NODE_DOWNLOAD_SHA 1ea408e9a467ed4571730e160993f67a100e8c347f6f9891c9a83350df2bf2be
RUN curl -SL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" --output nodejs.tar.gz \
    && echo "$NODE_DOWNLOAD_SHA nodejs.tar.gz" | sha256sum -c - \
    && tar -xzf "nodejs.tar.gz" -C /usr/local --strip-components=1 \
    && rm nodejs.tar.gz \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs

USER dotnet
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
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "{{.Values.service.assemblyName}}.dll"]