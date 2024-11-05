#!/bin/bash

# Define the script directory and source functions
script_dir=$(dirname "$0")
source "$script_dir/functions.sh"

# Script Description
echo "This script sets up the PulseChain Validator Node with options for different execution and consensus clients."
echo "It manages user permissions, Docker setups, and client configurations."

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a user can access Docker
can_access_docker() {
    local user=$1
    if sudo -u $user docker info &>/dev/null; then
        log_message "User $user can access Docker."
        return 0
    else
        log_message "User $user cannot access Docker. Attempting to add to Docker group..."
        sudo usermod -aG docker $user
        if sudo -u $user docker info &>/dev/null; then
            log_message "User $user can now access Docker after being added to the group."
        else
            log_message "Failed to grant Docker access to user $user. Please ensure the Docker service is running and the user is logged out and back in."
        fi
        return 1
    fi
}

# Function to safely execute Docker commands
execute_docker_command() {
    local cmd="$1"
    local user="$(echo "$cmd" | grep -oP '(?<=sudo -u ).+?(?= docker)')"
    local container_name="$(echo "$cmd" | grep -oP '(?<=--name ).+?(?= -v)')"

    # Ensure the user can run Docker commands
    sudo usermod -aG docker $user

    # Check if the container exists
    if docker ps -a | grep -q "$container_name"; then
        log_message "Removing existing container $container_name"
        sudo -u $user docker rm -f $container_name
    fi

    # Run the Docker command
    if eval "$cmd"; then
        log_message "Successfully executed Docker command for $container_name."
    else
        log_message "Failed to execute Docker command for $container_name."
        exit 1
    fi
}

# Path to original image
original_image="/home/barchef/Desktop/pulse-node/project_pi_pulse_node/PP.png"
# Path to resized image
resized_image="/home/barchef/Desktop/pulse-node/project_pi_pulse_node/PP_resized.png"

# Resize the image using ImageMagick
convert "$original_image" -resize 200x200 "$resized_image"

# Initial information dialog with YAD
yad --title "PulseChain Validator Node Setup" \
    --image="$resized_image" --image-on-top \
    --text "PulseChain Validator Node Setup by Project Pi\n\nPlease press OK to continue." \
    --button=gtk-ok:0 --buttons-layout=center --geometry=530x10+800+430

# Check if the user pressed OK
if [[ $? -ne 0 ]]; then
    yad --window-icon=error --title "Setup Aborted" \
        --text "Setup aborted by the user." \
        --button=gtk-ok:0 --buttons-layout=center --geometry=300x200+100+100
    exit 1
fi

# Create users if they do not exist and add them to the docker group
for user in geth erigon lighthouse; do
    if ! id "$user" &>/dev/null; then
        sudo useradd -m -s /bin/bash $user
        sudo usermod -aG docker $user
        log_message "User $user created and added to docker group."
        can_access_docker $user
    else
        sudo usermod -aG docker $user
        can_access_docker $user
    fi
done

# Network choice using Zenity
network_choice=$(zenity --list --width=300 --height=200 --title="Choose Network" \
                        --text="Select the network for the node setup:" \
                        --radiolist --column="Select" --column="Network" \
                        FALSE "Mainnet" FALSE "Testnet")
if [ -z "$network_choice" ]; then
    zenity --error --text="No network choice was made."
    exit 1
fi

# Inform the user and enable NTP
zenity --info --text="We are going to setup the timezone first. It is important to be synced in time for the chain to work correctly.\n\nClick OK to enable NTP for timesync." --width=300
if [[ $? -ne 0 ]]; then
    exit 1
fi

sudo timedatectl set-ntp true
zenity --info --text="NTP timesync has been enabled." --width=300

