#!/usr/bin/sh

#--------------------------------------------------------------------------------------------
# Expecting the following arguments in order -
# <ignore_value> = this is a parameter that is inserted by Zabbix
#                  It represents hostname/ip address entered in the host configuration.
# host = hostname/ip-address of Hadoop cluster JobTracker server.
#        This is made available as a macro in host configuration.
# port = Port # on which the JobTracker metrics are available (default = 50030)
#        This is made available as a macro in host configuration.
# zabbix_name = Name by which the Hadoop JobTracker is configured in Zabbix.
#        This is made available as a macro in host configuration.
#--------------------------------------------------------------------------------------------

COMMAND_LINE="$0 $*" 

export SCRIPT_NAME="$0"

#--------------------------------------------------------------------------------------------
# Ignore the first parameter - which is ALWAYS inserted implicitly by Zabbix
#--------------------------------------------------------------------------------------------
shift ;

usage() {
   echo "Usage: $SCRIPT_NAME <discarded_value> <host> <port> <zabbix_name>"
}

if [ $# -ne 3 ]
then
    usage ;
    exit ;
fi


#--------------------------------------------------------------------------------------------
# First 2 parameters are required for connecting to Hadoop JobTracker
# The 3th parameter ZABBIX_NAME is required to be sent back to Zabbix to identify the 
# Zabbix host/entity for which these metrics are destined.
#--------------------------------------------------------------------------------------------
export CLUSTER_HOST=$1

export METRICS_PORT=$2

export ZABBIX_NAME=$3


#--------------------------------------------------------------------------------------------
# Set the data output file and the log fle from zabbix_sender
#--------------------------------------------------------------------------------------------
export RAW_FILE="/tmp/${ZABBIX_NAME}.raw"
export DATA_FILE="/tmp/${ZABBIX_NAME}.txt"
export LOG_FILE="/tmp/${ZABBIX_NAME}.log"


#--------------------------------------------------------------------------------------------
# Use curl to get the metrics data from Hadoop JobTracker and use screen-scraping to extract
# metrics. 
# The final result of screen scraping is a file containing data in the following format -
# <ZABBIX_NAME> <METRIC_NAME> <METRIC_VALUE>
#--------------------------------------------------------------------------------------------
curl --silent http://${CLUSTER_HOST}:${METRICS_PORT}/jobtracker.jsp 2>$LOG_FILE  | sed 's/<[^>]*>/|/g' | sed 's/| *| /|/g' | sed 's/: *|/|/g' > $RAW_FILE

jobtracker_state="`egrep '^\|State\|' $RAW_FILE | cut -f3 -d'|' | sed 's/ //'`"
jobtracker_start_time="`egrep '\|Started\|' $RAW_FILE | cut -f3 -d'|' | sed 's/^ //'`"
hadoop_version="`egrep '\|Version\|' $RAW_FILE | cut -f3 -d'|' | sed 's/^ //' | sed 's/,//'`"
running_map_tasks="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f3 -d'|'`"
running_reduce_tasks="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f5 -d'|'`"
total_jobs_submitted="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f7 -d'|'`"
total_nodes="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f10 -d'|'`"
occupied_map_slots="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f13 -d'|'`"
occupied_reduce_slots="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f15 -d'|'`"
reserved_map_slots="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f17 -d'|'`"
reserved_reduce_slots="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f19 -d'|'`"
map_task_capacity="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f21 -d'|'`"
reduce_task_capacity="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f23 -d'|'`"
avg_task_capacity_per_node="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f25 -d'|'`"
blacklisted_nodes="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f28 -d'|'`"
excluded_nodes="`grep -A 1 'Running Map Tasks' $RAW_FILE | tail -1 | cut -f32 -d'|'`"
running_jobs="`sed -n '1,/Completed Jobs/p' $RAW_FILE| sed -n '/Map % Complete/,$ p' | grep job_| wc -l`"
completed_jobs="`sed -n '/Completed Jobs/,$p' $RAW_FILE| sed '/Failed Jobs/,$d'| grep -i job_| wc -l`"
failed_jobs="`sed -n '/Failed Jobs/,$p' $RAW_FILE| sed '/Retired Jobs/,$d'| grep job_ | wc -l`"
retired_jobs="`sed -n '/^|Retired Jobs|/,$p' $RAW_FILE| sed '/^$/,$d'| grep job_| wc -l`"

echo "$ZABBIX_NAME jobtracker_state $jobtracker_state
$ZABBIX_NAME jobtracker_start_time $jobtracker_start_time
$ZABBIX_NAME hadoop_version $hadoop_version
$ZABBIX_NAME running_map_tasks $running_map_tasks
$ZABBIX_NAME running_reduce_tasks $running_reduce_tasks
$ZABBIX_NAME total_jobs_submitted $total_jobs_submitted
$ZABBIX_NAME total_nodes $total_nodes
$ZABBIX_NAME occupied_map_slots $occupied_map_slots
$ZABBIX_NAME occupied_reduce_slots $occupied_reduce_slots
$ZABBIX_NAME reserved_map_slots $reserved_map_slots
$ZABBIX_NAME reserved_reduce_slots $reserved_reduce_slots
$ZABBIX_NAME map_task_capacity $map_task_capacity
$ZABBIX_NAME reduce_task_capacity $reduce_task_capacity
$ZABBIX_NAME avg_task_capacity_per_node $avg_task_capacity_per_node
$ZABBIX_NAME blacklisted_nodes $blacklisted_nodes
$ZABBIX_NAME excluded_nodes $excluded_nodes
$ZABBIX_NAME running_jobs $running_jobs
$ZABBIX_NAME completed_jobs $completed_jobs
$ZABBIX_NAME failed_jobs $failed_jobs
$ZABBIX_NAME retired_jobs $retired_jobs " >  $DATA_FILE


#--------------------------------------------------------------------------------------------
# Use curl to get node level map and reduce task data
#--------------------------------------------------------------------------------------------
curl --silent http://${CLUSTER_HOST}:${METRICS_PORT}/machines.jsp?type=active 2>$LOG_FILE  | sed 's/<[^>]*>/|/g' | sed 's/| *| /|/g' | sed 's/: *|/|/g' | grep tracker_ | sed 's/^|||||//' | sed 's/^|||//' | grep -v 'Highest Failures' > $RAW_FILE

max_running_tasks="`grep 'tracker_' $RAW_FILE | cut -f6 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
min_running_tasks="`grep 'tracker_' $RAW_FILE | cut -f6 -d'|' | sed 's/^ //' | sort -n | head -1 `"
max_configured_map_tasks="`grep 'tracker_' $RAW_FILE | cut -f8 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
min_configured_map_tasks="`grep 'tracker_' $RAW_FILE | cut -f8 -d'|' | sed 's/^ //' | sort -n | head -1 `"
max_configured_reduce_tasks="`grep 'tracker_' $RAW_FILE | cut -f10 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
min_configured_reduce_tasks="`grep 'tracker_' $RAW_FILE | cut -f10 -d'|' | sed 's/^ //' | sort -n | head -1 `"

#--------------------------------------------------------------------------------------------
# Perform a ping check of the host. Having this item/check makes it easy to debug issues.
#--------------------------------------------------------------------------------------------
ping -w 1 -W 1 -c 1 $CLUSTER_HOST 2>/dev/null 1>/dev/null
if [ $? -gt 0 ]
then
   echo "$ZABBIX_NAME ping_check FAILED"
else
   echo "$ZABBIX_NAME ping_check PASSED"
fi >> $DATA_FILE


#--------------------------------------------------------------------------------------------
# Check the size of $DATA_FILE. If it is not empty, use zabbix_sender to send data to Zabbix.
#--------------------------------------------------------------------------------------------
if [[ -s $DATA_FILE ]]
then
   zabbix_sender -vv -z 127.0.0.1 -i $DATA_FILE 2>>$LOG_FILE 1>>$LOG_FILE
   echo  -e "Successfully executed $COMMAND_LINE" >>$LOG_FILE
else
   echo "Error in executing $COMMAND_LINE" >> $LOG_FILE
fi
