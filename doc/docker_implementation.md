# Docker Implementation

## Overview

CodeMedic now supports containerized execution through Docker, allowing users to run the tool without installing .NET locally. The implementation includes cross-platform build scripts that automatically version containers using Nerd Bank Git Versioning (NBGv2).

## Components

### 1. Dockerfile
Located at: `Dockerfile` (repository root)

**Multi-stage build strategy:**
- **Build stage**: Uses `mcr.microsoft.com/dotnet/sdk:10.0` to compile the application
- **Runtime stage**: Uses `mcr.microsoft.com/dotnet/runtime:10.0` for minimal final image size
- **Result**: ~204MB final image (vs ~800MB if SDK was included)

**Key features:**
- Accepts version information as build arguments (not copied from `version.json`)
- Restores dependencies using layer caching for faster rebuilds
- Version arguments: `VERSION`, `ASSEMBLY_VERSION`, `FILE_VERSION`, `INFORMATIONAL_VERSION`
- Sets `ENTRYPOINT` to `dotnet CodeMedic.dll`
- Default `CMD` shows help message
- Supports build configuration argument (`Release`/`Debug`)

**Cache optimization:**
- Project files copied before source code for optimal layer caching
- Version information passed as build arguments to avoid cache invalidation
- Dependency restore layer is cached and reused across version changes
- Rebuild time with cache: <1 second vs ~20+ seconds without cache

### 2. Build Scripts

Three platform-specific scripts provide consistent build experience:

#### PowerShell Script (`build-docker.ps1`)
- **Platform**: Windows (PowerShell 5.1+)
- **Features**:
  - Parameter validation and help
  - Colored console output
  - JSON parsing via PowerShell cmdlets
  - Error handling with exit codes

#### Bash Script (`build-docker.sh`)
- **Platform**: Linux, macOS, WSL
- **Features**:
  - POSIX-compliant shell scripting
  - Argument parsing with long/short options
  - JSON parsing via `grep` and `cut`
  - Executable permissions needed: `chmod +x build-docker.sh`

#### Batch Script (`build-docker.cmd`)
- **Platform**: Windows (Command Prompt)
- **Features**:
  - Traditional Windows batch syntax
  - PowerShell integration for JSON parsing
  - Argument parsing for options
  - Backward compatibility with older Windows versions

### 3. Build Script Features

All scripts provide:

**Automatic Versioning:**
- Retrieves version from NBGv2 (`nbgv get-version`)
- Extracts: `SemVer2`, `Version`, `AssemblyVersion`, `AssemblyFileVersion`, `AssemblyInformationalVersion`, `GitCommitIdShort`
- Passes version information to Docker as build arguments
- Creates multiple image tags for flexibility

**Image Tags Created:**
- `codemedic:x.y.z-ghash` (e.g., `0.1.6-g29cbcb89ce`) - Full semantic version
- `codemedic:x.y` (e.g., `0.1`) - Major.minor for compatibility
- `codemedic:latest` - Always points to most recent build
- `codemedic:x.y.z-ghash-shorthash` - Version with commit for tracking

**Options:**
- `--registry` / `-r`: Specify Docker registry prefix (e.g., `ghcr.io/owner`)
- `--push` / `-p`: Push images to registry after build
- `--configuration` / `-c`: Build configuration (`Release` or `Debug`)
- `--help` / `-h`: Display usage information

**Dependency Management:**
- Checks for Docker availability
- Installs `nbgv` CLI tool if not present
- Provides clear error messages for missing dependencies

### 4. .dockerignore
Located at: `.dockerignore` (repository root)

Optimizes build context by excluding:
- Build artifacts (`bin/`, `obj/`)
- IDE files (`.vs/`, `.vscode/`, `.idea/`)
- Documentation (`doc/`, `user-docs/`, `*.md`)
- Test projects
- Git metadata
- OS-specific files

**Benefits:**
- Faster build context transfer
- Smaller build cache
- Reduced security exposure

### 5. Project File Updates
File: `src/CodeMedic/CodeMedic.csproj`

Added Docker-specific properties:
```xml
<DockerDefaultTargetOS>Linux</DockerDefaultTargetOS>
<DockerfileContext>..\..</DockerfileContext>
```

These properties enable:
- Visual Studio Docker tooling integration
- Correct context path for multi-project solutions
- Linux as default container OS

## Usage Patterns

### Local Development
```bash
# Build image
.\build-docker.ps1

# Run against local repository
docker run --rm -v ${PWD}:/repo codemedic:latest health /repo
```

### CI/CD Integration
```yaml
# GitHub Actions example
- name: Build CodeMedic Container
  run: ./build-docker.sh

- name: Run Health Check
  run: docker run --rm -v ${{ github.workspace }}:/repo codemedic:latest health /repo
```

### Publishing to Registry
```bash
# GitHub Container Registry
.\build-docker.ps1 -Registry "ghcr.io/csharpfritz" -Push

# Docker Hub
./build-docker.sh --registry docker.io/username --push
```

## Architecture Decisions

### Multi-Stage Build
**Decision**: Use separate build and runtime stages

**Rationale**:
- Reduces final image size by ~75% (204MB vs ~800MB)
- Excludes build tools from production image
- Improves security posture (smaller attack surface)
- Faster image pulls and deployments

