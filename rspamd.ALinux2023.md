# rspamd for Amazon Linux 2023

## Objective
Amazon Linux 2023 does not package rspamd — not in its own base repositories, and not in SPAL (Supplementary Packages for Amazon Linux, AL2023's EPEL9-derived extra repo). This repo rebuilds rspamd for AL2023, `x86_64` and `aarch64`, from the project's own published RHEL/EL9 source.

## Reference pattern
Follow the structure of [dovecot.2.4.ALinux2023](https://github.com/YasharF/dovecot.2.4.ALinux2023), an existing repo doing the same thing for a different package:
- `README.md` — why the repo exists, install instructions, how the automation works, and a section documenting exactly what had to change from the upstream spec to build cleanly on AL2023 and why.
- `build/` — a `build.sh` that runs inside an `amazonlinux:2023` container (e.g. `docker run --rm -v "$PWD:/w" -w /w public.ecr.aws/amazonlinux/amazonlinux:2023 ./build/build.sh <version> <release>`) and produces RPMs under `out/RPMS`. Any spec patches or stub packages needed live alongside it.
- `verify/` — installs the built RPMs on a clean AL2023 host/container and runs functional checks against the running service, not just an install-succeeded check.
- GitHub Actions, chained end-to-end: a job that watches for a new upstream release not yet published here, a job that rebuilds it for both architectures, a job that runs the verify harness against the build output, and a job that publishes the RPMs as a `dnf` repository (e.g. via GitHub Pages).
- Every published build stays published — `dnf list --showduplicates` should show the full history, with any specific version installable by name.
- License: MIT (or whatever the maintainer prefers) covering only this repo's own content — build scripts, spec patches, verify harness, workflows. It does not cover rspamd itself: no rspamd source is vendored, and the RPMs this repo builds and publishes are rspamd's own unmodified software (aside from whatever AL2023-specific spec changes prove necessary), carrying rspamd's own license inside each package as built by its spec.

## Source material
rspamd publishes its own RPM repository directly, including CentOS/RHEL 9 packages, at `https://rspamd.com/rpm-stable/centos-9/`. That's the vendor's own build for the same OS family AL2023 is derived from, and is the natural rebuild input. Confirm exactly what that repo publishes (binary RPMs only, vs. an actual source RPM) before assuming there's an SRPM to rebuild from — if there isn't one, the rebuild input is their spec plus the upstream source tarball instead.

## What to expect
No attempt has been made yet to actually build rspamd on AL2023 — this is a starting brief, not a known-working recipe. Expect to find and document real AL2023-specific incompatibilities during the build, the way the dovecot repo did (see its README's "Changes to RHEL Spec" section for the kind of thing that turns up: a `BuildRequires` on a `-devel` package AL2023 ships under a different name, an optional dependency AL2023's version of some library can't support, and so on). Document whatever's actually found and why it was necessary — don't guess at likely issues ahead of time.

## Architecture
Both `x86_64` and `aarch64`.

## Milter mode
rspamd has a worker (`rspamd_proxy`) that speaks the milter protocol natively, for deployments that want to run it as a Postfix milter. No separate glue package is needed for that — worth keeping in mind if this package is meant to sit alongside a SpamAssassin build, which needs a second, separate package (`spamass-milter`) for the same purpose.
