#!/bin/sh

###############################################################################
# setup.sh
# DirectAdmin  setup.sh  file  is  the  first  file  to  download  when doing a
# DirectAdmin Install.   It  will  ask  you  for  relevant information and will
# download  all  required  files.   If  you  are unable to run this script with
# ./setup.sh  then  you probably need to set it's permissions.  You can do this
# by typing the following:
#
# chmod 755 setup.sh
#
# after this has been done, you can type ./setup.sh to run the script.
#
###############################################################################

OS=`uname`;

if [ "$(id -u)" != "0" ]; then
	echo "You must be root to execute the script. Exiting."
	exit 1
fi

if ! command -v dig > /dev/null || ! command -v curl > /dev/null || ! command -v tar > /dev/null || ! command -v perl > /dev/null; then
	echo "Installing dependencies..."
	if [ -e /etc/debian_version ]; then
        	apt-get --quiet --yes update || true
		apt-get --quiet --quiet --yes install curl tar perl bind9-dnsutils || apt-get --quiet --quiet --yes install curl tar perl dnsutils || true
	else
		yum --quiet --assumeyes install curl tar bind-utils perl || true
	fi
fi

if ! command -v curl > /dev/null; then
	echo "Please make sure 'curl' tool is available on your system and try again."
	exit 1
fi
if ! command -v tar > /dev/null; then
	echo "Please make sure 'tar' tool is available on your system and try again."
	exit 1
fi

if ! command -v perl > /dev/null; then
  echo "Please make sure 'perl' tool is available on your system and try again."
  exit 1
fi

random_pass() {
	PASS_LEN=`perl -le 'print int(rand(6))+9'`
	START_LEN=`perl -le 'print int(rand(8))+1'`
	END_LEN=$(expr ${PASS_LEN} - ${START_LEN})
	SPECIAL_CHAR=`perl -le 'print map { (qw{@ ^ _ - /})[rand 6] } 1'`;
	NUMERIC_CHAR=`perl -le 'print int(rand(10))'`;
	PASS_START=`perl -le "print map+(A..Z,a..z,0..9)[rand 62],0..$START_LEN"`;
	PASS_END=`perl -le "print map+(A..Z,a..z,0..9)[rand 62],0..$END_LEN"`;
	PASS=${PASS_START}${SPECIAL_CHAR}${NUMERIC_CHAR}${PASS_END}
	echo $PASS
}
DA_PATH=/usr/local/directadmin
SCRIPTS_PATH=$DA_PATH/scripts
SETUP=$SCRIPTS_PATH/setup.txt

ADMIN_USER="admin"
DB_USER="da_admin"
ADMIN_PASS=`random_pass`
DB_ROOT_PASS=`random_pass`

CMD_LINE=0
CID=0
LID=0
ETH_DEV=eth0
IP=0
HOST=`hostname -f`;
if [ "${HOST}" = "" ]; then
	if [ -x /usr/bin/hostnamectl ]; then
		HOST=`/usr/bin/hostnamectl status | grep 'hostname:' | grep -v 'n/a' | head -n1 | awk '{print $3}'`
	fi
fi


if [ -e /usr/local/directadmin/conf/directadmin.conf ]; then
	echo "";
	echo "";
	echo "*** DirectAdmin already exists ***";
	echo "    Press Ctrl-C within the next 10 seconds to cancel the install";
	echo "    Else, wait, and the install will continue, but will destroy existing data";
	echo "";
	echo "";
	sleep 10;
fi

if [ -e /usr/local/cpanel ]; then
        echo "";
        echo "";
        echo "*** CPanel exists on this system ***";
        echo "    Press Ctrl-C within the next 10 seconds to cancel the install";
        echo "    Else, wait, and the install will continue overtop (as best it can)";
        echo "";
        echo "";
        sleep 10;
fi

yesno="n"
while [ "$yesno" = "n" ];
do
{
	# echo -n "Please enter your Client ID : ";
	# read CID;

	# echo -n "Please enter your License ID : ";
	# read LID;

	echo "Please enter your hostname (server.domain.com)";
	echo "It must be a Fully Qualified Domain Name";
	echo "Do *not* use a domain you plan on using for the hostname:";
	echo "eg. don't use domain.com. Use server.domain.com instead.";
	echo "Do not enter http:// or www";
	echo "";

	echo "Your current hostname is: ${HOST}";
	echo "Leave blank to use your current hostname";
	OLD_HOST=$HOST
	echo "";
	echo -n "Enter your hostname (FQDN) : ";
	read HOST;
	if [ "$HOST" = "" ]; then
		HOST=$OLD_HOST
	fi
	echo "Hostname: $HOST";
	echo -n "Is this correct? (y,n) : ";
	read yesno;
}
done;


############

# Get the other info
EMAIL=${ADMIN_USER}@${HOST}
if [ -s /root/.email.txt ]; then
	EMAIL=`cat /root/.email.txt | head -n 1`
fi

