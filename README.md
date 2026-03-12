# Neopz Docker

A Docker-based development environment for [NeoPZ](https://github.com/labmec/neopz) — a C++ finite element method (FEM) library developed by [LabMeC](https://labmec.github.io/) at Unicamp.

This repository provides a fully automated, reproducible setup: a single script builds a Docker image with NeoPZ compiled and installed, ready for you to develop, build, and debug your own FEM projects inside a container — with full VS Code integration.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Step 1 — Build the Image (`build.sh`)](#step-1--build-the-image-buildsh)
  - [Build Options](#build-options)
  - [MUMPS Numeric Variants](#mumps-numeric-variants)
- [Step 2 — Run the Container (`run.sh`)](#step-2--run-the-container-runsh)
  - [Volume Mapping](#volume-mapping)
  - [Example Project](#example-project)
  - [VS Code Integration](#vs-code-integration)
- [Container Layout](#container-layout)
- [Developing Your Own Project](#developing-your-own-project)
- [VS Code Extensions](#vs-code-extensions)
- [Dockerfile Architecture](#dockerfile-architecture)

---

## Overview

NeoPZ is a high-performance C++ library for the development of finite element simulations. Setting up its dependencies (CMake, optional solvers, logging libraries, Intel MKL) manually is tedious and error-prone across different operating systems.

This project solves that by packaging NeoPZ and all its optional dependencies into a Docker image. You write your simulation code on your host machine; the container handles compilation and execution in a clean, controlled environment.

---

## Prerequisites

| Tool | Notes |
|---|---|
| **Docker** | Installed automatically by `build.sh` on Debian/Ubuntu and macOS (via Homebrew) |
| **VS Code** *(optional)* | Required only for the VS Code integration features |
| **Dev Containers extension** *(optional)* | VS Code extension `ms-vscode-remote.remote-containers` |

> **Apple Silicon (M1/M2/M3):** Intel MKL is x86_64-only and will be automatically disabled. All other features work normally.

---

## Repository Structure

```
neopz-docker/
├── Dockerfile                  # Multi-stage image definition
├── build.sh                    # Interactive image build script
├── run.sh                      # Container startup and project scaffold script
└── install_vscode_extensions.sh # Installs recommended host-side VS Code extensions
```

---

## Quick Start

```bash
# 1. Build the Docker image (interactive – you will be asked about optional features)
./build.sh

# 2. Start the container and (optionally) create an example project
./run.sh
```

That is all. `run.sh` will open VS Code attached to the running container if `code` is in your PATH.

---

## Step 1 — Build the Image (`build.sh`)

```bash
./build.sh          # Build the image only
./build.sh vscode   # Build the image and also install the host-side VS Code extensions
```

The script guides you through an interactive configuration menu, then calls `docker build` with the chosen flags. If Docker is not installed, it will install it automatically (Linux via the official Docker APT repository; macOS via Homebrew).

If any `neopz-dev:*` image already exists, the script lists them and asks whether you want to build a new one or skip. When building, you are asked for a **tag** (default: `latest`), so multiple variants can coexist as `neopz-dev:latest`, `neopz-dev:mumps`, `neopz-dev:release`, etc.

### Build Options

| Option | Default | Description |
|---|---|---|
| `BUILD_TYPE` | `Debug` | **`Debug`**: includes debug symbols, no optimization — ideal for development and stepping through code in a debugger. **`Release`**: full compiler optimizations, smaller binary — use for production runs. |
| `BUILD_UNITTESTING` | `OFF` | Compiles the NeoPZ unit test suite using the [Catch2](https://github.com/catchorg/Catch2) framework. Enable this if you want to verify the NeoPZ build itself. |
| `USING_LOG4CXX` | `ON` | Enables the [Apache Log4cxx](https://logging.apache.org/log4cxx/) logging library inside NeoPZ. Provides structured, levelled log output for simulation diagnostics. |
| `USING_MUMPS` | `OFF` | Enables the [MUMPS](https://mumps-solver.org/) multifrontal sparse direct solver. Required for large, ill-conditioned, or saddle-point linear systems that iterative solvers struggle with. |
| `USING_MKL` | `OFF` | Links NeoPZ against [Intel oneAPI MKL](https://www.intel.com/content/www/us/en/developer/tools/oneapi/onemkl.html) for optimised BLAS/LAPACK routines. Significant performance gain on Intel CPUs. x86_64 only. |
| `USING_METIS` | `OFF` | Enables the [METIS](http://glaros.dtc.umn.edu/gkhome/metis/metis/overview) graph partitioner for mesh partitioning and reordering. Works independently of other options. When both METIS and MUMPS are enabled, MUMPS is also compiled with METIS support automatically. |

### MUMPS Numeric Variants

MUMPS supports four floating-point variants. The **double (`d`)** variant is always compiled when MUMPS is enabled. You may additionally select:

| Code | Variant | Use case |
|---|---|---|
| `s` | `smumps` — real single precision | Reduced memory footprint |
| `c` | `cmumps` — complex single precision | Complex-valued PDEs (low precision) |
| `z` | `zmumps` — complex double precision | Complex-valued PDEs (high precision) |
| `all` | All four variants | |

---

## Step 2 — Run the Container (`run.sh`)

```bash
./run.sh
```

This script:

1. Ensures Docker is available and running (starts the daemon if needed).
2. Lists any existing `neopz-dev` containers whose host volume directory still exists — letting you **resume a previous container** without re-answering any questions.
3. If you choose to create a new container:
   - Asks for the **projects directory** on your host (default: `~/programming`).
   - Lets you **select which image** to use when multiple `neopz-dev:*` tags are available.
   - Suggests a unique container name (`neopz-dev`, `neopz-dev-2`, …).
4. Optionally scaffolds a ready-to-compile **example project** (see below).
5. Starts the container in **detached mode** with your projects directory mounted as a volume.
6. Opens **VS Code** attached to the running container (if `code` is in your PATH).

### Volume Mapping

| Host path | Container path | Purpose |
|---|---|---|
| `<projects_dir>` (you choose) | `/home/labmec/programming/neopz/neopz_projects` | Your source code, live-synced between host and container |

Everything else inside the container (NeoPZ headers, libraries, source, optional solvers) is baked into the image and is read-only from your perspective.

### Example Project

If you choose to create an example project, `run.sh` generates a complete, compilable project with:

- **`CMakeLists.txt`** — finds and links against the installed NeoPZ package.
- **`main.cpp`** — a Darcy flow simulation on a 2D quadrilateral mesh, producing VTK output.
- **`<name>.code-workspace`** — a VS Code multi-root workspace that opens both your project folder and the NeoPZ source tree (for IDE navigation and debugger source stepping).

To compile and run it inside the container:

```bash
# Open a shell in the running container
docker exec -it neopz-dev /bin/bash

# Navigate to your project and build it
cd /home/labmec/programming/neopz/neopz_projects/firsttest
cmake -B build -G Ninja -DNeoPZ_DIR=$NeoPZ_DIR
cmake --build build
./build/firsttest
```

### VS Code Integration

When `run.sh` finishes, VS Code opens directly attached to the container via the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension. All editing, building, debugging, and IntelliSense happen inside the container — no local C++ toolchain required.

The generated `.code-workspace` file adds the NeoPZ source tree as a second root folder, enabling:
- Full symbol navigation across NeoPZ headers and implementation files.
- Source-level stepping into NeoPZ code with GDB.
- `clangd`/IntelliSense powered by the `compile_commands.json` generated during the NeoPZ build.

To stop the container:

```bash
docker stop neopz-dev
```

The container is kept after stopping and can be restarted by running `./run.sh` again (select it from the list) or directly with `docker start neopz-dev`. Your project files always remain safe on the host.

---

## Container Layout

```
/home/labmec/programming/neopz/
├── neopz/               ← NeoPZ source tree (headers + compile_commands.json, no build artifacts)
├── neopz_install/       ← Installed NeoPZ headers and compiled libraries
├── mumps/               ← MUMPS install (present only when built with USING_MUMPS=1)
└── neopz_projects/      ← Volume mount — your project source code lives here
```

The environment variable `NeoPZ_DIR` is pre-set to `/home/labmec/programming/neopz/neopz_install` inside the container, so CMake's `find_package(NeoPZ REQUIRED)` works without any extra flags.

---

## Developing Your Own Project

Any project inside `neopz_projects/` follows this minimal CMake template:

```cmake
cmake_minimum_required(VERSION 3.14)
project(MySimulation)

find_package(NeoPZ REQUIRED HINTS $ENV{NeoPZ_DIR})

add_executable(MySimulation main.cpp)
target_link_libraries(MySimulation NeoPZ::pz)
```

Build it inside the container:

```bash
cmake -B build -G Ninja
cmake --build build
```

---

## VS Code Extensions

Running `./build.sh vscode` (or calling `install_vscode_extensions.sh` directly) installs the following extensions on the **host**:

| Extension | Purpose |
|---|---|
| `ms-vscode.cpptools` | C/C++ language support, IntelliSense, and debugging |
| `ms-vscode.cmake-tools` | CMake project integration, configure/build from the VS Code UI |

The **Dev Containers** extension (`ms-vscode-remote.remote-containers`) must be installed separately from the VS Code Marketplace to use the container-attach workflow.

---

## Dockerfile Architecture

The image is built in three stages to keep the final image lean:

| Stage | Base | Purpose |
|---|---|---|
| `builder-mumps` | `debian:trixie-slim` | Clones and compiles MUMPS from source. Produces an empty directory when `USING_MUMPS=0`, so downstream stages are always valid. |
| `builder` | `debian:trixie-slim` | Installs the build toolchain, optional packages (Log4cxx, METIS, MKL), copies MUMPS artifacts, clones NeoPZ, and runs the CMake configure + build + install cycle. Strips build artifacts from the source tree before export. |
| *(final)* | `debian:trixie-slim` | Copies only the installed NeoPZ files, the stripped source tree, MUMPS libs, and MKL runtime libs from the builder stages. Registers shared libraries with `ldconfig`. Creates the `labmec` user and sets the working directory. |

This multi-stage approach ensures that compilers, intermediate object files, and build caches are never present in the shipped image.
