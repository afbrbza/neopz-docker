# =============================================================
# NeoPZ Development Image
# Build args (0 = off, 1 = on):
#   BUILD_TYPE          – Debug or Release             (default: Debug)
#   BUILD_UNITTESTING   – Catch2 unit tests            (default: 0)
#   USING_LOG4CXX       – LOG4CXX logging              (default: 1)
#   USING_MKL           – Intel MKL / oneAPI           (default: 0, x86_64 only)
#   USING_METIS         – METIS graph partitioner      (default: 0)
#   USING_MUMPS         – MUMPS sparse solver          (default: 0)
#   MUMPS_BUILD_SINGLE  – MUMPS single (s) variant     (default: 0)
#   MUMPS_BUILD_COMPLEX – MUMPS complex float (c)      (default: 0)
#   MUMPS_BUILD_COMPLEX16 – MUMPS complex double (z)   (default: 0)
#   (MUMPS double (d) variant is always built when USING_MUMPS=1)
#
# Runtime container layout:
#   /home/labmec/programming/neopz/
#     ├── neopz/               ← NeoPZ source (for IDE navigation / debug)
#     ├── neopz_install/       ← NeoPZ installed headers + libs
#     ├── mumps/               ← MUMPS install (when USING_MUMPS=1)
#     └── neopz_projects/      ← volume-mounted user projects
# =============================================================


# =============================================================
# Stage 1 – MUMPS builder
# Based on: giavancini/mumps (CMake build system)
# Ref: MUMPS_IMPLEMENTATION.md
# Variant flag names follow MUMPS/LAPACK conventions:
#   BUILD_DOUBLE=on   → dmumps (d - real double)       always ON
#   BUILD_SINGLE=on   → smumps (s - real single)
#   BUILD_COMPLEX=on  → cmumps (c - complex float)
#   BUILD_COMPLEX16=on→ zmumps (z - complex double)
# =============================================================
FROM debian:trixie-slim AS builder-mumps

