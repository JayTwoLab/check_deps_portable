#!/usr/bin/env bash
# usage: ./*.sh <binary or shared-object>
# Description:
#   Cross-distro dependency scanner:
#     1) Use ldd to list shared libs
#     2) Map each .so file to owning package (installed DB first; then repo search if available)
#     3) Suggest build packages (-dev/-devel) heuristically by distro family

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <binary or shared-object>"
  exit 1
fi

BIN="$1"

if ! command -v ldd >/dev/null; then
  echo "ldd not found. Please install your libc tools (e.g., glibc / libc-bin) first."
  exit 1
fi

# ---- Detect distro family ----------------------------------------------------
DISTRO_ID=""
DISTRO_LIKE=""
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-}"
  DISTRO_LIKE="${ID_LIKE:-}"
fi

is_like() {
  local needle="$1"
  [[ "$DISTRO_ID" == "$needle" ]] && return 0
  [[ "$DISTRO_LIKE" == *"$needle"* ]] && return 0
  return 1
}

family="unknown"
if is_like "debian" || [[ "$DISTRO_ID" == "ubuntu" ]]; then
  family="debian"
elif is_like "rhel" || is_like "fedora" || is_like "centos" || [[ "$DISTRO_ID" =~ ^(rhel|centos|fedora|almalinux|rocky|amzn|ol)$ ]]; then
  family="rhel"
elif is_like "suse" || [[ "$DISTRO_ID" =~ ^(opensuse|sles|sled)$ ]]; then
  family="suse"
elif [[ "$DISTRO_ID" =~ ^(arch|manjaro)$ ]] || is_like "arch"; then
  family="arch"
elif [[ "$DISTRO_ID" == "alpine" ]]; then
  family="alpine"
elif [[ "$DISTRO_ID" == "gentoo" ]]; then
  family="gentoo"
elif [[ "$DISTRO_ID" == "void" ]]; then
  family="void"
fi

echo ">>> Detected distro family: $family"
echo ">>> Scanning dependencies of: $BIN"
echo

declare -A RUNTIME_PKG
declare -A DEV_PKG_CAND

# ---- Dev package heuristics --------------------------------------------------
guess_dev_pkg_debian() {
  local pkg="$1"
  case "$pkg" in
    libc6:amd64|libc6) echo "libc6-dev" ;;
    libgcc-s1*|gcc-*) echo "gcc" ;;
    libstdc++6*|g++-*) echo "g++" ;;
    libm6*) echo "libc6-dev" ;;
    *)
      if [[ "$pkg" =~ ^lib([a-z0-9.+-]+)[0-9]*(:amd64)?$ ]]; then
        echo "lib${BASH_REMATCH[1]}-dev"
      fi
      ;;
  esac
}

guess_dev_pkg_rpm() {
  local pkg="$1"
  case "$pkg" in
    glibc*) echo "glibc-devel" ;;
    libgcc*) echo "gcc" ;;
    libstdc++*) echo "gcc-c++" ;;
    *)
      if [[ "$pkg" =~ ^(lib)?([a-z0-9.+-]+)$ ]]; then
        local base="${BASH_REMATCH[0]}"
        echo "${base}-devel"
      fi
      ;;
  esac
}

guess_dev_pkg_suse() { guess_dev_pkg_rpm "$1"; }
guess_dev_pkg_arch() {
  local pkg="$1"
  case "$pkg" in
    glibc) echo "glibc" ;;
    gcc-libs) echo "base-devel" ;;
    libstdc++*) echo "gcc" ;;
    *) echo "" ;;
  esac
}
guess_dev_pkg_alpine() {
  local pkg="$1"
  case "$pkg" in
    musl) echo "musl-dev" ;;
    libstdc++) echo "g++" ;;
    gcc*) echo "gcc" ;;
    *)
      if [[ "$pkg" =~ ^lib([a-z0-9.+-]+)$ ]]; then
        echo "lib${BASH_REMATCH[1]}-dev"
      fi
      ;;
  esac
}
guess_dev_pkg_gentoo() { echo ""; }
guess_dev_pkg_void() {
  local pkg="$1"
  case "$pkg" in
    glibc) echo "glibc-devel" ;;
    gcc-libs) echo "base-devel" ;;
    libstdc++*) echo "gcc" ;;
    *) echo "" ;;
  esac
}

