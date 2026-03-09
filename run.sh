#!/usr/bin/env bash
# =============================================================
# run.sh – Start the NeoPZ development container (detached)
# Compatible with: Linux and macOS
# =============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="neopz-dev"
CONTAINER_NAME="neopz-dev"
WORKDIR_IN_CONTAINER="/home/labmec/programming/neopz/neopz_projects"
NEOPZ_SRC_IN_CONTAINER="/home/labmec/programming/neopz/neopz"

GREEN="\033[0;32m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
section() { echo -e "\n${CYAN}▶ $*${RESET}"; }

section "NeoPZ Docker development environment"
# This directory will be mounted as the projects volume inside the container.
PROJECTS_DIR="$HOME/programming"
printf "  Projects volume – host directory to mount into the container\n"
printf "  (default: %s): " "$PROJECTS_DIR"
read -r PROJECTS_DIR
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/programming}"

# ─────────────────────────────────────────────────────────────
# 1. Ensure Docker is available and running
# ─────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    warn "Docker not found. Running build.sh to install it first..."
    "${SCRIPT_DIR}/build.sh"
fi

if ! docker info &>/dev/null 2>&1; then
    echo "Docker daemon is not running."
    case "$(uname -s)" in
        Darwin) open -a Docker; echo "  Waiting for Docker to start..."; sleep 8 ;;
        Linux)  sudo systemctl start docker ;;
    esac
    if ! docker info &>/dev/null 2>&1; then
        echo "Error: Docker daemon did not start. Please start it manually." >&2; exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────
# 2. Build image if it doesn't exist
# ─────────────────────────────────────────────────────────────
if ! docker image inspect "$IMAGE_NAME" &>/dev/null 2>&1; then
    warn "Image '${IMAGE_NAME}' not found. Running build.sh..."
    echo ""
    "${SCRIPT_DIR}/build.sh"
    echo ""
fi

# ─────────────────────────────────────────────────────────────
# 3. Prepare projects volume
# ─────────────────────────────────────────────────────────────
mkdir -p "$PROJECTS_DIR"

# ─────────────────────────────────────────────────────────────
# 4. Offer to create an example project
# ─────────────────────────────────────────────────────────────
VSCODE_OPEN_PROJECT=""   # will be set to project name if example is created

section "Example project"
printf "  Create an example NeoPZ project? (Y/n): "
read -r CREATE_EXAMPLE
CREATE_EXAMPLE="${CREATE_EXAMPLE:-y}"

if [[ "$CREATE_EXAMPLE" =~ ^[yY]$ ]]; then
    printf "  Project name (default: firsttest): "
    read -r PROJECT_NAME
    PROJECT_NAME="${PROJECT_NAME:-firsttest}"
    PROJECT_DIR="${PROJECTS_DIR}/${PROJECT_NAME}"

    # Always set the project name so VSCode opens the project folder regardless of
    # whether the project was just created or already existed from a prior run.
    VSCODE_OPEN_PROJECT="$PROJECT_NAME"

    if [ -d "$PROJECT_DIR" ]; then
        warn "Project '${PROJECT_NAME}' already exists at ${PROJECT_DIR}. Skipping creation."
    else
        mkdir -p "$PROJECT_DIR"

        # ── CMakeLists.txt ──────────────────────────────────
        cat > "${PROJECT_DIR}/CMakeLists.txt" << EOF
cmake_minimum_required(VERSION 3.14)
project(${PROJECT_NAME})

# ----- Find NeoPZ -----
# NeoPZ_DIR is set as an environment variable inside the container.
# Alternatively, pass -DNeoPZ_DIR=/home/labmec/programming/neopz/neopz_install to cmake.
find_package(NeoPZ REQUIRED HINTS \$ENV{NeoPZ_DIR})

add_executable(\${PROJECT_NAME} main.cpp)
target_link_libraries(\${PROJECT_NAME} NeoPZ::pz)
EOF

        # ── main.cpp ────────────────────────────────────────
        cat > "${PROJECT_DIR}/main.cpp" << 'MAIN_EOF'
