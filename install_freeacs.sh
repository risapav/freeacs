#!/bin/bash 

clear # clear terminal window
TRUE='1'
TOMCAT="tomcat8"
MYSQL="mysql-server-5.7"
JDK="openjdk-8-jre-headless"

#mysql variables
ACCESSKEY="[client]\nuser=%s\npassword=%s\nhost=localhost\n" # secure mysql access
MYSQLROOTPW=""	# root password
ACSDBPW=""	# acs user password
OLDACSDBPW=""	# old acs user password

#################################
#only root is allowed to change system settings
function are_you_root {
	
    if (( $EUID != 0 )); then
        echo "Installation must be run with root permission."
        exit
    fi
	
    mkdir tmp
    cd tmp
}
####################################
#install/update necessary applications
function install_apps {
    apt-get update
    apt-get install zip unzip
    apt-get install $MYSQL
    apt-get install $JDK
#    apt-get install $TOMCAT $TOMCAT-docs $TOMCAT-examples $TOMCAT-admin
}
####################################
#prepare ports on which tomcat will be listen to
function prepare_ports {
   
    PORTS=(100 8080 443)

    for i in "${PORTS[@]}"
    do
        echo "/etc/authbind/byport/$i"
        touch /etc/authbind/byport/$i
        echo "500 /etc/authbind/byport/$i"
        chmod 500 /etc/authbind/byport/$i
        echo "$TOMCAT /etc/authbind/byport/$i"
        chown $TOMCAT /etc/authbind/byport/$i
    done
    #Tomcat must own the cacerts file
    echo "$TOMCAT:$TOMCAT"
    chown $TOMCAT:$TOMCAT /etc/ssl/certs/java/cacerts
}
###################################
#load prepared web app files from repository
function download_resources {  

    FILES=( Fusion_Installation.pdf create_db.sql install_db.sql core.war monitor.war shell.jar spp.war stun.war syslog.war tr069.war web.war ws.war tables.zip )

    for i in "${FILES[@]}" 
    do
        if [ ! -f "$i" ] ; then
            echo "  downloading https://raw.githubusercontent.com/risapav/freeacs/master/download/$i"
            wget --verbose --no-check-certificate --content-disposition https://raw.githubusercontent.com/risapav/freeacs/master/download/$i
        fi 
    done
}
#################################
# add xaps user into mysql
function create_freeacsdbuser {
    # create DB xaps if not exist
    mysql --defaults-extra-file=root.pw < create_db.sql
    # freeacsdbuserok=`mysql --defaults-extra-file=root.pw -e "SELECT count(user) FROM mysql.user where user = 'xaps'" #2> /dev/null | tail -n1`
    printf "GRANT ALL ON xaps.* TO \`xaps\` IDENTIFIED BY '%s';\n" "$ACSDBPW" > mkdb.sql
    printf "GRANT ALL ON xaps.* TO \`xaps\`@\`localhost\` IDENTIFIED BY '%s';\n" "$ACSDBPW" >> mkdb.sql
    # make user xaps to access DB xaps
    mysql --defaults-extra-file=root.pw < mkdb.sql
}
#################################
# transfer all tables into mysql DB
function load_database_tables {
    # transfer all tables into xaps DB
    mysql --defaults-extra-file=user.pw < install_db.sql #2> .tmp
}
###################################
#setup mysql database to accept tomcat users
function database_setup {
    mkdir tables 2> /dev/null
    unzip -o -q -d tables/ tables.zip

    # read root password to access mysql 
    verified='n'
    until [ $verified == 'y' ] || [ $verified == 'Y' ]; do
        read -p "State the root password for the MySQL database: " MYSQLROOTPW
        read -p "Is [$MYSQLROOTPW] correct? (y/n) " verified
    done

    printf $ACCESSKEY "root" "$MYSQLROOTPW" > root.pw

    echo ""
    echo "Specify/create the password for the FreeACS MySQL user."
    echo "NB! The FreeACS MySQL user name defaults to 'xaps'"
    echo "NB! If the user has been created before: Do not try "
    echo "to change the password - this script will not handle "
    echo "the change of password into MySQL, but the configuration"
    echo "files will be changed - causing a password mismatch!!"

    # read password to prepare xaps user
    verified='n'
    until [ $verified == 'y' ] || [ $verified == 'Y' ]; do
        read -p "Specify/create the password for the FreeACS MySQL user: " ACSDBPW
        read -p "Is [$ACSDBPW] correct? (y/n) " verified
    done

    printf $ACCESSKEY "xaps" "$ACSDBPW" > user.pw
    # create database xaps
    create_freeacsdbuser
    # transfer tables into database xaps
    load_database_tables
}
###################################
#configure tomcat server
function tomcat_setup {

    mkdir /var/lib/$TOMCAT/shell 2> /dev/null
    echo ""
    # Extracts and removes all xaps-*.properties files from the jar/war archives 
    ARCHIVES=( core.war monitor.war spp.war stun.war syslog.war tr069.war web.war ws.war )

    for i in "${ARCHIVES[@]}"
    do
        unzip -j -q -o $i WEB-INF/classes/xaps*.properties > /dev/null 2>&1
        zip -d -q $i WEB-INF/classes/xaps*.properties > /dev/null 2>&1
    done

    unzip -j -q -o shell.jar xaps-shell*.properties > /dev/null 2>&1
    zip -d -q shell.jar xaps-shell*.properties > /dev/null 2>&1

    # Changes the default FreeACS MySQL password in the property files
    OLDACSDBPW=`grep -e "^db.xaps.url" xaps-tr069.properties | cut -d" " -f3 | cut -b6-40 | cut -d"@" -f1`
    sed -i 's/xaps\/'$OLDACSDBPW'/xaps\/'$ACSDBPW'/g' *.properties

    echo "NB! Important! Checks to see whether you have some existing" 
    echo "configuration of FreeACS. In that case, a diff between the" 
    echo "existing config and the new default config is shown. The new"
    echo "default config is NOT applied, but you should inspect the"
    echo "diff to understand if new properties are added or old ones"
    echo "removed. If so, please update your property files accordingly." 
    echo "The diff is printed to file config-diff.txt.	"

    MODULES=( core monitor spp stun syslog tr069 web ws )
    echo "" > config-diff.txt
    for j in "${MODULES[@]}"
    do
        PROPERTYFILES=( xaps-$j.properties xaps-$j-logs.properties )
        for propertyfile in "${PROPERTYFILES[@]}"
        do
            overwrite=''
            if [ -f /var/lib/$TOMCAT/common/$propertyfile ] ; then
                diff /var/lib/$TOMCAT/common/$propertyfile $propertyfile > .tmp
                if [ -s .tmp ] ; then
                    echo "  $propertyfile diff found, added diff to config-diff.txt - please inspect!"
                    echo "$propertyfile diff:" >> config-diff.txt
                    echo "------------------------------------------------" >> config-diff.txt
                    cat .tmp >> config-diff.txt
                    echo "" >> config-diff.txt
                else 
                    mv -f $propertyfile /var/lib/$TOMCAT/common
            fi
              else
                mv -f $propertyfile /var/lib/$TOMCAT/common
            fi      
        done    
    done

    PROPERTYFILES=( xaps-shell.properties xaps-shell-logs.properties )
    for propertyfile in "${PROPERTYFILES[@]}"
    do
        if [ -f /var/lib/$TOMCAT/shell/$propertyfile ] ; then
            diff /var/lib/$TOMCAT/shell/$propertyfile $propertyfile > .tmp
            if [ -s .tmp ] ; then
                echo "  $propertyfile diff found, added diff to config-diff.txt - please inspect!"
                echo "$propertyfile diff:" >> config-diff.txt
                echo "------------------------------------------------" >> config-diff.txt
                cat .tmp >> config-diff.txt
                echo "" >> config-diff.txt
            else
                mv -f $propertyfile /var/lib/$TOMCAT/shell
            fi
        else
            mv -f $propertyfile /var/lib/$TOMCAT/shell
        fi      
    done
    echo "All property files have been checked. Those which weren't found"
    echo "in the system have been installed."
    echo ""

    # Copies all war, jar and property files into their correct location
    # This actually deploys the application into Tomcat  
    mv *.war /var/lib/$TOMCAT/webapps
    mv *.jar /var/lib/$TOMCAT/shell
    echo "All WAR/JAR/property files have been moved to Tomcat - servers have been deployed!"
  
    # Makes requests to http://hostname/ redirect to http://hostname/web
    rm -rf /var/lib/$TOMCAT/webapps/ROOT
    ln -s /var/lib/$TOMCAT/webapps/web /var/lib/$TOMCAT/webapps/ROOT
  
    # Changes all ownership and permissions - $TOMCAT user owns everything
    chown -R $TOMCAT:$TOMCAT /var/lib/$TOMCAT
    chmod g+w /var/lib/$TOMCAT/common /var/lib/$TOMCAT/webapps /var/lib/$TOMCAT/shell
    chmod g+s /var/lib/$TOMCAT/common /var/lib/$TOMCAT/webapps /var/lib/$TOMCAT/shell
    echo "All file ownership and permissions have been transferred to the $TOMCAT user"
    echo ""


    groupadd tomcat
    useradd -s /bin/false -g tomcat -d /opt/tomcat tomcat
    mkdir /opt/tomcat /opt/tomcat/conf /opt/tomcat/webapps /opt/tomcat/work /opt/tomcat/temp /opt/tomcat/logs

    wget http://apache.mirrors.ionfish.org/tomcat/tomcat-8/v8.5.24/bin/apache-tomcat-8.5.24.tar.gz
    tar -xzvf apache-tomcat-8.5.24.tar.gz
    mv apache-tomcat-8.5.24/* /opt/tomcat

    chgrp -R tomcat /opt/tomcat
    chown -R tomcat /opt/tomcat
    chmod -R 755 /opt/tomcat

    JAVA=$(update-java-alternatives -l | awk '{print $NF}')

    cat > /etc/systemd/system/tomcat.service << EOF
    [Unit]
    Description=Apache Tomcat Web Server
    After=network.target

    [Service]
    Type=forking

    Environment=JAVA_HOME=$JAVA/jre
    Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
    Environment=CATALINA_HOME=/opt/tomcat
    Environment=CATALINA_BASE=/opt/tomcat
    Environment='CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC'
    Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

    ExecStart=/opt/tomcat/bin/startup.sh
    ExecStop=/opt/tomcat/bin/shutdown.sh

    User=tomcat
    Group=tomcat
    UMask=0007
    RestartSec=15
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOF

    # enable firewall ports
    PORTS=(100 8080 443)

    for i in "${PORTS[@]}"
    do
        ufw allow $i
    done

    # run service
    systemctl daemon-reload
    systemctl start tomcat
    #systemctl status tomcat
    systemctl enable tomcat
}
###################################
#configure remote shell accesible via web
function shell_setup {
    
    echo "cd /var/lib/$TOMCAT/shell" > /usr/bin/fusionshell
    echo "java -jar shell.jar" >> /usr/bin/fusionshell
    chmod 755 /usr/bin/fusionshell

    verified='n'
    until [ $verified == 'y' ] || [ $verified == 'Y' ]; do
        read -p "What is your Ubuntu username (will add $TOMCAT group to this user): " ubuntuuser
        read -p "Is [$ubuntuuser] correct? (y/n) " verified
    done
    usermod -a -G $TOMCAT $ubuntuuser

    echo ""
    echo "Shell is set up and can be accessed using the 'fusionshell' command."
    echo "NB! The group change will not take effect before next login with "
    echo "your ubuntu user. Running the shell before that can cause some error"
    echo "messages."
    echo ""
}
###################################
#tidy up after completed configuration
function cleanup {
    cd ..
    rm -R tmp/
}
###################################
#main app
###################################
are_you_root
#install_apps 
#prepare_ports
#download_resources
#database_setup
#tomcat_setup
#apt-get update

#shell_setup
cleanup
###################################
