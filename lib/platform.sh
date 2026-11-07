# What machine is this? Sourced by lib/components.sh.
#
# Sets: OS_KIND      linux | macos | other
#       OS_NAME      "Ubuntu 24.04.5 LTS", "Arch Linux", "macOS 15.1" ...
#       PKG_MGR      apt | pacman | dnf | zypper | apk | brew | none
#       HAS_GNOME    1 when GNOME's shell and gsettings are here, else 0
#       DESKTOP_NAME "GNOME", "KDE", "macOS" ... (what to call it in messages)
#
# A component says what it needs in requires_of (lib/components.sh); the
# installer skips it, with the reason, when this machine can't give that.
# Adding a platform later = teach platform_detect about it, then widen the
# component's requires_of line (for example "apt" -> "apt|brew").

platform_detect() {
  local id="" id_like="" pretty=""
  case "$(uname -s)" in
    Linux)  OS_KIND=linux ;;
    Darwin) OS_KIND=macos ;;
    *)      OS_KIND=other ;;
  esac

  if [[ $OS_KIND == linux && -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    IFS='|' read -r id id_like pretty < <(. /etc/os-release; printf '%s|%s|%s\n' "${ID:-}" "${ID_LIKE:-}" "${PRETTY_NAME:-}")
  fi
  case "$OS_KIND" in
    macos) OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null)"; OS_NAME=${OS_NAME% } ;;
    linux) OS_NAME=${pretty:-Linux} ;;
    *)     OS_NAME=$(uname -s) ;;
  esac

  # The package manager that's actually here wins; the distro name is the tiebreak.
  PKG_MGR=none
  if   command -v apt-get >/dev/null && [[ " $id $id_like " == *" debian "* || " $id $id_like " == *" ubuntu "* ]]; then PKG_MGR=apt
  elif command -v pacman  >/dev/null; then PKG_MGR=pacman
  elif command -v dnf     >/dev/null; then PKG_MGR=dnf
  elif command -v zypper  >/dev/null; then PKG_MGR=zypper
  elif command -v apk     >/dev/null; then PKG_MGR=apk
  elif command -v brew    >/dev/null; then PKG_MGR=brew
  elif command -v apt-get >/dev/null; then PKG_MGR=apt
  fi

  HAS_GNOME=0
  [[ $OS_KIND == linux ]] && command -v gnome-shell >/dev/null && command -v gsettings >/dev/null && HAS_GNOME=1

  # Name shown in "needs GNOME (this is KDE)". The session's own name when set.
  if [[ $OS_KIND == macos ]]; then DESKTOP_NAME=macOS
  elif (( HAS_GNOME )); then DESKTOP_NAME=GNOME
  else
    DESKTOP_NAME=${XDG_CURRENT_DESKTOP:-}
    DESKTOP_NAME=${DESKTOP_NAME##*:}
    [[ -n $DESKTOP_NAME ]] || DESKTOP_NAME="no desktop"
  fi
}

# unmet_requirement <need>: prints why this machine can't give <need>; nothing when it can.
unmet_requirement() {
  case "$1" in
    linux) [[ $OS_KIND == linux ]] || echo "Linux only for now (this is $OS_NAME)" ;;
    gnome) (( HAS_GNOME )) || echo "needs GNOME (this is $DESKTOP_NAME)" ;;
    apt)   [[ $PKG_MGR == apt ]] || echo "needs apt, Debian/Ubuntu only for now (this has ${PKG_MGR/none/no package manager})" ;;
    *)     echo "unknown requirement '$1'" ;;
  esac
}

platform_detect
