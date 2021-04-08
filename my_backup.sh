#!/bin/bash
#
# SCRIPT: my_backup.sh
# AUTHOR: Luiz Carlos Stevanatto <stevanatto@yahoo.com>
# DATE:   2018-08-19
# REV:    1.0   (For Alpha, Beta, Dev, Test and Production)
#
# PLATFORM: Not platform dependent
#
## PURPOSE: Incremental rsync backup script.
##  Run hourly via cron and it will take a back up every hour up to X hours, 
##  Y days, Z months and years. Every snapshot is saved as YYYY-MMM-DD-HH:MM.
##  Then rotate/exlcude snapshots out of the intervals. Do not use names with
##  spaces. Saved snapshots are like:
##  /roob/backup/my_local/2018-10-30-16:42
## OBS: Do not delte old backups as you wish, because it is linked from old 
##  files in new directories.
#
# @/etc/crontab
# 42 *    * * *   root    /bin/sh backup.sh

# ------------- backup interval -----------------------------------------------
# make hourly snapshot
HOURLY_INTERVAL=4
# make dayly snapshot
DAILY_INTERVAL=3
# make weekly snapshot
WEEKLY_INTERVAL=3
# make monthly snapshot
MONTHLY_INTERVAL=2
# make yearly snapshot - forever

# No. parallel jobs to execute
MAX_JOBS=2

# ------------- file locations ------------------------------------------------
MOUNT_DEVICE=/dev/hdb
SNAPSHOT_DIR=/home/stevanatto/Dropbox/backup

# Normally the SNAPSHOT_DIR is in a external device used with read only access
# for extra security. Then you have to mount it with read and write access for a 
# short time. Do not forget to full fill the fstab file with something like 
# above. If you do not have external device keep the MOUNT_DEVICE in blank.
# @/etc/fstab
# /dev/hdb        /root/backup                            ext4    ro,errors=remount-ro    0       0
# /root/backup    /var/local/backup                       none    bind,user,ro            0       0
#TODO: Perform tests with sshfs locations (it only works if will not ask password).


# directories to backup (do not finish with '/')
LOCATION=(
    /home/stevanatto/Documents
    /home/stevanatto/Projects
)
# examples:
# /home/user/Documents
# /home/user/Another\ Directory
#

# excludes
EXCLUDES=(
    ~*
    *.lnk
    *.tmp
    baloo*
    [cC]ache
)


# ------------- system commands renamed by this script ---------------------------
#MV=/bin/mv;
MV=my_mv;

# ------------- local variables -----------------------------------------------
DATE_NOW=`date "+%Y-%m-%d-%Hh%Mm"`

# ------------- subroutines ---------------------------------------------------
function snapshot() {
    # extract only the last part of the location
    ADDRESS=${LOCATION##*/}

    # if backup directory already exists, continue ...
    if [ -d $SNAPSHOT_DIR/$ADDRESS ]; then
        
        echo "Regular snapshot: $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW"
        # rsync from the system into the latest snapshot (notice that rsync behaves
        # like cp --remove-destination by default, so the destination is unlinked
        # first. If it were not so, this would copy over the other snapshot(s) too!
        DATE_OLD=`ls -tAd $SNAPSHOT_DIR/$ADDRESS/* | tail -1`
        DATE_OLD=${DATE_OLD##*/}
        rsync -qaAXEW `exclude` --delete \
            --link-dest=$SNAPSHOT_DIR/$ADDRESS/$DATE_OLD \
            $LOCATION/ \
            $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW/;
                
    # else if backup directory does not already exist...
    else
        echo "First snapshot: $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW"
        mkdir -p $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW
        rsync -qaAXEW --stats `exclude` $LOCATION/ $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW
    fi
    
    # update the mtime of backup dir to reflect the snapshot time
    touch -a $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW;

    # rotate snapshots
    # Check interval between backups and delete others.
    # It do not shift backups but compare the time and exclude the unecessary 
    # ones.
    rotate

    # Main program is the last routine.
}


#Now       Old
# |<--<1h-->|<--1h-->|<--1h-->|<--1h<X<1d-->|<----1d----->|<----1d----->|<--1d<Y<30d-->|<----30d---->|<--30d<Z<365d-->|<----365d---->|
function rotate() {
    # Check interval between backups and delete others.
    # It do not shift backups but compare the time and exclude the unecessary 
    # ones.

    # Time in seconds
    ONE_MINUTE=60
    ONE_HOUR=60*$ONE_MINUTE
    ONE_DAY=24*$ONE_HOUR
    ONE_WEEK=7*$ONE_DAY
    ONE_MONTH=30*$ONE_DAY
    ONE_YEAR=12*$ONE_MONTH
    DATE_NOW_SEC=`date "+%s"`
    
    ALL_SNAPSHOTS=(`ls -tAd $SNAPSHOT_DIR/$ADDRESS/*`)
    DISTANCES=() # empty variable
    for n in ${!ALL_SNAPSHOTS[*]}; do
        #DISTANCES=(${DISTANCES[*]} $((DATE_NOW_SEC - `date -r ${ALL_SNAPSHOTS[$n]} +%s`)) )
        # This solve the unexpected deleted backups if no modification exist.
        DISTANCES=(${DISTANCES[*]} $((DATE_NOW_SEC - `stat ${ALL_SNAPSHOTS[$n]} --format=%X`)) )
    done
    #echo ${DISTANCES[*]}
    
    # Inside the snapshot directory test every directory saved, where time is 
    # his name (YYYY-MMM-DD-HH:MM). The test is the distance between the  
    # snapshots and the reference like 1hour, 2hours, ..., 2days, 3days, ...
    # That is saved in KEEP array.
    KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[0]} )
    echo "[0] ${ALL_SNAPSHOTS[0]} is the newest backup. Keep it."

    echo "Test if it is a valid hourly backup (under $HOURLY_INTERVAL hours)."
    validate_backups $HOURLY_INTERVAL $ONE_HOUR

    echo "Test if it is a valid daily backup (under $DAILY_INTERVAL days)."
    validate_backups $DAILY_INTERVAL $ONE_DAY
    
    echo "Test if it is a valid weekly backup (under $WEEKLY_INTERVAL weeks)."
    validate_backups $WEEKLY_INTERVAL $ONE_WEEK
    
    echo "Test if it is a valid monthly backup (under $MONTHLY_INTERVAL months)."
    validate_backups $MONTHLY_INTERVAL $ONE_MONTH

    echo "Test if it is a valid monthly backup (under 99 years)."
    validate_backups 99 $ONE_YEAR

    # report and delete
    for D in ${ALL_SNAPSHOTS[*]}; do
        if [[ ! " ${KEEP[@]} " =~ " ${D} " ]]; then
            echo "$D is an uncecessary backup. Delete it."
            rm -fr "$D"
        fi
    done
}


