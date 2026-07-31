#!/usr/bin/env bash
set -euo pipefail

version="v26.7.11"
archive="libxray-apple-cgo.zip"
url="https://github.com/XTLS/libXray/releases/download/${version}/${archive}"
vendor_dir="Vendor"
framework="${vendor_dir}/LibXray.xcframework"

if [[ -d "${framework}" ]]; then
  echo "LibXray ${version} 已存在"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "下载 LibXray ${version}..."
curl --fail --location --retry 3 --output "${tmp_dir}/${archive}" "${url}"

mkdir -p "${vendor_dir}"
unzip -q "${tmp_dir}/${archive}" -d "${tmp_dir}/unpacked"
source_framework="${tmp_dir}/unpacked/libxray-apple-cgo/LibXray.xcframework"

if [[ ! -f "${source_framework}/Info.plist" ]]; then
  echo "下载包中未找到 LibXray.xcframework" >&2
  exit 1
fi

mv "${source_framework}" "${framework}"
echo "已安装 ${framework}"
