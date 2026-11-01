#!/usr/bin/env bash
set -euo pipefail
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-27.2.12479018}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-35}"
GO_VERSION="${GO_VERSION:-1.23.1}"

sudo apt-get update
sudo apt-get install -y curl unzip git make build-essential pkg-config ca-certificates openjdk-17-jdk
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in amd64) GO_ARCH=amd64 ;; arm64) GO_ARCH=arm64 ;; *) echo "arch?"; exit 1 ;; esac
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tgz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/go.tgz

mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
if [[ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o /tmp/clt.zip
  rm -rf /tmp/clt "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mkdir -p /tmp/clt && unzip -q /tmp/clt.zip -d /tmp/clt
  mv /tmp/clt/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
fi

export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-$(dpkg --print-architecture)"
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="/usr/local/go/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" "platforms;android-${ANDROID_PLATFORM}" "build-tools;35.0.0" "ndk;${ANDROID_NDK_VERSION}"
yes | sdkmanager --licenses >/dev/null || true
echo "Done. Add to ~/.bashrc: export JAVA_HOME=$JAVA_HOME; export ANDROID_HOME=$ANDROID_HOME; export PATH=$PATH"
