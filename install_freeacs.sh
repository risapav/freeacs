#!/bin/bash -xv

clear # clear terminal window
TRUE='1'
TOMCAT="tomcat8"
MYSQL="mysql-server-5.7"
JDK="openjdk-8-jre-headless"

#mysql variables
MYSQLROOTPW=""	# root password
ACSDBPW=""		# acs user password
OLDACSDBPW=""	# old acs user password

#################################
#only root is allowed to change system settings
function are_you_root {
    echo "Prepare system for installation"
    read -p "Do you run this script with sudo (root) permission? (y/n) " yn
    case $yn in
      [Yy]* ) echo "" ;;
      *     ) echo "Installation must be run with root permission."
              exit;;
    esac
    mkdir tmp
}
####################################
#install/update necessary applications
function install_apps {
    apt-get update
    apt-get install zip unzip
    apt-get install $MYSQL
    apt-get install $JDK
    apt-get install $TOMCAT
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

    FILES=( Fusion_Installation.pdf core.war install2013R1.sql monitor.war shell.jar spp.war stun.war syslog.war tr069.war web.war ws.war tables.zip )

    for i in "${FILES[@]}" 
    do
        if [ ! -f "$i" ] ; then
            echo "  downloading https://raw.githubusercontent.com/risapav/freeacs/master/download/$i"
            wget -P tmp --verbose --no-check-certificate --content-disposition https://raw.githubusercontent.com/risapav/freeacs/master/download/$i
        fi 
    done
}
#################################
# add xaps user into mysql
function create_freeacsdbuser {
    freeacsdbuserok=`mysql -uroot -p$MYSQLROOTPW -e "SELECT count(user) FROM mysql.user where user = 'xaps'" 2> /dev/null | tail -n1`
echo "pozor1 $freeacsdbuserok"
    if [ "$freeacsdbuserok" != '2' ] ; then
        mysql -uroot -p$MYSQLROOTPW -e "CREATE DATABASE xaps" 2> /dev/null
        mysql -uroot -p$MYSQLROOTPW xaps -e "GRANT ALL ON xaps.* TO 'xaps' IDENTIFIED BY '$ACSDBPW'"  2> tmp/.tmp
        mysql -uroot -p$MYSQLROOTPW xaps -e "GRANT ALL ON xaps.* TO 'xaps'@'localhost' IDENTIFIED BY '$ACSDBPW'" 2>> tmp/.tmp
        freeacsdbuserok=`mysql -uroot -p$MYSQLROOTPW -e "SELECT count(user) FROM mysql.user where user = 'xaps'" 2> /dev/null | tail -n1`
echo "pozor2 $freeacsdbuserok"
        if [ "$freeacsdbuserok" != '2' ] ; then
            echo "The FreeACS MySQL database users 'xaps' and 'xaps'@'localhost' is not found"
            echo "in the mysql.user table. Maybe you stated the wrong MySQL root password??"
            echo "Please make sure this is corrected, either by running this script again with"
            echo "the correct root password or by running the equivalent of the following"
            echo " SQL-statements:"
            echo ""
            echo "Running as MySQL Root user:"
            echo "  CREATE DATABASE xaps"
            echo "  GRANT ALL ON xaps.* TO 'xaps' IDENTIFIED BY 'A_PASSWORD'"
            echo "  GRANT ALL ON xaps.* TO 'xaps'@'localhost' IDENTIFIED BY 'A_PASSWORD'"
            echo ""
            echo "Below are stderr output from the commands above - they may indicate"
            echo "the problem at hand:"
            echo "------------------------------------------------"
            cat tmp/.tmp
            echo "------------------------------------------------"
            echo ""
            exit
        else
            echo ""
            echo "The FreeACS MySQL database user is OK. "
            echo ""
        fi
    else
        echo ""
        echo "The FreeACS MySQL database user is OK. "
        echo ""
    fi
}
#################################
# transfer all tables into mysql DB
function load_database_tables {
    echo ""
    echo "Loads all FreeACS table defintions into MySQL"
    mysql -uxaps -p$ACSDBPW xaps < tmp/install2013R1.sql 2> tmp/.tmp
    installtables=`wc -l tmp/.tmp | cut -b1-1`
echo "pozor 3 $installtables"
cat tmp/.tmp
    if [ "$installtables" != '1' ] ; then
        echo "The output from the installation of the tables indicate some"
        echo "errors occurred:"
        echo "------------------------------------------------"
        cat tmp/.tmp
        echo "------------------------------------------------"  
        exit
    else
        echo "Loading of all FreeACS tables was OK"
    fi
}
###################################
#setup mysql database to accept tomcat users
function database_setup {

    mkdir tmp/tables 2> /dev/null
    unzip -o -q -d tmp/tables/ tmp/tables.zip

    verified='n'
    until [ $verified == 'y' ] || [ $verified == 'Y' ]; do
        read -p "State the root password for the MySQL database: " MYSQLROOTPW
        read -p "Is [$MYSQLROOTPW] correct? (y/n) " verified
    done
    echo ""
    echo "Specify/create the password for the FreeACS MySQL user."
    echo "NB! The FreeACS MySQL user name defaults to 'xaps'"
    echo "NB! If the user has been created before: Do not try "
    echo "to change the password - this script will not handle "
    echo "the change of password into MySQL, but the configuration"
    echo "files will be changed - causing a password mismatch!!"

    verified='n'
    until [ $verified == 'y' ] || [ $verified == 'Y' ]; do
        read -p "Specify/create the password for the FreeACS MySQL user: " ACSDBPW
        read -p "Is [$ACSDBPW] correct? (y/n) " verified
    done
    echo ""
    create_freeacsdbuser

    tablepresent=`mysql -uxaps -p$ACSDBPW xaps -e "SHOW TABLES LIKE 'unit_type'" 2> /dev/null  | wc -l`
    if [ "$tablepresent" == "2" ] ; then
        echo "WARNING! An important FreeACS table is found in the database,"
            echo "indicating that the database tables have already been loaded. "
            echo "If you decide to load all table definitions, you will delete "
            echo "ALL FreeACS data in the database, and start over."
        verified='n'
        until [ $verified == 'y' ] || [ $verified == 'Y' ]; 
        do
            read -p "Load all table defintions (and overwriting all data)? (y/n): " yn
            read -p "Is [$yn] correct? (y/n) " verified
        done
        echo 
        if [ "$yn" == 'y' ] ; then
            load_database_tables
        fi
    else
        load_database_tables
    fi
    echo ""
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
        unzip -j -q -o tmp/$i WEB-INF/classes/xaps*.properties > /dev/null 2>&1
        zip -d -q tmp/$i WEB-INF/classes/xaps*.properties > /dev/null 2>&1
    done

    unzip -j -q -o tmp/shell.jar xaps-shell*.properties > /dev/null 2>&1
    zip -d -q tmp/shell.jar xaps-shell*.properties > /dev/null 2>&1

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
                diff /var/lib/$TOMCAT/common/$propertyfile $propertyfile > tmp/.tmp
                if [ -s tmp/.tmp ] ; then
                    echo "  $propertyfile diff found, added diff to config-diff.txt - please inspect!"
                    echo "$propertyfile diff:" >> config-diff.txt
                    echo "------------------------------------------------" >> config-diff.txt
                    cat tmp/.tmp >> config-diff.txt
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
            diff /var/lib/$TOMCAT/shell/$propertyfile $propertyfile > tmp/.tmp
            if [ -s tmp/.tmp ] ; then
                echo "  $propertyfile diff found, added diff to config-diff.txt - please inspect!"
                echo "$propertyfile diff:" >> config-diff.txt
                echo "------------------------------------------------" >> config-diff.txt
                cat tmp/.tmp >> config-diff.txt
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
    mv tmp/*.war /var/lib/$TOMCAT/webapps
    mv tmp/*.jar /var/lib/$TOMCAT/shell
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
    rm -R tmp/
}
###################################
#main app
###################################
are_you_root
install_apps 
prepare_ports

download_resources
database_setup
tomcat_setup
shell_setup
cleanup
###################################
