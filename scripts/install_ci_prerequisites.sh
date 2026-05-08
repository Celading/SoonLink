#!/bin/sh
set -eu

run_with_privilege() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return 0
  fi

  echo "missing root privileges and sudo is unavailable; cannot install CI prerequisites automatically" >&2
  return 1
}

install_first_available_package() {
  package_manager="$1"
  shift

  for package_name in "$@"; do
    if run_with_privilege "$package_manager" install -y "$package_name"; then
      return 0
    fi
  done

  return 1
}

have_required_commands() {
  for cmd in curl file git tar unzip zip python3 cmake gcc g++; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      return 1
    fi
  done

  if ! command -v ninja >/dev/null 2>&1 && ! command -v ninja-build >/dev/null 2>&1; then
    return 1
  fi

  if ! command -v pkg-config >/dev/null 2>&1; then
    return 1
  fi

  if ! pkg-config --exists openssl >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

if have_required_commands; then
  exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
  run_with_privilege apt-get update -o Acquire::Retries=5
  run_with_privilege apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    file \
    git \
    libssl-dev \
    ninja-build \
    pkg-config \
    tar \
    unzip \
    zip \
    python3
elif command -v dnf >/dev/null 2>&1; then
  run_with_privilege dnf install -y \
    gcc \
    gcc-c++ \
    make \
    cmake \
    openssl \
    openssl-devel \
    ca-certificates \
    curl \
    file \
    git \
    tar \
    unzip \
    zip \
    python3 \
    findutils \
    which
  install_first_available_package dnf ninja-build ninja
  install_first_available_package dnf pkgconf-pkg-config pkgconf pkgconfig
elif command -v yum >/dev/null 2>&1; then
  run_with_privilege yum install -y \
    gcc \
    gcc-c++ \
    make \
    cmake \
    openssl \
    openssl-devel \
    ca-certificates \
    curl \
    file \
    git \
    tar \
    unzip \
    zip \
    python3 \
    findutils \
    which
  install_first_available_package yum ninja-build ninja
  install_first_available_package yum pkgconf-pkg-config pkgconf pkgconfig
else
  echo "unsupported package manager; install curl, file, git, tar, unzip, zip, python3, cmake, ninja, pkg-config, openssl development headers, and a C/C++ toolchain manually" >&2
  exit 1
fi

have_required_commands || {
  echo "missing required CI native build prerequisites after dependency installation" >&2
  exit 1
}
