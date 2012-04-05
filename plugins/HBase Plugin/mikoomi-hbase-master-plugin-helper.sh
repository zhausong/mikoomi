#!/usr/bin/sh

#--------------------------------------------------------------------------------------------
# Expecting the following arguments in order -
# <ignore_value> = this is a parameter that is inserted by Zabbix
#                  It represents hostname/ip address entered in the host configuration.
# host = hostname/ip-address of HBase cluster Master server.
#        This is made available as a macro in host configuration.
# port = Port # on which the Master metrics are available (default = 50070)
#        This is made available as a macro in host configuration.
# zabbix_name = Name by which the HBase Master is configured in Zabbix.
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
# First 2 parameters are required for connecting to HBase Master
# The 3th parameter ZABBIX_NAME is required to be sent back to Zabbix to identify the 
# Zabbix host/entity for which these metrics are destined.
#--------------------------------------------------------------------------------------------
export START_TIME="`date +%s`"
export MASTER_HOST=$1
export MASTER_PORT=$2

export ZABBIX_NAME=$3


#--------------------------------------------------------------------------------------------
# Set and initialize output and log files.
#--------------------------------------------------------------------------------------------
export RAW_FILE="/tmp/${ZABBIX_NAME}.raw"
export DATA_FILE="/tmp/${ZABBIX_NAME}.txt"
export LOG_FILE="/tmp/${ZABBIX_NAME}.log"

> ${RAW_FILE}
> ${DATA_FILE}
> ${LOG_FILE}
> ${RAW_FILE}.regionservers
> ${RAW_FILE}.regionservers_all
> ${DATA_FILE}.regionservers
> ${DATA_FILE}.tables


#--------------------------------------------------------------------------------------------
# Perform a ping check of the host. Having this item/check makes it easy to debug issues.
#--------------------------------------------------------------------------------------------
ping -w 1 -W 1 -c 1 $MASTER_HOST 2>/dev/null 1>/dev/null
if [ $? -gt 0 ]
then
   echo "$ZABBIX_NAME ping_check FAILED"
else
   echo "$ZABBIX_NAME ping_check PASSED"
fi >> ${DATA_FILE}


#--------------------------------------------------------------------------------------------
# Use curl to get the metrics data from HBase Master and use screen-scraping to extract
# metrics. 
# The final result of screen scraping is a file containing data in the following format -
# <ZABBIX_NAME> <METRIC_NAME> <METRIC_VALUE>
#--------------------------------------------------------------------------------------------
curl --silent http://${MASTER_HOST}:${MASTER_PORT}/master.jsp 2>$LOG_FILE  | sed 's/<[^>]*>/|/g' | sed 's/| *| /|/g' | sed 's/: *|/|/g' > ${RAW_FILE}

hbase_version="`egrep '^\|\|HBase Version\|' ${RAW_FILE} | cut -f5 -d'|' | sed 's/,.*//g'`"
hadoop_version="`egrep '^\|\|Hadoop Version\|' ${RAW_FILE} | cut -f5 -d'|' | sed 's/,.*//g'`"
hbase_root_directory="`egrep '^\|\|HBase Root Directory\|' ${RAW_FILE} | cut -f5 -d'|' | sed 's/,.*//g'`"
load_average="`egrep '^\|\|Load average\|' ${RAW_FILE} | cut -f5 -d'|' | sed 's/,.*//g'`"
zookeeper_nodes="`egrep '^\|\|Zookeeper Quorum\|' ${RAW_FILE} | cut -f5 -d'|'`"
table_count="`grep 'table(s) in set.|' ${RAW_FILE} | cut -f2 -d'|' | cut -f2 -d' '`"
total_nodes="`egrep 'requests=.*, regions=.*, usedHeap=.*, maxHeap=' ${RAW_FILE} | wc -l`"


#--------------------------------------------------------------------------------------------
# Save Master metrics as
# <ZABBIX_NAME> <METRIC_NAME> <METRIC_VALUE>
#--------------------------------------------------------------------------------------------
echo "$ZABBIX_NAME hbase_version $hbase_version
$ZABBIX_NAME hadoop_version $hadoop_version
$ZABBIX_NAME hbase_root_directory $hbase_root_directory
$ZABBIX_NAME load_average $load_average
$ZABBIX_NAME zookeeper_nodes $zookeeper_nodes
$ZABBIX_NAME table_count $table_count
$ZABBIX_NAME total_nodes $total_nodes" > $DATA_FILE


