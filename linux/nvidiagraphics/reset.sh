#!/bin/bash

#shell color descriptions
YLW='\033[1;33m'
RED='\033[0;31m'
GRN='\033[1;32m'
NC='\033[0m' # No Color

echo -e "\n${RED}CAUTION: This script is going to reset FlytSim's container to factory default for you. This would delete all of your files present inside the container\n${NC}"

read -p "Do you still want to continue?[y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]
then
	if ! 'groups' | grep -q docker
		then
		if [[ $EUID -ne 0 ]]; then
			cat <<-EOF

			If you would like to use Docker as a non-root user, you should now consider
			adding your user to the "docker" group with something like:

			  sudo usermod -aG docker $USER

			Remember that you will have to log out and back in for this to take effect!

			WARNING: Adding a user to the "docker" group will grant the ability to run
			         containers which can be used to obtain root privileges on the
			         docker host.
			         Refer to https://docs.docker.com/engine/security/security/#docker-daemon-attack-surface
			         for more information.

			EOF
			echo -e "${RED}ERROR${NC}: This script must be run as root, unless you follow the above command, ${YLW}run with sudo ./stop.sh, ${NC}exiting ...${NC}" 
			exit 1
		else
			cat <<-EOF

			If you would like to use Docker as a non-root user, you should now consider
			adding your user to the "docker" group with something like:

			  sudo usermod -aG docker $SUDO_USER

			Remember that you will have to log out and back in for this to take effect!

			WARNING: Adding a user to the "docker" group will grant the ability to run
			         containers which can be used to obtain root privileges on the
			         docker host.
			         Refer to https://docs.docker.com/engine/security/security/#docker-daemon-attack-surface
			         for more information.

			EOF
		fi
	fi

	cd `cd $(dirname $BASH_SOURCE) ; pwd -P`
	docker stop `grep container_name docker-compose.yml | awk -F ' ' '{print $2}'`
	docker rm `grep container_name docker-compose.yml | awk -F ' ' '{print $2}'`
else
	echo -e "\n${RED}Script aborted by user. Exiting..."
	exit 1
fi