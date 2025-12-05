#!/bin/bash
# CodeMedic Docker Build Script (Bash version)
# Builds the CodeMedic Docker container with versioning from Nerd Bank Git Versioning

set -e

REGISTRY=""
PUSH=false
BUILD_CONFIGURATION="Release"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=true
            shift
            ;;
        -c|--configuration)
            BUILD_CONFIGURATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -r, --registry REGISTRY    Docker registry prefix (e.g., ghcr.io/owner)"
            echo "  -p, --push                 Push images to registry after build"
            echo "  -c, --configuration CONFIG Build configuration (Release or Debug)"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --registry ghcr.io/csharpfritz --push"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🏥 CodeMedic Docker Build Script"
echo "================================="
echo ""

# Change to script directory
cd "$(dirname "$0")"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check if nbgv is available, if not install it
if ! command -v nbgv &> /dev/null; then
    echo "📦 Installing Nerd Bank Git Versioning CLI tool..."
    dotnet tool install -g nbgv
    
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to install nbgv"
        exit 1
    fi
    
    # Add to PATH for current session
    export PATH="$HOME/.dotnet/tools:$PATH"
fi

# Get version information from NBGv2
echo "🔢 Retrieving version information from NBGv2..."
VERSION_JSON=$(nbgv get-version -f json)

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to retrieve version information from NBGv2"
    exit 1
fi

VERSION=$(echo "$VERSION_JSON" | grep -o '"Version":"[^"]*"' | cut -d'"' -f4)
SEMVER2=$(echo "$VERSION_JSON" | grep -o '"SemVer2":"[^"]*"' | cut -d'"' -f4)
ASSEMBLY_VERSION=$(echo "$VERSION_JSON" | grep -o '"AssemblyVersion":"[^"]*"' | cut -d'"' -f4)
FILE_VERSION=$(echo "$VERSION_JSON" | grep -o '"AssemblyFileVersion":"[^"]*"' | cut -d'"' -f4)
INFORMATIONAL_VERSION=$(echo "$VERSION_JSON" | grep -o '"AssemblyInformationalVersion":"[^"]*"' | cut -d'"' -f4)
VERSION_MAJOR=$(echo "$VERSION_JSON" | grep -o '"VersionMajor":[0-9]*' | cut -d':' -f2)
VERSION_MINOR=$(echo "$VERSION_JSON" | grep -o '"VersionMinor":[0-9]*' | cut -d':' -f2)
COMMIT=$(echo "$VERSION_JSON" | grep -o '"GitCommitIdShort":"[^"]*"' | cut -d'"' -f4)

MAJOR_MINOR="${VERSION_MAJOR}.${VERSION_MINOR}"

echo "  Version: $VERSION"
echo "  SemVer2: $SEMVER2"
echo "  Assembly Version: $ASSEMBLY_VERSION"
echo "  File Version: $FILE_VERSION"
echo "  Informational: $INFORMATIONAL_VERSION"
echo "  Commit:  $COMMIT"
echo ""

# Construct image name
IMAGE_NAME="codemedic"
if [ -n "$REGISTRY" ]; then
    IMAGE_NAME="$REGISTRY/$IMAGE_NAME"
fi

# Build tags
TAGS=(
    "${IMAGE_NAME}:${SEMVER2}"
    "${IMAGE_NAME}:${MAJOR_MINOR}"
    "${IMAGE_NAME}:latest"
    "${IMAGE_NAME}:${SEMVER2}-${COMMIT}"
)

echo "🐳 Building Docker image..."
echo "  Image name: $IMAGE_NAME"
echo "  Tags:"
for tag in "${TAGS[@]}"; do
    echo "    - $tag"
done
echo ""

# Build the Docker image
BUILD_ARGS=(
    "build"
    "-f" "Dockerfile"
    "--build-arg" "BUILD_CONFIGURATION=$BUILD_CONFIGURATION"
    "--build-arg" "VERSION=$SEMVER2"
    "--build-arg" "ASSEMBLY_VERSION=$ASSEMBLY_VERSION"
    "--build-arg" "FILE_VERSION=$FILE_VERSION"
    "--build-arg" "INFORMATIONAL_VERSION=$INFORMATIONAL_VERSION"
)

for tag in "${TAGS[@]}"; do
    BUILD_ARGS+=("-t" "$tag")
done

BUILD_ARGS+=(".")

echo "🔨 Executing: docker ${BUILD_ARGS[*]}"
docker "${BUILD_ARGS[@]}"

if [ $? -ne 0 ]; then
    echo "❌ Error: Docker build failed"
    exit 1
fi

echo ""
echo "✅ Docker image built successfully!"
echo ""

# Push if requested
if [ "$PUSH" = true ]; then
    if [ -z "$REGISTRY" ]; then
        echo "❌ Error: Cannot push without specifying a registry. Use --registry parameter."
        exit 1
    fi
    
    echo "📤 Pushing images to registry..."
    for tag in "${TAGS[@]}"; do
        echo "  Pushing: $tag"
        docker push "$tag"
        
        if [ $? -ne 0 ]; then
            echo "❌ Error: Failed to push $tag"
            exit 1
        fi
    done
    
    echo ""
    echo "✅ All images pushed successfully!"
    echo ""
fi

# Display usage examples
echo "📋 Usage Examples:"
echo "  Run health check:"
echo "    docker run --rm -v \$(pwd):/repo ${TAGS[0]} health /repo"
echo ""
echo "  Show help:"
echo "    docker run --rm ${TAGS[0]} --help"
echo ""
echo "  Interactive shell:"
echo "    docker run --rm -it --entrypoint /bin/bash ${TAGS[0]}"
echo ""
