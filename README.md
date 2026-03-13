# NeoPZ Docker Development Environment

A high-performance Docker image optimized for [NeoPZ](https://github.com/labmec/neopz) development, featuring **Intel MKL** and **PARDISO** support, with all dependencies pre-compiled in Debug mode.

## 🎯 Features

- **Pre-compiled in Debug**: NeoPZ compiled with debug symbols for easy stepping and debugging.
- **Intel oneAPI MKL & PARDISO**: Industry-standard high-performance math libraries enabled by default.
- **All features enabled**:
  - ✅ **MKL/PARDISO** (Intel Math Kernel Library)
  - ✅ **MUMPS** (all variants: d, s, c, z)
  - ✅ **METIS** (mesh partitioner)
  - ✅ **LOG4CXX** (logging)
  - ✅ **LAPACK/BLAS** (via MKL)
  - ✅ **Catch2** (unit testing)
  - ✅ **Build tools** (CMake, Ninja, GCC)
  - ✅ **Debug tools** (GDB, Valgrind)
  - ✅ **VSCode extension defaults** (C++ Tools, CMake Tools via Dev Containers metadata)

- **Customizable**: Recompile NeoPZ inside the container with reduced features if needed.
- **Clean layout**: Well-organized folder structure at `/home/labmec/`.

## 📦 Container Layout

```
/home/labmec/
├── neopz/                ← NeoPZ source code (IDE, debugging)
├── neopz_install/        ← Compiled headers and libraries
├── mumps/                ← Pre-compiled MUMPS libraries (linked to MKL)
└── <workspace>/          ← Your projects (volume mount)
```

## 🚀 Quick Start

### 1. Build the Image

```bash
./build.sh
```

- Installs Docker if missing (Linux).
- Configures Intel oneAPI repositories.
- Compiles MUMPS and NeoPZ against MKL.

### 2. Create and Run Container

#### **Linux**
```bash
./run.sh
```

#### **macOS / Windows (Docker Desktop)**
```bash
./run.sh
```

The script offers:
- Reuse existing container or create new.
- Interactive volume mounting of your project.
- Automatic VSCode attachment (Linux/macOS with VSCode installed).

**Note**: On macOS with Apple Silicon (M1/M2/M3), the image runs in **x86_64 emulation mode** via Docker's `--platform=linux/amd64` flag. This is necessary because:
- The base image is Debian AMD64 (Intel/x86_64 architecture)
- Intel MKL and PARDISO libraries are x86_64 only
- Performance impact is minimal for development workflows

## 🛠️ How to Use

### Platform Compatibility

#### Linux (x86_64)
- ✅ **Fully supported**: Native performance
- Builds and runs without any platform flags

#### macOS (Intel)
- ✅ **Fully supported**: Native performance with Docker Desktop
- Runs container with `--platform=linux/amd64` (automatic, no action needed)

#### macOS (Apple Silicon - M1/M2/M3)
- ✅ **Supported with x86_64 emulation**: Docker Desktop handles architecture translation
- Performance impact: Minimal for typical development workflows
- Container runs in emulated x86_64 environment (required for MKL/PARDISO)
- If you need native ARM64 builds, you'll need to recompile inside the container after removing MKL (see "Recompiling without MKL" below)

#### Windows (WSL2 / Docker Desktop)
- ✅ **Supported**: Docker Desktop with WSL2 backend
- Use `./run.sh` via WSL terminal, or Docker Desktop GUI for container management

### Compiling your project with MKL

The container automatically loads MKL environment variables in `.bashrc`. To compile a project:

```bash
mkdir build && cd build
cmake .. -DNeoPZ_DIR=/home/labmec/neopz_install -DUSING_MKL=ON
cmake --build .
```

### Using PARDISO in NeoPZ

In your code, you can now use the PARDISO solver provided by MKL:

```cpp
#include "TPZLinearAnalysis.h"
#include "TPZSSpStructMatrix.h"
#include "TPZStepSolver.h"

// ... inside your analysis setup
TPZSSpStructMatrix<STATE> strmat(cmesh);
strmat.SetNumThreads(8);
analysis.SetStructMatrix(strmat);

TPZStepSolver<STATE> step;
step.SetDirect(ELDLT); // PARDISO will be used if NeoPZ was built with USING_MKL=ON
analysis.SetSolver(step);
```

### Recompiling NeoPZ without MKL (ARM64 native on Apple Silicon)

If you're on Apple Silicon and need native ARM64 performance instead of emulation:

```bash
# Inside the container
cd /home/labmec/neopz
rm -rf build neopz_install
mkdir build && cd build

# Rebuild with OpenBLAS instead of MKL
cmake .. \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_INSTALL_PREFIX=/home/labmec/neopz_install_arm64 \
    -DUSING_LOG4CXX=ON \
    -DUSING_METIS=ON \
    -DUSING_MUMPS=ON \
    -DUSING_MKL=OFF \
    -DLAPACK_VENDOR=OpenBLAS

cmake --build .
cmake --install .
```

## 🔧 Maintenance

### Accessing the Container

```bash
# Standard shell
docker exec -it neopz-dev /bin/bash

# Root access (to install extra packages)
docker exec -it -u root neopz-dev /bin/bash
```