# Loop to attempt timezone setting until confirmed
while true; do
    zenity --info --text="Please choose your CORRECT timezone in the upcoming screen. Press OK to continue." --width=300
    if [[ $? -ne 0 ]]; then
        zenity --error --text="Timezone configuration aborted." --width=300
        exit 1
    fi

    # Launch the timezone configuration GUI
    x-terminal-emulator -e sudo dpkg-reconfigure tzdata 

    # Ask the user if they successfully set the timezone
    if zenity --question --text="Did you successfully set your timezone?" --width=300; then
        zenity --info --text="Timezone set successfully." --width=300
        break
    else
        if zenity --question --text="Timezone setting was not confirmed. Would you like to try setting the timezone again?" --width=300; then
            continue
        else
            zenity --error --text="Timezone setting aborted. Exiting the setup." --width=300
            exit 1
        fi
    fi
done

# Ask the user to choose an Execution Client
execution_client=$(zenity --list --width=500 --height=200 --title="Choose an Execution Client" \
                          --text="Please choose an Execution Client:" \
                          --radiolist --column="Select" --column="Client" \
                          FALSE "Geth (full node, faster sync time)" \
                          FALSE "Erigon (archive node, longer sync time)" \
                          FALSE "Erigon (pruned to keep the last 2000 blocks)")
if [ -z "$execution_client" ]; then
    zenity --error --text="No execution client was chosen. Exiting." --width=300
    exit 1
fi

# Set the chosen client
case "$execution_client" in
    "Geth (full node, faster sync time)")
        ETH_CLIENT="geth"
        ;;
    "Erigon (archive node, longer sync time)"|"Erigon (pruned to keep the last 2000 blocks)")
        ETH_CLIENT="erigon"
        ;;
    *)
        zenity --error --text="Invalid choice. Exiting."
        exit 1
        ;;
esac

# Ask the user to choose a Consensus Client
consensus_client_choice=$(zenity --list --width=300 --height=200 --title="Choose your Consensus Client" \
                                  --text="Select the consensus client for the node setup:" \
                                  --radiolist --column="Select" --column="Client" \
                                  TRUE "Lighthouse" \
                                  --hide-header)

# Check if the user made a choice or cancelled
if [ -z "$consensus_client_choice" ]; then
    zenity --error --text="No consensus client was chosen. Exiting."
    exit 1
fi

# Display choice and set the consensus client variable
CONSENSUS_CLIENT="lighthouse"
zenity --info --text="Lighthouse selected as Consensus Client."

# Enable tab autocompletion for interactive shells (This part may be skipped in GUI)
if [ -n "$BASH_VERSION" ] && [ -n "$PS1" ] && [ -t 0 ]; then
  bind '"\t":menu-complete'
fi

# Get custom path for the blockchain folder
CUSTOM_PATH=$(zenity --entry --title="Installation Path" \
                     --text="Enter the target path for node and client data (Press Enter for default):" \
                     --entry-text "/blockchain")

# Check if the user made a choice or cancelled
if [ -z "$CUSTOM_PATH" ]; then
    CUSTOM_PATH="/blockchain"  # Default path if nothing entered
fi

zenity --info --text="Data will be installed under: $CUSTOM_PATH"

# Define Docker commands
GETH_CMD="sudo -u geth docker run -dt --restart=always \
          --network=host \
          --name execution \
          -v ${CUSTOM_PATH}:/blockchain \
          registry.gitlab.com/pulsechaincom/go-pulse:latest \
          --http \
          --txlookuplimit 0 \
          --gpo.ignoreprice 1 \
          --cache 16384 \
          --metrics \
          --db.engine=leveldb \
          --pprof \
          --http.api eth,net,engine,admin \
          --authrpc.jwtsecret=/blockchain/jwt.hex \
          --datadir=/blockchain/execution/geth"

# Execute Docker command as erigon user

if ! id "erigon" &>/dev/null; then
    sudo useradd -m -s /bin/bash erigon
fi

LIGHTHOUSE_CMD="sudo -u lighthouse docker run -dt --restart=always \
                --network=host \
                --name lighthouse \
                -v ${CUSTOM_PATH}:/blockchain \
                registry.gitlab.com/pulsechaincom/lighthouse-pulse:latest \
                lighthouse bn \
                --network mainnet \
                --execution-jwt=/blockchain/jwt.hex \
                --datadir=/blockchain/consensus/lighthouse \
                --execution-endpoint=http://localhost:8551 \
                --checkpoint-sync-url=\"http://checkpoint.node\" \
                --staking \
                --metrics \
                --validator-monitor-auto \
                --http"

