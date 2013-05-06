#!/bin/bash
# WARNING:
# *** do NOT use TABS for indentation, use SPACES
# *** TABS will cause errors in some linux distributions

export INSTALL_LOG_FILE=/tmp/mtwilson-install.log
cat /dev/null > $INSTALL_LOG_FILE

if [ -f functions ]; then . functions; else echo "Missing file: functions"; exit 1; fi

if [ -f /root/mtwilson.env ]; then  . /root/mtwilson.env; fi
if [ -f mtwilson.env ]; then  . mtwilson.env; fi

script_name=''
package_name=''
intel_conf_dir=/etc/intel/cloudsecurity
package_dir=/opt/intel/cloudsecurity/${package_name}
package_config_filename=${intel_conf_dir}/${package_name}.properties
package_env_filename=${package_dir}/${package_name}.env
package_install_filename=${package_dir}/${package_name}.install

APICLIENT_YUM_PACKAGES="unzip"
APICLIENT_APT_PACKAGES="unzip"
APICLIENT_YAST_PACKAGES="unzip"
APICLIENT_ZYPPER_PACKAGES="unzip"
auto_install "Installer requirements" "APICLIENT"

echo "Supported database systems are:"
echo "postgres"
echo "mysql"
prompt_with_default DATABASE_VENDOR "Database System:" ${DATABASE_VENDOR:-postgres}
if [ "$DATABASE_VENDOR" != "postgres" ] && [ "$DATABASE_VENDOR" != "mysql" ]; then
  DATABASE_VENDOR=postgres
  echo_warning "Unrecognized selection. Using $DATABASE_VENDOR"
fi

echo "Supported web servers are:"
echo "tomcat"
echo "glassfish"
prompt_with_default WEBSERVER_VENDOR "Web App Server:" ${WEBSERVER_VENDOR:-glassfish}
if [ "$WEBSERVER_VENDOR" != "tomcat" ] && [ "$WEBSERVER_VENDOR" != "glassfish" ]; then
  WEBSERVER_VENDOR=tomcat
  echo_warning "Unrecognized selection. Using $WEBSERVER_VENDOR"
fi

export DATABASE_VENDOR=${DATABASE_VENDOR:-postgres}
export WEBSERVER_VENDOR=${WEBSERVER_VENDOR:-glassfish}

if using_glassfish; then
  export DEFAULT_API_PORT=$DEFAULT_GLASSFISH_API_PORT; 
elif using_tomcat; then
  export DEFAULT_API_PORT=$DEFAULT_TOMCAT_API_PORT;
fi

echo "DEFAULT_API_PORT=$DEFAULT_API_PORT"

# if customer selected mysql but there is no connector present, we abort the install 
if [ "$DATABASE_VENDOR" == "mysql" ] ; then
  mysqlconnector_file=`ls ~ -1 2>/dev/null | grep -i mysql`
  if [ -n "$mysqlconnector_file" ]; then
    mkdir -p /opt/intel/cloudsecurity/setup-console
    cp ~/$mysqlconnector_file /opt/intel/cloudsecurity/setup-console
  fi
  mysqlconnector_file=`ls -1 /opt/intel/cloudsecurity/setup-console/* 2>/dev/null | grep -i mysql`
  if [ -z "$mysqlconnector_file" ]; then
    echo_failure "Cannot find MySQL Connector/J"
    echo "Recommended steps:"
    echo "1. Download MySQL Connector/J, available free at www.mysql.com"
    echo "2. Copy the .jar from MySQL Connector/J to your home directory"
    echo "3. Run this installer again"
    exit 1
  fi
fi


# ensure we have some global settings available before we continue so the rest of the code doesn't have to provide a default
#if using_mysql; then
    export MYSQL_REQUIRED_VERSION=${MYSQL_REQUIRED_VERSION:-5.0}
#elif using_postgres; then
    export POSTGRES_REQUIRED_VERSION=${POSTGRES_REQUIRED_VERSION:-8.4}
