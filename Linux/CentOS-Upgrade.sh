#!/bin/bash
#
#  A script to upgrade CentOS 7 
#
#  Samuel Brucker 2024 - 2025

sudo dnf update
sudo sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sudo sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

sudo dnf install centos-release-stream
sudo dnf swap centos-{linux,stream}-repos

sudo dnf distro-sync

