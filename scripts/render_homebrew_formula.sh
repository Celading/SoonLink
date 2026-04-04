#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${ROOT_DIR}/dist/homebrew/soonlink.rb"
FORMULA_URL=""
FORMULA_SHA256=""
FORMULA_VERSION=""

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

if [ -z "$FORMULA_URL" ] || [ -z "$FORMULA_SHA256" ] || [ -z "$FORMULA_VERSION" ]; then
  echo "usage: $0 --url <url> --sha256 <sha256> --version <version> [--output <path>]" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

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

echo "rendered Homebrew formula: $OUTPUT_PATH"
