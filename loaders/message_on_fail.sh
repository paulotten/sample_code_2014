#!/bin/bash

LOG="output.tmp"

echo $@

$@ > $LOG 2>&1
ERROR=$?

if [ $ERROR -ne 0 ]
then
  MESSAGE="message.txt"
  echo $HOSTNAME" \""$@"\" failed." > $MESSAGE
  cat $LOG >> $MESSAGE
  STRING=$(cat $MESSAGE | sed 's/#/%23/g')
  while [ ${#STRING} -gt 0 ]
  do
    SUBSTRING=${STRING:0:5000} # HipChat claims to limit messages to 10,000 characters, 5,000 seems to be what will actually work
    wget "https://api.hipchat.com/v1/rooms/message?auth_token=${API_KEY}&room_id=${ROOM}&from=${FROM}&message=${SUBSTRING}&color=red&message_format=text" -Oq- > /dev/null 2>&1
    STRING=${STRING:5000:1000000000}
    sleep 1 # messages seem to some times get processed out of order on HipChat, lets give them 1000ms to sort them out
  done
  rm $MESSAGE
fi

rm $LOG

echo $ERROR
exit $ERROR
