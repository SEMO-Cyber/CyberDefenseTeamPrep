#!/bin/bash
#
#  A script to upgrade CentOS 7 
#
#  Samuel Brucker 2024 - 2025

sudo yum update
sudo sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sudo sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

sudo yum install centos-release-stream
sudo yum swap centos-{linux,stream}-repos

sudo yum distro-sync

echo "Migration complete. RESTART THE SYSTEM!!!"