#include <iostream>
#include <TPZGenGrid3D.h>
#include <TPZGenGrid2D.h>
#include <DarcyFlow/TPZDarcyFlow.h>
#include <TPZLinearAnalysis.h>
#include "TPZSSpStructMatrix.h"
#include "pzstepsolver.h"
#include "TPZMultiphysicsCompMesh.h"
#include "TPZSimpleTimer.h"
#include "pzbuildmultiphysicsmesh.h"
#include "TPZVTKGenerator.h"
#include "TPZStructMatrixOMPorTBB.h"
#include "pzskylstrmatrix.h"
#include "TPZVTKGeoMesh.h"
#include "pzfmatrix.h"
#include "pzlog.h"

using namespace std;

enum EnumMatids { EMatId = 1, EBottom = 2, ETop = 3, ELeft = 4, ERight = 5 };

TPZGeoMesh *createMeshWithGenGrid(const TPZVec<int> &nelDiv, const TPZVec<REAL> &minX, const TPZVec<REAL> &maxX)
{
    TPZGeoMesh *gmesh = new TPZGeoMesh;
    TPZGenGrid2D generator(nelDiv, minX, maxX);
    generator.SetElementType(MMeshType::EQuadrilateral);
    generator.Read(gmesh, EMatId);
    generator.SetBC(gmesh, 4, EBottom); // bottom
    generator.SetBC(gmesh, 5, ERight);  // right
    generator.SetBC(gmesh, 6, ETop);    // top
    generator.SetBC(gmesh, 7, ELeft);   // left
    return gmesh;
}

TPZGeoMesh *createRectangularGmesh()
{
    TPZGeoMesh *gmesh = new TPZGeoMesh;
    TPZManVector<REAL, 3> coord(3, 0.);

    TPZGeoNode nod0(0, coord, *gmesh);
    coord[0] = 1.;
    TPZGeoNode nod1(1, coord, *gmesh);
    coord[1] = 1.;
    TPZGeoNode nod2(2, coord, *gmesh);
    coord[0] = 0.;
    TPZGeoNode nod3(3, coord, *gmesh);
    coord[0] = 2.; coord[1] = 0.;
    TPZGeoNode nod4(4, coord, *gmesh);
    coord[1] = 1.;
    TPZGeoNode nod5(5, coord, *gmesh);

    gmesh->NodeVec().Resize(6);
    gmesh->NodeVec()[0] = nod0; gmesh->NodeVec()[1] = nod1;
    gmesh->NodeVec()[2] = nod2; gmesh->NodeVec()[3] = nod3;
    gmesh->NodeVec()[4] = nod4; gmesh->NodeVec()[5] = nod5;

    TPZManVector<int64_t, 4> nodeindexes(4);
    int64_t index = 0;
    nodeindexes = {0,1,2,3};
    TPZGeoEl *gel  = gmesh->CreateGeoElement(EQuadrilateral, nodeindexes, EMatId, index);
    index = 1;
    nodeindexes = {1,4,5,2};
    TPZGeoEl *gel2 = gmesh->CreateGeoElement(EQuadrilateral, nodeindexes, EMatId, index);

    gel->CreateBCGeoEl(4, EBottom);  gel2->CreateBCGeoEl(4, EBottom);
    gel2->CreateBCGeoEl(5, ERight);
    gel2->CreateBCGeoEl(6, ETop);    gel->CreateBCGeoEl(6, ETop);
    gel->CreateBCGeoEl(7, ELeft);

    gmesh->SetDimension(2);
    gmesh->BuildConnectivity();
    return gmesh;
}

