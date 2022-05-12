#!/bin/sh
clear

# Insert credentials
USER=$(cat ./username)
PWD=$(cat ./password)
SERVER=$1

if [ ! -z $USER ] && [ ! -z $PWD ] && [ ! -z $SERVER ]&& [ ! -z $2 ]; then

	# Define variables
	NETPLAN_TEMPLATE_PATH="/tmp"               # Directory to host template file
	NETPLAN_TEMPLATE_FILE="Netplan.template"   # Template of Netplan settings file
	NETPLAN_PATH="/etc/netplan"                # Directory to host Netplan file
	NETPLAN_FILE="42-${2}-network-config.yaml" # Name of standard Netplan file

	# Check if node is reachable
	nc -zv $SERVER 22
	if [ $? -eq 0 ]; then
		# Copy template file
		# sshpass -p $PWD scp ${NETPLAN_TEMPLATE_FILE} ${USER}@${SERVER}:${NETPLAN_TEMPLATE_PATH}/${NETPLAN_TEMPLATE_FILE}

		# Connect to remote node via ssh
		NETPLAN_APPLY=$(sshpass -p $PWD ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "

			wget --directory-prefix=${NETPLAN_TEMPLATE_PATH} \"https://raw.githubusercontent.com/JanRK/rancher-netplan/main/Netplan.template\"
			wget --directory-prefix=${NETPLAN_TEMPLATE_PATH} \"https://raw.githubusercontent.com/JanRK/rancher-netplan/main/nodeCleanup.sh\"
			echo $PWD | sudo chmod +x ${NETPLAN_TEMPLATE_PATH}/nodeCleanup.sh
	
            # Renaming non standard files
			FILES=\"\$(find ${NETPLAN_PATH} -type f \( -iname '*.yaml' ! -iname ${NETPLAN_FILE} \) -printf '%f\n')\"

			for FILE in \$FILES
				#for FILE in \"\$(find ${NETPLAN_PATH} -type f \( -iname '*.yaml' ! -iname ${NETPLAN_FILE} \) -printf '%f\n')\"
			do
				if [ ! -z \"\$FILE\" ]
				then
					echo -e \"Renaming the file ${NETPLAN_PATH}/\$FILE to ${NETPLAN_PATH}/\${FILE}.x\n\"
					echo $PWD | sudo -S mv ${NETPLAN_PATH}/\$FILE ${NETPLAN_PATH}/\${FILE}.x
				fi
			done

			# Check if netplan file exists
			if test -f "${NETPLAN_PATH}/${NETPLAN_FILE}"
			then
				# Check if netplan matches the template
				if cmp -s ${NETPLAN_TEMPLATE_PATH}/${NETPLAN_TEMPLATE_FILE} ${NETPLAN_PATH}/${NETPLAN_FILE}
				then
					echo -e \"\nThe Netplan is already properly applied on server \"\$(hostname)\"\"
				else
					echo "The Netplan file mismatch the template, updating from template file"
					echo $PWD | sudo -S cp ${NETPLAN_TEMPLATE_PATH}/${NETPLAN_TEMPLATE_FILE} ${NETPLAN_PATH}/${NETPLAN_FILE}
					echo $PWD | sudo -S chmod 644 ${NETPLAN_PATH}/${NETPLAN_FILE}

					# Apply Netplan
					echo $PWD | sudo -S netplan generate
					echo $PWD | sudo -S netplan apply
				fi
			else
				echo "Generate Netplan from template file"
				echo $PWD | sudo -S cp ${NETPLAN_TEMPLATE_PATH}/${NETPLAN_TEMPLATE_FILE} ${NETPLAN_PATH}/${NETPLAN_FILE}
				echo $PWD | sudo -S chmod 644 ${NETPLAN_PATH}/${NETPLAN_FILE}

				# Apply Netplan
				echo $PWD | sudo -S netplan generate
				echo $PWD | sudo -S netplan apply
			fi
	    " </dev/null)

		# Show results of the actions
		echo $NETPLAN_APPLY
	else
		echo "The server $SERVER is unreachable"
	fi
else
	echo "User, password, server and/or company were not inserted as arguments"
fi
