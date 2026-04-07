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

have_required_commands() {
  for cmd in curl file git tar unzip zip python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      return 1
    fi
  done

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
    curl \
    file \
    git \
    tar \
    unzip \
    zip \
    python3
elif command -v dnf >/dev/null 2>&1; then
  run_with_privilege dnf install -y \
    gcc \
    gcc-c++ \
    make \
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
elif command -v yum >/dev/null 2>&1; then
  run_with_privilege yum install -y \
    gcc \
    gcc-c++ \
    make \
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
else
  echo "unsupported package manager; install curl, file, git, tar, unzip, zip, python3, and a C/C++ toolchain manually" >&2
  exit 1
fi

have_required_commands || {
  echo "missing required CI commands after dependency installation" >&2
  exit 1
}
