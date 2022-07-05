#!/usr/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root. Please use \`\$ sudo\`"
  exit
else
  echo "WARN: This script ONLY supports Debian or Ubuntu, for other platforms, please refer to [https://pdos.csail.mit.edu/6.S081/2021/tools.html] for environment setup."
  echo "WARN: You are going to install a lot of tool chains, please understand what you are doing. Proceed? [y/n]"
  read ans
  if [ $ans == "y" ]; then
    apt-get update && sudo apt-get upgrade
    apt-get install git build-essential gdb-multiarch qemu-system-misc gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
  else
    echo "Operation Canceled"
  fi
fi
