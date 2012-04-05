#!/usr/bin/sh

#--------------------------------------------------------------------------------------------
# Expecting the following arguments in order -
# <ignore_value> = this is a parameter that is inserted by Zabbix
#                  It represents hostname/ip address entered in the host configuration.
# solr_admin_stats_url = This is the URL of the Solr admin stats page.
#        This is made available as a macro in host configuration.
# zabbix_name = Name by which the Solr host is configured in Zabbix.
#        This is made available as a macro in host configuration.
#--------------------------------------------------------------------------------------------

COMMAND_LINE="$0 $*" 

export SCRIPT_NAME="$0"

export DIR_NAME="`dirname $SCRIPT_NAME`"
export PHP_SCRIPT="$DIR_NAME/mikoomi-solr-helper.php"

#--------------------------------------------------------------------------------------------
# Ignore the first parameter - which is ALWAYS inserted implicitly by Zabbix
#--------------------------------------------------------------------------------------------
shift ;

usage() {
   echo "Usage: $SCRIPT_NAME <discarded_value> <solr_url> <zabbix_name>"
}

if [ $# -ne 2 ]
then
    usage ;
    exit ;
fi


#--------------------------------------------------------------------------------------------
# First parameter are required for connecting to Solr.
# The 2nd parameter ZABBIX_NAME is required to be sent back to Zabbix to identify the 
# Zabbix host/entity for which these metrics are destined.
#--------------------------------------------------------------------------------------------
export START_TIME="`date +%s`"
export SOLR_ADMIN_STATS_URL=$1

export ZABBIX_NAME=$2


#--------------------------------------------------------------------------------------------
# Set and initialize output and log files.
#--------------------------------------------------------------------------------------------
export RAW_FILE="/tmp/${ZABBIX_NAME}.raw"
export DATA_FILE="/tmp/${ZABBIX_NAME}.txt"
export LOG_FILE="/tmp/${ZABBIX_NAME}.log"

> ${RAW_FILE}
> ${DATA_FILE}
> ${LOG_FILE}

#--------------------------------------------------------------------------------------------
# 
#--------------------------------------------------------------------------------------------
echo "curl $SOLR_ADMIN_STATS_URL > $RAW_FILE 2>/dev/null " >${LOG_FILE}
curl $SOLR_ADMIN_STATS_URL > $RAW_FILE 2>/dev/null
if [[ $? -ne 0 ]]
then
   echo "Problem !!!!!"
   exit
fi

# Some numbers reported by Solr could be very small and are reported in scientific notation
# which is not understood by Zabbix. Since they are very small, rounding them to 0
php $PHP_SCRIPT $RAW_FILE $ZABBIX_NAME | sed 's/[0-9.]*E-[0-9]/0/' > $DATA_FILE

#--------------------------------------------------------------------------------------------
# Check the size of ${DATA_FILE}. If it is not empty, use zabbix_sender to send data to Zabbix.
#--------------------------------------------------------------------------------------------
zabbix_sender -vv -z 127.0.0.1 -i ${DATA_FILE} 2>>$LOG_FILE 1>>$LOG_FILE

export END_TIME="`date +%s`"

expr $END_TIME - $START_TIME
