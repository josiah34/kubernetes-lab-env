#!/usr/bin/env bash

set -euo pipefail

# Set noninteractive mode for apt-get so I can run without user input
export DEBIAN_FRONTEND=noninteractive


apt-get update -y 

# Install tools

apt-get install -y \
  curl \
  wget \
  git \
  vim \
  nano \
  jq \
  tree \
  htop \
  unzip \
  ca-certificates \
  gnupg \
  bash-completion \
  iproute2 \
  dnsutils \
  net-tools