# Execute the Docker commands after confirmation
if zenity --question --text="Do you want to execute the Geth Docker command?" --width=500; then
    execute_docker_command "$GETH_CMD"
    zenity --info --text="Geth Docker container started successfully." --width=300
else
    zenity --info --text="Geth Docker container startup aborted." --width=300
fi


if zenity --question --text="Do you want to execute the Lighthouse Docker command?" --width=500; then
    eval $LIGHTHOUSE_CMD
    zenity --info --text="Lighthouse Docker container started successfully." --width=300
else
    zenity --info --text="Lighthouse Docker container startup aborted." --width=300
fi

#!/bin/bash

# Clear the screen
clear

# Check for any snap version of Docker installed and remove it
if snap list | grep -q '^docker '; then
    zenity --info --text="Docker snap package found. Removing..." --width=300
    sudo snap remove docker
else
    zenity --info --text="No Docker snap package found." --width=300
fi

# Display information message with Zenity
zenity --info --text="Checking for the latest Python version in Debian repositories." --width=300

# Update and install Python dependencies if available
sudo apt-get update -y

# Attempt to install Python 3.10 (or adjust to the required version available in Debian)
if sudo apt-get install -y python3.10 python3.10-venv python3.10-dev; then
    zenity --info --text="Python 3.10 installed successfully from Debian repositories." --width=300
else
    zenity --info --text="Python 3.10 not found in Debian repositories. Installing from source..." --width=300

    # Install build dependencies
    sudo apt-get install -y build-essential zlib1g-dev libssl-dev libncurses5-dev \
        libgdbm-dev libnss3-dev libreadline-dev libffi-dev libsqlite3-dev wget

    # Download and compile Python 3.10 from source
    wget https://www.python.org/ftp/python/3.10.0/Python-3.10.0.tgz
    tar -xf Python-3.10.0.tgz
    cd Python-3.10.0
    ./configure --enable-optimizations
    make -j $(nproc)
    sudo make altinstall
    cd ..
    rm -rf Python-3.10.0 Python-3.10.0.tgz

    zenity --info --text="Python 3.10 installed successfully from source." --width=300
fi


# Update and upgrade the system
zenity --info --text="Updating and upgrading system packages. This may take a while..." --width=300
sudo apt-get update -y && sudo apt-get upgrade -y

# Perform a distribution upgrade and remove unused packages
zenity --info --text="Performing distribution upgrade and cleaning up unused packages." --width=300
sudo apt-get dist-upgrade -y
sudo apt autoremove -y

# Install required packages
zenity --info --text="Installing required packages..." --width=300
sudo apt-get install -y apt-transport-https ca-certificates curl htop gnupg git ufw tmux dialog rhash openssl wmctrl jq lsb-release dbus-x11 python3.10 python3.10-venv python3.10-dev python3-pip

# Notify completion
zenity --info --text="All required packages have been installed successfully." --width=300

#!/bin/bash

# Notify the user about adding the Docker repository and installing Docker
zenity --info --text="Adding Docker repository and installing Docker. Please wait..." --width=300
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Adding the Docker repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Updating package lists
zenity --info --text="Updating package lists for Docker installation..." --width=300
sudo apt-get update -y

# Installing Docker and its components
zenity --info --text="Installing Docker and its components. This may take a while..." --width=300
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Starting and enabling Docker service
zenity --info --text="Starting and enabling Docker service..." --width=300
sudo systemctl start docker
sudo systemctl enable docker

# Adding the main user to the Docker group
zenity --info --text="Adding your user to the Docker group..." --width=300
add_user_to_docker_group

# Notify completion
zenity --info --text="Docker has been installed and configured successfully." --width=300

#!/bin/bash

# Creating main folder and subfolders
zenity --info --text="Creating main folder and subfolders for blockchain data..." --width=300
sudo mkdir -p "${CUSTOM_PATH}"
sudo mkdir -p "${CUSTOM_PATH}/execution/$ETH_CLIENT"
sudo mkdir -p "${CUSTOM_PATH}/consensus/$CONSENSUS_CLIENT"

