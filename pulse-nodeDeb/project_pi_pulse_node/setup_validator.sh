#!/bin/bash

# v.1.1

#Icosa, Hex, Hedron,
#Three shapes in symmetry dance,
#Nature's art is shown.

# By tdslaine aka Peter L Dipslayer  TG: @dipslayer369  Twitter: @dipslayer

start_dir=$(pwd)
script_dir=$(dirname "$0")
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

source "$script_dir/functions.sh"

tab_autocomplete
check_and_set_network_variables

echo "Setting up a validator on the $EXECUTION_NETWORK_FLAG network"

sleep 2

function get_user_choices() {
    echo ""
    echo "+--------------------------------------------+"
    echo "| Choose your Validator Client               |"
    echo "|                                            |"
    echo "| (based on your consensus/beacon Client)    |"
    echo "+--------------------------------------------+"
    echo "| 1. Lighthouse                              |"
    echo "|                                            |"
    echo "| 2. Prysm                                   |"
    echo "+--------------------------------------------+"
    echo "| 0. Return or Exit                          |"
    echo "+--------------------------------------------+"
    echo ""
    read -p "Enter your choice (1, 2 or 0): " client_choice

    # Validate user input for client choice
    while [[ ! "$client_choice" =~ ^[0-2]$ ]]; do
        echo "Invalid input. Please enter a valid choice (1, 2 or 0): "
        read -p "Enter your choice (1, 2 or 0): " client_choice
    done

    if [[ "$client_choice" == "0" ]]; then
        echo "Exiting..."
        exit 0
    fi
}

# Main Setup Starts here ################################################################

# Start Validator Setup
clear
get_user_choices

# Checking for installed/Required software
common_task_software_check

# Add "validator" user to system and docker-grp
create_user "validator"  >/dev/null 2>&1

# Prompt User for Set up installation path
echo ""
set_install_path
echo ""

# Cloning staking Client into installation path
clone_staking_deposit_cli "${INSTALL_PATH}"
echo ""
# Create PRYSM-Wallet pw.txt if First-Time Setup and User choose Prysm-Client

    if [[ "$client_choice" == "2" ]]; then
            create_subfolder "wallet"
            create_prysm_wallet_password
            sudo chmod -R 777 "${INSTALL_PATH}/wallet"
            sudo chown $main_user: "$INSTALL_PATH/wallet"
        fi 

sudo groupadd pls-validator > /dev/null 2>&1 

Staking_Cli_launch_setup

sudo chmod -R 777 $INSTALL_PATH/validator_keys
sudo chmod -R 777 $INSTALL_PATH/staking-deposit-cli

clear

# Generate Key functions 