function validate_backups() {
    TOTAL_INTERVALS=$1
    DELTA_TIME=$2
    m=1
    for (( l=1; l<=$TOTAL_INTERVALS; l++ )); do
        REFERENCE=$(( l *DELTA_TIME ))
        for (( n=$m; n<${#ALL_SNAPSHOTS[*]}; n++ )); do
            if (( (( $REFERENCE >= ${DISTANCES[$n]} )) &&
                  (( ${DISTANCES[$n]} > ${DISTANCES[$m]} )) ))
            then
                #echo "[$m,$n] ${ALL_SNAPSHOTS[$n]} is something nearest from left side of the reference."
                m=$n
            fi
        done
        
        if (( $(( REFERENCE -DISTANCES[$m] )) <= $DELTA_TIME  ))
        then
            echo "[$m] ${ALL_SNAPSHOTS[$m]} is a valid backup. Keep it."
            KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[$m]} )
        else
            echo "[$m] ${ALL_SNAPSHOTS[$m]} is too far from referential and will not be included as valid backup."
        fi
    done
}


function exclude() {
    for E in ${EXCLUDES[*]}; do 
        echo -n "--exclude=$E " 
    done
}


function forky() {
    while [[ $(jobs | wc -l) -ge $MAX_JOBS ]] ; do
        sleep 10
    done
}


function my_mv() {
   REF=/tmp/makesnapshot-my_mv-$$;
   /bin/touch -r $1 $REF;
   /bin/mv $1 $2;
   /bin/touch -r $REF $2;
   /bin/rm $REF;
}

# ------------- the script itself ---------------------------------------------
{
    # make sure we're running as root
    if (( `id -u` != 0 )); then { echo "Sorry, must be root.   Exiting..."; exit; } fi

    # if a backup process is already running, exit
    lockdir=/tmp/my_backup.lock
    if mkdir "$lockdir"; then
        # Remove lockdir when the script finishes, or when it receives a signal
        trap 'rm -rf "$lockdir"' 0  # remove directory when script finishes
        #trap "exit 2" 1 2 3 15     # terminate script when receiving signal
    else
        echo "Cannot acquire lock (Already running).    Exiting..."
        exit 0
    fi

    # attempt to remount the RW mount point as RW; else abort
    if [[ $MOUNT_DEVICE  ]]; then
    {
        mount -o remount,rw $MOUNT_DEVICE $SNAPSHOT_DIR ;
        if (( $? )); then
        {
            echo "snapshot: could not remount $SNAPSHOT_DIR readwrite";
            exit;
        } fi
    } fi

    # save and change IFS (for names paces)
    OLDIFS=$IFS
    IFS=$'\n'
    
    # execute the jobs
    if (( $MAX_JOBS > 1 )); then
        for LOCATION in ${LOCATION[*]}; do
            snapshot &
            forky
        done
    else
        for LOCATION in ${LOCATION[*]}; do
            snapshot
        done
    fi

    wait
    
    # restore IFS (for names paces)
    IFS=$OLDIFS
    
    # now remount the RW snapshot mountpoint as readonly
    if [[ $MOUNT_DEVICE  ]]; then
    {
        mount -o remount,ro $MOUNT_DEVICE $SNAPSHOT_DIR ;
        if (( $? )); then
        {
            echo "snapshot: could not remount $SNAPSHOT_DIR readonly";
            exit;
        } fi
    } fi
    
    # That's all folks !
}
# ------------- the end--------------------------------------------------------


## Refrences...
## http://www.mikerubel.org/computers/rsync_snapshots/ by Mike Rubel.
## http://sourcebench.com/languages/bash/simple-parallel-processing-with-bash-using-wait-and-jobs/
## http://mywiki.wooledge.org/BashFAQ/045 ensure that only one instance of a script is running at a time.