guess_dev_pkg() {
  case "$family" in
    debian) guess_dev_pkg_debian "$1" ;;
    rhel)   guess_dev_pkg_rpm "$1" ;;
    suse)   guess_dev_pkg_suse "$1" ;;
    arch)   guess_dev_pkg_arch "$1" ;;
    alpine) guess_dev_pkg_alpine "$1" ;;
    gentoo) guess_dev_pkg_gentoo "$1" ;;
    void)   guess_dev_pkg_void "$1" ;;
    *)      echo "" ;;
  esac
}

# ---- Helpers per family ------------------------------------------------------
owner_via_repo_search() {
  local base="$1"
  case "$family" in
    debian)
      if command -v apt-file >/dev/null; then
        apt-file search -x "/$base$" 2>/dev/null | head -n3 || true
      fi
      ;;
    rhel|suse)
      local provides_cmd=""
      if command -v dnf >/dev/null; then
        provides_cmd="dnf -q provides"
      elif command -v yum >/dev/null; then
        provides_cmd="yum -q provides"
      elif command -v repoquery >/dev/null; then
        provides_cmd="repoquery --whatprovides"
      fi
      if [[ -n "$provides_cmd" ]]; then
        $provides_cmd "*/$base" 2>/dev/null | head -n3 || true
      fi
      ;;
    arch)
      if command -v pacman >/dev/null; then
        pacman -Fq "$base" 2>/dev/null | head -n3 || true
      fi
      ;;
    alpine)
      if command -v apk >/dev/null; then
        apk search -x "$base" 2>/dev/null | head -n3 || true
      fi
      ;;
    gentoo)
      if command -v equery >/dev/null; then
        true
      fi
      ;;
    void)
      if command -v xbps-query >/dev/null; then
        xbps-query -Rs "$base" 2>/dev/null | head -n3 || true
      fi
      ;;
  esac
}

owner_for_path() {
  local path="$1"
  case "$family" in
    debian) dpkg -S "$path" 2>/dev/null | head -n1 | cut -d: -f1 || true ;;
    rhel|suse) rpm -qf "$path" 2>/dev/null || true ;;
    arch) pacman -Qo "$path" 2>/dev/null | awk '{print $5}' || true ;;
    alpine) apk info -W "$path" 2>/dev/null | awk -F' ' '{print $1}' | sed 's/-[0-9].*$//' | head -n1 || true ;;
    gentoo) equery b "$path" 2>/dev/null | head -n1 | awk '{print $1}' || true ;;
    void) xbps-query -o "$path" 2>/dev/null | awk '{print $3}' || true ;;
    *) echo "" ;;
  esac
}

ensure_repo_search_hint() {
  case "$family" in
    debian)
      if ! command -v apt-file >/dev/null; then
        echo "hint: apt-file is missing. Install with: sudo apt update && sudo apt install -y apt-file && sudo apt-file update"
      fi
      ;;
    arch)
      echo "hint: for 'pacman -F', run once: sudo pacman -Fy"
      ;;
    gentoo)
      echo "hint: for 'equery', install gentoolkit: sudo emerge --ask app-portage/gentoolkit"
      ;;
  esac
}

mapfile -t LIBS < <(ldd "$BIN" | awk '{print $3}' | grep -E '^/')

for so in "${LIBS[@]}"; do
  real="$(readlink -f "$so" || true)"
  [[ -z "$real" ]] && real="$so"

  pkg="$(owner_for_path "$real")"
  base="$(basename "$real")"

  if [[ -n "$pkg" ]]; then
    echo "$real => $pkg (installed DB)"
    RUNTIME_PKG["$pkg"]=1
  else
    echo -n "$real => "
    cand="$(owner_via_repo_search "$base")"
    if [[ -n "$cand" ]]; then
      echo
      echo "$cand" | sed 's/^/    cand: /'
      first_pkg="$(echo "$cand" | head -n1 | sed 's/[:, ].*$//' )"
      [[ -n "$first_pkg" ]] && RUNTIME_PKG["$first_pkg"]=1
    else
      echo "(no owner; maybe custom/copy)"
    fi
  fi
done

echo
echo ">>> Runtime packages (unique):"
for p in "${!RUNTIME_PKG[@]}"; do
  echo "  - $p"
done

echo
echo ">>> Suggested *build* packages (heuristic):"
for p in "${!RUNTIME_PKG[@]}"; do
  dev="$(guess_dev_pkg "$p")"
  [[ -n "$dev" ]] && DEV_PKG_CAND["$dev"]=1
done
for d in "${!DEV_PKG_CAND[@]}"; do
  echo "  - $d"
done

echo
ensure_repo_search_hint
