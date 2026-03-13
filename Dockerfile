# =============================================================
# NeoPZ Development Image – Pre-compiled Debug Build
#
# All optional libraries are compiled into the image by default:
# - MUMPS (all variants: d, s, c, z)
# - METIS (mesh partitioner)
# - LOG4CXX (logging)
# - LAPACK (via OpenBLAS on all platforms)
# - VSCode extensions (C++ Tools, CMake Tools)
#
# Users can recompile NeoPZ inside the container with
# reduced features if needed.
#
# Runtime container layout:
#   /home/labmec/
#     ├── neopz/               ← NeoPZ source (IDE navigation, debugging)
#     ├── neopz_install/       ← NeoPZ installed headers + libraries
#     ├── mumps/               ← MUMPS libraries
#     └── <user_project_name>/ ← user projects (volume mounts, any name)
# =============================================================


# =============================================================
# Stage 1 – MUMPS builder (always built with all variants)
# Based on: giavancini/mumps (CMake build system)
# Variant flag names follow MUMPS/LAPACK conventions:
#   BUILD_DOUBLE=on   → dmumps (d - real double)       always ON
#   BUILD_SINGLE=on   → smumps (s - real single)       always ON (new)
#   BUILD_COMPLEX=on  → cmumps (c - complex float)     always ON (new)
#   BUILD_COMPLEX16=on→ zmumps (z - complex double)    always ON (new)
# =============================================================
FROM debian:trixie-slim AS builder-mumps

ARG USING_METIS=1
ARG MUMPS_REPO=https://github.com/giavancini/mumps.git

ENV DEBIAN_FRONTEND=noninteractive

