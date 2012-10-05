#!/bin/sh
#yavdb -s $1 -t jdb "jdb -classpath $2 -sourcepath $3 $4"

HOSTNAME=localhost

if [ -n "$4" ]; then
   HOSTNAME=$4
fi

yavdb -s $1 -t jdb "jdb -sourcepath $2 -connect com.sun.jdi.SocketAttach:hostname=$HOSTNAME,port=$3"

echo "<enter to quit>"
read dummy
