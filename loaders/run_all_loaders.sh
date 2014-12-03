#!/bin/bash

source env.sh

ERROR=0

cd application
bash ../message_on_fail.sh bash run_application_loader.sh
ERROR=`expr $ERROR + $?`
cd ..

cd facebook_social
bash ../message_on_fail.sh ruby facebook_social_loader.rb
ERROR=`expr $ERROR + $?`
cd ..

cd google_analytics
bash ../message_on_fail.sh ruby google_analytics_loader.rb
ERROR=`expr $ERROR + $?`
cd ..

cd newrelic
bash ../message_on_fail.sh ruby newrelic_loader.rb
ERROR=`expr $ERROR + $?`
cd ..

cd salesforce
bash ../message_on_fail.sh ruby salesforce_loader.rb
ERROR=`expr $ERROR + $?`
cd ..

cd twitter
bash ../message_on_fail.sh ruby twitter_loader.rb
ERROR=`expr $ERROR + $?`
cd ..

# application and salesforce loaders can recreate tables, recreate views to pickup changes
cd ../views
bash ../loaders/message_on_fail.sh bash create_all_views.sh
ERROR=`expr $ERROR + $?`
cd ../loaders

# Eventually we need to do some database maintenance.
# It only takes a few minutes at the moment, so let's do it now
bash message_on_fail.sh bash vacuum.sh
ERROR=`expr $ERROR + $?`

# want to test a failure? uncomment the below lines
# cd tests
# bash ../message_on_fail.sh sh will_fail.sh
# ERROR=`expr $ERROR + $?`
# cd ..

MESSAGE="message.txt"

echo $ERROR

if [ $ERROR -ne 0 ]
then
  echo "<b>"$HOSTNAME" loader(s) failed.</b><br />" > $MESSAGE
	echo $ERROR" loader(s) failed. You should see an individual message for each failure." >> $MESSAGE
  wget "https://api.hipchat.com/v1/rooms/message?auth_token=${API_KEY}&room_id=${ROOM}&from=${FROM}&message=$(cat $MESSAGE)&color=red" -qO- > /dev/null 2>&1
else
  echo "<b>"$HOSTNAME" loaders successful.</b><br />" > $MESSAGE
	echo "All loaders were successful." >> $MESSAGE
  wget "https://api.hipchat.com/v1/rooms/message?auth_token=${API_KEY}&room_id=${ROOM}&from=${FROM}&message=$(cat $MESSAGE)&color=green" -qO- > /dev/null 2>&1
fi

rm $MESSAGE
