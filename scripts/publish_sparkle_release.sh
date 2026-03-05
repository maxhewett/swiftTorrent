#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/publish_sparkle_release.sh <version> <exported-app-or-zip> [release-notes-html] [--channel stable|beta]
  scripts/publish_sparkle_release.sh --version <version> --artifact <path> [--release-notes <path>] [--channel stable|beta]

Example:
  scripts/publish_sparkle_release.sh 0.1.5 ~/Desktop/swiftTorrent.app docs/release-notes/0.1.5.html --channel beta

What it does:
  - accepts either a signed exported .app or a prebuilt .zip
  - creates a Sparkle-friendly zip when given a .app
  - derives the GitHub Releases download URL from the origin remote and version
  - creates or updates the GitHub Release when gh is available and authenticated
  - uploads the release asset when gh is available and authenticated
  - runs Sparkle's generate_appcast against the supplied signed archive
  - rewrites enclosure/release notes URLs for GitHub Releases / GitHub Pages
  - writes appcast to docs/appcast.xml (stable) or docs/beta/appcast.xml (beta)

Requirements:
  - Sparkle must already be resolved by Xcode
  - generate_appcast must be available, or SPARKLE_GENERATE_APPCAST must be set
  - if your Sparkle setup requires an explicit key file, set SPARKLE_PRIVATE_KEY_PATH
USAGE
}

VERSION=""
INPUT_PATH=""
RELEASE_NOTES_PATH=""
CHANNEL="stable"

parse_args() {
  if [[ $# -ge 2 && "$1" != --* ]]; then
    VERSION="$1"
    INPUT_PATH="$2"
    RELEASE_NOTES_PATH="${3:-}"
    shift $(( $# >= 3 ? 3 : 2 ))
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        VERSION="${2:-}"
        shift 2
        ;;
      --artifact)
        INPUT_PATH="${2:-}"
        shift 2
        ;;
      --release-notes)
        RELEASE_NOTES_PATH="${2:-}"
        shift 2
        ;;
      --channel)
        CHANNEL="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$VERSION" || -z "$INPUT_PATH" ]]; then
    usage
    exit 1
  fi

  if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "beta" ]]; then
    echo "Unsupported channel: $CHANNEL" >&2
    exit 1
  fi
}

parse_args "$@"

INPUT_PATH="$(cd "$(dirname "$INPUT_PATH")" && pwd)/$(basename "$INPUT_PATH")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
APPCAST_DIR="$DOCS_DIR"
if [[ "$CHANNEL" == "beta" ]]; then
  APPCAST_DIR="$DOCS_DIR/beta"
fi
APPCAST_PATH="$APPCAST_DIR/appcast.xml"
RELEASES_DIR="$ROOT_DIR/release-artifacts"
APP_NAME="swiftTorrent"

if [[ ! -e "$INPUT_PATH" ]]; then
  echo "Input not found: $INPUT_PATH" >&2
  exit 1
fi

if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  RELEASE_NOTES_PATH="$(cd "$(dirname "$RELEASE_NOTES_PATH")" && pwd)/$(basename "$RELEASE_NOTES_PATH")"
  if [[ ! -f "$RELEASE_NOTES_PATH" ]]; then
    echo "Release notes not found: $RELEASE_NOTES_PATH" >&2
    exit 1
  fi
fi

find_generate_appcast() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" && -x "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    printf '%s\n' "$SPARKLE_GENERATE_APPCAST"
    return 0
  fi

  local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
  if [[ -d "$derived_data" ]]; then
    find "$derived_data" -type f \
      \( -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -o -path '*/SourcePackages/checkouts/Sparkle/generate_appcast' \) \
      2>/dev/null | head -n 1
    return 0
  fi

  return 1
}

GENERATE_APPCAST="$(find_generate_appcast)"
if [[ -z "${GENERATE_APPCAST:-}" || ! -x "$GENERATE_APPCAST" ]]; then
  echo "Could not find Sparkle's generate_appcast tool." >&2
  echo "Set SPARKLE_GENERATE_APPCAST to the full path after Xcode resolves the Sparkle package." >&2
  exit 1
fi

REMOTE_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo "Could not parse GitHub owner/repo from origin: $REMOTE_URL" >&2
  exit 1
fi

TAG_SUFFIX=""
if [[ "$CHANNEL" == "beta" ]]; then
  TAG_SUFFIX="-beta"
fi
TAG="v${VERSION}${TAG_SUFFIX}"

PAGES_BASE_URL="https://${OWNER}.github.io/${REPO}"
CHANNEL_PAGES_BASE_URL="$PAGES_BASE_URL"
if [[ "$CHANNEL" == "beta" ]]; then
  CHANNEL_PAGES_BASE_URL="${PAGES_BASE_URL}/beta"
fi

RELEASE_NOTES_URL=""
mkdir -p "$RELEASES_DIR"
mkdir -p "$APPCAST_DIR"

make_archive_if_needed() {
  local input_path="$1"
  local suffix=""
  if [[ "$CHANNEL" == "beta" ]]; then
    suffix="-beta"
  fi
  local output_path="$RELEASES_DIR/${APP_NAME}-${VERSION}${suffix}.zip"

  if [[ -d "$input_path" && "$input_path" == *.app ]]; then
    echo "Packaging exported app into $(basename "$output_path")..." >&2
    ditto -c -k --sequesterRsrc --keepParent "$input_path" "$output_path"
    printf '%s\n' "$output_path"
    return 0
  fi

  if [[ -f "$input_path" && "$input_path" == *.zip ]]; then
    printf '%s\n' "$input_path"
    return 0
  fi

  echo "Input must be a signed .app bundle or a .zip archive: $input_path" >&2
  exit 1
}

