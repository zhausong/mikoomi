#!/bin/bash
PATH=$PATH:/etc/zabbix/externalscripts:/home/zabbix/bin:/bin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/local/sbin
export PATH
shift
BASE_DIR="`dirname $0`"
/usr/bin/php $BASE_DIR/mikoomi-aws-ec2-overview-plugin.php $* 2>/dev/null 1>/dev/null