TEST=`echo $HOST | cut -d. -f3`
if [ "$TEST" = "" ]
then
        NS1=ns1.`echo $HOST | cut -d. -f1,2`
        NS2=ns2.`echo $HOST | cut -d. -f1,2`
else
        NS1=ns1.`echo $HOST | cut -d. -f2,3,4,5,6`
        NS2=ns2.`echo $HOST | cut -d. -f2,3,4,5,6`
fi

if [ -s /root/.ns1.txt ] && [ -s /root/.ns2.txt ]; then
	NS1=`cat /root/.ns1.txt | head -n1`
	NS2=`cat /root/.ns2.txt | head -n1`
fi

## Get the ethernet_dev

clean_dev()
{
	C=`echo $1 | grep -o ":" | wc -l`

	if [ "${C}" -eq 0 ]; then
		echo $1;
		return;
	fi

	if [ "${C}" -ge 2 ]; then
		echo $1 | cut -d: -f1,2
		return;
	fi

	TAIL=`echo $1 | cut -d: -f2`
	if [ "${TAIL}" = "" ]; then
		echo $1 | cut -d: -f1
		return;
	fi

	echo $1
}



if [ $CMD_LINE -eq 0 ]; then
  DEVS=`ip link show | grep -e "^[1-9]" | awk '{print $2}' | cut -d: -f1 | grep -v lo | grep -v sit0 | grep -v ppp0 | grep -v faith0`
  if [ -z "${DEVS}" ] && [ -x /sbin/ifconfig ]; then
    DEVS=`/sbin/ifconfig -a | grep -e "^[a-z]" | awk '{ print $1; }' | grep -v lo | grep -v sit0 | grep -v ppp0 | grep -v faith0`
  fi
  COUNT=0;
  for i in $DEVS; do
  {
    COUNT=$(($COUNT+1));
  };
  done;

  if [ $COUNT -eq 0 ]; then
          echo "Could not find your ethernet device.";
          echo -n "Please enter the name of your ethernet device: ";
          read ETH_DEV;
  elif [ $COUNT -eq 1 ]; then

    #DIP=`/sbin/ifconfig $DEVS | grep 'inet addr:' | cut -d: -f2 | cut -d\  -f1`;
    DEVS=`clean_dev $DEVS`
    DIP=`ip addr show $DEVS | grep -m1 'inet ' | awk '{print $2}' | cut -d/ -f1`
    #ifconfig fallback
    if [ -z "${DIP}" ] && [ -x /sbin/ifconfig ]; then
      DIP=`/sbin/ifconfig $DEVS | grep 'inet ' | awk '{print $2}' | cut -d: -f2`;
    fi

          echo -n "Is $DEVS your network adaptor with the license IP ($DIP)? (y,n) : ";
          read yesno;
          if [ "$yesno" = "n" ]; then
                  echo -n "Enter the name of the ethernet device you wish to use : ";
                  read ETH_DEV;
          else
                  ETH_DEV=$DEVS
          fi
  else
          # more than one
          echo "The following ethernet devices/IPs were found. Please enter the name of the device you wish to use:";
          echo "";
          #echo $DEVS;
          for i in $DEVS; do
          {
      D=`clean_dev $i`
      DIP=`ip addr show $D | grep -m1 'inet ' | awk '{print $2}' | cut -d/ -f1`
      if [ -z "${D}" ] && [ -x /sbin/ifconfig ]; then
        DIP=`/sbin/ifconfig $D | grep 'inet ' | awk '{print $2}' | cut -d: -f2`;
      fi
            echo "$D       $DIP";
          };
          done;

          echo "";
          echo -n "Enter the device name: ";
          read ETH_DEV;
  fi
fi

if [ "$IP" = "0" ]; then
  #IP=`/sbin/ifconfig $ETH_DEV | grep 'inet addr:' | cut -d: -f2 | cut -d\  -f1`;
  IP=`ip addr show $ETH_DEV | grep -m1 'inet ' | awk '{print $2}' | cut -d/ -f1`
  if [ -z "${IP}" ] && [ -x /sbin/ifconfig ]; then
    IP=`/sbin/ifconfig $ETH_DEV | grep 'inet ' | awk '{print $2}' | cut -d: -f2`;
  fi
fi

prefixToNetmask(){
      BINARY_IP=""
      for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32; do {
              if [ ${i} -le ${1} ]; then
                      BINARY_IP="${BINARY_IP}1"
              else
                      BINARY_IP="${BINARY_IP}0"
              fi
      }
      done

      B1=`echo ${BINARY_IP} | cut -c1-8`
      B2=`echo ${BINARY_IP} | cut -c9-16`
      B3=`echo ${BINARY_IP} | cut -c17-24`
      B4=`echo ${BINARY_IP} | cut -c25-32`
      NM1=`perl -le "print ord(pack('B8', '${B1}'))"`
      NM2=`perl -le "print ord(pack('B8', '${B2}'))"`
      NM3=`perl -le "print ord(pack('B8', '${B3}'))"`
      NM4=`perl -le "print ord(pack('B8', '${B4}'))"`

      echo "${NM1}.${NM2}.${NM3}.${NM4}"
}