################################################### Generate New ##################################################
generate_new_validator_key() {

    if [[ "$client_choice" == "1" ]]; then
        check_and_pull_lighthouse
    elif [[ "$client_choice" == "2" ]]; then
        check_and_pull_prysm_validator
    fi

    clear

    warn_network

    clear


    if [[ "$network_off" =~ ^[Yy]$ ]]; then
        network_interface_DOWN
    fi


    echo ""
    echo "Generating the validator keys via staking-cli"
    echo ""
    echo "Please follow the instructions and make sure to READ! and understand everything on screen"
    echo ""
    echo -e "${RED}Attention:${NC}"
    echo ""
    echo "The next step requires you to enter the wallet address that you would like to use for receiving"
    echo "validator rewards while validating and withdrawing your funds when you exit the validator pool."
    echo -e "This is the ${GREEN}Withdrawal- or Execution-Wallet (they are the same)${NC}"
    echo ""
    echo -e "Make sure ${RED}you have full access${NC} to this Wallet. ${RED}Once set, it cannot be changed${NC}"
    echo ""
    echo -e "You need to provide this Wallet-Adresss in the ${GREEN}proper format (checksum)${NC}."
    echo -e "One way to achive this, is to copy your adress from the Blockexplorer"
    echo ""
    if confirm_prompt "I have read this information and confirm that I understand the importance of using the right Withdrawal-Wallet Address."; then
        echo ""
        echo "proceeding..."
        sleep 2
    else
        echo "Exiting script now."
        network_interface_UP
        exit 1
    fi


    echo ""

# Check if the address is a valid address, loop until it is...
while true; do
    read -e -p "Please enter your Execution/Withdrawal-Wallet address: " withdrawal_wallet
    if [[ "${withdrawal_wallet}" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        break
    else
        echo "Invalid address format. Please enter a valid PRC20 address."
    fi
done

    
    # Running staking-cli to Generate the new validator_keys
    echo ""
    echo "Starting staking-cli to Generate the new validator_keys"
    echo ""

    cd ${INSTALL_PATH}/staking-deposit-cli
    ./deposit.sh new-mnemonic \
    --mnemonic_language=english \
    --chain=${DEPOSIT_CLI_NETWORK} \
    --folder="${INSTALL_PATH}" \
    --eth1_withdrawal_address="${withdrawal_wallet}"


    cd "${INSTALL_PATH}"
    sudo chmod -R 770 "${INSTALL_PATH}/validator_keys" >/dev/null 2>&1
    sudo chmod -R 770 "${INSTALL_PATH}/wallet" >/dev/null 2>&1


    if [[ "$network_off" =~ ^[Yy]$ ]]; then
        network_interface_UP
    fi

    if [[ "$client_choice" == "1" ]]; then
        import_lighthouse_validator
    elif [[ "$client_choice" == "2" ]]; then
        import_prysm_validator
    fi

sudo find "$INSTALL_PATH/validator_keys" -type f -name "keystore*.json" -exec sudo chmod 440 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -name "deposit*.json" -exec sudo chmod 444 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -exec sudo chown $main_user:pls-validator {} \;
    
}

################################################### Import ##################################################
import_restore_validator_keys() {

    if [[ "$client_choice" == "1" ]]; then
        check_and_pull_lighthouse
    elif [[ "$client_choice" == "2" ]]; then
        check_and_pull_prysm_validator
    fi

    while true; do
        clear
        # Prompt the user to enter the path to the root directory containing the 'validator_keys' backup-folder
        echo -e "Enter the path to the root directory which contains the 'validator_keys' backup-folder."
        echo -e "For example, if your 'validator_keys' folder is located in '/home/user/my_backup/validator_keys',"
        echo -e "then provide the path '/home/user/my_backup'. You can use tab-autocomplete when entering the path."
        echo ""
        read -e -p "Path to backup: " backup_path
    
        # Check if the source directory exists
        if [ -d "${backup_path}/validator_keys" ]; then
            # Check if the source and destination paths are different
            if [ "${INSTALL_PATH}/validator_keys" != "${backup_path}/validator_keys" ]; then
                # Copy the validator_keys folder to the install path
                sudo cp -R "${backup_path}/validator_keys" "${INSTALL_PATH}"
                # Inform the user that the keys have been successfully copied over
                echo "Keys successfully copied."
                # Exit the loop
                break
            else
                # Inform the user that the source and destination paths match and no action is needed
                echo "Source and destination paths match. Skipping restore-copy; keys seem already in place."
                echo "Key import will still proceed..."
                # Exit the loop
                break
            fi
        else
            # Inform the user that the source directory does not exist and ask them to try again
            echo "Source directory does not exist. Please check the provided path and try again."
        fi
    done
    
        
    echo ""
    echo "Importing validator keys now"
    echo ""

    sudo chmod -R 770 "${INSTALL_PATH}/validator_keys" >/dev/null 2>&1
    sudo chmod -R 770 "${INSTALL_PATH}/wallet" >/dev/null 2>&1
    
    if [[ "$client_choice" == "1" ]]; then
        import_lighthouse_validator
        elif [[ "$client_choice" == "2" ]]; then
        import_prysm_validator
    fi

sudo find "$INSTALL_PATH/validator_keys" -type f -name "keystore*.json" -exec sudo chmod 440 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -name "deposit*.json" -exec sudo chmod 444 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -exec sudo chown $main_user:pls-validator {} \;

        
}

################################################### Restore ##################################################
# Function to restore from SeedPhrase 
Restore_from_MN() {

    echo "Restoring validator_keys from SeedPhrase (Mnemonic)"

    if [[ "$client_choice" == "1" ]]; then
        check_and_pull_lighthouse
    elif [[ "$client_choice" == "2" ]]; then
        check_and_pull_prysm_validator
    fi


    clear

    warn_network

    clear


    if [[ "$network_off" =~ ^[Yy]$ ]]; then
        network_interface_DOWN
    fi
    # Check if the address is a valid address, loop until it is...
    while true; do
    read -e -p "Please enter your Execution/Withdrawal-Wallet address: " withdrawal_wallet
    if [[ "${withdrawal_wallet}" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        break
    else
        echo "Invalid address format. Please enter a valid PRC20 address."
    fi
    done
    
    
    echo ""
    echo "Now running staking-cli command to restore from your SeedPhrase (Mnemonic)"
    echo ""
    
    cd "${INSTALL_PATH}"
    sudo chmod -R 777 "${INSTALL_PATH}/validator_keys" >/dev/null 2>&1
    sudo chmod -R 777 "${INSTALL_PATH}/wallet" >/dev/null 2>&1
       
    cd ${INSTALL_PATH}/staking-deposit-cli/
    ./deposit.sh existing-mnemonic \
    --chain=${DEPOSIT_CLI_NETWORK} \
    --folder="${INSTALL_PATH}" \
    --eth1_withdrawal_address="${withdrawal_wallet}"
     

    if [[ "$network_off" =~ ^[Yy]$ ]]; then
        network_interface_UP
    fi

    if [[ "$client_choice" == "1" ]]; then
        import_lighthouse_validator
    elif [[ "$client_choice" == "2" ]]; then
        import_prysm_validator

    fi

sudo chmod -R 770 "${INSTALL_PATH}/validator_keys"
sudo find "$INSTALL_PATH/validator_keys" -type f -name "keystore*.json" -exec sudo chmod 770 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -name "deposit*.json" -exec sudo chmod 774 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -exec sudo chown $main_user:pls-validator {} \;
}
    


# Selection menu

echo "-----------------------------------------"
echo "|           Validator Key Setup         |"
echo "-----------------------------------------"
echo ""
PS3=$'\nChoose an option (1-3): '
options=("Generate new validator_keys (fresh)" "Import/Restore validator_keys from a Folder (from Offline generation or Backup)" "Restore or Add from a Seed Phrase (Mnemonic) to current or initial setup")
COLUMNS=1
select opt in "${options[@]}"

do
    case $REPLY in
        1)
            generate_new_validator_key
            break
            ;;
        2)
            import_restore_validator_keys
            break
            ;;
        3)
            Restore_from_MN
            break
            ;;  
        *)
            echo "Invalid option. Please choose option (1-3)."
            ;;
    esac
