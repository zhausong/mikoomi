#!/bin/bash
PATH=$PATH:/opt/mikoomi/bin:/opt/mikoomi/admin:/opt/mikoomi/plugins:/opt/mikoomi/alertscripts
export PATH
shift
echo 0
/usr/bin/php /opt/mikoomi/plugins/mikoomi-aws-ec2-overview-plugin.php $* 2>/dev/null 1>/dev/null
