#!/bin/bash
sudo nmap -sV --script=vuln --script-args mincvss=8.0 --open -p1-1024,3000-3100,6000-6100,6600-6700,8000-8100 -T4 --max-retries 2 --max-rtt-timeout 300ms -n -oN intenseLocalScan.txt 127.0.0.1
