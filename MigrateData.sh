#!/bin/bash
#
# This script is meant to migrate data from a Time Machine backup drive to a new computer
# that has an existing account setup. The script is generally run from the Jamf Pro admin
# account with root privileges. The Time Machine backup is used as the source of the
# transfer. The easiest way to populate the drive paths is to drag and drop the destination
# into the terminal window and the proper path will be entered.
#
# Updated to use new path to cups directory in macOS Catalina and new method of getting the
# current user using bash or zsh.
# 
# VERSION 1.2
# Written by: Michael Permann
# Created On: September 06, 2018
# Updated On: October 31, 2020

CURRENT_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )
USER_ID=$(/usr/bin/id -u "$CURRENT_USER")
DATA_MIGRATION_LOG=/Users/Shared/DataMigrationLog.txt

/usr/bin/caffeinate -dis &
caffeinatePID=$(echo $!)

if [[ $(id -u) -ne 0 ]]; then
  /bin/echo "Script needs run as root"
  /bin/echo "Example: sudo MigrateData.sh"
  exit 1
fi

/bin/echo $(date) > "$DATA_MIGRATION_LOG"
/bin/echo ""
/bin/echo "Provide path to latest backup of Macintosh HD"
/bin/echo "Example: /Volumes/Backup/Backups.backupdb/John\ Doe\ 54321/Latest/Macintosh HD\ - Data"
read -p 'Path: ' latestBackupPath
/bin/echo ""
/bin/echo "Provide user short name from backup drive"
/bin/echo "Example: jdoe"
read -p 'Old user short name: ' oldShortName
/bin/echo ""
/bin/echo "Provide user short name from replacement computer"
/bin/echo "Example: jdoe"
read -p 'New user short name: ' newShortName
/bin/echo ""

/bin/echo "User entered latest backup of Machintosh HD: $latestBackupPath" >> "$DATA_MIGRATION_LOG"
/bin/echo "User entered old user short name: $oldShortName" >> "$DATA_MIGRATION_LOG"
/bin/echo "User entered new user short name: $newShortName" >> "$DATA_MIGRATION_LOG"

if [[ -d "$latestBackupPath" ]]
then
  /bin/echo "Path appears valid" >> "$DATA_MIGRATION_LOG"
  /bin/echo "Path to latest backup of Macintosh HD: $latestBackupPath" >> "$DATA_MIGRATION_LOG"
else
  /bin/echo "Path to latest backup of Macintosh HD appears invalid: $latestBackupPath" >> "$DATA_MIGRATION_LOG"
  /bin/echo "Path to latest backup of Macintosh HD appears invalid: $latestBackupPath"
  /bin/echo "Please verify path and re-run script"
  exit 1
fi

if [[ -d "$latestBackupPath/Users/$oldShortName" ]]
then
  /bin/echo "Old user short name appears valid: $oldShortName" >> "$DATA_MIGRATION_LOG"
else
  /bin/echo "Old user short name appears invalid: $oldShortName" >> "$DATA_MIGRATION_LOG"
  /bin/echo "Old user short name appears invalid: $oldShortName"
  /bin/echo "Please verify old user short name and re-run script"
  exit 1
fi

if [[ -d "/Users/$newShortName" ]]
then
  /bin/echo "New user short name appears valid: $newShortName" >> "$DATA_MIGRATION_LOG"
else
  /bin/echo "New user short name appears invalid: $newShortName" >> "$DATA_MIGRATION_LOG"
  /bin/echo "New user short name appears invalid: $newShortName"
  /bin/echo "Please verify new user short name and re-run script"
  exit 1
fi

oldHomeSize=$(/usr/bin/du -shk "$latestBackupPath/Users/$oldShortName/" | /usr/bin/awk '{print $1}')
/usr/sbin/system_profiler SPStorageDataType -xml > /tmp/storage.plist
newDriveCapacity=$(( $(/usr/libexec/PlistBuddy -c "Print :0:_items:0:free_space_in_bytes" /tmp/storage.plist) / 1022 ))

if [[ oldHomeSize -lt newDriveCapacity ]]
then
  /bin/echo "There should be enough space to copy data: $oldHomeSize" >> "$DATA_MIGRATION_LOG"
  /bin/echo "Available space: $newDriveCapacity" >> "$DATA_MIGRATION_LOG"
else
  /bin/echo "User's home folder may be larger than available space: $oldHomeSize" >> "$DATA_MIGRATION_LOG"
  /bin/echo "Available space: $newDriveCapacity" >> "$DATA_MIGRATION_LOG"
  /bin/echo "User's home folder may be larger than available space: $oldHomeSize"
  /bin/echo "Available space: $newDriveCapacity"
  /bin/echo "Please verify size of user's home folder and available space and run script again"
  exit 1
fi

/bin/echo "********** Start Migration of printer settings errors **********" >> "$DATA_MIGRATION_LOG"
/bin/cp -p "$latestBackupPath/private/etc/cups/printers.conf" /private/etc/cups/printers.conf 2>> "$DATA_MIGRATION_LOG"
/bin/cp -pR "$latestBackupPath/private/etc/cups/ppd/" /private/etc/cups/ppd/ 2>> "$DATA_MIGRATION_LOG"
/bin/echo "**********  End Migration of printer settings errors  **********" >> "$DATA_MIGRATION_LOG"

/bin/echo "********** Start Migration of user data errors **********" >> "$DATA_MIGRATION_LOG"
/usr/bin/rsync -plarv "$latestBackupPath/Users/$oldShortName/" /Users/"$newShortName"/ 2>> "$DATA_MIGRATION_LOG"
/bin/echo "**********  End Migration of user data errors  **********" >> "$DATA_MIGRATION_LOG"

/bin/echo "Permissions are about to be fixed on the user's home folder in Finder" >> "$DATA_MIGRATION_LOG"
/bin/launchctl asuser "$USER_ID" /usr/bin/osascript -e 'tell application "Finder" to open information window of folder "'"$newShortName"'" of folder "Users" of startup disk'
/bin/launchctl asuser "$USER_ID" /usr/bin/osascript -e 'display dialog "Propagate permissions on user home folder in the Finder window that just appeared. Click OK when that task has completed."'
/bin/echo "About to run diskutil resetUserPermissions / $(id -u "$newShortName")" >> "$DATA_MIGRATION_LOG"
/usr/sbin/diskutil resetUserPermissions / $(id -u "$newShortName")

/bin/launchctl asuser "$USER_ID" /usr/bin/osascript -e 'display dialog "Migration is complete. You can restart the computer and log in as user and complete backup"'
kill ${caffeinatePID}

exit 0
