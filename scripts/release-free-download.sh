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

# Colors only on a terminal, and never when NO_COLOR is set (https://no-color.org).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); red=$(printf '\033[31m')
    green=$(printf '\033[32m'); yellow=$(printf '\033[33m'); blue=$(printf '\033[34m')
    reset=$(printf '\033[0m')
else
    bold=""; dim=""; red=""; green=""; yellow=""; blue=""; reset=""
fi

started=$(date +%s)
step_number=0
step_title=""
if $create_release; then step_count=8; else step_count=7; fi

elapsed() {
    seconds=$(($(date +%s) - started))
    printf '%d:%02d' $((seconds / 60)) $((seconds % 60))
}

step() {
    step_number=$((step_number + 1))
    step_title="$*"
    printf '\n%s%s[%d/%d] %s%s %s(%s)%s\n' \
        "$bold" "$blue" "$step_number" "$step_count" "$*" "$reset" "$dim" "$(elapsed)" "$reset"
}

info() {
    printf '    %s%s%s\n' "$dim" "$*" "$reset"
}

ok() {
    printf '    %s✓ %s%s\n' "$green" "$*" "$reset"
}

warn() {
    printf '    %s! %s%s\n' "$yellow" "$*" "$reset"
}

fail() {
    printf '\n%s%s✗ %s%s\n' "$bold" "$red" "$*" "$reset" >&2
    trap - EXIT
    exit 1
}

# Any other failing command (set -e) ends up here, so the last step is always named.
on_exit() {
    status=$?
    if [ "$status" -ne 0 ]; then
        printf '\n%s%s✗ Failed during [%d/%d] %s (exit %d, after %s)%s\n' \
            "$bold" "$red" "$step_number" "$step_count" "$step_title" "$status" "$(elapsed)" "$reset" >&2
    fi
}
trap on_exit EXIT

[ -d "$project" ] || fail "Run this from the repository root."

step "Checking the working tree"
[ -z "$(git status --porcelain)" ] || fail "The working tree has uncommitted changes."
ok "Working tree is clean"
if $create_release; then
    branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$branch" = "main" ] || fail "Releases are made from main (current branch: $branch)."
    info "Fetching origin/main and tags"
    git fetch -q origin main --tags
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
        || fail "main is not equal to origin/main. Run: git pull origin main --ff-only"
    ok "main is up to date with origin/main"
    gh auth status >/dev/null 2>&1 || fail "gh is not signed in. Run: gh auth login"
    ok "gh is signed in"
else
    warn "--no-release: building the zip only, no tag or GitHub release"
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
ok "Version ${bold}$version${reset}${green}, tag $tag, commit $(git rev-parse --short HEAD)"

if $create_release; then
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        fail "Tag $tag already exists. Raise MARKETING_VERSION in Config/Shared.xcconfig first."
    fi
    if gh release view "$tag" >/dev/null 2>&1; then
        fail "A GitHub release $tag already exists."
    fi
    ok "Tag and release $tag are still free"
fi

step "Archiving $scheme"
info "This takes a few minutes; only warnings and errors are shown."
rm -rf "$out"
mkdir -p "$out"
xcodebuild -project "$project" -scheme "$scheme" -configuration "$configuration" \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -allowProvisioningUpdates -quiet archive
ok "Archived to $archive"

step "Exporting with Developer ID and submitting for notarization"
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist Config/ExportOptions-DeveloperID.plist \
    -exportPath "$export_dir" -allowProvisioningUpdates -quiet
ok "Signed with Developer ID and uploaded to Apple's notary service"

step "Waiting for notarization"
info "Checking every $poll_interval s, at most $((poll_interval * poll_attempts / 60)) minutes"
attempt=1
log="$out/export-notarized.log"
until xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$notarized_dir" >"$log" 2>&1; do
    if [ "$attempt" -ge "$poll_attempts" ]; then
        cat "$log" >&2
        fail "The notarized app is not available yet. Check the status in Xcode (Window > Organizer), then run: xcodebuild -exportNotarizedApp -archivePath $archive -exportPath $notarized_dir"
    fi
    info "Not notarized yet (check $attempt of $poll_attempts, $(elapsed) elapsed)"
    attempt=$((attempt + 1))
    sleep "$poll_interval"
done
app="$notarized_dir/$app_name"
[ -d "$app" ] || fail "$app was not exported (see $log)."
ok "Notarized app exported to $app"

step "Verifying signature, notarization ticket and Gatekeeper"
codesign --verify --deep --strict "$app"
ok "Code signature is valid"
xcrun stapler validate -q "$app"
ok "Notarization ticket is stapled"
assessment=$(spctl --assess --type execute --verbose "$app" 2>&1)
info "$assessment"
ok "Gatekeeper accepts the app"

step "Zipping"
ditto -c -k --keepParent "$app" "$zip"
checksum=$(shasum -a 256 "$zip" | awk '{ print $1 }')
ok "$zip"
info "SHA-256: $checksum"

if ! $create_release; then
    printf '\n%s%s✓ Done in %s.%s No release created (--no-release).\n' "$bold" "$green" "$(elapsed)" "$reset"
    exit 0
fi

step "Creating the GitHub release $tag"
draft_flag="--draft"
$publish && draft_flag=""
# shellcheck disable=SC2086 # draft_flag is empty or one word on purpose.
release_url=$(gh release create "$tag" "$zip" $draft_flag --target "$commit" --title "SlidePilot $version" \
    --generate-notes --notes "Free download for macOS 26. SHA-256 of the zip: $checksum")
ok "$release_url"

if $publish; then
    printf '\n%s%s✓ Published %s in %s.%s\n' "$bold" "$green" "$tag" "$(elapsed)" "$reset"
else
    printf '\n%s%s✓ Created the draft release %s in %s.%s\n' "$bold" "$green" "$tag" "$(elapsed)" "$reset"
    info "Review the notes on GitHub and publish the release there."
fi
