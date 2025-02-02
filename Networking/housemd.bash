#!/bin/bash
# 
# housemd.sh
# 
# Palo alto setup script
# 
# James Meghrian
# Jan. 2025

printf "Starting housemd script\n"

# get team ip
printf "Enter team IP number should be between (21-40): "
read team

echo "set cli scripting-mode on" > palolog.txt
echo "configure" >> palolog.txt
echo "set address public-fedora ip-netmask 172.25.$team.39" >> palolog.txt
echo "set address public-splunk ip-netmask 172.25.$team.9" >> palolog.txt
echo "set address public-centos ip-netmask 172.25.$team.11" >> palolog.txt
echo "set address public-debian ip-netmask 172.25.$team.20" >> palolog.txt
echo "set address public-ubuntu-web ip-netmask 172.25.$team.23" >> palolog.txt
echo "set address public-windows-server ip-netmask 172.25.$team.27" >> palolog.txt
echo "set address public-windows-docker ip-netmask 172.25.$team.97" >> palolog.txt
echo "set address public-win10 ip-netmask 172.31.$team.5" >> palolog.txt
echo "set address public-ubuntu-wkst ip-netmask 172.25.$team.111" >> palolog.txt
echo "set address this-fw ip-netmask 172.31.$team.2" >> palolog.txt
echo "set address this-fw2 ip-netmask 172.25.$team.150" >> palolog.txt

cat ./housemd.txt >> palolog.txt
cp ./housemd.txt ./backup-housemd.txt
mv palolog.txt housemd.txt
echo "commit" >> housemd.txt


ssh -T admin@172.20.242.150 < ./housemd.txt

cp ./housemd.txt ./ran.txt
mv ./backup-housemd.txt ./housemd.txt

exit 0
