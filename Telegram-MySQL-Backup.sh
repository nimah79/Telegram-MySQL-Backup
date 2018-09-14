#!/bin/bash

#==============================================================================
#TITLE:            Telegram-MySQL-Backup.sh
#DESCRIPTION:      Script for automating the daily MySQL backups to Telegram
#AUTHOR:           NimaH79 (thanks to tleish)
#USAGE:            ./Telegram-MySQL-Backup.sh
#CRON:
  # example cron for daily MySQL backup @ 00:00
  # min hr mday month wday command
  # 0   0  *    *     *    /path/to/Telegram-MySQL-Backup.sh

#RESTORE FROM BACKUP
  #$ gunzip < [backupfile.sql.gz] | mysql -u [uname] -p[pass] [dbname]
#==============================================================================

#==============================================================================
# CUSTOM SETTINGS
#==============================================================================

# directory to put the backup files
BACKUP_DIR=./

# MYSQL Parameters
MYSQL_UNAME=YOUR_MYSQL_USERNAME
MYSQL_PWORD=YOUR_MYSQL_PASSWORD

# Don't backup databases with these names 
# Example: starts with mysql (^mysql) or ends with _schema (_schema$)
IGNORE_DB="(^mysql|_schema$)"

# Include mysql and mysqldump binaries for cron bash user
PATH=$PATH:/usr/bin/mysql

# Number of days to keep backups on disk (0 to disable)
KEEP_BACKUPS_FOR=30 # days

# Token of Telegram bot
BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN

# chat_id of user who wants to get backup files in Telegram
CHAT_ID=YOUR_CHAT_ID

# Current time in YYYY-MM-DD format
DATE=$(date +%F)

#==============================================================================
# METHODS
#==============================================================================

function telegram_send_message() {
    curl -F chat_id="$1" -F text="$2" https://api.telegram.org/bot$BOT_TOKEN/sendMessage &> /dev/null
}

function telegram_send_document() {
    curl -F chat_id="$1" -F document=@"$2" caption="$3" https://api.telegram.org/bot$BOT_TOKEN/sendDocument &> /dev/null
}

function delete_old_backups() {
    if [ $KEEP_BACKUPS_FOR -ne 0 ]; then
        find $BACKUP_DIR -type f -name "*.sql.gz" -mtime +$KEEP_BACKUPS_FOR -exec rm {} \;
    fi
}

function mysql_login() {
    local mysql_login="-u $MYSQL_UNAME" 
    if [ -n "$MYSQL_PWORD" ]; then
        local mysql_login+=" -p$MYSQL_PWORD" 
    fi
    echo $mysql_login
}

function database_list() {
    local show_databases_sql="SHOW DATABASES WHERE \`Database\` NOT REGEXP '$IGNORE_DB'"
    echo $(mysql $(mysql_login) -e "$show_databases_sql"|awk -F " " '{if (NR!=1) print $1}')
}

function backup_database() {
    backup_file="$BACKUP_DIR/$DATE.$database.sql.gz"
    mysqldump $(mysql_login) $database | gzip -9 > $backup_file
    backup_file_size=$(stat -c%s $backup_file)
    if [ $backup_file_size -le 50000000 ]; then
        # Send backup file to Telegram
        telegram_send_document $CHAT_ID $backup_file
    else
        # Split backup file, then send to Telegram
        zipped_backup_file="$BACKUP_DIR/$DATE.$database"
        zip -r -s 50m "$zipped_backup_file.zip" $backup_file
        number_of_parts=$(($backup_file_size / 50000000))
        telegram_send_document $CHAT_ID "$zipped_backup_file.zip"
        if [ $KEEP_BACKUPS_FOR -eq 0 ]; then
            rm "$zipped_backup_file.zip"
        fi
        for i in $(seq -f "%02g" 1 $number_of_parts); do
            telegram_send_document $CHAT_ID "$zipped_backup_file.z$i"
            if [ $KEEP_BACKUPS_FOR -eq 0 ]; then
                rm "$zipped_backup_file.z$i"
            fi
        done
    fi
    if [ $KEEP_BACKUPS_FOR -eq 0 ]; then
        rm $backup_file
    fi
}

function backup_databases() {
    # Send current date to Telegram
    telegram_send_message $CHAT_ID "MySQL Backup - $DATE:"
    for database in $(database_list); do
        backup_database
    done
}

#==============================================================================
# RUN SCRIPT
#==============================================================================

delete_old_backups
backup_databases
