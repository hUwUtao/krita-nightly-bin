#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <krita_commit_hash>" >&2
  exit 1
fi

target_commit="$1"
builder_user="${BUILDER_USER:-builder}"
artifact_dir="${ARTIFACT_DIR:-/tmp/krita-artifacts}"

pacman -Syu --noconfirm --needed base-devel git sudo curl jq

if ! id -u "${builder_user}" >/dev/null 2>&1; then
  useradd -m -G wheel "${builder_user}"
fi

echo "${builder_user} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/10-${builder_user}"
chmod 440 "/etc/sudoers.d/10-${builder_user}"

sudo -u "${builder_user}" bash -lc '
set -euo pipefail
if ! command -v yay >/dev/null 2>&1; then
  rm -rf "$HOME/yay-bin"
  git clone https://aur.archlinux.org/yay-bin.git "$HOME/yay-bin"
  cd "$HOME/yay-bin"
  makepkg -si --noconfirm --needed
fi
'

sudo -u "${builder_user}" bash -lc "
set -euo pipefail
rm -rf \"\$HOME/krita-git\"
git clone https://aur.archlinux.org/krita-git.git \"\$HOME/krita-git\"
cd \"\$HOME/krita-git\"

sed -Ei 's/^pkgname=.*/pkgname=krita-nightly-bin/' PKGBUILD
sed -Ei 's/^pkgdesc=.*/pkgdesc='\''A nightly-built Krita package forked from krita-git.'\''/' PKGBUILD
sed -Ei 's|^conflicts=.*|conflicts=(\"krita\" \"krita-git\" \"krita-qt6-git\")|' PKGBUILD
sed -Ei \"s|^source=\\(\\\"git\\+https://invent.kde.org/graphics/krita.git\\\"\\)|source=(\\\"git+https://invent.kde.org/graphics/krita.git#commit=${target_commit}\\\")|\" PKGBUILD

makepkg --printsrcinfo > .SRCINFO

mapfile -t all_deps < <(
  awk -F \" = \" '/^(depends|makedepends) = / { print \$2 }' .SRCINFO |
  sed -E 's/[<>=].*$//' |
  sed '/^$/d' |
  sort -u
)

aur_deps=()
for dep in \"\${all_deps[@]}\"; do
  if pacman -Si \"\$dep\" >/dev/null 2>&1; then
    continue
  fi
  aur_deps+=(\"\$dep\")
done

if [[ \${#aur_deps[@]} -gt 0 ]]; then
  yay -S --noconfirm --needed --asdeps \"\${aur_deps[@]}\"
fi

makepkg -s --noconfirm --needed --cleanbuild
"

rm -rf "${artifact_dir}"
mkdir -p "${artifact_dir}"
cp /home/"${builder_user}"/krita-git/*.pkg.tar.zst* "${artifact_dir}/"

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
