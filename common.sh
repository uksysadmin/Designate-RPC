#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
echo "set grub-pc/install_devices /dev/sda" | debconf-communicate

sudo apt-get update && sudo apt-get upgrade -y
