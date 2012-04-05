#!/usr/bin/sh

nohup "`dirname $0`"/mikoomi-hbase-master-plugin-helper.sh $* 1>/dev/null 2>/dev/null & 
echo "Ok"
exit