#fi
#if using_glassfish; then
    export GLASSFISH_REQUIRED_VERSION=${GLASSFISH_REQUIRED_VERSION:-3.0}
#elif using_tomcat; then
    export TOMCAT_REQUIRED_VERSION=${TOMCAT_REQUIRED_VERSION:-6.0}
#fi
export JAVA_REQUIRED_VERSION=${JAVA_REQUIRED_VERSION:-1.6.0_29}


find_installer() {
  local installer="${1}"
  binfile=`ls -1 $installer-*.bin | head -n 1`
  echo $binfile
}

java_installer=`find_installer java`
monit_installer=`find_installer monit`
mtwilson_util=`find_installer MtWilsonLinuxUtil`
privacyca_service=`find_installer PrivacyCAService`
management_service=`find_installer ManagementService`
whitelist_service=`find_installer WLMService`
attestation_service=`find_installer AttestationService`
whitelist_portal=`find_installer WhiteListPortal`
management_console=`find_installer ManagementConsole`
trust_dashboard=`find_installer TrustDashBoard`

# Make sure the nodeploy flag is cleared, so service setup commands will deploy their .war files
export MTWILSON_SETUP_NODEPLOY=

# Gather default configuration
MTWILSON_SERVER_IP_ADDRESS=${MTWILSON_SERVER_IP_ADDRESS:-$(hostaddress)}

# Prompt for installation settings
echo "Configuring Mt Wilson Server Name..."
echo "Please enter the IP Address or Hostname that will identify the Mt Wilson server.
This address will be used in the server SSL certificate and in all Mt Wilson URLs.
For example, if you enter localhost then the Mt Wilson URL is https://localhost:8181
Detected the following options on this server:"
IFS=$'\n'; echo "$(hostaddress_list)"; IFS=' '; hostname;
prompt_with_default MTWILSON_SERVER "Mt Wilson Server:" $MTWILSON_SERVER_IP_ADDRESS
export MTWILSON_SERVER
echo


# We need Java up front in order to run the setup-console, which contains code for setting up
# or upgrading the database schema. So Java and mtwilson utils and setup-console
# must be done first, before the database and application servers and apps.