PREFIX=`ip addr show ${ETH_DEV} | grep -m1 'inet ' | awk '{print $2}' | cut -d'/' -f2`
NM=`prefixToNetmask ${PREFIX}`
if [ -z "${NM}" ] && [ -x /sbin/ifconfig ]; then
  NM=`/sbin/ifconfig ${ETH_DEV} | grep -oP "(netmask |Mask:)\K[^\s]+(?=.*)"`
fi


if [ $CMD_LINE -eq 0 ]; then

	echo -n "Your external IP: ";
	wget -q -O - http://myip.directadmin.com
	echo "";
	echo "The external IP should typically match your license IP.";
	echo "";

	if [ "$IP" = "" ]; then
		yesno="n";
	else
		echo -n "Is $IP the IP in your license? (y,n) : ";
		read yesno;
	fi

	if [ "$yesno" = "n" ]; then
		echo -n "Enter the IP used in your license file : ";
		read IP;
	fi

	if [ "$IP" = "" ]; then
		echo "The IP entered is blank.  Please try again, and enter a valid IP";
	fi
fi

############

echo "";
echo "DirectAdmin will now be installed on: $OS $OS_VER";



#######
# Ok, we're ready to go.





#ensure /etc/hosts has localhost
COUNT=`grep 127.0.0.1 /etc/hosts | grep -c localhost`
if [ "$COUNT" -eq 0 ]; then
	echo -e "127.0.0.1\t\tlocalhost" >> /etc/hosts
fi

OLDHOST=`hostname --fqdn`
if [ "${OLDHOST}" = "" ]; then
  echo "old hostname is blank. Setting a temporary placeholder";
  /bin/hostname $HOST;
  sleep 5;
fi



FILE="directadmin.tar.gz"
TMP_DIR=$(mktemp -d)
cleanup() {
        rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Downloading DirectAdmin distribution package ${FILE}..."
curl --progress-bar --location --connect-timeout 60 -o "${TMP_DIR}/${FILE}" "https://github.com/thai306/DL_SERVER_BACKUP/raw/main/directadmin.tar.gz" \
	|| curl --progress-bar --location --connect-timeout 60 -o "${TMP_DIR}/${FILE}" "https://github.com/thai306/DL_SERVER_BACKUP/raw/main/directadmin.tar.gz"

if [ ! -e "${TMP_DIR}/${FILE}" ]; then
	echo "Unable to download";
	exit 3;
fi

COUNT=`head -n 4 "${TMP_DIR}/${FILE}" | grep -c "* You are not allowed to run this program *"`;
if [ $COUNT -ne 0 ]; then
	echo "";
	echo "You are not authorized to download the update package with that client id and license id for this IP address. Please email sales@directadmin.com";
	exit 4;
fi

echo "Extracting DirectAdmin package ${FILE} to /usr/local/directadmin ..."
mkdir -p "${DA_PATH}"
tar -xzf "${TMP_DIR}/${FILE}" -C "${DA_PATH}"

if [ ! -e $DA_PATH/directadmin ]; then
	echo "Cannot find the DirectAdmin binary.  Extraction failed";
	exit 5;
fi

###############################################################################

# write the setup.txt

echo "hostname=$HOST"        >  $SETUP;
echo "email=$EMAIL"          >> $SETUP;
echo "mysql=$DB_ROOT_PASS"   >> $SETUP;
echo "mysqluser=$DB_USER"    >> $SETUP;
echo "adminname=$ADMIN_USER" >> $SETUP;
echo "adminpass=$ADMIN_PASS" >> $SETUP;
echo "ns1=$NS1"              >> $SETUP;
echo "ns2=$NS2"              >> $SETUP;
echo "ip=$IP"                >> $SETUP;
echo "netmask=$NM"           >> $SETUP;
echo "uid=$CID"              >> $SETUP;
echo "lid=$LID"              >> $SETUP;
echo "services=auto"         >> $SETUP;

CFG=$DA_PATH/data/templates/directadmin.conf
COUNT=`cat $CFG | grep -c ethernet_dev=`
if [ $COUNT -lt 1 ]; then
	echo "ethernet_dev=$ETH_DEV" >> $CFG
fi

chmod 600 $SETUP

###############################################################################
###############################################################################

chmod 0755 ${DA_PATH}/scripts/setup.sh
${DA_PATH}/scripts/setup.sh "$@"

if [ -s /usr/local/directadmin/conf/directadmin.conf ]; then
	echo ""
	echo "Install Complete!";
	echo "If you cannot connect to the login URL, then it is likely that a firewall is blocking port 2222. Please see:"
	echo "  https://help.directadmin.com/item.php?id=75"
fi

printf \\a
sleep 1
printf \\a
sleep 1
printf \\a

exit ${RET}
