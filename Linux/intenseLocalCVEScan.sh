#!/bin/bash
sudo nmap --script=vuln --script-args mincvss=7.0 --open -p1-1000,3000,3030,6000,6060,8000,8080,9997 -T4 --max-retries 2 --max-rtt-timeout 300ms -T4 -n -oN scanResultsINTENSE.txt 127.0.0.1