# api client: ensure destination exists and clean it before copying
mkdir -p /usr/local/share/mtwilson/apiclient/java
rm -rf /usr/local/share/mtwilson/apiclient/java/*
unzip api-client*.zip -d /usr/local/share/mtwilson/apiclient/java >> $INSTALL_LOG_FILE

# setup console: create folder and copy the executable jar
# this is required before we can run any "mtwilson setup" commands using the "mtwilson" script provided in "mtwilson-util" / "linux-util"
mkdir -p /opt/intel/cloudsecurity/setup-console
rm -rf /opt/intel/cloudsecurity/setup-console/setup-console*.jar
cp setup-console*.jar /opt/intel/cloudsecurity/setup-console


chmod +x *.bin

if [[ -n "$java_installer" ]]; then
echo "Installing Java..." | tee -a  $INSTALL_LOG_FILE
./$java_installer
echo "Java installation done..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$mtwilson_util" ]]; then
echo "Installing Mt Wilson Utils..." | tee -a  $INSTALL_LOG_FILE
./$mtwilson_util  >> $INSTALL_LOG_FILE
echo "Mt Wilson Utils installation done..." | tee -a  $INSTALL_LOG_FILE
fi


if using_mysql; then
  mysql_userinput_connection_properties
  export MYSQL_HOSTNAME MYSQL_PORTNUM MYSQL_DATABASE MYSQL_USERNAME MYSQL_PASSWORD

  # Install MySQL server (if user selected localhost)
  if [[ "$MYSQL_HOSTNAME" == "127.0.0.1" || "$MYSQL_HOSTNAME" == "localhost" || -n `echo "${hostaddress_list}" | grep "$MYSQL_HOSTNAME"` ]]; then
    echo "Installing mysql server..."
    # when we install mysql server on ubuntu it prompts us for root pw
    # we preset it so we can send all output to the log
    aptget_detect; dpkg_detect;
    if [[ -n "$aptget" ]]; then
     echo "mysql-server-5.1 mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
     echo "mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections 
    fi 
    mysql_server_install 
    mysql_start & >> $INSTALL_LOG_FILE
    echo "Installation of mysql server complete..."
  fi
  echo "Installing mysql client..."
  mysql_install  
  # the mysql_create_database function only creates an empty "mw_as" database so we can connect to it -- it does not use 
  # any java code 
  mysql_create_database 
  echo "Installation of mysql client complete..."
  export is_mysql_available mysql_connection_error
  if [ -z "$is_mysql_available" ]; then echo_warning "Run 'mtwilson setup' after a database is available"; fi
elif using_postgres; then
  postgres_userinput_connection_properties

  export POSTGRES_HOSTNAME POSTGRES_PORTNUM POSTGRES_DATABASE POSTGRES_USERNAME POSTGRES_PASSWORD
  echo "$POSTGRES_HOSTNAME:$POSTGRES_PORTNUM:$POSTGRES_DATABASE:$POSTGRES_USERNAME:$POSTGRES_PASSWORD" > $HOME/.pgpass
  chmod 0600 $HOME/.pgpass
  
  # Install Postgres server (if user selected localhost)
  if [[ "$POSTGRES_HOSTNAME" == "127.0.0.1" || "$POSTGRES_HOSTNAME" == "localhost" || -n `echo "$(hostaddress_list)" | grep "$POSTGRES_HOSTNAME"` ]]; then
    echo "Installing postgres server..."
    # when we install postgres server on ubuntu it prompts us for root pw
    # we preset it so we can send all output to the log
    aptget_detect; dpkg_detect; yum_detect;
    if [[ -n "$aptget" ]]; then
     echo "postgresql app-pass password $POSTGRES_PASSWORD" | debconf-set-selections 
    fi 
    postgres_server_install 
    postgres_restart & >> $INSTALL_LOG_FILE
    sleep 5
  fi
  echo "Installing postgres client..."
  #postgres_install
  #postgres_restart & >> $INSTALL_LOG_FILE
  #sleep 10
  echo "Installation of postgres client complete..."

  postgres_create_database

  export is_postgres_available postgres_connection_error
  if [ -z "$is_postgres_available" ]; then 
    echo_warning "Run 'mtwilson setup' after a database is available"; 
  fi
 
fi



# Attestation service auto-configuration
export PRIVACYCA_SERVER=$MTWILSON_SERVER



if using_glassfish; then
  glassfish_installer=`find_installer glassfish`
  if [[ -n "$glassfish_installer" ]]; then
    echo "Installing Glassfish..." | tee -a  $INSTALL_LOG_FILE
    ./$glassfish_installer  >> $INSTALL_LOG_FILE
    mtwilson glassfish-sslcert
    echo "Glassfish installation complete..." | tee -a  $INSTALL_LOG_FILE
  fi
elif using_tomcat; then
  tomcat_installer=`find_installer tomcat`
  if [[ -n "$tomcat_installer" ]]; then
    echo "Installing Tomcat..." | tee -a  $INSTALL_LOG_FILE
    
    if grep -q MaxPermSize /usr/loca/bin/tomcat_starter.sh; then
     someRand=""
    else
      #setup the java_opts and tomcat start in the starter file
      if [ ! -f /usr/local/bin/tomcat_starter.sh ]; then
	    echo "#!/bin/bash" >> /usr/local/bin/tomcat_starter.sh
        echo "export JAVA_OPTS=\"\$JAVA_OPTS -Djava.library.path=/usr/lib -Xms512m -Xmx2560m -XX:MaxPermSize=384m\"" >> /usr/local/bin/tomcat_starter.sh
        echo "/usr/share/apachace/bin/catalina.sh start"  >> /usr/local/bin/tomcat_starter.sh
      fi
      #make the starter file exec on startup
      if [ ! -f /etc/init.d/tomcat.sh ]; then
        echo "#!/bin/bash" >> /etc/init.d/tomcat.sh
        echo "case \"\$1\" in" >> /etc/init.d/tomcat.sh
        echo "start)" >> /etc/init.d/tomcat.sh
        echo "/usr/local/bin/tomcat_starter.sh" >> /etc/init.d/tomcat.sh
        echo ";;" >> /etc/init.d/tomcat.sh
        echo "stop)" >> /etc/init.d/tomcat.sh
        echo "/usr/share/apache-tomcat-6.0.29/bin/catalina.sh stop" >> /etc/init.d/tomcat.sh
        echo ";;" >> /etc/init.d/tomcat.sh
        echo "esac" >> /etc/init.d/tomcat.sh
      fi 
    fi

    chmod +x /etc/init.d/tomcat.sh
    ./$tomcat_installer  >> $INSTALL_LOG_FILE
    
    #mtwilson tomcat-sslcert
    if tomcat_running; then 
      echo "Restarting Tomcat ..."
      tomcat_restart
    else
      echo "Starting Tomcat ..."
      tomcat_start
    fi
    echo "Tomcat installation complete..." | tee -a  $INSTALL_LOG_FILE
  fi
fi 


if [[ -n "$privacyca_service" ]]; then
echo "Installing Privacy CA (this can take some time, please do not interrupt installer)..." | tee -a  $INSTALL_LOG_FILE
./$privacyca_service 
echo "Privacy installation complete..." | tee -a  $INSTALL_LOG_FILE

# removing restart because now the pca keys are generated by the installer... so first time it starts it will already have them.
echo "Restarting Privacy CA..." | tee -a  $INSTALL_LOG_FILE
/usr/local/bin/pcactl restart >> $INSTALL_LOG_FILE
echo "Privacy CA restarted..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$attestation_service" ]]; then
echo "Installing Attestation Service..." | tee -a  $INSTALL_LOG_FILE
./$attestation_service
echo "Attestation Service installed..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$management_service" ]]; then
echo "Installing Management Service..." | tee -a  $INSTALL_LOG_FILE
./$management_service
echo "Management Service installed..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$whitelist_service" ]]; then
echo "Installing Whitelist Service..." | tee -a  $INSTALL_LOG_FILE
./$whitelist_service >> $INSTALL_LOG_FILE
echo "Whitelist Service installed..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$management_console" ]]; then
echo "Installing Management Console..." | tee -a  $INSTALL_LOG_FILE
./$management_console
echo "Management Console installed..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$whitelist_portal" ]]; then
echo "Installing WhiteList Portal..." | tee -a  $INSTALL_LOG_FILE
./$whitelist_portal >> $INSTALL_LOG_FILE
echo "WhiteList Portal installed..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$trust_dashboard" ]]; then
echo "Installing Trust Dashboard..." | tee -a  $INSTALL_LOG_FILE
./$trust_dashboard >> $INSTALL_LOG_FILE
echo "Trust Dashboard installed..." | tee -a  $INSTALL_LOG_FILE
fi

if [[ -n "$monit_installer" ]]; then
echo "Installing Monit..." | tee -a  $INSTALL_LOG_FILE
./$monit_installer  >> $INSTALL_LOG_FILE
echo "Monit installed..." | tee -a  $INSTALL_LOG_FILE
fi

if using_glassfish; then
  echo "Restarting Glassfish..." | tee -a  $INSTALL_LOG_FILE
  mtwilson glassfish-restart >> $INSTALL_LOG_FILE
  echo "Glassfish restarted..." | tee -a  $INSTALL_LOG_FILE
else
  if tomcat_running; then 
      echo "Restarting Tomcat ..." | tee -a  $INSTALL_LOG_FILE
      tomcat_restart
    else
      echo "Starting Tomcat ..." | tee -a  $INSTALL_LOG_FILE
      tomcat_start
    fi
  fi

echo "Log file for install is located at $INSTALL_LOG_FILE"
