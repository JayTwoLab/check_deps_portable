
# `check_deps_portable.sh`

[Korean](README.ko.md)

## Overview
`check_deps_portable.sh` is a cross‑distribution ELF dependency scanner. It:
1) runs `ldd` on a target binary or shared object,
2) maps each resolved `.so` path to its **owning package** (installed DB first; repo search as a fallback),
3) suggests **build/development packages** (`-dev` / `-devel` or equivalents) using distro‑specific heuristics.

This helps you quickly list runtime packages and find headers/devel packages you might need to compile against the same libraries on another machine.

## Supported distributions
The script auto‑detects the distro family via `/etc/os-release` and supports:

- **Debian/Ubuntu/Kali/Pop!_OS**: `dpkg -S`, `apt-file search`
- **RHEL/CentOS/Alma/Rocky/Amazon Linux/Fedora**: `rpm -qf`, `dnf|yum provides` (or `repoquery`)
- **openSUSE/SLES**: `rpm -qf`, `zypper what-provides`
- **Arch/Manjaro**: `pacman -Qo`, `pacman -F` (file database required)
- **Alpine**: `apk info -W`, `apk search -x`
- **Gentoo**: `equery b` (requires `gentoolkit`)
- **Void**: `xbps-query -o`, `xbps-query -Rs`

> If your distribution isn’t listed but is compatible with one of these families, the script will likely still work.

## Requirements
- POSIX shell + common CLI tools
- `ldd` (from your system libc tooling, e.g. `glibc`/`libc-bin`/`musl-utils`)
- For repository search (fallback when a file isn’t owned locally), install the family‑specific tools:
  - **Debian/Ubuntu**: `apt-file` (`sudo apt update && sudo apt install -y apt-file && sudo apt-file update`)
  - **RHEL/Fedora**: `dnf`/`yum` (or `repoquery`) with configured repos
  - **openSUSE**: `zypper`
  - **Arch**: `pacman -Fy` once to enable file database
  - **Alpine**: `apk` already included; repo indexes must be available
  - **Gentoo**: `app-portage/gentoolkit` for `equery`
  - **Void**: `xbps-query`

The script still works in “installed DB only” mode if repo search tools are missing; it just won’t suggest owners for files not installed from packages.

## Installation
```bash
chmod +x check_deps_portable.sh
```

## Usage
```bash
./check_deps_portable.sh /path/to/your/binary
```

### Example
```bash
./check_deps_portable.sh /usr/bin/curl
```

## Output
- A list of resolved `.so` files with their owning package (from local DB when possible).
- When a file is not owned locally, up to a few candidate providers from repos (“cand:” lines).
- A **Runtime packages** summary (unique)
- A **Suggested build packages** summary (heuristic; may include `-dev` / `-devel` packages or toolchain groups like `base-devel`)

## Heuristics for dev packages
Different families use different conventions:
- Debian/Ubuntu: `libfooN` → `libfoo-dev`
- RHEL/Fedora/SUSE: `libfoo` → `libfoo-devel`
- Alpine: often `libfoo` → `libfoo-dev`
- Arch/Void/Gentoo: dev headers may come from toolchain groups (`base-devel`) or from the main package; suggestions are best‑effort.

Treat the suggestions as hints; verify exact package names in your repos.

## Troubleshooting
- **No output from repo search**: ensure you’ve initialized the search index:
  - Debian/Ubuntu: `apt-file update`
  - Arch: `sudo pacman -Fy`
  - Gentoo: `sudo emerge --ask app-portage/gentoolkit`
- **Custom or bundled libraries**: the script will report “no owner; maybe custom/copy” when it can’t find a package.
- **Containers/minimal images**: you may need to install the package query tools first.

## Security notes
- The script reads `ldd` output. Avoid running it on **untrusted binaries** from unknown sources on production systems.
- Repository queries may disclose package names/versions to your configured mirrors (standard package manager behavior).

## License
- MIT