# Generating jwt.hex secret
if zenity --question --text="Do you want to generate a new jwt.hex secret file?" --width=300; then
    sudo sh -c "openssl rand -hex 32 > ${CUSTOM_PATH}/jwt.hex"
    zenity --info --text="jwt.hex secret generated successfully." --width=300
else
    zenity --info --text="Skipping jwt.hex generation." --width=300
fi

# Get main user name for folder permissions, assuming get_main_user defines $main_user
main_user=$(whoami)  # Simulate get_main_user function

# Creating users for Ethereum client and Consensus client, and setting permissions
zenity --info --text="Setting up user accounts and permissions..." --width=300
sudo useradd -M -G docker $ETH_CLIENT || zenity --error --text="Failed to create user $ETH_CLIENT. It may already exist." --width=300
sudo useradd -M -G docker $CONSENSUS_CLIENT || zenity --error --text="Failed to create user $CONSENSUS_CLIENT. It may already exist." --width=300

sudo chown -R ${ETH_CLIENT}:docker "${CUSTOM_PATH}/execution"
sudo chmod -R 750 "${CUSTOM_PATH}/execution"
sudo chown -R ${CONSENSUS_CLIENT}:docker "${CUSTOM_PATH}/consensus/"
sudo chmod -R 750 "${CUSTOM_PATH}/consensus"

zenity --info --text="Users created and permissions set." --width=300

# Setting permissions for jwt.hex file
zenity --info --text="Configuring access permissions for jwt.hex file..." --width=300
sudo groupadd pls-shared
sudo usermod -aG pls-shared ${ETH_CLIENT}
sudo usermod -aG pls-shared ${CONSENSUS_CLIENT}
sudo chown ${ETH_CLIENT}:pls-shared ${CUSTOM_PATH}/jwt.hex
sudo chmod 640 ${CUSTOM_PATH}/jwt.hex

zenity --info --text="Permissions for jwt.hex configured successfully." --width=300

# Confirmation of completion
zenity --info --text="Setup of folders, users, and permissions is complete." --width=300

# Setting up firewall rules with Zenity dialogs
zenity --info --text="Preparing to set up firewall rules for secure network operations." --width=300

# Retrieve IP range for local network
ip_range=$(get_ip_range)  # Ensure this function outputs the IP range appropriately

# Ask if the user wants to restrict RPC and SSH access to the local network
local_network_choice=$(zenity --list --radiolist --column="Select" --column="Choice" \
    FALSE "Yes, restrict to local network ($ip_range)" \
    TRUE "No, allow from any location" \
    --title="Local Network Restriction" --text="Do you want to restrict RPC and SSH access to your local network?" --width=500 --height=200)

# Ask if the user wants to enable RPC access
rpc_choice=$(zenity --list --radiolist --column="Select" --column="Choice" \
    TRUE "Yes" \
    FALSE "No" \
    --title="RPC Access" --text="Do you want to enable RPC access on port 8545?" --width=400 --height=200)

if [[ "$rpc_choice" == "Yes" ]]; then
    sudo ufw allow from 127.0.0.1 to any port 8545 proto tcp comment 'RPC Port'
    if [[ "$local_network_choice" == "Yes, restrict to local network ($ip_range)" ]]; then
        sudo ufw allow from $ip_range to any port 8545 proto tcp comment 'RPC Port for private IP range'
    fi
fi

# Ask if the user wants to enable SSH access
ssh_choice=$(zenity --list --radiolist --column="Select" --column="Choice" \
    TRUE "Yes" \
    FALSE "No" \
    --title="SSH Access" --text="Do you want to enable SSH access to this server?" --width=400 --height=200)

if [[ "$ssh_choice" == "Yes" ]]; then
    ssh_port=$(zenity --entry --title="SSH Port" --text="Enter SSH port (default is 22):" --entry-text="22")
    if [[ -z "$ssh_port" ]]; then
        ssh_port=22
    fi

    if [[ "$local_network_choice" == "Yes, restrict to local network ($ip_range)" ]]; then
        sudo ufw allow from $ip_range to any port $ssh_port proto tcp comment 'SSH Port for private IP range'
    else
        sudo ufw allow $ssh_port/tcp comment 'SSH Port'
    fi
