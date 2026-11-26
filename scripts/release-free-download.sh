#!/bin/sh
# Builds, notarizes and publishes the free Mac download (ADR 0011) as a GitHub release.
#
# Usage (from the repository root, on an up-to-date main):
#   scripts/release-free-download.sh             # creates a draft release for review
#   scripts/release-free-download.sh --publish   # publishes the release right away
#   scripts/release-free-download.sh --no-release  # only builds the notarized zip
#
# Steps: archive the scheme "SlidePilot Free Download", export it with Developer ID and
# send it to Apple's notary service, wait until the notarized app can be exported,
# verify signature and stapling, zip it and create the release "vX.Y.Z" at the current
# commit with notes generated from the merged pull requests.
#
# Needs the signing identity of the Xcode account, the network and a signed-in gh, so run
# it in your own terminal, not in the Claude Code sandbox. See docs/release.md.
set -eu

project="SlidePilot.xcodeproj"
scheme="SlidePilot Free Download"
configuration="FreeDownload"
out="./build/release-free-download"
archive="$out/SlidePilot-FreeDownload.xcarchive"
export_dir="$out/export"
notarized_dir="$out/notarized"
app_name="SlidePilot.app"
# Notarization usually takes a few minutes; give up after 30 polls (about 30 minutes).
poll_interval=60
poll_attempts=30

publish=false
create_release=true
for arg in "$@"; do
    case "$arg" in
        --publish) publish=true ;;
        --no-release) create_release=false ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 64 ;;
    esac
done

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    printf '\n==> %s\n' "$*"
}

[ -d "$project" ] || fail "Run this from the repository root."

step "Checking the working tree"
[ -z "$(git status --porcelain)" ] || fail "The working tree has uncommitted changes."
if $create_release; then
    branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$branch" = "main" ] || fail "Releases are made from main (current branch: $branch)."
    git fetch origin main --tags
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
        || fail "main is not equal to origin/main. Run: git pull origin main --ff-only"
    gh auth status >/dev/null 2>&1 || fail "gh is not signed in. Run: gh auth login"
fi
commit=$(git rev-parse HEAD)

step "Reading the version"
version=$(xcodebuild -project "$project" -scheme "$scheme" -configuration "$configuration" \
    -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '$1 ~ /^ *MARKETING_VERSION$/ { print $2; exit }')
printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail "MARKETING_VERSION '$version' is not of the form X.Y.Z."
tag="v$version"
zip="$out/SlidePilot-$version-macOS.zip"
echo "Version $version, tag $tag, commit $commit"

if $create_release; then
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        fail "Tag $tag already exists. Raise MARKETING_VERSION in Config/Shared.xcconfig first."
    fi
    if gh release view "$tag" >/dev/null 2>&1; then
        fail "A GitHub release $tag already exists."
    fi
fi

step "Archiving $scheme"
rm -rf "$out"
mkdir -p "$out"
xcodebuild -project "$project" -scheme "$scheme" -configuration "$configuration" \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -allowProvisioningUpdates -quiet archive

step "Exporting with Developer ID and submitting for notarization"
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist Config/ExportOptions-DeveloperID.plist \
    -exportPath "$export_dir" -allowProvisioningUpdates

step "Waiting for notarization (up to $((poll_interval * poll_attempts / 60)) minutes)"
attempt=1
log="$out/export-notarized.log"
until xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$notarized_dir" >"$log" 2>&1; do
    if [ "$attempt" -ge "$poll_attempts" ]; then
        cat "$log" >&2
        fail "The notarized app is not available yet. Check the status in Xcode (Window > Organizer), then run: xcodebuild -exportNotarizedApp -archivePath $archive -exportPath $notarized_dir"
    fi
    echo "Not notarized yet (attempt $attempt of $poll_attempts), checking again in $poll_interval s"
    attempt=$((attempt + 1))
    sleep "$poll_interval"
done
app="$notarized_dir/$app_name"
[ -d "$app" ] || fail "$app was not exported (see $log)."

step "Verifying signature, notarization ticket and Gatekeeper"
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"

step "Zipping"
ditto -c -k --keepParent "$app" "$zip"
checksum=$(shasum -a 256 "$zip" | awk '{ print $1 }')
echo "$zip"
echo "SHA-256: $checksum"

if ! $create_release; then
    echo "Done. No release created (--no-release)."
    exit 0
fi

step "Creating the GitHub release $tag"
draft_flag="--draft"
$publish && draft_flag=""
# shellcheck disable=SC2086 # draft_flag is empty or one word on purpose.
gh release create "$tag" "$zip" $draft_flag --target "$commit" --title "SlidePilot $version" \
    --generate-notes --notes "Free download for macOS 26. SHA-256 of the zip: $checksum"

if $publish; then
    echo "Published $tag."
else
    echo "Created the draft release $tag. Review the notes on GitHub and publish it there."
fi
