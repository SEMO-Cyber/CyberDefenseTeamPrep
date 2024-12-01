#!/bin/bash
sudo nmap --script=vuln --script-args mincvss=8.0 --open -p1-1024,3000,3030,4443,6000,6060,8000,8080,9997 -T5 --max-retries 1 --max-rtt-timeout 200ms -T5 -n -oN scanresultsQUICK.txt 127.0.0.1