#--------------------------------------------------------------------------------------------
# Now identify the regionserver web UI connection info from the Master data and use curl
# to get metrics for each regionserver and each table in HBase
#--------------------------------------------------------------------------------------------

###
# Regionserver metrics
###
grep -i usedHeap ${RAW_FILE} | cut -f4 -d'|' | while read regionserver
do
   export regionserver_host="`echo $regionserver | cut -f1 -d':'`"
   export regionserver_port="`echo $regionserver | cut -f2 -d':'`"
   curl --silent http://${regionserver_host}:${regionserver_port}/regionserver.jsp 2>>$LOG_FILE  |\
        sed 's/<[^>]*>/|/g' | sed 's/| *| /|/g' | sed 's/: *|/|/g' > ${RAW_FILE}.regionservers
   CURL_STATUS=$?
   if [[ $CURL_STATUS != 0 ]]
   then
      CURL_ERROR="`echo $regionserver_host:$regionserver_host,`"
      continue
   fi
   cat ${RAW_FILE}.regionservers >> ${RAW_FILE}.regionservers_all
   requests_to_regionserver="`egrep 'requests=.*, regions=.*, usedHeap=.*, maxHeap=' ${RAW_FILE} | grep $regionserver_host | cut -f9 -d'|' | cut -f2 -d'=' | cut -f1 -d','`"
   number_of_regions="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f2 -d',' | cut -f2 -d'='`"
   number_of_stores="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f3 -d',' | cut -f2 -d'='`"
   number_of_storefiles="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f4 -d',' | cut -f2 -d'='`"
   storefile_index_size_mb="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f5 -d',' | cut -f2 -d'='`"
   memstore_size_mb="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f6 -d',' | cut -f2 -d'='`"
   compaction_queue_size="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f7 -d',' | cut -f2 -d'='`"
   flush_queue_size="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f8 -d',' | cut -f2 -d'='`"
   heap_mem_size_mb="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f9 -d',' | cut -f2 -d'='`"
   heap_mem_upper_limit_mb="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f10 -d',' | cut -f2 -d'='`"
   block_cache_size_bytes="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f11 -d',' | cut -f2 -d'='`"
   block_cache_size_mb="`expr $block_cache_size_bytes / 1024 / 1024`"
   block_cache_free_bytes="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f12 -d',' | cut -f2 -d'='`"
   block_cache_free_mb="`expr $block_cache_free_bytes / 1024 / 1024`"
   blocks_in_block_cache="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f13 -d',' | cut -f2 -d'='`"
   block_cache_hit_count="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f14 -d',' | cut -f2 -d'='`"
   block_cache_miss_count="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f15 -d',' | cut -f2 -d'='`"
   block_cache_evicted_count="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f16 -d',' | cut -f2 -d'='`"
   block_cache_hit_ratio="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f17 -d',' | cut -f2 -d'='`"
   block_cache_hit_caching_ratio="`egrep '^\|\|Metrics\|' ${RAW_FILE}.regionservers | cut -f5 -d'|' | cut -f18 -d',' | cut -f2 -d'='`"

   echo "$regionserver_host requests_to_regionserver $requests_to_regionserver
         $regionserver_host number_of_regions $number_of_regions
         $regionserver_host number_of_stores $number_of_stores
         $regionserver_host number_of_storefiles $number_of_storefiles
         $regionserver_host storefile_index_size_mb $storefile_index_size_mb
         $regionserver_host memstore_size_mb $memstore_size_mb
         $regionserver_host compaction_queue_size $compaction_queue_size
         $regionserver_host flush_queue_size $flush_queue_size
         $regionserver_host heap_mem_size_mb $heap_mem_size_mb
         $regionserver_host heap_mem_upper_limit_mb $heap_mem_upper_limit_mb
         $regionserver_host block_cache_size_mb $block_cache_size_mb
         $regionserver_host block_cache_free_mb $block_cache_free_mb
         $regionserver_host blocks_in_block_cache $blocks_in_block_cache
         $regionserver_host block_cache_hit_count $block_cache_hit_count
         $regionserver_host block_cache_miss_count $block_cache_miss_count
         $regionserver_host block_cache_evicted_count $block_cache_evicted_count
         $regionserver_host block_cache_hit_ratio $block_cache_hit_ratio
         $regionserver_host block_cache_hit_caching_ratio $block_cache_hit_caching_ratio" >> ${DATA_FILE}.regionservers
