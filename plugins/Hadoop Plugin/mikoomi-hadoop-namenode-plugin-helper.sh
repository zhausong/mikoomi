#!/usr/bin/sh

#--------------------------------------------------------------------------------------------
# Expecting the following arguments in order -
# <ignore_value> = this is a parameter that is inserted by Zabbix
#                  It represents hostname/ip address entered in the host configuration.
# host = hostname/ip-address of Hadoop cluster NameNode server.
#        This is made available as a macro in host configuration.
# port = Port # on which the NameNode metrics are available (default = 50070)
#        This is made available as a macro in host configuration.
# zabbix_name = Name by which the Hadoop NameNode is configured in Zabbix.
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
# First 2 parameters are required for connecting to Hadoop NameNode
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
# Use curl to get the metrics data from Hadoop NameNode and use screen-scraping to extract
# metrics. 
# The final result of screen scraping is a file containing data in the following format -
# <ZABBIX_NAME> <METRIC_NAME> <METRIC_VALUE>
#--------------------------------------------------------------------------------------------
curl --silent http://${CLUSTER_HOST}:${METRICS_PORT}/dfshealth.jsp 2>$LOG_FILE  | sed 's/<[^>]*>/|/g' | sed 's/| *| /|/g' | sed 's/: *|/|/g' > $RAW_FILE

start_time="`egrep '^\|Started\|' $RAW_FILE | cut -f3 -d'|' | sed 's/^ //'`"
hadoop_version="`egrep '^\|Version\|' $RAW_FILE | cut -f3 -d'|'| cut -f1 -d',' | sed 's/ //'`"
file_and_directory_count="`egrep 'files and directories,.*blocks.*total'  $RAW_FILE | cut -f2 -d' '`"
dfs_blocks="`egrep 'files and directories,.*blocks.*total'  $RAW_FILE | cut -f6 -d' '`"
namenode_process_heap_size="`egrep 'files and directories,.*blocks.*total'  $RAW_FILE | cut -f15 -d' '`"
max_heap_size="`egrep 'files and directories,.*blocks.*total'  $RAW_FILE | cut -f18 -d' '`"
storage_unit="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f4 -d'|' | cut -f3 -d' '`"
configured_cluster_storage="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f4 -d'|' | cut -f2 -d' '`"
dfs_use_storage="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f7 -d'|' | cut -f2 -d' '`"
non_dfs_use_storage="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f10 -d'|' | cut -f2 -d' '`"
available_dfs_storage="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f13 -d'|' | cut -f2 -d' '`"
used_storage_pct="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f16 -d'|' | cut -f2 -d' '`"
available_storage_pct="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f19 -d'|' | cut -f2 -d' '`"
live_nodes="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f23 -d'|' | cut -f2 -d' '`"
dead_nodes="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f27 -d'|' | cut -f2 -d' '`"
decommissioned_nodes="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f31 -d'|' | cut -f2 -d' '`"
under_repllicated_nodes="`egrep '^\|Configured Capacity' $RAW_FILE | cut -f34 -d'|' | cut -f2 -d' '`"

echo "$ZABBIX_NAME start_time $start_time
$ZABBIX_NAME hadoop_version $hadoop_version
$ZABBIX_NAME file_and_directory_count $file_and_directory_count
$ZABBIX_NAME dfs_blocks $dfs_blocks
$ZABBIX_NAME namenode_process_heap_size $namenode_process_heap_size
$ZABBIX_NAME max_heap_size $max_heap_size
$ZABBIX_NAME storage_unit $storage_unit
$ZABBIX_NAME configured_cluster_storage $configured_cluster_storage
$ZABBIX_NAME dfs_use_storage $dfs_use_storage
$ZABBIX_NAME non_dfs_use_storage $non_dfs_use_storage
$ZABBIX_NAME available_dfs_storage $available_dfs_storage
$ZABBIX_NAME used_storage_pct $used_storage_pct
$ZABBIX_NAME available_storage_pct $available_storage_pct
$ZABBIX_NAME live_nodes $live_nodes
$ZABBIX_NAME dead_nodes $dead_nodes
$ZABBIX_NAME decommissioned_nodes $decommissioned_nodes
$ZABBIX_NAME under_repllicated_nodes $under_repllicated_nodes" > $DATA_FILE


#--------------------------------------------------------------------------------------------
# Use curl to get the storage metrics data across all data nodes in the Hadoop Cluster
#--------------------------------------------------------------------------------------------
curl --silent http://${CLUSTER_HOST}:${METRICS_PORT}/dfsnodelist.jsp?whatNodes=LIVE 2>$LOG_FILE  | sed 's/<[^>]*>/|/g' | sed 's/| *| /|/g' | sed 's/: *|/|/g' > $RAW_FILE

max_configured_storage="`grep 'In Service' $RAW_FILE | cut -f7 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
max_configured_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,7 -d '|' | grep $max_configured_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"
min_configured_storage="`grep 'In Service' $RAW_FILE | cut -f7 -d'|' | sed 's/^ //' | sort -n | head -1 `"
min_configured_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,7 -d '|' | grep $min_configured_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"