# ── Intel oneAPI repository (MKL / PARDISO) ───────────────────
RUN apt-get update -qq && apt-get install -qq -y wget gpg ca-certificates && \
    wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
            | gpg --dearmor -o /usr/share/keyrings/intel-oneapi-archive-keyring.gpg && \
        echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
            > /etc/apt/sources.list.d/oneAPI.list && \
        apt-get update -qq && apt-get install -qq -y intel-oneapi-mkl-devel && \
        rm -rf /var/lib/apt/lists/*;
        
# Force use of /bin/bash for the build steps to ensure proper sourcing of Intel oneAPI environment
SHELL [ "/bin/bash", "-c" ]

RUN source /opt/intel/oneapi/setvars.sh && \
    mkdir -p /home/labmec/mumps && \
    apt-get update -qq && apt-get install -qq -y \
        build-essential cmake git gfortran \
        libopenblas-dev libmetis-dev \
        && rm -rf /var/lib/apt/lists/* && \
    git clone --depth=1 "${MUMPS_REPO}" /tmp/mumps-src && \
    cmake -S /tmp/mumps-src -B /tmp/mumps-src/build \
        -DBUILD_SINGLE=on \
        -DBUILD_DOUBLE=on \
        -DBUILD_COMPLEX=on \
        -DBUILD_COMPLEX16=on \
        -DMUMPS_parallel=false \
        -DMUMPS_openmp=on \
        -DBUILD_SHARED_LIBS=on \
        -DMUMPS_intsize64=on \
        -DMUMPS_metis=on \
        -DMUMPS_find_SCALAPACK=false \
        -DMUMPS_scalapack=false \
        -DLAPACK_VENDOR=MKL \
        -DCMAKE_INSTALL_PREFIX=/tmp/mumps-src/build/install && \
    cmake --build /tmp/mumps-src/build && \
    cmake --install /tmp/mumps-src/build && \
    cp -r /tmp/mumps-src/build/install/. /home/labmec/mumps/ && \
    rm -rf /tmp/mumps-src


# =============================================================
# Stage 2 – NeoPZ builder (always Debug, all features enabled)
# =============================================================
FROM debian:trixie-slim AS builder

ARG NEOPZ_REPO=https://github.com/labmec/neopz.git

ENV DEBIAN_FRONTEND=noninteractive

# ── Intel oneAPI repository (MKL / PARDISO) ───────────────────
RUN apt-get update -qq && apt-get install -qq -y wget gpg ca-certificates && \
    wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
            | gpg --dearmor -o /usr/share/keyrings/intel-oneapi-archive-keyring.gpg && \
        echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
            > /etc/apt/sources.list.d/oneAPI.list && \
        apt-get update -qq && apt-get install -qq -y intel-oneapi-mkl-devel && \
        rm -rf /var/lib/apt/lists/*;

# ── Base build tools ──────────────────────────────────────────
RUN apt-get update -qq && apt-get install -qq -y \
    build-essential \
    cmake \
    pkg-config \
    ninja-build \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── All optional libraries (always enabled) ───────────────────
RUN apt-get update -qq && apt-get install -qq -y \
    liblog4cxx-dev \
    libmetis-dev \
    gfortran \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Import MUMPS artifacts ────────────────────────────────────
COPY --from=builder-mumps /home/labmec/mumps /home/labmec/mumps

# ── Clone NeoPZ repository ────────────────────────────────────
WORKDIR /home/labmec
RUN git clone --depth=1 --branch develop "${NEOPZ_REPO}" neopz

# ── Configure & build (Debug, all features) ───────────────────
WORKDIR /home/labmec/neopz

# Force use of /bin/bash for the build steps to ensure proper sourcing of Intel oneAPI environment
SHELL [ "/bin/bash", "-c" ]

RUN source /opt/intel/oneapi/setvars.sh && \
    cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_INSTALL_PREFIX=/home/labmec/neopz_install \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DBUILD_UNITTESTING=ON \
    -DUSING_LOG4CXX=ON \
    -DUSING_METIS=ON \
    -DUSING_MUMPS=ON \
    -DUSING_MKL=ON \
    -DMUMPS_ROOT=/home/labmec/mumps \
    -DMUMPS_USE_DOUBLE=ON \
    -DMUMPS_USE_SINGLE=ON \
    -DMUMPS_USE_COMPLEX=ON \
    -DMUMPS_USE_COMPLEX16=ON

RUN cmake --build build
RUN cmake --install build

# ── Prepare source tree for IDE / debug (no build artifacts) ──
# compile_commands.json is preserved at the source root for clangd / IntelliSense
RUN cp build/compile_commands.json /home/labmec/neopz/ 2>/dev/null || true && \
    rm -rf /home/labmec/neopz/build


# =============================================================
# Stage 3 – Runtime image
# =============================================================
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# ── Runtime dependencies (all features always available) ──────

# ── Intel oneAPI repository (for MKL / PARDISO) ───────────────
RUN apt-get update -qq && apt-get install -qq -y wget gpg ca-certificates && \
    wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
            | gpg --dearmor -o /usr/share/keyrings/intel-oneapi-archive-keyring.gpg && \
        echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
            > /etc/apt/sources.list.d/oneAPI.list && \
        apt-get update -qq && apt-get install -qq -y intel-oneapi-mkl-devel && \
        rm -rf /var/lib/apt/lists/*;

RUN apt-get update -qq && apt-get install -qq -y \
    build-essential \
    cmake \
    ninja-build \
    git \
    gdb \
    valgrind \
    python3 \
    liblog4cxx-dev \
    libmetis-dev \
    libopenblas-dev \
    intel-oneapi-mkl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash labmec

# ── NeoPZ installed headers + libs ───────────────────────────
COPY --from=builder /home/labmec/neopz_install /home/labmec/neopz_install

# ── NeoPZ source (for IDE navigation and gdb source stepping) ─
COPY --from=builder /home/labmec/neopz /home/labmec/neopz

# ── MUMPS library ───────────────────────────────────────────────
COPY --from=builder-mumps /home/labmec/mumps /home/labmec/mumps

# Register shared libraries
RUN echo "/home/labmec/mumps/lib" > /etc/ld.so.conf.d/mumps.conf && ldconfig
# Load Intel oneAPI environment automatically
RUN echo "source /opt/intel/oneapi/setvars.sh >/dev/null 2>&1" >> /etc/bash.bashrc

# VS Code Dev Containers metadata:
# when attaching from VS Code, these extensions are auto-installed.
LABEL devcontainer.metadata='[{"customizations":{"vscode":{"extensions":["ms-vscode.cpptools","ms-vscode.cmake-tools"]}}}]'

ENV NeoPZ_DIR=/home/labmec/neopz_install

# ── Prepare user home ─────────────────────────────────────────
RUN chown -R labmec:labmec /home/labmec

USER labmec
WORKDIR /home/labmec

# Force use /bin/bash as the default shell for interactive sessions
SHELL ["/bin/bash", "-c"]

# let image let container running to allow users to attach or access the shell
CMD ["/bin/bash", "-c", "sleep infinity"]