done

###
# HBase table metrics
###
egrep '^\|\|\-ROOT\-|\|\|\.META\.|\.\|$|memstoreSizeMB'  ${RAW_FILE}.regionservers_all | grep -v 'for further' | \
      while read line1
      do
            read line2
            line_x="`echo $line1 | sed 's/,.*/ /'`"
            line_y="`echo $line_x, $line2`"
            echo $line_y 
            echo $line_y | cut -f1,2 -d',' 
            echo $line_y | cut -f1,3 -d',' 
            echo $line_y | cut -f1,4 -d',' 
            echo $line_y | cut -f1,5 -d',' 
            echo $line_y | cut -f1,6 -d',' 
     done | sed 's/=/ /g' | sed 's/,/ /g' | \
     awk "BEGIN {
                  SUBSEP = \" \"
         }
         {
           table_name = \$1
           metric_name = \"table_\" \$2
           metric_value = \$3
           total_sum[table_name,\" \",metric_name] += \$3
           if (metric_name == \"table_memstoreSizeMB\") {
              total_regions[table_name] += 1
           }
         }
         END {
              for (table_metric_name in total_sum) {
                  print(table_metric_name, total_sum[table_metric_name])
              }
              for (table_name in total_regions) {
                  print(table_name, \"table_region_count\", total_regions[table_name])
              }
             } 
         "  | sed 's/|//g' | egrep -v '\-ROOT\-|\.META\.' | sort >> ${DATA_FILE}.tables


#-------------------------------------------------------------------------------------------
# Next for each regionserver and table metric sort the data based on the value and save the 
# top 3 and bottom 3 metrics to Master metric data file. 
# Each regionserver metric name is in the form <base_metric_name>_[max|min]_#rank
# We also capture the regionserver that constitutes the top/bottom 3.
# In addition, we also capture the "average" for each metric.
#--------------------------------------------------------------------------------------------

###
# Regionserver metrics
###
for metric_name in requests_to_regionserver number_of_regions number_of_stores number_of_storefiles storefile_index_size_mb memstore_size_mb compaction_queue_size flush_queue_size heap_mem_size_mb heap_mem_upper_limit_mb block_cache_size_mb block_cache_free_mb blocks_in_block_cache block_cache_hit_count block_cache_miss_count block_cache_evicted_count block_cache_hit_ratio block_cache_hit_caching_ratio 
do
  grep $metric_name ${DATA_FILE}.regionservers | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, int(\$3)) }" 
  grep $metric_name ${DATA_FILE}.regionservers | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, \"~node\", \$1) }" 
  grep $metric_name ${DATA_FILE}.regionservers | sort -nr -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR,  int(\$3)) }"  
  grep $metric_name ${DATA_FILE}.regionservers | sort -nr -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR, \"~node\",  \$1) }"  