fi

zenity --info --text="Firewall settings have been configured." --width=300

# Displaying information about setting default firewall rules
zenity --info --text="Setting default firewall rules to deny incoming and allow outgoing connections." --width=300

# Set default firewall rules
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Display what ports will be enabled based on user choices for the Ethereum client
if [ "$ETH_CLIENT_CHOICE" = "1" ]; then
  # Geth client ports
  message="Allowing network ports for Geth: TCP and UDP on port 30303."
  sudo ufw allow 30303/tcp
  sudo ufw allow 30303/udp
elif [ "$ETH_CLIENT_CHOICE" = "2" ]; then
  # Erigon client ports
  message="Allowing network ports for Erigon: TCP and UDP on ports 30303, 30304, 42069 and TCP on 4001, UDP on 4000."
  sudo ufw allow 30303/tcp
  sudo ufw allow 30303/udp
  sudo ufw allow 30304/tcp
  sudo ufw allow 30304/udp
  sudo ufw allow 42069/tcp
  sudo ufw allow 42069/udp
  sudo ufw allow 4000/udp
  sudo ufw allow 4001/tcp
fi

# Confirm firewall rules with the user
zenity --info --text="$message\n\nThe firewall is now configured to allow necessary ports for your Ethereum client." --width=400

# Enable the firewall
if zenity --question --text="Do you want to enable the firewall with these settings?" --width=300; then
    sudo ufw enable
    zenity --info --text="Firewall has been enabled." --width=300
else
    zenity --error --text="Firewall setup aborted." --width=300
    exit 1
fi

# Allow specific ports for consensus clients
if [ "$CONSENSUS_CLIENT" = "prysm" ]; then
  # Prysm client ports
  zenity --info --text="Allowing network ports for Prysm: TCP on port 13000 and UDP on port 12000." --width=300
  sudo ufw allow 13000/tcp
  sudo ufw allow 12000/udp
elif [ "$CONSENSUS_CLIENT" = "lighthouse" ]; then
  # Lighthouse client ports
  zenity --info --text="Allowing network port for Lighthouse: TCP/UDP on port 9000." --width=300
  sudo ufw allow 9000
fi

# Final prompt before enabling the firewall
if zenity --question --text="Ready to enable the firewall with the specified settings?" --width=300; then
    sudo ufw enable
    zenity --info --text="Firewall has been enabled successfully." --width=300
else
    zenity --error --text="Firewall activation cancelled." --width=300
    exit 1
fi

# Clear the screen and inform the user about script generation
zenity --info --text="Preparing to generate startup scripts for Ethereum and Consensus clients." --width=300

# Generate start_execution.sh script
cat > start_execution.sh <<EOL
#!/bin/bash

echo "Starting ${ETH_CLIENT}"
EOL

# Append the Docker command to start the execution client
if [ "$ETH_CLIENT" = "geth" ]; then
    echo "${GETH_CMD}" >> start_execution.sh
elif [ "$ETH_CLIENT" = "erigon" ]; then
    echo "${ERIGON_CMD}" >> start_execution.sh
fi

# Make the script executable and move it to the appropriate directory
chmod +x start_execution.sh
mv start_execution.sh "$CUSTOM_PATH"

# Inform user of script generation
zenity --info --text="Scripts to start Ethereum and Consensus clients have been created in $CUSTOM_PATH." --width=300


