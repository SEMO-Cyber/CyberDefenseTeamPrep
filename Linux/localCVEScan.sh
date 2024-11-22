#!/bin/bash
sudo nmap -sV --script=vuln --script-args vulns.showall --open -p- -T4 -oN localhost_scan.txt 127.0.0.1
