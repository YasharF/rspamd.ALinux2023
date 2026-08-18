#!/bin/bash
# Rebuild rspamd for Amazon Linux 2023.
#
#   build/build.sh 4.1.5 1
#
# Run on AL2023 as root (a container is fine). RPMs land in ./out/RPMS.
#
# rspamd.com's centos-9 repo publishes binary RPMs only, no SRPMs, so the
# rebuild input is the project's own rpm/rspamd.spec plus its GitHub release
# tarball, both pinned to the requested version's git tag.

set -eux -o pipefail

V=${1:?usage: build.sh <rspamd-version> <release>}
R=${2:?usage: build.sh <rspamd-version> <release>}
DEST=$PWD/out/RPMS
# Not $PWD: in CI that's a bind mount of the runner's workspace, and the
# from-source deps below (vectorscan, fasttext, luajit, ragel) install into
# absolute paths outside it anyway. Building on the container's own
# filesystem keeps everything in one place.
WORK=${RSPAMD_BUILD_WORK:-/var/tmp/rspamd-build}
TOP=$WORK/rpmbuild

# No curl here: AL2023 ships curl-minimal, and asking for curl conflicts with it.
dnf -y install rpm-build 'dnf-command(builddep)' \
    gcc gcc-c++ cmake make git patch findutils tar gzip which diffutils \
    systemd-rpm-macros boost-devel python3-devel

rm -rf "$WORK"
mkdir -p "$TOP"/SPECS "$TOP"/SOURCES "$TOP"/BUILD "$TOP"/RPMS "$TOP"/SRPMS "$TOP"/BUILDROOT

# AL2023 carries no ragel package at all (it's a build-only tool rspamd -- and
# vectorscan, below -- use to generate tokenizer/parser code, not a library
# dependency). The vendor's own build container doesn't rely on its host
# distro for this either -- it builds ragel 6.10 from source the same way, on
# every platform. Built first: vectorscan's own CMake configure step requires
# it on PATH.
rm -rf /ragel-6.10 /ragel-6.10.tar.gz
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
    -o /ragel-6.10.tar.gz https://www.colm.net/files/ragel/ragel-6.10.tar.gz
tar xf /ragel-6.10.tar.gz -C /
(cd /ragel-6.10 && ./configure --prefix=/usr && make -j"$(nproc)" && make install)
rm -rf /ragel-6.10 /ragel-6.10.tar.gz

# AL2023 ships hyperscan-devel for neither architecture (see README). The
# vendor's own EL9 build container already builds vectorscan -- a drop-in,
# actively-maintained hyperscan fork -- from source for aarch64, since real
# hyperscan-devel is x86_64-only even on RHEL. AL2023 gets the same treatment
# on both architectures.
rm -rf /vectorscan-src
git clone --depth 1 --branch vectorscan/5.4.12 \
    https://github.com/VectorCamp/vectorscan /vectorscan-src
cmake -S /vectorscan-src -B /vectorscan-src/build \
    -DCMAKE_INSTALL_PREFIX=/vectorscan -DCMAKE_BUILD_TYPE=Release \
    -DFAT_RUNTIME=ON -DCMAKE_C_FLAGS='-fpic -fPIC' -DCMAKE_CXX_FLAGS='-fPIC -fpic' \
    -DPCRE_SUPPORT_LIBBZ2=OFF
make -C /vectorscan-src/build -j"$(nproc)"
make -C /vectorscan-src/build install
rm -rf /vectorscan-src

# fastText is rspamd's own fork and isn't packaged anywhere; the vendor
# builds it from source unconditionally, on every platform including its own
# EL9 build container. Same here.
rm -rf /fasttext-src
git clone --depth 1 https://github.com/rspamd/fastText.git /fasttext-src
cmake -S /fasttext-src -B /fasttext-src/build \
    -DCMAKE_INSTALL_PREFIX=/fasttext -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS='-fpic -fPIC' -DCMAKE_CXX_FLAGS='-fPIC -fpic'
make -C /fasttext-src/build -j"$(nproc)"
make -C /fasttext-src/build install
mv -f /fasttext/lib/libfasttext_pic.a /fasttext/lib/libfasttext.a
rm -f /fasttext/lib/*.so
rm -rf /fasttext-src

# LuaJIT, matching the vendor's own official rspamd.com builds (LUAJIT=1),
# built from source rather than linked against AL2023's system Lua.
rm -rf /luajit-src /luajit-build
git clone -b v2.1 https://luajit.org/git/luajit-2.0.git /luajit-src
(cd /luajit-src && make clean && \
    make -j"$(nproc)" CC='gcc -fPIC' PREFIX=/luajit-build && \
    make install PREFIX=/luajit-build)
rm -f /luajit-build/lib/*.so
rm -rf /luajit-src

curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
    -o "$TOP/SOURCES/rspamd-$V.tar.gz" \
    "https://github.com/rspamd/rspamd/archive/$V/rspamd-$V.tar.gz"
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
    -o "$TOP/SOURCES/rspamd.logrotate" \
    "https://raw.githubusercontent.com/rspamd/rspamd/$V/rpm/rspamd.logrotate"
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
    -o "$TOP/SOURCES/80-rspamd.preset" \
    "https://raw.githubusercontent.com/rspamd/rspamd/$V/rpm/80-rspamd.preset"
curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
    -o "$TOP/SPECS/rspamd.spec" \
    "https://raw.githubusercontent.com/rspamd/rspamd/$V/rpm/rspamd.spec"

# The spec hardcodes a placeholder Version/Release; set them to what we're
# actually building.
sed -i -e "s/^Version:.*/Version:          $V/" \
       -e "s/^Release:.*/Release:          $R%{?dist}/" \
       "$TOP/SPECS/rspamd.spec"

# Two changes needed for AL2023:
#
# - `BuildRequires: hyperscan-devel` (x86_64 only) is gated on
#   `%{?el8} || %{?fedora} > 10`. AL2023's rpm macros set %fedora to 34 (it's
#   packaged from Fedora sources), which trips this branch as though it were
#   real Fedora with a hyperscan-devel package -- AL2023 has none, on either
#   architecture. Dropped; vectorscan (built above) replaces it.
# - `BuildRequires: ragel` has no AL2023 package at all (see above). Dropped;
#   built from source above instead.
sed -i -e '/^BuildRequires:    hyperscan-devel$/d' \
       -e '/^BuildRequires:    ragel$/d' \
       "$TOP/SPECS/rspamd.spec"
grep -q '^BuildRequires:    hyperscan-devel$' "$TOP/SPECS/rspamd.spec" && exit 1
grep -q '^BuildRequires:    ragel$' "$TOP/SPECS/rspamd.spec" && exit 1

# The CMake invocation only points x86_64 at a custom HYPERSCAN_ROOT_DIR when
# %el7 or %el10 is set (elsewhere it expects a system hyperscan-devel to be
# found automatically). AL2023 is neither, so make that branch unconditional:
# vectorscan lives at /vectorscan on both architectures here.
sed -i 's/^%if 0%{?el7} || 0%{?el10}$/%if 1/' "$TOP/SPECS/rspamd.spec"
grep -q '^%if 1$' "$TOP/SPECS/rspamd.spec"

export LUAJIT=1
dnf -y builddep "$TOP/SPECS/rspamd.spec"
rpmbuild -bb --define "_topdir $TOP" "$TOP/SPECS/rspamd.spec"

mkdir -p "$DEST"
find "$TOP/RPMS" -name '*.rpm' -exec mv -t "$DEST" {} +
ls -1 "$DEST"