**Trade-off**:
- Slightly longer build times (must copy artifacts between stages)
- Cannot run `dotnet restore` in runtime container

### Version Automation
**Decision**: Integrate NBGv2 into build scripts and pass as build arguments

**Rationale**:
- Single source of truth for version numbers
- Consistent versioning across artifacts (binaries, containers, NuGet packages)
- Git-driven workflow (versions derived from commits and tags)
- Eliminates manual version management
- Optimizes Docker layer caching by not copying `version.json` into image
- Version changes don't invalidate dependency restore cache

**Trade-off**:
- Requires `nbgv` CLI tool (auto-installed by scripts)
- Version determination depends on Git repository state
- Slightly more complex Dockerfile with multiple build arguments

### Cross-Platform Scripts
**Decision**: Provide three separate build scripts instead of one

**Rationale**:
- Native experience on each platform (PowerShell, Bash, Cmd)
- No dependencies on cross-platform scripting tools
- Idiomatic syntax for each shell environment
- Handles platform-specific quirks (path separators, JSON parsing)

**Trade-off**:
- Must maintain three implementations
- Risk of feature drift between scripts

### Entrypoint Design
**Decision**: Use `ENTRYPOINT` for `dotnet CodeMedic.dll`, default `CMD` for `--help`

**Rationale**:
- Users can override commands easily: `docker run ... health /repo`
- Default behavior is helpful (shows available commands)
- Follows Docker best practices for CLI tools
- Supports both `docker run codemedic` and `docker run codemedic health ...`

## Security Considerations

1. **Minimal Runtime Image**: Uses .NET runtime (not SDK) to reduce attack surface
2. **.dockerignore**: Prevents sensitive files from being included in image
3. **No Secrets**: Build scripts never embed credentials or tokens
4. **Official Base Images**: Uses Microsoft-provided .NET images from MCR (Microsoft Container Registry)
5. **Non-Root User**: TODO - Consider adding non-root user in runtime stage

## Performance Characteristics

### Build Performance
- **First build**: ~20-30 seconds (depends on network speed for base image pull)
- **Incremental builds** (code changes): ~10-15 seconds (Docker layer caching for dependencies)
- **Version-only changes**: <1 second (all layers cached, only tags change)
- **Build context**: ~130KB (thanks to `.dockerignore`)

**Cache Strategy**:
The Dockerfile is optimized for maximum cache efficiency:
1. Copy project files first → cache dependency restore
2. Copy source code last → avoid invalidating restore cache
3. Pass version as build args → don't invalidate any file-based cache layers

### Runtime Performance
- **Image size**: ~204MB (compressed: ~75MB)
- **Startup time**: <1 second (cold start)
- **Memory overhead**: ~50MB base + application memory
- **I/O performance**: Native (no virtualization overhead for volume mounts)

## Future Enhancements

1. **Non-Root User**: Add dedicated user in runtime stage for improved security
2. **ARM Support**: Add multi-arch builds (AMD64, ARM64) for broader platform support
3. **Alpine Variant**: Investigate Alpine-based images for smaller size (~100MB)
4. **Build Cache**: Implement BuildKit cache mounts for faster dependency restoration
5. **Health Check**: Add Docker `HEALTHCHECK` instruction for orchestration
6. **Labels**: Add OCI annotations for metadata (version, source, description)
7. **Registry Automation**: GitHub Actions workflow for automated publishing
8. **Signature Verification**: Sign images using Docker Content Trust or Cosign

## Testing

The implementation has been tested with:
- ✅ Building image with version tags
- ✅ Running `--help` command
- ✅ Executing `health` command with volume mount
- ✅ Multiple version tags on same image
- ✅ Image size optimization

## Documentation

User-facing documentation: `user-docs/docker_usage.md`
- Installation and setup
- Common usage patterns
- Troubleshooting guide
- CI/CD examples
- Registry publishing instructions

## Dependencies

**Runtime**:
- Docker Engine 20.10+ (or compatible runtime)
- .NET 10.0 Runtime (bundled in container)

**Build-time**:
- Docker Engine 20.10+
- Nerd Bank Git Versioning (`nbgv` CLI tool - auto-installed)
- Git repository (for version calculation)

**Optional**:
- Docker registry account (for publishing)
- GitHub token or Docker Hub credentials (for push)

## Maintenance

### Updating Base Images
When new .NET versions are released:

1. Update `Dockerfile`:
   ```dockerfile
   FROM mcr.microsoft.com/dotnet/sdk:10.X AS build
   FROM mcr.microsoft.com/dotnet/runtime:10.X AS final
   ```

2. Update `.csproj`:
   ```xml
   <TargetFramework>net10.X</TargetFramework>
   ```

3. Test build and runtime

### Script Maintenance
When adding features or fixing bugs:

1. Implement in primary script (PowerShell preferred)
2. Port changes to Bash and Batch scripts
3. Update help text in all three scripts
4. Update `user-docs/docker_usage.md`
5. Test on all platforms (Windows, Linux, macOS)

## References

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [.NET Docker Images](https://hub.docker.com/_/microsoft-dotnet)
- [Nerd Bank Git Versioning](https://github.com/dotnet/Nerdbank.GitVersioning)
