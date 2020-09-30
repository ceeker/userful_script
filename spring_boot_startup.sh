#! /bin/bash
#
# Spring Boot Launcher Management Script
# Copyright (c) Netease Corporation
# Copy from Hmail Service launcher.sh (Written by Qiu Sheng <qiusheng@corp.netease.com>)

# ************************* We need to set at least 4 parameters (begin) ************************* 
# Param 1, springboot app name, and daemon uses the name to guarantee a single named instance
NAME="qy-wework"

# Param 2, spring boot app jar
APPJAR="qy-wework-server-3.0.jar"

# Param 3, root log dir
ROOTLOGDIR="/home/appops/logs"

# Param 4, java home
#JAVAHOME="/usr/java/jdk1.8.0_121"
JAVAHOME="/home/appops/openjdk/jdk-14"
# ************************* We need to set at least 4 parameters (end)  ************************* 

# log dir
LOGDIR="$ROOTLOGDIR/$NAME"
if ! [ -a $LOGDIR ] ; then
    mkdir -p $LOGDIR
fi
LOGFILE="$LOGDIR/launcher.log"
ERRLOGFILE="$LOGDIR/launcher.err.log"
GCLOGFILE="$LOGDIR/launcher.gc.log"

# java command
export JAVA_HOME=$JAVAHOME
JAVACMD="$JAVAHOME/bin/java"

# description
DESC="$NAME Launcher"

# get absolute path
RUNDIR=`pwd` 
# server pid file
PIDFILE="$RUNDIR/launcher.pid"

# delay between spawn attempt bursts (seconds)
SPAWNDELAY=350

# character set
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# is dev or testing
ISDEV=0

# java virtual memory limit
MEM_SIZE=`free|grep Mem|awk '{print $2}'`
JAVAOPTS=""
init_java_heap_size()
{
	if [ $MEM_SIZE -gt 36000000 ] ; then
	    HEAP_SIZE="24g"
	elif [ $MEM_SIZE -gt 24000000 ] ; then
	    HEAP_SIZE="$(( $MEM_SIZE / 1048576 - 9 ))g"
	elif [ $MEM_SIZE -gt 20000000 ] ; then
	    HEAP_SIZE="$(( $MEM_SIZE / 1048576 - 7 ))g"
	elif [ $MEM_SIZE -gt 10000000 ] ; then
	    HEAP_SIZE="$(( $MEM_SIZE / 1048576 - 4 ))g"
	else
	    HEAP_SIZE="4g"
	fi
	
	if [ $ISDEV == 1 ] ; then
		HEAP_SIZE="2g"
	fi
	
	# java additional options
	# -XX:+PrintGCDateStamps
	JAVAOPTS="-Xms$HEAP_SIZE -Xmx$HEAP_SIZE -Duser.timezone=GMT+8 -XX:+ExitOnOutOfMemoryError -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+DisableExplicitGC -Xloggc:$GCLOGFILE -Dspring.profiles.active=dev"
}

#
# Function that checks whether the server is running
#
do_check()
{
    if [ -s "$PIDFILE" ] ; then
        echo "[$PIDFILE] exists!"

        PID=`tail -n 1 $PIDFILE`
        STATUS=`ps h $PID`
        if [ -z "$STATUS" ] ; then
            echo "$PID process does not exists, remove $PIDFILE automatically"
            rm -f $PIDFILE
            return 0
        fi

        echo "OLD $DESC is running, pid=$PID"
        return 1
    fi

    return 0
}

#
# Function that starts the server
#
do_start()
{
    do_check
    if [ $? == 1 ] ; then
        return 1
    fi
    
    init_java_heap_size

    echo "Use Max Memory: $HEAP_SIZE"
    echo "Java Options: $JAVAOPTS"
    echo "Use Version: $APPJAR"
    
    echo -n "$DESC START "
    
    # start service
    # use daemon
    daemon -i -n "$NAME" -L $SPAWNDELAY -r -D "$RUNDIR" -F "$PIDFILE" -o "$LOGFILE" -O "$LOGFILE" -E "$ERRLOGFILE" -- $JAVACMD $JAVAOPTS -jar $APPJAR

    STATUSRESULT="-1"
    for (( i = 0; i < 15 ; i ++ )) ; do
        echo -n "."
        sleep 1

        PID=`tail -n 1 $PIDFILE`
        COUNT=`ps h -p $PID|wc -l`
        if [ $COUNT -eq 1 ] ; then
            STATUSRESULT="0"
            break;
        fi
    done

    if [ "$STATUSRESULT" == "0" ] ; then
        echo " [OK]"
        return 0
    else
        echo " [FAILED]"
        return 1
    fi
}

#
# Function that removes PIDFILE when the server process does not exists 
#
try_remove_pid()
{
    STATUS=`ps h -p $1`
    if [ -z "$STATUS" ] ; then
        rm -f $PIDFILE
    fi
    
    return 0
}

try_force_stop()
{
    # check is daemon used
    DAEMONUSED=`ps h $PID | grep daemon | grep "$NAME"`

    if ! [ -z "$DAEMONUSED" ] ; then
        # stop daemon process

        daemon -n "$NAME" -F "$PIDFILE" --stop
        # force stop child
        CHILDLIST=`ps h -o pid --ppid $PID`
        for CPID in $CHILDLIST ; do
             if ! [ -z "$CPID" ] ; then
                 kill -9 $CPID
             fi
        done
    else
        # stop normal java process 
        kill -9 $PID
    fi

    for (( i = 0; i < 15 ; i ++ )) ; do
        echo -n "."
        sleep 2

        try_remove_pid $PID
        if [ $? == 0 ] ; then
            echo ""
            echo "$DESC STOP [OK]"
            break
        fi
    done

    if [ -s "$PIDFILE" ] ; then
        echo ""
        echo "Force Remove $PIDFILE"
        rm -f $PIDFILE
    fi
}

#
# Function that stops the server
#
do_stop()
{
    if [ -r "$PIDFILE" ] ; then
        # read server PID
        PID=`tail -n 1 $PIDFILE`
        
        # to kill process
        echo -n "to stop server: PID=$PID"
        
        try_force_stop
    else
        echo "can't find the PID file: $PIDFILE"
    fi

    return 0
}

# parse command args
for arg in "$@" ; do
    case $arg in
        dev)
            ISDEV=1
        ;;
    esac
done

# parse command

case $1 in
    stop)
        echo "Force Stopping $DESC ... "
        do_stop
    ;;
    
    start)
        echo "Starting $DESC ... "
        do_start
    ;;
    
    restart)
        echo "Force Restarting $DESC ... "
        do_stop
        do_start
    ;;
    
    *)
        echo "Usage $0 <start (dev) | stop | restart (dev)>"
    ;;
esac