TPZCompMesh *createCompMesh(TPZGeoMesh *gmesh)
{
    TPZCompMesh *cmesh = new TPZCompMesh(gmesh);
    cmesh->SetDimModel(gmesh->Dimension());
    cmesh->SetDefaultOrder(1);
    cmesh->SetAllCreateFunctionsContinuous();

    TPZDarcyFlow *mat = new TPZDarcyFlow(EMatId, gmesh->Dimension());
    mat->SetConstantPermeability(1.0);
    cmesh->InsertMaterialObject(mat);

    int dirichletType = 0, neumannType = 1;
    TPZManVector<REAL, 1> val2(1, 0.);
    TPZFMatrix<REAL> val1(1, 1, 0.);
    TPZBndCondT<REAL> *bcond;

    bcond = mat->CreateBC(mat, EBottom, neumannType,  val1, val2); cmesh->InsertMaterialObject(bcond);
    val2[0] = 1.;
    bcond = mat->CreateBC(mat, ERight,  dirichletType, val1, val2); cmesh->InsertMaterialObject(bcond);
    val2[0] = 0.;
    bcond = mat->CreateBC(mat, ETop,    neumannType,  val1, val2); cmesh->InsertMaterialObject(bcond);
    val2[0] = 3.;
    bcond = mat->CreateBC(mat, ELeft,   dirichletType, val1, val2); cmesh->InsertMaterialObject(bcond);

    cmesh->AutoBuild();
    return cmesh;
}

int main(int argc, char const *argv[]) {
#ifdef PZ_LOG
    TPZLogger::InitializePZLOG();
#endif
    const int nthreads = 0;

    TPZGeoMesh *gmesh = nullptr;
    const bool isUseGenGrid = true;
    if (isUseGenGrid) {
        const int neldiv = 2;
        gmesh = createMeshWithGenGrid({neldiv, neldiv}, {0.,0.}, {2.,1.});
    } else {
        gmesh = createRectangularGmesh();
    }
    gmesh->Print(std::cout);

    std::ofstream out("gmesh.vtk");
    TPZVTKGeoMesh::PrintGMeshVTK(gmesh, out);

    TPZCompMesh *cmesh = createCompMesh(gmesh);
    cmesh->Print(std::cout);

    TPZLinearAnalysis an(cmesh);

    // Skyline solver (no MKL)
    TPZSkylineStructMatrix<STATE> matsp(cmesh);
    matsp.SetNumThreads(nthreads);
    an.SetStructuralMatrix(matsp);
    TPZStepSolver<STATE> step;
    step.SetDirect(ECholesky);
    an.SetSolver(step);
    an.Run();

    an.Solution().Print("Solution");

    const std::string plotfile = "postproc";
    constexpr int vtkRes = 0;
    TPZManVector<std::string,2> fields = {"Flux","Pressure"};
    auto vtk = TPZVTKGenerator(cmesh, fields, plotfile, vtkRes);
    vtk.Do();
    return 0;
}
MAIN_EOF

        # ── <name>.code-workspace ───────────────────────────
        # Uses absolute container paths so the workspace works correctly
        # regardless of whether it is opened locally or inside the container.
        cat > "${PROJECT_DIR}/${PROJECT_NAME}.code-workspace" << EOF
{
    "folders": [
        { "path": "${WORKDIR_IN_CONTAINER}/${PROJECT_NAME}" },
        { "path": "${NEOPZ_SRC_IN_CONTAINER}" }
    ],
    "settings": {
        "files.associations": {
            "iosfwd": "cpp", "iostream": "cpp", "sstream": "cpp",
            "regex": "cpp", "algorithm": "cpp", "memory": "cpp",
            "numeric": "cpp", "array": "cpp", "atomic": "cpp",
            "bit": "cpp", "bitset": "cpp", "cctype": "cpp",
            "charconv": "cpp", "chrono": "cpp", "clocale": "cpp",
            "cmath": "cpp", "compare": "cpp", "complex": "cpp",
            "concepts": "cpp", "condition_variable": "cpp",
            "cstdarg": "cpp", "cstddef": "cpp", "cstdint": "cpp",
            "cstdio": "cpp", "cstdlib": "cpp", "cstring": "cpp",
            "ctime": "cpp", "cwchar": "cpp", "cwctype": "cpp",
            "deque": "cpp", "forward_list": "cpp", "list": "cpp",
            "map": "cpp", "set": "cpp", "string": "cpp",
            "unordered_map": "cpp", "unordered_set": "cpp",
            "vector": "cpp", "exception": "cpp", "functional": "cpp",
            "iterator": "cpp", "memory_resource": "cpp", "optional": "cpp",
            "random": "cpp", "ratio": "cpp", "string_view": "cpp",
            "system_error": "cpp", "tuple": "cpp", "type_traits": "cpp",
            "utility": "cpp", "format": "cpp", "fstream": "cpp",
            "future": "cpp", "initializer_list": "cpp", "iomanip": "cpp",
            "istream": "cpp", "limits": "cpp", "mutex": "cpp",
            "new": "cpp", "numbers": "cpp", "ostream": "cpp",
            "ranges": "cpp", "semaphore": "cpp", "shared_mutex": "cpp",
            "span": "cpp", "stacktrace": "cpp", "stdexcept": "cpp",
            "stop_token": "cpp", "streambuf": "cpp", "thread": "cpp",
            "cfenv": "cpp", "cinttypes": "cpp", "typeinfo": "cpp",
            "variant": "cpp"
        }
    }
}
EOF

        info "Example project created: ${PROJECT_DIR}"
    fi