# Prompt to start script generation
if zenity --question --text="Do you want to generate the start_execution.sh script for the Ethereum client now?" --width=300; then
    echo "Starting ${ETH_CLIENT}" > start_execution.sh
    if [ "$ETH_CLIENT_CHOICE" = "1" ]; then
        # Pull Docker image and append command to the script
        sudo docker pull registry.gitlab.com/pulsechaincom/go-pulse:latest
        echo "${GETH_CMD}" >> start_execution.sh
    elif [ "$ETH_CLIENT_CHOICE" = "2" ]; then
        sudo docker pull registry.gitlab.com/pulsechaincom/erigon-pulse:latest
        echo "${ERIGON_CMD}" >> start_execution.sh
    elif [ "$ETH_CLIENT_CHOICE" = "3" ]; then
        echo "${ERIGON_CMD2}" >> start_execution.sh
    fi

    # Make the script executable and move it to the appropriate directory
    chmod +x start_execution.sh
    sudo mv start_execution.sh "$CUSTOM_PATH"
    sudo chown $main_user:docker "$CUSTOM_PATH/start_execution.sh"
    zenity --info --text="Execution script for ${ETH_CLIENT} has been generated and stored in $CUSTOM_PATH." --width=300
else
    zenity --error --text="Script generation aborted by user." --width=300
    exit 1
fi

# Prompt to generate start_consensus.sh script
if zenity --question --text="Do you want to generate the start_consensus.sh script for the Consensus client now?" --width=300; then
    echo "Starting ${CONSENSUS_CLIENT}" > start_consensus.sh

    # Continue script generation based on consensus client choice
    if [ "$CONSENSUS_CLIENT" = "prysm" ]; then
        sudo docker pull registry.gitlab.com/pulsechaincom/prysm-pulse/beacon-chain:latest
        echo "${PRYSM_CMD}" >> start_consensus.sh
    elif [ "$CONSENSUS_CLIENT" = "lighthouse" ]; then
        sudo docker pull registry.gitlab.com/pulsechaincom/lighthouse-pulse:latest
        echo "${LIGHTHOUSE_CMD}" >> start_consensus.sh
    fi

    chmod +x start_consensus.sh
    sudo mv start_consensus.sh "$CUSTOM_PATH"
    sudo chown $main_user:docker "$CUSTOM_PATH/start_consensus.sh"
    zenity --info --text="Consensus script for ${CONSENSUS_CLIENT} has been generated and stored in $CUSTOM_PATH." --width=300
else
    zenity --error --text="Script generation aborted by user." --width=300
    exit 1
fi


# Prompt to generate the start_consensus.sh script
if zenity --question --text="Do you want to generate the start_consensus.sh script for the Consensus client now?" --width=300; then
    echo "Starting ${CONSENSUS_CLIENT}" > start_consensus.sh

    # Pull Docker images and append the command based on the consensus client
    if [ "$CONSENSUS_CLIENT" = "prysm" ]; then
        sudo docker pull registry.gitlab.com/pulsechaincom/prysm-pulse/beacon-chain:latest
        sudo docker pull registry.gitlab.com/pulsechaincom/prysm-pulse/prysmctl:latest
        echo "${PRYSM_CMD}" >> start_consensus.sh
    elif [ "$CONSENSUS_CLIENT" = "lighthouse" ]; then
        sudo docker pull registry.gitlab.com/pulsechaincom/lighthouse-pulse:latest
        echo "${LIGHTHOUSE_CMD}" >> start_consensus.sh
    fi

    chmod +x start_consensus.sh
    sudo mv start_consensus.sh "$CUSTOM_PATH"
    sudo chown $main_user:docker "$CUSTOM_PATH/start_consensus.sh"
    zenity --info --text="Consensus script for ${CONSENSUS_CLIENT} has been generated and stored in $CUSTOM_PATH." --width=300
else
    zenity --error --text="Script generation aborted by user." --width=300
    exit 1
fi

echo ""
zenity --info --text="start_execution.sh and start_consensus.sh created successfully!" --width=300

# Create the helper directory if it doesn't exist
sudo mkdir -p "${CUSTOM_PATH}/helper"
zenity --info --text="Creating helper directory and copying necessary scripts..." --width=300