ARG USING_MUMPS=0
ARG USING_METIS=0
ARG MUMPS_BUILD_SINGLE=0
ARG MUMPS_BUILD_COMPLEX=0
ARG MUMPS_BUILD_COMPLEX16=0

ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir -p /home/labmec/programming/neopz/mumps && \
    if [ "${USING_MUMPS}" = "1" ]; then \
        METIS_PKG=""; [ "${USING_METIS}" = "1" ] && METIS_PKG="libmetis-dev"; \
        apt-get update && apt-get install -y \
            build-essential cmake git gfortran \
            libopenblas-dev $METIS_PKG \
            && rm -rf /var/lib/apt/lists/* && \
        git clone --depth=1 https://github.com/giavancini/mumps.git /tmp/mumps-src && \
        METIS_FLAG="-DMUMPS_metis=off"; \
        [ "${USING_METIS}" = "1" ] && METIS_FLAG="-DMUMPS_metis=on"; \
        cmake -S /tmp/mumps-src -B /tmp/mumps-src/build \
            -DBUILD_DOUBLE=on \
            "-DBUILD_SINGLE=$([ "${MUMPS_BUILD_SINGLE}"      = "1" ] && echo on || echo off)" \
            "-DBUILD_COMPLEX=$([ "${MUMPS_BUILD_COMPLEX}"     = "1" ] && echo on || echo off)" \
            "-DBUILD_COMPLEX16=$([ "${MUMPS_BUILD_COMPLEX16}" = "1" ] && echo on || echo off)" \
            -DMUMPS_parallel=false \
            -DMUMPS_openmp=on \
            -DBUILD_SHARED_LIBS=on \
            -DMUMPS_intsize64=on \
            $METIS_FLAG \
            -DMUMPS_find_SCALAPACK=false \
            -DMUMPS_scalapack=false \
            -DLAPACK_VENDOR=OpenBLAS \
            -DCMAKE_INSTALL_PREFIX=/tmp/mumps-src/build/install && \
        cmake --build /tmp/mumps-src/build && \
        cmake --install /tmp/mumps-src/build && \
        cp -r /tmp/mumps-src/build/install/. /home/labmec/programming/neopz/mumps/ && \
        rm -rf /tmp/mumps-src; \
    fi


# =============================================================
# Stage 2 – NeoPZ builder
# =============================================================
FROM debian:trixie-slim AS builder

ARG BUILD_TYPE=Debug
ARG BUILD_UNITTESTING=0
ARG USING_LOG4CXX=1
ARG USING_MKL=0
ARG USING_METIS=0
ARG USING_MUMPS=0

ENV DEBIAN_FRONTEND=noninteractive

# ── Base build tools ──────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    ninja-build \
    git \
    wget \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# ── Optional apt packages ─────────────────────────────────────
RUN set -e; \
    PKGS=""; \
    [ "${USING_LOG4CXX}" = "1" ] && PKGS="$PKGS liblog4cxx-dev"; \
    [ "${USING_METIS}"   = "1" ] && PKGS="$PKGS libmetis-dev"; \
    if [ -n "$PKGS" ]; then \
        apt-get update && apt-get install -y $PKGS && rm -rf /var/lib/apt/lists/*; \
    fi

# ── Intel oneAPI MKL (x86_64 only) ───────────────────────────
RUN mkdir -p /opt/intel && \
    if [ "${USING_MKL}" = "1" ]; then \
        wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
            | gpg --dearmor -o /usr/share/keyrings/intel-oneapi-archive-keyring.gpg && \
        echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
            > /etc/apt/sources.list.d/oneAPI.list && \
        apt-get update && apt-get install -y intel-oneapi-mkl-devel && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# ── Import MUMPS artifacts ────────────────────────────────────
COPY --from=builder-mumps \
    /home/labmec/programming/neopz/mumps \
    /home/labmec/programming/neopz/mumps

# ── Clone NeoPZ repository ────────────────────────────────────
WORKDIR /home/labmec/programming/neopz
RUN git clone --depth=1 --branch develop https://github.com/labmec/neopz.git

# ── Configure & build ─────────────────────────────────────────
WORKDIR /home/labmec/programming/neopz/neopz

RUN MKL_FLAG=""; MUMPS_FLAG=""; \
    [ "${USING_MKL}"   = "1" ] && MKL_FLAG="-DMKL_ROOT=/opt/intel/oneapi/mkl/latest"; \
    [ "${USING_MUMPS}" = "1" ] && MUMPS_FLAG="-DMUMPS_ROOT=/home/labmec/programming/neopz/mumps"; \
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DCMAKE_INSTALL_PREFIX=/home/labmec/programming/neopz/neopz_install \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        "-DBUILD_UNITTESTING=$([ "${BUILD_UNITTESTING}" = "1" ] && echo ON || echo OFF)" \
        "-DUSING_LOG4CXX=$([ "${USING_LOG4CXX}" = "1" ] && echo ON || echo OFF)" \
        "-DUSING_MKL=$([ "${USING_MKL}" = "1" ] && echo ON || echo OFF)" \
        "-DUSING_METIS=$([ "${USING_METIS}" = "1" ] && echo ON || echo OFF)" \
        "-DUSING_MUMPS=$([ "${USING_MUMPS}" = "1" ] && echo ON || echo OFF)" \
        $MKL_FLAG $MUMPS_FLAG

RUN cmake --build build
RUN cmake --install build

# ── Prepare source tree for IDE / debug (no build artifacts) ──
# compile_commands.json is preserved at the source root for clangd / IntelliSense
RUN cp -r /home/labmec/programming/neopz/neopz \
          /home/labmec/programming/neopz/neopz_src && \
    cp build/compile_commands.json /home/labmec/programming/neopz/neopz_src/ 2>/dev/null || true && \
    rm -rf /home/labmec/programming/neopz/neopz_src/build


# =============================================================
# Stage 3 – Runtime image
# =============================================================
FROM debian:trixie-slim

# ARGs must be re-declared in each stage that uses them
ARG USING_LOG4CXX=1
ARG USING_METIS=0

ENV DEBIAN_FRONTEND=noninteractive

RUN set -e; \
    PKGS="build-essential cmake ninja-build git gdb valgrind python3"; \
    [ "${USING_LOG4CXX}" = "1" ] && PKGS="$PKGS liblog4cxx-dev"; \
    [ "${USING_METIS}"   = "1" ] && PKGS="$PKGS libmetis-dev"; \
    apt-get update && apt-get install -y $PKGS && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash labmec

# ── NeoPZ installed headers + libs ───────────────────────────
COPY --from=builder \
    /home/labmec/programming/neopz/neopz_install \
    /home/labmec/programming/neopz/neopz_install

# ── NeoPZ source (for IDE navigation and gdb source stepping) ─
COPY --from=builder \
    /home/labmec/programming/neopz/neopz_src \
    /home/labmec/programming/neopz/neopz

# ── MUMPS install (empty dir when USING_MUMPS=0) ─────────────
COPY --from=builder-mumps \
    /home/labmec/programming/neopz/mumps \
    /home/labmec/programming/neopz/mumps

# ── Intel MKL runtime libs (empty dir when USING_MKL=0) ──────
COPY --from=builder /opt/intel /opt/intel

# Register shared libraries (harmless if dirs are empty)
RUN echo "/home/labmec/programming/neopz/mumps/lib" > /etc/ld.so.conf.d/mumps.conf \
    && echo "/opt/intel/oneapi/mkl/latest/lib/intel64" > /etc/ld.so.conf.d/mkl.conf \
    && ldconfig

ENV NeoPZ_DIR=/home/labmec/programming/neopz/neopz_install

RUN mkdir -p /home/labmec/programming/neopz/neopz_projects \
    && chown -R labmec:labmec /home/labmec

USER labmec
WORKDIR /home/labmec/programming/neopz/neopz_projects

VOLUME /home/labmec/programming/neopz/neopz_projects

CMD ["/bin/bash"]
