#!/bin/bash
nmcli device modify ens18 ipv4.addresses "172.20.241.20/24"
nmcli device modify ens18 ipv4.dns "8.8.8.8 8.8.8.9"