# Copy over helper scripts
sudo cp setup_validator.sh "$CUSTOM_PATH/helper"
sudo cp setup_monitoring.sh "$CUSTOM_PATH/helper"
sudo cp functions.sh "$CUSTOM_PATH/helper"
sudo cp helper/* "$CUSTOM_PATH/helper"

# Set permissions and ownership
sudo chmod -R +x $CUSTOM_PATH/helper/
sudo chmod -R 755 $CUSTOM_PATH/helper/
sudo chown -R $main_user:docker $CUSTOM_PATH/helper

zenity --info --text="Helper scripts copied and permissions set." --width=300

#!/bin/bash

# Permissions and copying feedback
zenity --info --text="Finished setting permissions and copying helper scripts." --width=300

# Creating a small menu for general housekeeping
zenity --info --text="Creating a small menu for general housekeeping..." --width=300
menu_script="$(script_launch_template)"
menu_script+="$(printf '\nhelper_scripts_path="%s/helper"\n' "${CUSTOM_PATH}")"
menu_script+="$(menu_script_template)"

# Write the menu script to the helper directory
echo "${menu_script}" | sudo tee "${CUSTOM_PATH}/menu.sh" > /dev/null
sudo chmod +x "${CUSTOM_PATH}/menu.sh"
sudo cp "${CUSTOM_PATH}/menu.sh" /usr/local/bin/plsmenu
sudo chown -R $main_user:docker "${CUSTOM_PATH}/menu.sh"
zenity --info --text="Menu script has been generated and written to ${CUSTOM_PATH}/menu.sh" --width=300

# Handling desktop shortcuts
if zenity --question --text="Do you want to add Desktop-Shortcuts to a menu for general logging and node/validator settings? This is recommended for easier access." --width=300; then
    create-desktop-shortcut "${CUSTOM_PATH}/helper/tmux_logviewer.sh" tmux_LOGS
    create-desktop-shortcut "${CUSTOM_PATH}/helper/log_viewer.sh" ui_LOGS
    # Uncomment these if needed in future updates
    # create-desktop-shortcut "${CUSTOM_PATH}/helper/restart_docker.sh" Restart-clients
    create-desktop-shortcut "${CUSTOM_PATH}/helper/stop_docker.sh" Stop-clients
    # create-desktop-shortcut "${CUSTOM_PATH}/helper/update_docker.sh" Update-clients
    create-desktop-shortcut "${CUSTOM_PATH}/menu.sh" Validator-Menu "${CUSTOM_PATH}/helper/LogoVector.svg"
    zenity --info --text="Desktop shortcuts created successfully. You may need to allow launching for these shortcuts." --width=300
else
    zenity --info --text="Desktop shortcuts creation skipped." --width=300
fi

echo "Menu generated and copied over to /usr/local/bin/plsmenu - you can open this helper menu by running plsmenu in the terminal."
zenity --info --text="Setup is complete. Press OK to finish." --width=300


# Setting permissions for execution folder for backup purposes
sudo chmod 775 -R "${CUSTOM_PATH}/execution"
zenity --info --text="Permissions set for backup purposes on execution folder." --width=300

# Validator setup prompt
if zenity --question --text="Would you like to setup a validator now?" --width=300; then
    echo "Starting setup_validator.sh script..."
    cd "${start_dir}"
    sudo chmod +x setup_validator.sh
    sudo ./setup_validator.sh
else
    zenity --info --text="Skipping creation of validator. You can always create a validator later by running the setup_validator.sh script separately." --width=300
fi

# Prompt to start the execution and consensus scripts
if zenity --question --text="Do you want to start the execution and consensus scripts now?" --width=300; then
    command1="${CUSTOM_PATH}/start_execution.sh > /dev/null 2>&1 &"
    command2="${CUSTOM_PATH}/start_consensus.sh > /dev/null 2>&1 &"
    eval "$command1"
    sleep 1
    eval "$command2"
    sleep 1
    zenity --info --text="The Ethereum and Consensus clients have been started successfully!" --width=300
else
    zenity --info --text="Execution and consensus scripts will not be started now." --width=300
fi

# Completion message
zenity --info --text="Congratulations, node installation/setup is now complete. You can close this window or continue to use the terminal." --width=300

# Display credits (assumed function display_credits exists, otherwise comment out or add your display logic)
display_credits

zenity --info --text="Setup complete! Press OK to exit." --width=300
