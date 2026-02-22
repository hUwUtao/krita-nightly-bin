#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <krita_commit_hash>" >&2
  exit 1
fi

target_commit="$1"
builder_user="${BUILDER_USER:-builder}"
artifact_dir="${ARTIFACT_DIR:-/tmp/krita-artifacts}"

pacman -Syu --noconfirm --needed base-devel git sudo curl jq clang lld llvm

if ! id -u "${builder_user}" >/dev/null 2>&1; then
  useradd -m -G wheel "${builder_user}"
fi

builder_home="$(getent passwd "${builder_user}" | cut -d: -f6)"
if [[ -z "${builder_home}" ]]; then
  builder_home="/home/${builder_user}"
fi

# Cache restore may create these paths as root before the user exists.
mkdir -p "${builder_home}"
chown "${builder_user}:${builder_user}" "${builder_home}"
for cache_path in "${builder_home}/.cache" "${builder_home}/.config" "${builder_home}/yay-bin"; do
  if [[ -e "${cache_path}" ]]; then
    chown -R "${builder_user}:${builder_user}" "${cache_path}"
  fi
done

echo "${builder_user} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/10-${builder_user}"
chmod 440 "/etc/sudoers.d/10-${builder_user}"

sudo -u "${builder_user}" bash -lc "
set -euo pipefail
rm -rf \"\$HOME/krita-git\"
git clone https://aur.archlinux.org/krita-git.git \"\$HOME/krita-git\"
cd \"\$HOME/krita-git\"

sed -Ei 's/^pkgname=.*/pkgname=krita-nightly-bin/' PKGBUILD
sed -Ei 's/^pkgdesc=.*/pkgdesc='\''A nightly-built Krita package forked from krita-git.'\''/' PKGBUILD
sed -Ei 's|^conflicts=.*|conflicts=(\"krita\" \"krita-git\" \"krita-qt6-git\")|' PKGBUILD
sed -Ei \"s|^source=\\(\\\"git\\+https://invent.kde.org/graphics/krita.git\\\"\\)|source=(\\\"git+https://invent.kde.org/graphics/krita.git#commit=${target_commit}\\\")|\" PKGBUILD
sed -Ei 's/\\<kseexpr-qt6-git\\>/kseexpr/g' PKGBUILD

makepkg --printsrcinfo > .SRCINFO

mapfile -t all_deps < <(
  awk -F \" = \" '/^[[:space:]]*(depends|makedepends)(_[^ ]+)? = / { print \$2 }' .SRCINFO |
  sed -E 's/[<>=].*$//' |
  sed '/^$/d' |
  sort -u
)

repo_deps=()
aur_deps=()
for dep in \"\${all_deps[@]}\"; do
  if pacman -Si \"\$dep\" >/dev/null 2>&1; then
    repo_deps+=(\"\$dep\")
    continue
  fi
  aur_deps+=(\"\$dep\")
done

if [[ \${#repo_deps[@]} -gt 0 ]]; then
  echo \"Installing repo deps (\${#repo_deps[@]}): \${repo_deps[*]}\"
  sudo pacman -S --noconfirm --needed --asdeps \"\${repo_deps[@]}\"
fi

if [[ \${#aur_deps[@]} -gt 0 ]]; then
  echo \"Installing AUR deps (\${#aur_deps[@]}): \${aur_deps[*]}\"
  if ! command -v yay >/dev/null 2>&1; then
    rm -rf \"\$HOME/yay-bin\"
    git clone https://aur.archlinux.org/yay-bin.git \"\$HOME/yay-bin\"
    cd \"\$HOME/yay-bin\"
    makepkg -si --noconfirm --needed
    cd \"\$HOME/krita-git\"
  fi
  yay -S --noconfirm --needed --asdeps \"\${aur_deps[@]}\"
fi

cat > \"\$HOME/.makepkg-llvm-lto.conf\" <<'EOF'
source /etc/makepkg.conf

# Force LLVM toolchain and full LTO for the target package build.
CC=clang
CXX=clang++
AR=llvm-ar
NM=llvm-nm
RANLIB=llvm-ranlib
LD=ld.lld
CFLAGS=\"\${CFLAGS} -fuse-ld=lld -flto=full\"
CXXFLAGS=\"\${CXXFLAGS} -fuse-ld=lld -flto=full\"
LDFLAGS=\"\${LDFLAGS} -fuse-ld=lld -flto=full\"
RUSTFLAGS=\"\${RUSTFLAGS} -C linker=clang -C link-arg=-fuse-ld=lld -C lto=fat -C codegen-units=1\"
options=(\${options[@]/!lto/})
options+=(lto)
EOF

makepkg --config \"\$HOME/.makepkg-llvm-lto.conf\" --noconfirm --needed --cleanbuild
"

rm -rf "${artifact_dir}"
mkdir -p "${artifact_dir}"
cp "${builder_home}"/krita-git/*.pkg.tar.zst* "${artifact_dir}/"

mapfile -t pkg_files < <(find "${artifact_dir}" -maxdepth 1 -type f -name 'krita-nightly-bin-*.pkg.tar.zst' -printf '%f\n' | sort)
if [[ "${#pkg_files[@]}" -eq 0 ]]; then
  echo "No package files were produced." >&2
  exit 1
fi

{
  echo "Built from Krita commit \`${target_commit}\`."
  echo
  echo "Packages:"
  for pkg in "${pkg_files[@]}"; do
    echo "- \`${pkg}\`"
  done
} > "${artifact_dir}/RELEASE_NOTES.md"