done

# Code from here is for fresh-install only to generate the start_validator.sh launch script.
echo ""
echo -e "${GREEN}Gathering data for the Validator-Client, data will be used to generate the start_validator script${NC}"
echo ""

echo ""
get_fee_receipt_address             # Set Fee-Receipt address

graffiti_setup                      # Set Graffiti 


## Defining the start_validator.sh script content, this is only done during the "first-time-setup"

if [[ "$client_choice" == "1" ]]; then
    VALIDATOR="
    sudo -u validator docker run -dt --network=host --restart=always \\
    -v "${INSTALL_PATH}":/blockchain \\
    --name validator \\
    registry.gitlab.com/pulsechaincom/lighthouse-pulse:latest \\
    lighthouse vc \\
    --network=${LIGHTHOUSE_NETWORK_FLAG} \\
    --validators-dir=/blockchain/validators \\
    --suggested-fee-recipient="${fee_wallet}" \\
    --graffiti="${user_graffiti}" \\
    --metrics \\
    --beacon-nodes=http://127.0.0.1:5052 "

elif [[ "$client_choice" == "2" ]]; then 
VALIDATOR="
sudo -u validator docker run -dt --network=host --restart=always \\
-v "${INSTALL_PATH}"/wallet:/wallet \\
-v "${INSTALL_PATH}"/validator_keys:/keys \\
--name=validator \\
registry.gitlab.com/pulsechaincom/prysm-pulse/validator:latest --${PRYSM_NETWORK_FLAG} \\
--suggested-fee-recipient="${fee_wallet}" \\
--wallet-dir=/wallet --wallet-password-file=/wallet/pw.txt \\
--graffiti "${user_graffiti}" --rpc " 

