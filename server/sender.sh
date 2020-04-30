#!/bin/bash

for i in "$@"
do
	echo $i
	n=`printf "\x%1x" $i`
	var=$var$n
done
echo "var is now $var"
#gnu-netcat
echo -en "$var" | timeout 1 nc -x 127.0.0.1 8080
#openbsd-netcat
#echo -en "$var" | timeout 1 nc  127.0.0.1 8080

