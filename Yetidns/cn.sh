#!/usr/bin/env bash
# set-zh-cn.sh
# 自动将系统语言切换为 zh_CN.UTF-8（尽量兼容 Ubuntu/Debian/RHEL/Fedora/CentOS）
# 2025-11-04

set -euo pipefail
IFS=$'\n\t'

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "此脚本需要以 root 运行。请使用 sudo 或切换到 root 用户。"
    exit 1
  fi
}

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

enable_locale_debian() {
  local locale="zh_CN.UTF-8"
  info "配置 / 生成 locale: ${locale}（Debian/Ubuntu 流程）"

  # 确保 locales 包存在
  if ! dpkg -s locales >/dev/null 2>&1; then
    info "安装 locales"
    apt-get update -y
    apt-get install -y locales || true
  fi

  # 启用 locale 行
  if ! grep -q "^${locale}" /etc/locale.gen 2>/dev/null; then
    info "在 /etc/locale.gen 中启用 ${locale}"
    sed -i "/^# ${locale}/s/^# //g" /etc/locale.gen 2>/dev/null || echo "${locale} UTF-8" >> /etc/locale.gen
  fi

  info "运行 locale-gen"
  locale-gen "${locale}" || true

  info "使用 update-locale 持久化"
  if command -v update-locale >/dev/null 2>&1; then
    update-locale LANG="${locale}" LANGUAGE="zh_CN:zh"
  else
    cat > /etc/default/locale <<EOF
LANG=${locale}
LANGUAGE=zh_CN:zh
EOF
  fi

  # 尝试使用 localectl（如果存在）
  if command -v localectl >/dev/null 2>&1; then
    info "使用 localectl 应用系统级 locale"
    localectl set-locale LANG="${locale}"
  fi
}

enable_locale_rpm() {
  local locale="zh_CN.UTF-8"
  info "配置 / 生成 locale: ${locale}（RHEL/CentOS/Fedora 流程）"

  # 在 RPM 系列，安装语言包的不同版本
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y glibc-langpack-zh || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y glibc-common glibc-langpack-zh || true
  fi

  # 生成 locale（localedef）
  if command -v localedef >/dev/null 2>&1; then
    info "运行 localedef 生成 zh_CN.UTF-8（可能已存在）"
    localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true
  fi

  # 使用 localectl 持久化
  if command -v localectl >/dev/null 2>&1; then
    info "使用 localectl 设置系统语言"
    localectl set-locale LANG="${locale}"
  else
    warn "systemd/localectl 不存在，尝试写入 /etc/locale.conf"
    echo "LANG=${locale}" > /etc/locale.conf
  fi
}

install_fonts_and_packs_apt() {
  info "尝试安装中文语言包与字体（apt）"
  apt-get update -y
  # Ubuntu 上 language-pack-zh-hans 可用；在 Debian 上可能不存在，但 locales 足够
  apt-get install -y language-pack-zh-hans fonts-noto-cjk fonts-noto-cjk-extra || {
    info "部分包不可用，尝试安装备用字体 packages"
    apt-get install -y fonts-noto-cjk || true
  }
}

install_fonts_and_packs_dnf_yum() {
  info "尝试安装中文字体（dnf/yum）"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y google-noto-sans-cjk-ttc || dnf install -y noto-sans-cjk-ttc || true
  else
    yum install -y google-noto-sans-cjk-ttc || yum install -y noto-sans-cjk-ttc || true
  fi
}

install_fonts_pacman() {
  info "尝试安装中文字体（pacman）"
  pacman -Syu --noconfirm noto-fonts-cjk || true
}

write_profile() {
  local locale="zh_CN.UTF-8"
  info "写入 /etc/profile.d/locale-zh_CN.sh 以为登录 shell 设置环境变量"
  cat > /etc/profile.d/locale-zh_CN.sh <<'EOF'
# set system locale to zh_CN for interactive sessions
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
EOF
  chmod 644 /etc/profile.d/locale-zh_CN.sh
}

main() {
  require_root

  PKG=$(detect_pkg_mgr)
  info "检测到包管理器: ${PKG}"

  case "$PKG" in
    apt)
      install_fonts_and_packs_apt
      enable_locale_debian
      ;;
    dnf|yum)
      install_fonts_and_packs_dnf_yum
      enable_locale_rpm
      ;;
    pacman)
      install_fonts_pacman
      # pacman/Arch 同样使用 localectl
      if command -v localectl >/dev/null 2>&1; then
        localectl set-locale LANG=zh_CN.UTF-8
      else
        echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
      fi
      ;;
    *)
      warn "无法识别包管理器，尝试仅使用 localectl/手动生成"
      if command -v localectl >/dev/null 2>&1; then
        localectl set-locale LANG=zh_CN.UTF-8
      else
        warn "localectl 不可用，请手动编辑 /etc/locale.conf 或 /etc/default/locale"
      fi
      ;;
  esac

  # 通用：写 profile
  write_profile

  info "已完成系统级设置。下面是建议的后续操作："
  echo "  1) 退出登录并重新登录，或重启系统：sudo reboot"
  echo "  2) 对于 GUI 桌面，可能需在登录界面选择中文语言或在控制中心 -> Region & Language 中确认"
  echo "  3) 验证：运行命令 `locale`，应显示 LANG=zh_CN.UTF-8"

  info "现在输出当前 locale（注意：新终端或重启后才完全生效）"
  locale || true

  info "如果你想回退到英文，请运行："
  echo "  sudo localectl set-locale LANG=en_US.UTF-8"
  echo "  sudo sed -i '/^export LANG=/d' /etc/profile.d/locale-zh_CN.sh"
}

main "$@"
