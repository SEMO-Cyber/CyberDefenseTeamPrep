#!/bin/bash
sudo nmap -sV --script=vuln --script-args mincvss=8.0 --open -p1-1024,300,3030,4443,6000,6060,8000,8080,9997 -T4 --max-retries 2 --max-rtt-timeout 300ms -T4 -n -oN scanResultsINTENSE.txt 127.0.0.1
