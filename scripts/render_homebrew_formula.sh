#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${ROOT_DIR}/dist/homebrew/soonlink.rb"
FORMULA_URL=""
FORMULA_SHA256=""
FORMULA_VERSION=""
FORMULA_URL_AMD64=""
FORMULA_SHA256_AMD64=""
FORMULA_URL_ARM64=""
FORMULA_SHA256_ARM64=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      FORMULA_URL="${2:-}"
      shift 2
      ;;
    --sha256)
      FORMULA_SHA256="${2:-}"
      shift 2
      ;;
    --version)
      FORMULA_VERSION="${2:-}"
      shift 2
      ;;
    --url-amd64)
      FORMULA_URL_AMD64="${2:-}"
      shift 2
      ;;
    --sha256-amd64)
      FORMULA_SHA256_AMD64="${2:-}"
      shift 2
      ;;
    --url-arm64)
      FORMULA_URL_ARM64="${2:-}"
      shift 2
      ;;
    --sha256-arm64)
      FORMULA_SHA256_ARM64="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$FORMULA_VERSION" ]; then
  echo "usage: $0 --version <version> [--url <url> --sha256 <sha256>] [--url-amd64 <url> --sha256-amd64 <sha256> --url-arm64 <url> --sha256-arm64 <sha256>] [--output <path>]" >&2
  exit 1
fi

if [ -n "$FORMULA_URL" ] || [ -n "$FORMULA_SHA256" ]; then
  if [ -z "$FORMULA_URL" ] || [ -z "$FORMULA_SHA256" ]; then
    echo "single-archive mode requires both --url and --sha256" >&2
    exit 1
  fi
fi

if [ -n "$FORMULA_URL_AMD64" ] || [ -n "$FORMULA_SHA256_AMD64" ] || [ -n "$FORMULA_URL_ARM64" ] || [ -n "$FORMULA_SHA256_ARM64" ]; then
  if [ -z "$FORMULA_URL_AMD64" ] || [ -z "$FORMULA_SHA256_AMD64" ] || [ -z "$FORMULA_URL_ARM64" ] || [ -z "$FORMULA_SHA256_ARM64" ]; then
    echo "multi-arch mode requires amd64 and arm64 URLs plus checksums" >&2
    exit 1
  fi
fi

if [ -z "$FORMULA_URL" ] && [ -z "$FORMULA_URL_AMD64" ]; then
  echo "missing formula archive URL" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [ -n "$FORMULA_URL_AMD64" ]; then
  cat > "$OUTPUT_PATH" <<EOF
class Soonlink < Formula
  desc "SoonLink file transfer service"
  homepage "https://github.com/Celading/SoonLink"
  license "Apache-2.0"
  version "${FORMULA_VERSION}"

  on_macos do
    if Hardware::CPU.arm?
      url "${FORMULA_URL_ARM64}"
      sha256 "${FORMULA_SHA256_ARM64}"
    else
      url "${FORMULA_URL_AMD64}"
      sha256 "${FORMULA_SHA256_AMD64}"
    end
  end

  def install
    libexec.install Dir["*"]
    (bin/"soonlink").write <<~SH
      #!/bin/sh
      cd "\#{libexec}"
      exec "\#{libexec}/soonlnk" "\$@"
    SH
    chmod 0755, bin/"soonlink"
  end

  test do
    output = shell_output("#{bin}/soonlink version")
    assert_match "SoonLink", output
  end
end
EOF
else
  cat > "$OUTPUT_PATH" <<EOF
class Soonlink < Formula
  desc "SoonLink file transfer service"
  homepage "https://github.com/Celading/SoonLink"
  url "${FORMULA_URL}"
  sha256 "${FORMULA_SHA256}"
  version "${FORMULA_VERSION}"
  license "Apache-2.0"

  def install
    libexec.install Dir["*"]
    (bin/"soonlink").write <<~SH
      #!/bin/sh
      cd "\#{libexec}"
      exec "\#{libexec}/soonlnk" "\$@"
    SH
    chmod 0755, bin/"soonlink"
  end

  test do
    output = shell_output("#{bin}/soonlink version")
    assert_match "SoonLink", output
  end
end
EOF
fi

echo "rendered Homebrew formula: $OUTPUT_PATH"
