# install in cron as:
# sudo -u medeo crontab -e
# 00 1 * * * sh /home/medeo/medeo-metrics/database/loaders/cron_job.sh > /dev/null 2>&1

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd /home/medeo/medeo-metrics/database/loaders/
bash run_all_loaders.sh