ARCHIVE_PATH="$(make_archive_if_needed "$INPUT_PATH")"
ASSET_NAME="$(basename "$ARCHIVE_PATH")"
DOWNLOAD_BASE_URL="https://github.com/${OWNER}/${REPO}/releases/download/${TAG}"
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/${ASSET_NAME}"

if [[ "$ARCHIVE_PATH" == *.zip ]]; then
  if ! unzip -p "$ARCHIVE_PATH" "*/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Could not inspect Info.plist inside archive: $ARCHIVE_PATH" >&2
    exit 1
  fi

  BUNDLE_VERSION="$(unzip -p "$ARCHIVE_PATH" "*/Contents/Info.plist" | plutil -extract CFBundleVersion raw -o - - 2>/dev/null || true)"
  if [[ -z "${BUNDLE_VERSION:-}" ]]; then
    echo "Archive is missing CFBundleVersion. Sparkle requires a numeric build version." >&2
    exit 1
  fi

  if ! [[ "$BUNDLE_VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    echo "CFBundleVersion must be numeric for Sparkle updates. Found: $BUNDLE_VERSION" >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$ARCHIVE_PATH" "$TMP_DIR/"

if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  RELEASE_NOTES_DIR="$DOCS_DIR/release-notes"
  if [[ "$CHANNEL" == "beta" ]]; then
    RELEASE_NOTES_DIR="$DOCS_DIR/beta/release-notes"
  fi
  mkdir -p "$RELEASE_NOTES_DIR"
  RELEASE_NOTES_BASENAME="${VERSION}.html"
  cp "$RELEASE_NOTES_PATH" "$RELEASE_NOTES_DIR/$RELEASE_NOTES_BASENAME"
  RELEASE_NOTES_URL="${CHANNEL_PAGES_BASE_URL}/release-notes/${RELEASE_NOTES_BASENAME}"
fi

CMD=("$GENERATE_APPCAST" "$TMP_DIR")
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
  HELP_TEXT="$("$GENERATE_APPCAST" -h 2>&1 || true)"
  if grep -q -- '--ed-key-file' <<<"$HELP_TEXT"; then
    CMD+=("--ed-key-file" "$SPARKLE_PRIVATE_KEY_PATH")
  fi
fi

"${CMD[@]}"

GENERATED_APPCAST="$(find "$TMP_DIR" -maxdepth 1 -type f -name '*.xml' | head -n 1)"
if [[ -z "${GENERATED_APPCAST:-}" || ! -f "$GENERATED_APPCAST" ]]; then
  echo "generate_appcast did not produce an XML file in $TMP_DIR" >&2
  exit 1
fi

cp "$GENERATED_APPCAST" "$APPCAST_PATH"
perl -0pi -e "s#url=\"[^\"]*${ASSET_NAME}\"#url=\"${DOWNLOAD_URL}\"#g" "$APPCAST_PATH"

if [[ -n "$RELEASE_NOTES_URL" ]]; then
  perl -0pi -e "s#sparkle:releaseNotesLink=\"[^\"]*\"#sparkle:releaseNotesLink=\"${RELEASE_NOTES_URL}\"#g" "$APPCAST_PATH"
fi

publish_release_if_possible() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "Skipping GitHub Release publish: gh is not installed."
    return 0
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "Skipping GitHub Release publish: gh is not authenticated."
    return 0
  fi

  local notes_args=()
  if [[ -n "$RELEASE_NOTES_PATH" ]]; then
    notes_args=(--notes-file "$RELEASE_NOTES_PATH")
  else
    notes_args=(--notes "${APP_NAME} ${VERSION}")
  fi

  if gh release view "$TAG" --repo "${OWNER}/${REPO}" >/dev/null 2>&1; then
    echo "Uploading asset to existing GitHub Release ${TAG}..."
  else
    echo "Creating GitHub Release ${TAG}..."
    local create_args=("$TAG" --repo "${OWNER}/${REPO}" --title "${APP_NAME} ${VERSION}${TAG_SUFFIX}" "${notes_args[@]}")
    if [[ "$CHANNEL" == "beta" ]]; then
      create_args+=(--prerelease)
    fi
    gh release create "${create_args[@]}"
  fi

  echo "Uploading ${ASSET_NAME} to GitHub Release ${TAG}..."
  gh release upload "$TAG" "$ARCHIVE_PATH" --repo "${OWNER}/${REPO}" --clobber
}

publish_release_if_possible

echo "Updated appcast: $APPCAST_PATH"
echo "Archive: $ARCHIVE_PATH"
echo "Release channel: $CHANNEL"
echo "Release asset URL: $DOWNLOAD_URL"
if [[ -n "$RELEASE_NOTES_URL" ]]; then
  echo "Release notes URL: $RELEASE_NOTES_URL"
fi
echo
echo "Next:"
echo "1. Verify GitHub Release ${TAG} exists and contains ${ASSET_NAME}"
echo "2. Commit ${APPCAST_PATH#$ROOT_DIR/} and any docs/release-notes changes"
echo "3. Push main so GitHub Pages publishes the updated appcast"