max_used_storage="`grep 'In Service' $RAW_FILE | cut -f8 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
max_used_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,8 -d '|' | grep $max_used_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"
min_used_storage="`grep 'In Service' $RAW_FILE | cut -f8 -d'|' | sed 's/^ //' | sort -n | head -1 `"
min_used_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,8 -d '|' | grep $min_used_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"

max_non_dfs_used_storage="`grep 'In Service' $RAW_FILE | cut -f9 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
max_non_dfs_used_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,9 -d '|' | grep $max_non_dfs_used_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"
min_non_dfs_used_storage="`grep 'In Service' $RAW_FILE | cut -f9 -d'|' | sed 's/^ //' | sort -n | head -1 `"
min_non_dfs_used_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,9 -d '|' | grep $min_non_dfs_used_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"

max_free_storage="`grep 'In Service' $RAW_FILE | cut -f10 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
max_free_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,10 -d '|' | grep $max_free_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"
min_free_storage="`grep 'In Service' $RAW_FILE | cut -f10 -d'|' | sed 's/^ //' | sort -n | head -1 `"
min_free_storage_node_name="`grep 'In Service' $RAW_FILE | cut -f4,10 -d '|' | grep $min_free_storage | cut -f1 -d'|' | sed 's/^ //' | head -1 `"

max_used_storage_pct="`grep 'In Service' $RAW_FILE | cut -f11 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
max_used_storage_pct_node_name="`grep 'In Service' $RAW_FILE | cut -f4,11 -d '|' | grep $max_used_storage_pct | cut -f1 -d'|' | sed 's/^ //' | head -1 `"
min_used_storage_pct="`grep 'In Service' $RAW_FILE | cut -f11 -d'|' | sed 's/^ //' | sort -n | head -1 `"
min_used_storage_pct_node_name="`grep 'In Service' $RAW_FILE | cut -f4,11 -d '|' | grep $min_used_storage_pct | cut -f1 -d'|' | sed 's/^ //' | head -1 `"

max_free_storage_pct="`grep 'In Service' $RAW_FILE | cut -f21 -d'|' | sed 's/^ //' | sort -nr | head -1 `"
max_free_storage_pct_node_name="`grep 'In Service' $RAW_FILE | cut -f4,21 -d '|' | grep $max_free_storage_pct | cut -f1 -d'|' | sed 's/^ //' | head -1 `"
min_free_storage_pct="`grep 'In Service' $RAW_FILE | cut -f21 -d'|' | sed 's/^ //' | sort -n | head -1 `"
min_free_storage_pct_node_name="`grep 'In Service' $RAW_FILE | cut -f4,21 -d '|' | grep $min_free_storage_pct | cut -f1 -d'|' | sed 's/^ //' | head -1 `"

node_level_storage_unit="`grep 'Configured |Capacity' $RAW_FILE | cut -f2 -d '(' | cut -f1 -d ')'`"


echo "$ZABBIX_NAME max_configured_storage $max_configured_storage
$ZABBIX_NAME max_configured_storage_node_name $max_configured_storage_node_name
$ZABBIX_NAME min_configured_storage $min_configured_storage
$ZABBIX_NAME min_configured_storage_node_name $min_configured_storage_node_name
$ZABBIX_NAME max_used_storage $max_used_storage
$ZABBIX_NAME max_used_storage_node_name $max_used_storage_node_name
$ZABBIX_NAME min_used_storage $min_used_storage
$ZABBIX_NAME min_used_storage_node_name $min_used_storage_node_name
$ZABBIX_NAME max_non_dfs_used_storage $max_non_dfs_used_storage
$ZABBIX_NAME max_non_dfs_used_storage_node_name $max_non_dfs_used_storage_node_name
$ZABBIX_NAME min_non_dfs_used_storage $min_non_dfs_used_storage
$ZABBIX_NAME min_non_dfs_used_storage_node_name $min_non_dfs_used_storage_node_name
$ZABBIX_NAME max_free_storage $max_free_storage
$ZABBIX_NAME max_free_storage_node_name $max_free_storage_node_name
$ZABBIX_NAME min_free_storage $min_free_storage
$ZABBIX_NAME min_free_storage_node_name $min_free_storage_node_name
$ZABBIX_NAME max_used_storage_pct $max_used_storage_pct
$ZABBIX_NAME max_used_storage_pct_node_name $max_used_storage_pct_node_name
$ZABBIX_NAME min_used_storage_pct $min_used_storage_pct
$ZABBIX_NAME min_used_storage_pct_node_name $min_used_storage_pct_node_name
$ZABBIX_NAME max_free_storage_pct $max_free_storage_pct
$ZABBIX_NAME max_free_storage_pct_node_name $max_free_storage_pct_node_name
$ZABBIX_NAME min_free_storage_pct $min_free_storage_pct
$ZABBIX_NAME min_free_storage_pct_node_name $min_free_storage_pct_node_name
$ZABBIX_NAME node_level_storage_unit $node_level_storage_unit" >> $DATA_FILE


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