else 
    echo "Error - Debugging required"

fi

echo ""
echo "debug info:"
echo -e "Creating the start_validator.sh script with the following contents:\n${VALIDATOR}"
echo ""

if [[ "$network_off" =~ ^[Yy]$ ]]; then         # Restarting Network interface should it still be down for some reason
    network_interface_UP
fi

sudo chown :docker ${INSTALL_PATH}
sudo chmod -R 770 ${INSTALL_PATH}

#echo "Current directory is $(pwd)"

# Writing the start_validator.sh script, this is only done during "first-setup"
cat > "${INSTALL_PATH}/start_validator.sh" << EOF
#!/bin/bash

${VALIDATOR}
EOF

get_main_user  > /dev/null 2>&1 

echo "" 
echo $main_user > /dev/null 2>&1 
echo ""

sudo chmod +x "${INSTALL_PATH}/start_validator.sh"
sudo chown -R $main_user:docker ${INSTALL_PATH}/*.sh

sleep 1



# Setup ownership and file permissions

                                                         # get main user via logname
sudo groupadd pls-validator > /dev/null 2>&1 
sleep 1
# add pls-validator groupS
sudo usermod -aG pls-validator $main_user > /dev/null 2>&1                          # main user to pls-validator to access folders
sudo usermod -aG pls-validator validator > /dev/null 2>&1 

sudo chown -R validator:pls-validator "$INSTALL_PATH/validators" > /dev/null 2>&1       # set ownership to validator and pls-validator-group
sudo chown -R validator:pls-validator "$INSTALL_PATH/wallet"     > /dev/null 2>&1       # ""
sudo chown -R validator:pls-validator "$INSTALL_PATH/validator_keys" > /dev/null 2>&1   # ""

sudo chmod -R 770 "$INSTALL_PATH/validator_keys"
sudo find "$INSTALL_PATH/validator_keys" -type f -name "keystore*.json" -exec sudo chmod 770 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -name "deposit*.json" -exec sudo chmod 774 {} \;
sudo find "$INSTALL_PATH/validator_keys" -type f -exec sudo chown $main_user:pls-validator {} \;

sudo chmod -R 770 "$INSTALL_PATH/wallet" > /dev/null 2>&1
sudo chmod -R 770 "$INSTALL_PATH/validators" > /dev/null 2>&1

cron2

# Prompt the user if they want to run the scripts
start_scripts_first_time

## Clearing the Bash-Histroy
clear_bash_history

echo ""
read -e -p "$(echo -e "${GREEN}Do you want to run the Prometheus/Grafana Monitoring Setup now (y/n):${NC}")" choice

   while [[ ! "$choice" =~ ^(y|n)$ ]]; do
        read -e -p "Invalid input. Please enter 'y' or 'n': " choice
    done

if [[ "$choice" =~ ^[Yy]$ || "$choice" == "" ]]; then
    # Check if the setup_monitoring.sh script exists
    if [[ ! -f "${start_dir}/setup_monitoring.sh" ]]; then
        echo "setup_monitoring.sh script not found. Aborting Prometheus/Grafana Monitoring setup."
        exit 1
    fi
    # Set the permission and run the setup script
    sudo chmod +x "${start_dir}/setup_monitoring.sh"
    "${start_dir}/setup_monitoring.sh"

    # Check if the setup script was successful
    if [[ $? -ne 0 ]]; then
        echo "Prometheus/Grafana Monitoring setup failed. Please try again or set up manually."
        exit 1
    fi

        exit 0
    else
    echo "Skipping Prometheus/Grafana Monitoring Setup."
fi

echo ""

echo -e " ${RED}Note: Sync the chain fully before submitting your deposit_keys to prevent slashing; avoid using the same keys on multiple machines.${NC}"
echo ""
echo -e "Find more information in the repository's README."


display_credits
sleep 1
echo ""
echo "Due to changes in file-Permission it is highly recommended to reboot the system now"
reboot_prompt
sleep 2
reboot_advice
logviewer_prompt
echo ""
exit 0
fi