fi


# ─────────────────────────────────────────────────────────────
# 5. Start container (detached)
# ─────────────────────────────────────────────────────────────
_start_container() {
    docker rm -f "$CONTAINER_NAME" &>/dev/null 2>&1 || true
    docker run -d --rm \
        --name "$CONTAINER_NAME" \
        -v "${PROJECTS_DIR}":${WORKDIR_IN_CONTAINER} \
        "$IMAGE_NAME" \
        sleep infinity
    info "Container '${CONTAINER_NAME}' started with volume: ${PROJECTS_DIR}"
}

if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' \
        | grep -q "^${CONTAINER_NAME}$"; then
    CURRENT_VOLUME=$(docker inspect "$CONTAINER_NAME" \
        --format '{{range .Mounts}}{{if eq .Destination "'"${WORKDIR_IN_CONTAINER}"'"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
    if [ "$CURRENT_VOLUME" != "$PROJECTS_DIR" ]; then
        warn "Container running with a different volume:"
        warn "  current  : ${CURRENT_VOLUME}"
        warn "  requested: ${PROJECTS_DIR}"
        warn "Restarting container with the correct volume..."
        docker stop "$CONTAINER_NAME" &>/dev/null 2>&1 || true
        # Wait for --rm to fully remove the container before restarting
        _i=0
        while docker inspect "$CONTAINER_NAME" &>/dev/null 2>&1 && [ "$_i" -lt 15 ]; do
            sleep 1; _i=$((_i + 1))
        done
        _start_container
    else
        warn "Container '${CONTAINER_NAME}' is already running."
    fi
else
    _start_container
fi

# ─────────────────────────────────────────────────────────────
# 6. Usage hints
# ─────────────────────────────────────────────────────────────
section "How to access the container"
echo ""
echo "  Open a shell inside the container:"
echo -e "    ${CYAN}docker exec -it ${CONTAINER_NAME} /bin/bash${RESET}"
echo ""
echo "  Stop the container (removed automatically on stop):"
echo -e "    ${CYAN}docker stop ${CONTAINER_NAME}${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────
# 7. Open VSCode attached to the running container
# ─────────────────────────────────────────────────────────────
section "VSCode"
if [ -z "$VSCODE_OPEN_PROJECT" ]; then
    info "No project selected – skipping VSCode launch."
elif ! command -v code &>/dev/null; then
    warn "VSCode (code) not found in PATH."
    echo "  Install it from https://code.visualstudio.com"
    echo "  Then re-run this script to open VSCode automatically."
else
    CONTAINER_HEX=$(printf '%s' "{\"containerName\":\"/${CONTAINER_NAME}\"}" \
        | od -v -A n -t x1 | tr -d ' \n')
    FULL_URI="vscode-remote://attached-container+${CONTAINER_HEX}${WORKDIR_IN_CONTAINER}/${VSCODE_OPEN_PROJECT}"
    echo "  Opening project folder in VSCode (attached to container)..."
    echo -e "    ${CYAN}${WORKDIR_IN_CONTAINER}/${VSCODE_OPEN_PROJECT}${RESET}"
    code --folder-uri "$FULL_URI"
    info "VSCode launched. Install the 'Dev Containers' extension if prompted."
fi

echo ""
