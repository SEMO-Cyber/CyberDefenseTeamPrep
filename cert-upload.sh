#/bin/bash

echo -n "Enter destination machine's IP: ";
read dest;
echo -n "Enter username (leave blank if admin): ";
read user;
if [[ -z $user ]]; then
  user="admin";
fi;

echo -n "Enter destination filepath (leave blank for ~/): "
read loc
if [[ -z $loc ]]; then
  loc="~";
fi;
echo -n "Enter file name (!!make sure in same dir as script!!): ";
read file;

scp $file $user@$dest:$loc/$file;
