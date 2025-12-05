# CodeMedic Dockerfile
# Multi-stage build for optimized image size

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
ARG VERSION=0.0.0
ARG ASSEMBLY_VERSION=0.0.0.0
ARG FILE_VERSION=0.0.0.0
ARG INFORMATIONAL_VERSION=0.0.0
WORKDIR /src

# Copy project files
COPY ["src/CodeMedic.Abstractions/CodeMedic.Abstractions.csproj", "src/CodeMedic.Abstractions/"]
COPY ["src/CodeMedic/CodeMedic.csproj", "src/CodeMedic/"]

# Restore dependencies
RUN dotnet restore "src/CodeMedic/CodeMedic.csproj"

# Copy source code
COPY . .

# Build and publish
WORKDIR "/src/src/CodeMedic"
RUN dotnet build "CodeMedic.csproj" \
    -c $BUILD_CONFIGURATION \
    -o /app/build \
    /p:Version=$VERSION \
    /p:AssemblyVersion=$ASSEMBLY_VERSION \
    /p:FileVersion=$FILE_VERSION \
    /p:InformationalVersion=$INFORMATIONAL_VERSION

RUN dotnet publish "CodeMedic.csproj" \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    /p:UseAppHost=false \
    /p:Version=$VERSION \
    /p:AssemblyVersion=$ASSEMBLY_VERSION \
    /p:FileVersion=$FILE_VERSION \
    /p:InformationalVersion=$INFORMATIONAL_VERSION

# Runtime stage
FROM mcr.microsoft.com/dotnet/runtime:10.0 AS final
WORKDIR /app

# Copy published application
COPY --from=build /app/publish .

# Set entrypoint
ENTRYPOINT ["dotnet", "CodeMedic.dll"]

# Default command (shows help)
CMD ["--help"]