done | sed 's/ ~max~ /_max_/g' | sed 's/ ~min~ /_min_/g' | sed 's/ ~node/_node/g' >> $DATA_FILE
grep -v '^$' ${DATA_FILE}.regionservers | sort -nr -k2 | \
     awk "BEGIN {
           
           }
           {
              metric_name = \$2 
              metric_name_array[\$2] = \$2 
              rec_count[metric_name] += 1
              total_sum[metric_name] += \$3 
           }
           END {
                 for (metric_name in metric_name_array) {
                     print(\"$ZABBIX_NAME\", metric_name, \"~avg\", int(total_sum[metric_name]/rec_count[metric_name]))
                     print(\"$ZABBIX_NAME\", metric_name, \"~total\", total_sum[metric_name])
                 }
           }
         " | sed 's/ *~ */_/' >> ${DATA_FILE}

###
# HBase table metrics
###

#for metric_name in table_memstoreSizeMB table_storefileIndexSizeMB table_storefileSizeMB table_storefiles table_stores table_region_count
#do
#  grep $metric_name ${DATA_FILE}.tables | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, int(\$3)) }" 
#  grep $metric_name ${DATA_FILE}.tables | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, \"~table\", \$1) }" 
#  grep $metric_name ${DATA_FILE}.tables | sort -nr -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR,  int(\$3)) }"  
#  grep $metric_name ${DATA_FILE}.tables | sort -nr -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR, \"~table\",  \$1) }"  
#done | sed 's/ ~max~ /_max_/g' | sed 's/ ~min~ /_min_/g' | sed 's/ ~table/_table/g' >> $DATA_FILE

for metric_name in table_storefileIndexSizeMB table_storefileSizeMB
do
  grep $metric_name ${DATA_FILE}.tables | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, int(\$3)) }" 
  grep $metric_name ${DATA_FILE}.tables | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, \"~table\", \$1) }" 
  grep $metric_name ${DATA_FILE}.tables | sort -nr -k3 | head -10 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR,  int(\$3)) }"  
  grep $metric_name ${DATA_FILE}.tables | sort -nr -k3 | head -10 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR, \"~table\",  \$1) }"  
done | sed 's/ ~max~ /_max_/g' | sed 's/ ~min~ /_min_/g' | sed 's/ ~table/_table/g' >> $DATA_FILE

for metric_name in table_memstoreSizeMB table_storefiles table_stores table_region_count
do
  grep $metric_name ${DATA_FILE}.tables | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, int(\$3)) }" 
  grep $metric_name ${DATA_FILE}.tables | sort -n -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~min~\", NR, \"~table\", \$1) }" 
  grep $metric_name ${DATA_FILE}.tables | sort -nr -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR,  int(\$3)) }"  
  grep $metric_name ${DATA_FILE}.tables | sort -nr -k3 | head -3 | awk "{print(\"$ZABBIX_NAME\", \"$metric_name\", \"~max~\", NR, \"~table\",  \$1) }"  
done | sed 's/ ~max~ /_max_/g' | sed 's/ ~min~ /_min_/g' | sed 's/ ~table/_table/g' >> $DATA_FILE

grep -v '^$' ${DATA_FILE}.tables | sort -nr -k2 | \
     awk "BEGIN {
           
           }
           {
              metric_name = \$2 
              metric_name_array[\$2] = \$2 
              rec_count[metric_name] += 1
              total_sum[metric_name] += \$3 
           }
           END {
                 for (metric_name in metric_name_array) {
                     print(\"$ZABBIX_NAME\", metric_name, \"~avg\", int(total_sum[metric_name]/rec_count[metric_name]))
                     if (metric_name == \"table_storefileSizeMB\") {
                        print(\"$ZABBIX_NAME\", metric_name, \"~total\", total_sum[metric_name])
                     }
                 }
           }
         " | sed 's/ *~ */_/' >> ${DATA_FILE}


#--------------------------------------------------------------------------------------------
# If any curl errors were encountered for the regionserver, then save that list to send to Zabbix
#--------------------------------------------------------------------------------------------
if [[ ! -z $CURL_ERROR ]]
then
   echo "$ZABBIX_NAME curl_errors CURL_ERROR" >> $DATA_FILE
fi


#--------------------------------------------------------------------------------------------
# Check the size of ${DATA_FILE}. If it is not empty, use zabbix_sender to send data to Zabbix.
#--------------------------------------------------------------------------------------------
if [[ ! -z $hbase_version ]]
then
   zabbix_sender -vv -z 127.0.0.1 -i ${DATA_FILE} 2>>$LOG_FILE 1>>$LOG_FILE
   echo  -e "Successfully executed $COMMAND_LINE" >>$LOG_FILE
else
   echo "Error in executing $COMMAND_LINE (probably HBase cluster $MASTER_HOST:$MASTER_PORT is unreachable)" >> $LOG_FILE
fi

export END_TIME="`date +%s`"

expr $END_TIME - $START_TIME
