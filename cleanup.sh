#!/bin/bash 

clear # clear terminal window
###################################
#tidy up after completed configuration
function cleanup {
    cd ..
    rm -R tmp/
}
#################################
#only root is allowed to change system settings
if (( $EUID != 0 )); then
    echo "Installation must be run with root permission."
    exit
fi
# stop service
systemctl stop tomcat
systemctl disable tomcat
systemctl daemon-reload

rm -R /opt/tomcat
cleanup

