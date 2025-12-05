@echo off
REM CodeMedic Docker Build Script (Windows batch version)
REM Builds the CodeMedic Docker container with versioning from Nerd Bank Git Versioning

setlocal EnableDelayedExpansion

set REGISTRY=
set PUSH=0
set BUILD_CONFIGURATION=Release

REM Parse arguments
:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="-r" (
    set REGISTRY=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--registry" (
    set REGISTRY=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="-p" (
    set PUSH=1
    shift
    goto parse_args
)
if /i "%~1"=="--push" (
    set PUSH=1
    shift
    goto parse_args
)
if /i "%~1"=="-c" (
    set BUILD_CONFIGURATION=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--configuration" (
    set BUILD_CONFIGURATION=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
echo Unknown option: %~1
exit /b 1

:show_help
echo Usage: %~nx0 [OPTIONS]
echo.
echo Options:
echo   -r, --registry REGISTRY    Docker registry prefix (e.g., ghcr.io/owner)
echo   -p, --push                 Push images to registry after build
echo   -c, --configuration CONFIG Build configuration (Release or Debug)
echo   -h, --help                 Show this help message
echo.
echo Examples:
echo   %~nx0
echo   %~nx0 --registry ghcr.io/csharpfritz --push
exit /b 0

:end_parse

echo.
echo 🏥 CodeMedic Docker Build Script
echo =================================
echo.

REM Change to script directory
cd /d "%~dp0"

REM Check if Docker is available
docker --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Error: Docker is not installed or not in PATH
    exit /b 1
)

REM Check if nbgv is available
where nbgv >nul 2>&1
if errorlevel 1 (
    echo 📦 Installing Nerd Bank Git Versioning CLI tool...
    dotnet tool install -g nbgv
    if errorlevel 1 (
        echo ❌ Error: Failed to install nbgv
        exit /b 1
    )
)

REM Get version information from NBGv2
echo 🔢 Retrieving version information from NBGv2...

REM Use PowerShell to parse JSON (more reliable than batch)
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty SemVer2}"`) do set SEMVER2=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty Version}"`) do set VERSION=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty AssemblyVersion}"`) do set ASSEMBLY_VERSION=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty AssemblyFileVersion}"`) do set FILE_VERSION=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty AssemblyInformationalVersion}"`) do set INFORMATIONAL_VERSION=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty VersionMajor}"`) do set VERSION_MAJOR=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty VersionMinor}"`) do set VERSION_MINOR=%%v
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "& {nbgv get-version -f json | ConvertFrom-Json | Select-Object -ExpandProperty GitCommitIdShort}"`) do set COMMIT=%%v

set MAJOR_MINOR=%VERSION_MAJOR%.%VERSION_MINOR%

echo   Version: %VERSION%
echo   SemVer2: %SEMVER2%
echo   Assembly Version: %ASSEMBLY_VERSION%
echo   File Version: %FILE_VERSION%
echo   Informational: %INFORMATIONAL_VERSION%
echo   Commit:  %COMMIT%
echo.

REM Construct image name
set IMAGE_NAME=codemedic
if not "%REGISTRY%"=="" set IMAGE_NAME=%REGISTRY%/%IMAGE_NAME%

REM Build tags
set TAG1=%IMAGE_NAME%:%SEMVER2%
set TAG2=%IMAGE_NAME%:%MAJOR_MINOR%
set TAG3=%IMAGE_NAME%:latest
set TAG4=%IMAGE_NAME%:%SEMVER2%-%COMMIT%

echo 🐳 Building Docker image...
echo   Image name: %IMAGE_NAME%
echo   Tags:
echo     - %TAG1%
echo     - %TAG2%
echo     - %TAG3%
echo     - %TAG4%
echo.

REM Build the Docker image
echo 🔨 Building...
docker build -f Dockerfile ^
    --build-arg BUILD_CONFIGURATION=%BUILD_CONFIGURATION% ^
    --build-arg VERSION=%SEMVER2% ^
    --build-arg ASSEMBLY_VERSION=%ASSEMBLY_VERSION% ^
    --build-arg FILE_VERSION=%FILE_VERSION% ^
    --build-arg INFORMATIONAL_VERSION=%INFORMATIONAL_VERSION% ^
    -t "%TAG1%" -t "%TAG2%" -t "%TAG3%" -t "%TAG4%" .

if errorlevel 1 (
    echo ❌ Error: Docker build failed
    exit /b 1
)

echo.
echo ✅ Docker image built successfully!
echo.

REM Push if requested
if %PUSH%==1 (
    if "%REGISTRY%"=="" (
        echo ❌ Error: Cannot push without specifying a registry. Use --registry parameter.
        exit /b 1
    )
    
    echo 📤 Pushing images to registry...
    
    echo   Pushing: %TAG1%
    docker push "%TAG1%"
    if errorlevel 1 exit /b 1
    
    echo   Pushing: %TAG2%
    docker push "%TAG2%"
    if errorlevel 1 exit /b 1
    
    echo   Pushing: %TAG3%
    docker push "%TAG3%"
    if errorlevel 1 exit /b 1
    
    echo   Pushing: %TAG4%
    docker push "%TAG4%"
    if errorlevel 1 exit /b 1
    
    echo.
    echo ✅ All images pushed successfully!
    echo.
)

REM Display usage examples
echo 📋 Usage Examples:
echo   Run health check:
echo     docker run --rm -v %%cd%%:/repo %TAG1% health /repo
echo.
echo   Show help:
echo     docker run --rm %TAG1% --help
echo.
echo   Interactive shell:
echo     docker run --rm -it --entrypoint /bin/bash %TAG1%
echo.

endlocal
