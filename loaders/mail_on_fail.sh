#!/bin/bash

LOG="output.tmp"

echo $@

$@ > $LOG 2>&1
ERROR=$?

if [ $ERROR -ne 0 ]
then
	MESSAGE="email.txt"
	echo "Subject: " $HOSTNAME  " " $@ " failed." > $MESSAGE
	cat $LOG >> $MESSAGE
	sendmail -v $EMAIL < $MESSAGE
	rm $MESSAGE
fi

rm $LOG

echo $ERROR
exit $ERROR