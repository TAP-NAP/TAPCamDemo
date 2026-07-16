#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
metadata_file="$package_dir/ZSTD_SOURCE.json"

version=$(/usr/bin/plutil -extract version raw -o - "$metadata_file")
archive_url=$(/usr/bin/plutil -extract sourceArchive raw -o - "$metadata_file")
expected_sha=$(/usr/bin/plutil -extract sourceArchiveSHA256 raw -o - "$metadata_file")
expected_module_map_sha=$(/usr/bin/plutil -extract localModuleMapSHA256 raw -o - "$metadata_file")

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/czstd-verify.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

if [ "$#" -gt 1 ]; then
    echo "usage: $0 [zstd-source-archive.tar.gz]" >&2
    exit 64
fi

if [ "$#" -eq 1 ]; then
    archive_path=$1
else
    archive_path="$temporary_root/zstd-$version.tar.gz"
    /usr/bin/curl --fail --location --silent --show-error \
        "$archive_url" --output "$archive_path"
fi

actual_sha=$(/usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{print $1}')
if [ "$actual_sha" != "$expected_sha" ]; then
    echo "CZstd archive SHA-256 mismatch" >&2
    echo "expected: $expected_sha" >&2
    echo "actual:   $actual_sha" >&2
    exit 1
fi

/usr/bin/tar -xzf "$archive_path" -C "$temporary_root"
upstream_lib="$temporary_root/zstd-$version/lib"
vendored_lib="$package_dir/Vendor/zstd/lib"

if [ ! -d "$upstream_lib" ] || [ ! -d "$vendored_lib" ]; then
    echo "CZstd source tree is missing" >&2
    exit 1
fi

for source_directory in common compress decompress; do
    if ! /usr/bin/diff -qr \
        "$upstream_lib/$source_directory" \
        "$vendored_lib/$source_directory"; then
        echo "CZstd vendored $source_directory source differs from upstream" >&2
        exit 1
    fi
done

for public_header in zdict.h zstd.h zstd_errors.h; do
    if ! /usr/bin/cmp -s \
        "$upstream_lib/$public_header" \
        "$vendored_lib/$public_header"; then
        echo "CZstd vendored $public_header differs from upstream" >&2
        exit 1
    fi
done

unexpected_entries=$(/usr/bin/find "$vendored_lib" -mindepth 1 -maxdepth 1 \
    ! -name common \
    ! -name compress \
    ! -name decompress \
    ! -name zdict.h \
    ! -name zstd.h \
    ! -name zstd_errors.h \
    ! -name module.modulemap \
    -print)
if [ -n "$unexpected_entries" ]; then
    echo "CZstd vendored tree has unexpected top-level entries:" >&2
    echo "$unexpected_entries" >&2
    exit 1
fi

actual_module_map_sha=$(/usr/bin/shasum -a 256 \
    "$vendored_lib/module.modulemap" | /usr/bin/awk '{print $1}')
if [ "$actual_module_map_sha" != "$expected_module_map_sha" ]; then
    echo "CZstd local module map SHA-256 mismatch" >&2
    echo "expected: $expected_module_map_sha" >&2
    echo "actual:   $actual_module_map_sha" >&2
    exit 1
fi

echo "CZstd zstd $version source subset verified ($actual_sha)"
echo "CZstd local module map verified ($actual_module_map_sha)"
