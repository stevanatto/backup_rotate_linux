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
# make monthly snapshot
MONTHLY_INTERVAL=2
# make yearly snapshot - forever

# No. parallel jobs to execute
MAX_JOBS=1
#TODO: perform tests with MAX_JOBS=2

# ------------- file locations ------------------------------------------------
MOUNT_DEVICE=/dev/hdb
SNAPSHOT_DIR=/home/stevanatto/Dropbox/backup

# @/etc/fstab
# /dev/hdb        /root/backup                            ext4    ro,errors=remount-ro    0       0
# /root/backup    /var/local/backup                       none    bind,user,ro            0       0


# directories to backup
LOCATION=(
    /home/stevanatto/Dropbox/prg_backup_SC
)
#TODO: Perform tests with ssh locations
#TODO: Perform tests where names contain spaces

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
#DATE_NOW_S=`date +%s`

# ------------- subroutines ---------------------------------------------------
function snapshot() {
    DATE_NOW_S=`date +%s`
    # extract only the last part of the location
    ADDRESS=${LOCATION##*/}

    # if backup directory already exists, continue ...
    if [ -d $SNAPSHOT_DIR/$ADDRESS ]; then
        
        echo "Regular snapshot: $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW"
        # rsync from the system into the latest snapshot (notice that rsync behaves
        # like cp --remove-destination by default, so the destination is unlinked
        # first. If it were not so, this would copy over the other snapshot(s) too!
        DATE_OLD=`ls -tArd $SNAPSHOT_DIR/$ADDRESS/* | tail -1`
        DATE_OLD=${DATE_OLD##*/}
        rsync -qaAXEW `exclude` --delete \
            --link-dest=$SNAPSHOT_DIR/$ADDRESS/$DATE_OLD \
            $LOCATION/ \
            $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW/;
                
    # else if backup directory does not already exist...
    else
        echo "First snapshot: $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW"
        mkdir -p $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW
        rsync -qaAXEW --stats `exclude` $LOCATION/ $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW;
    fi
    
    # update the mtime of backup dir to reflect the snapshot time
    touch $SNAPSHOT_DIR/$ADDRESS/$DATE_NOW

    # rotate snapshots
    # Check interval between backups and delete others.
    # It do not shift backups but compare the time and exclude the unecessary 
    # ones.
    rotate

    # and thats it !
}


#Now       Old
# |<--<1h-->|<--1h-->|<--1h-->|<--1h<X<1d-->|<----1d----->|<----1d----->|<--1d<Y<30d-->|<----30d---->|<--30d<Z<365d-->|<----365d---->|
function rotate() {
    # Check interval between backups and delete others.
    # It do not shift backups but compare the time and exclude the unecessary 
    # ones.

    # Time in seconds
    ONE_MINUTE=1
    ONE_HOUR=60
    ONE_DAY=1200
    ONE_WEEK=7*$ONE_DAY
    ONE_MONTH=7200
    ONE_YEAR=21600
#    ONE_MINUTE=60
#    ONE_HOUR=60*$ONE_MINUTE
#    ONE_DAY=24*$ONE_HOUR
#    ONE_WEEK=7*$ONE_DAY
#    ONE_MONTH=30*$ONE_DAY
#    ONE_YEAR=12*$ONE_MONTH
    #DATE_NOW_S=`date "+%s"`
    
    ALL_SNAPSHOTS=(`ls -tAd $SNAPSHOT_DIR/$ADDRESS/*`)
    DISTANCES=() # empty variable
    for n in ${!ALL_SNAPSHOTS[*]}; do
        DISTANCES=(${DISTANCES[*]} $((DATE_NOW_S - `date -r ${ALL_SNAPSHOTS[$n]} +%s`)) )
    done
    
    # Inside the snapshot directory test every directory saved, where time is 
    # his name (YYYY-MMM-DD-HH:MM). The test is the distance between two 
    # snapshots.
    m=$(( ${#ALL_SNAPSHOTS[*]} -1 ))
    KEEP=( ${ALL_SNAPSHOTS[$m]} )
    echo "$m ${ALL_SNAPSHOTS[(($m))]} is the oldest backup. Keep it."

    # Test if it is a valid yearly backup
    for (( n=${#ALL_SNAPSHOTS[*]}-2; n>=0; n-- )); do
        #echo "$m,$n ${DISTANCES[$m]} - ${DISTANCES[$n]} = $((DISTANCES[$m] -DISTANCES[$n] )) / $ONE_YEAR = $(( (DISTANCES[$m] -DISTANCES[$n] )/ONE_YEAR )) , $(( (DISTANCES[$m] -DISTANCES[$n] )%ONE_YEAR ))     $((60*$ONE_DAY)) $((ONE_YEAR -60*ONE_DAY))"
        if (( $(( (DISTANCES[$m] -DISTANCES[$n] )%ONE_YEAR )) > $((ONE_YEAR -ONE_WEEK)) )) || 
        (( (( $(( (DISTANCES[$m] -DISTANCES[$n] )%ONE_YEAR )) < $ONE_WEEK )) &&
           (( $(( (DISTANCES[$m] -DISTANCES[$n] )/ONE_YEAR )) > 0 )) ))
        then
            echo "$n,$(((DISTANCES[$m]-DISTANCES[$n])/ONE_YEAR)) ${ALL_SNAPSHOTS[$n]} is a valid YEARly backup for this location. Keep it."
            KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[$n]} )
            m=$n
            #echo "$m $((ONE_YEAR -ONE_WEEK)) < $(( (DISTANCES[$m] -DISTANCES[$n] )%ONE_YEAR )),$(( (DISTANCES[$m] -DISTANCES[$n] )/ONE_YEAR )) < $((ONE_WEEK))"
        fi
    done
    #TODO: If the interval between backups is more than one year you should cath another one, if it exist.

    # Test if it is a valid monthly backup
    MAX_DISTANCE=$((ONE_MONTH*MONTHLY_INTERVAL +ONE_DAY*DAILY_INTERVAL +ONE_DAY -ONE_HOUR))
    for (( n=${#ALL_SNAPSHOTS[*]}-1; n>0; n-- )); do
        #echo "$n  ${DISTANCES[$n]} < $MAX_DISTANCE "
        if (( ${DISTANCES[$n]} < $MAX_DISTANCE )); then 
             l=$n
            MAX_DISTANCE=${DISTANCES[$n]}
            break
        fi
    done
    m=0
    for (( n=l; n>0; n-- )); do
        DISTANCE=$(( MAX_DISTANCE -DISTANCES[$n] ))
        if (( (( $(( DISTANCE %ONE_MONTH )) > $((ONE_MONTH -ONE_DAY)) )) &&
              (( $(( DISTANCE /ONE_MONTH )) > $((m-1)) )) )) ||
           (( (( $(( DISTANCE %ONE_MONTH )) < $((ONE_DAY)) )) &&
              (( $(( DISTANCE /ONE_MONTH )) >= $m )) ))
        then
            echo "$n ${ALL_SNAPSHOTS[$n]} is a valid MONTHly backup for this location. Keep it."
            KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[$n]} )
            ((m++))
            #echo "$m $((ONE_MONTH -ONE_DAY)) < $((DISTANCE/ONE_MONTH)),$((DISTANCE%ONE_MONTH)) < $((ONE_DAY))"
        fi
        #if (( ${DISTANCES[n]} < $((ONE_MONTH +ONE_DAY*DAILY_INTERVAL)) )); then break; fi
    done
    #TODO: If the interval between backups is more than one month you should cath another one, if it exist.

    # Test if it is a valid daily backup
    MAX_DISTANCE=$((ONE_DAY*DAILY_INTERVAL +ONE_HOUR*HOURLY_INTERVAL))
    for (( n=${#ALL_SNAPSHOTS[*]}-1; n>0; n-- )); do
        #echo "$n  ${DISTANCES[$n]} < $MAX_DISTANCE "
        if (( ${DISTANCES[$n]} < $MAX_DISTANCE )); then 
             l=$n
            MAX_DISTANCE=${DISTANCES[$n]}
            break
        fi
    done
    m=0
    for (( n=l; n>0; n-- )); do
        DISTANCE=$(( MAX_DISTANCE -DISTANCES[$n] ))
        if (( (( $(( DISTANCE %ONE_DAY )) > $((ONE_DAY -ONE_HOUR)) )) &&
              (( $(( DISTANCE /ONE_DAY )) > $((m-1)) )) )) ||
           (( (( $(( DISTANCE %ONE_DAY )) < $((ONE_HOUR)) )) &&
              (( $(( DISTANCE /ONE_DAY )) >= $m )) ))
        then
            echo "$n ${ALL_SNAPSHOTS[$n]} is a valid DAIly backup for this location. Keep it."
            KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[$n]} )
            ((m++))
            #echo "$m $((ONE_DAY -ONE_HOUR)) < $((DISTANCE/ONE_DAY)),$((DISTANCE%ONE_DAY)) < $((ONE_HOUR))"
        fi
        #if (( ${DISTANCES[n]} < $((ONE_DAY +ONE_HOUR*HOURLY_INTERVAL +ONE_DAY)) )); then break; fi
    done
    #TODO: If the interval between backups is more than one day you should cath another one, if it exist.

    # Test if it is a valid hourly backup
    m=1
    for (( n=1; n<${#ALL_SNAPSHOTS[*]}-1; n++ )); do
        if (( (( $(( DISTANCES[$n] %ONE_HOUR )) > $((ONE_HOUR -5*ONE_MINUTE)) )) &&
              (( $(( DISTANCES[$n] /ONE_HOUR )) > $((m-1)) )) )) ||
           (( (( $(( DISTANCES[$n] %ONE_HOUR )) < $((5*ONE_MINUTE)) )) &&
              (( $(( DISTANCES[$n] /ONE_HOUR )) >= $m )) ))
        then
            #echo "$n ${ALL_SNAPSHOTS[$n]} is a valid HOURly backup for this location. Keep it."
            KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[$n]} )
            ((m++))
            echo "$m $((ONE_HOUR -5*ONE_MINUTE)) < $((DISTANCES[$n]/ONE_HOUR)),$(( DISTANCES[$n] %ONE_HOUR )) < $((5*ONE_MINUTE))"
        fi
        if (( ${DISTANCES[$n]} > $(((HOURLY_INTERVAL-1)*ONE_HOUR -5*ONE_MINUTE)) )); then break; fi
    done

    KEEP=(${KEEP[*]} ${ALL_SNAPSHOTS[0]} )
    echo "0 ${ALL_SNAPSHOTS[0]} is the newest backup. Keep it."
    
    for D in ${ALL_SNAPSHOTS[*]}; do
        if [[ ! " ${KEEP[@]} " =~ " ${D} " ]]; then
            echo "$D is an uncecessary backup. Delete it."
            # DEBUG
            echo "$((ONE_YEAR -ONE_WEEK)) < $(( (DISTANCES[$m] -DISTANCES[$n] )%ONE_YEAR )),$(( (DISTANCES[$m] -DISTANCES[$n] )/ONE_YEAR )) < $((ONE_WEEK))"
            echo "$((ONE_MONTH -ONE_DAY)) < $((DISTANCE/ONE_MONTH)),$((DISTANCE%ONE_MONTH)) < $((ONE_DAY))"
            echo "$((ONE_DAY -ONE_HOUR)) < $((DISTANCE/ONE_DAY)),$((DISTANCE%ONE_DAY)) < $((ONE_HOUR))"
            echo "$((ONE_HOUR -5*ONE_MINUTE)) < $((DISTANCES[$n]/ONE_HOUR)),$(( DISTANCES[$n] %ONE_HOUR )) < $((5*ONE_MINUTE))"
            # GUBED
            rm -fr "$D"
        fi
    done
}
# VERIFICAR O QUE ACONTECE COM OS LINKS DEPOIS DE ROTACIONAR E APAGAR OS LINKS CRIADOS PELO RSYNC DAS REFERENCIAS


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
#    if (( `id -u` != 0 )); then { echo "Sorry, must be root.   Exiting..."; exit; } fi

    # if a backup process is already running, exit
#    lockdir=/tmp/my_backup.lock
#    if mkdir "$lockdir"; then
#        # Remove lockdir when the script finishes, or when it receives a signal
#        trap 'rm -rf "$lockdir"' 0  # remove directory when script finishes
        #trap "exit 2" 1 2 3 15     # terminate script when receiving signal
#    else
#        echo "Cannot acquire lock (Already running).    Exiting..."
#        exit 0
#    fi

    # attempt to remount the RW mount point as RW; else abort
#    mount -o remount,rw $MOUNT_DEVICE $SNAPSHOT_DIR ;
#    if (( $? )); then
#    {
#        echo "snapshot: could not remount $SNAPSHOT_DIR readwrite";
#        exit;
#    }
#    fi;

    # execute the jobs
    if (( $MAX_JOBS > 0 )); then
        for LOCATION in ${LOCATION[*]}; do
            snapshot
        done
    else
        for LOCATION in ${LOCATION[*]}; do
            snapshot &
            forky
        done
    fi

    wait

    # now remount the RW snapshot mountpoint as readonly
#    mount -o remount,ro $MOUNT_DEVICE $SNAPSHOT_DIR ;
#    if (( $? )); then
#    {
#        echo "snapshot: could not remount $SNAPSHOT_DIR readonly";
#        exit;
#    } fi;
}
# ------------- the end--------------------------------------------------------


## Refrences...
## http://www.mikerubel.org/computers/rsync_snapshots/ by Mike Rubel.
## http://sourcebench.com/languages/bash/simple-parallel-processing-with-bash-using-wait-and-jobs/
## http://mywiki.wooledge.org/BashFAQ/045 ensure that only one instance of a script is running at a time.
