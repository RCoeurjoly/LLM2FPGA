#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER_SRC="$ROOT/scripts/task6/task6_pcie_safe_root_helper.sh"
HELPER_DST="/usr/local/libexec/task6-pcie/task6-pcie-safe-root-helper"
SUDOERS_DST="/etc/sudoers.d/task6-pcie-safe-root-helper"
UDEV_INSTALLER="${TASK6_PCIE_UDEV_INSTALLER:-/home/roland/.local/bin/install-task6-pcie-rules.sh}"
SECRET_FILE="${TASK6_PCIE_TAPO_SECRET_FILE:-$HOME/.config/task6-pcie/tapo.env}"
INSTALL_USER="${SUDO_USER:-$USER}"
INSTALL_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
if [[ -n "${TASK6_PCIE_TAPO_SECRET_FILE:-}" ]]; then
  SECRET_FILE="$TASK6_PCIE_TAPO_SECRET_FILE"
elif [[ -n "$INSTALL_HOME" ]]; then
  SECRET_FILE="$INSTALL_HOME/.config/task6-pcie/tapo.env"
fi

usage() {
  cat >&2 <<'EOF'
usage: scripts/task6/task6_pcie_autonomous_setup.sh <install|doctor|uninstall>

One-time setup for hands-off Task 6 PCIe bring-up. The installed helper is
limited to udev reload/trigger and permission repair. It does not perform PCIe
root-port resets, bridge hot resets, Thunderbolt reauthorization, or endpoint
remove/rescan recovery.
EOF
  exit 2
}

[[ $# -eq 1 ]] || usage
MODE="$1"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This mode must be run as root. Use: sudo $0 $MODE" >&2
    exit 1
  fi
}

install_mode() {
  need_root
  [[ -x "$UDEV_INSTALLER" ]] || {
    echo "missing executable udev installer: $UDEV_INSTALLER" >&2
    exit 1
  }
  "$UDEV_INSTALLER"

  install -d -o root -g root -m 0755 /usr/local/libexec/task6-pcie
  install -o root -g root -m 0755 "$HELPER_SRC" "$HELPER_DST"

  cat >"$SUDOERS_DST.tmp" <<EOF
# Task 6 PCIe autonomous safe helper.
# This grants only the allowlisted helper; the helper itself refuses unsafe PCIe reset actions.
$INSTALL_USER ALL=(root) NOPASSWD: $HELPER_DST *
EOF
  chmod 0440 "$SUDOERS_DST.tmp"
  visudo -cf "$SUDOERS_DST.tmp" >/dev/null
  mv "$SUDOERS_DST.tmp" "$SUDOERS_DST"

  echo "Installed $HELPER_DST"
  echo "Installed $SUDOERS_DST"
  echo "Tapo secret file expected at: $SECRET_FILE"
}

doctor_mode() {
  sudo -n "$HELPER_DST" doctor
  if [[ -f "$SECRET_FILE" ]]; then
    mode="$(stat -c %a "$SECRET_FILE")"
    if [[ "$mode" != "600" ]]; then
      echo "warning: $SECRET_FILE mode is $mode; expected 600" >&2
      exit 1
    fi
    grep -q '^TAPO_USERNAME=' "$SECRET_FILE" || { echo "missing TAPO_USERNAME in $SECRET_FILE" >&2; exit 1; }
    grep -q '^TAPO_PASSWORD=' "$SECRET_FILE" || { echo "missing TAPO_PASSWORD in $SECRET_FILE" >&2; exit 1; }
    echo "Tapo secret file: ok"
  else
    echo "missing Tapo secret file: $SECRET_FILE" >&2
    exit 1
  fi
}

uninstall_mode() {
  need_root
  rm -f "$SUDOERS_DST"
  rm -f "$HELPER_DST"
  echo "Removed $SUDOERS_DST"
  echo "Removed $HELPER_DST"
}

case "$MODE" in
  install) install_mode ;;
  doctor) doctor_mode ;;
  uninstall) uninstall_mode ;;
  *) usage ;;
esac
