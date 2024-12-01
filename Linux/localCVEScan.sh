#!/bin/bash
sudo nmap -sV --script=vuln --script-args vulns.showall --open -p1-1024,3000-3100,6000-6100,6600-6700,8000-8100 -T4 -oN localhost_scan.txt 127.0.0.1
