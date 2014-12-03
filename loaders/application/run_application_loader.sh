#!/bin/bash

# check that the new data is fresh
if ! test `find ~/latest_obfuscated.sql -mtime -1`
then
	echo Data is more than 24 hours old. Failing.
	exit 1
fi

# load the data
dropdb medeo_development
createdb medeo_development
psql -d medeo_development -f ~/latest_obfuscated.sql

# run the loader
ruby application_loader.rb
