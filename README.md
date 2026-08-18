# rspamd for Amazon Linux 2023

Amazon Linux 2023 does not package rspamd -- not in its own base repositories, and not in SPAL (Supplementary Packages for Amazon Linux, AL2023's EPEL9-derived extra repo). This repo rebuilds rspamd for AL2023, `x86_64` and `aarch64`, from the project's own published spec and source, for both architectures.

Temporary - use an official AWS or rspamd package when one exists.

## Install

```sh
curl -fsSLo /etc/yum.repos.d/rspamd-al2023.repo https://yasharf.github.io/rspamd.ALinux2023/rspamd-al2023.repo
dnf install rspamd
```

The packages are unsigned, so the repository sets `gpgcheck=0`.

New versions are likely to show up here within a day of an upstream rspamd release, via the GitHub Action workflow in this repo. `dnf upgrade` picks them up when they do.

Every published build stays published. `dnf list --showduplicates rspamd` shows what's available, and you can install a specific version by name, e.g. `dnf install rspamd-4.1.4-1.amzn2023`.

## Milter mode

rspamd's `rspamd_proxy` worker speaks the milter protocol natively -- no separate glue package is needed to run rspamd as a Postfix milter. It's enabled by default (`milter = yes;` in `worker-proxy.inc`) and listens on `127.0.0.1:11332` out of the box. Point Postfix's `smtpd_milters` at it and there's nothing else to install. (Contrast a SpamAssassin deployment doing the same job, which needs a second, separate package -- `spamass-milter` -- for this.)

## How it works

GitHub Actions handles the whole process, chained end-to-end:

- `watch.yml` checks daily for a new rspamd release not yet published here.
- `build.yml` rebuilds it for AL2023, `x86_64` and `aarch64`.
- `verify.yml` installs the RPMs in an AL2023 container and checks the running daemon: the controller API, a local-rule scan through the normal worker, and a milter-protocol handshake against `rspamd_proxy`.
- `publish.yml` publishes the RPMs as the `dnf` repository above.

### Build

[`build/build.sh`](build/build.sh) is the whole build, and runs in a docker container:

```sh
docker run --rm -v "$PWD:/w" -w /w public.ecr.aws/amazonlinux/amazonlinux:2023 ./build/build.sh 4.1.5 1
```

RPMs land in `out/RPMS`.

rspamd.com's `centos-9` repository (the vendor's own EL9 build, the same OS family AL2023 is derived from) publishes binary RPMs only -- no SRPMs. So the rebuild input here is rspamd's own [`rpm/rspamd.spec`](https://github.com/rspamd/rspamd/blob/master/rpm/rspamd.spec) plus its GitHub release tarball, both pinned to the version being built. The spec is patched only where AL2023 actually needs it (see below); it is not vendored, just downloaded fresh for each build.

### Verify

[`verify/run.sh`](verify/run.sh) installs the built RPMs on a clean AL2023 host and starts rspamd in the foreground for `verify.yml` to test.

Unlike a typical daemon, rspamd won't drop root privileges on its own: started as root with no `-u`/`-g`, it refuses outright (`cannot run rspamd workers as root user`). Its systemd unit works because systemd itself starts the process as `User=_rspamd`, never as root; outside systemd, `-u _rspamd -g _rspamd` gets the same result. `verify/run.sh` also sets `RSPAMD_LOG_TYPE=console` (matching the project's own `rspamd-docker` image) so the log goes to this container's stdout, where `docker logs` and `verify.yml`'s failure diagnostics can see it, instead of `/var/log/rspamd/rspamd.log`.

### Changes to RHEL Spec

rspamd's own EL9 build container (`rspamd/rspamd-build-docker`, `centos-9/Dockerfile`) already builds several of its dependencies from source rather than relying on the target distro for them -- ragel, LuaJIT, fastText, and (on aarch64) vectorscan, a hyperscan-compatible fork. This repo's `build/build.sh` does the same, on both architectures, matching that recipe. What's specific to AL2023 is smaller:

- **`hyperscan-devel`, x86_64** -- the spec's `BuildRequires: hyperscan-devel` (x86_64 only) is gated on `%{?el8} || %{?fedora} > 10`. AL2023's rpm macros set `%fedora` to `34` (its packages are built from Fedora sources), which trips that branch as though this were real Fedora with a `hyperscan-devel` package -- AL2023 has none, on either architecture. The `BuildRequires` line is dropped, and the CMake invocation's `-DHYPERSCAN_ROOT_DIR=/vectorscan` -- which the spec already applies unconditionally on aarch64, and on x86_64 only for `%el7`/`%el10` -- is made unconditional on x86_64 too, so it points at the same self-built vectorscan aarch64 already uses.
- **`ragel`** -- AL2023 has no `ragel` package at all. The `BuildRequires: ragel` line is dropped; `build.sh` builds ragel 6.10 from source first (before vectorscan, which also needs it at configure time), the same way rspamd's own build container does.
- **`libarchive-devel`** -- CMake requires it unconditionally (`ProcessPackage(LIBARCHIVE ...)`), but the spec's `BuildRequires` never lists it; the vendor's own build container gets it for free as a base-image package. `build.sh` installs it directly since AL2023 ships it (`libarchive-devel`) but nothing else on a plain AL2023 image pulls it in.
- **No `gcc-toolset-*`** -- the spec sources a RHEL Software Collections gcc-toolset (10/12/15, per EL8/9/10) that AL2023 doesn't have and doesn't need: none of the `%el*` conditions are true here, so the spec's own logic already falls through to whatever `gcc`/`g++` is on `PATH`. `build.sh` just installs AL2023's own `gcc-c++` (11.5, which builds rspamd's C++20 sources fine) directly, the same way it installs `cmake`, `git`, and the rest of the toolchain the spec assumes is already present.

## License

[LICENSE](LICENSE) covers this repository's own content -- the build script, verify harness, and workflows -- under the MIT license. It does not cover rspamd: no rspamd source is vendored here, and the RPMs this repo builds and publishes are rspamd's own unmodified software (aside from the spec changes above), carrying rspamd's own `LICENSE.md` (Apache-2.0) inside each package as built by its spec.
