#!/bin/bash

# Define the GitHub repository URL
REPO_URL="https://github.com/tdslaine/install_pulse_node.git"

# Define a temporary directory to clone the repository
TMP_DIR=$(mktemp -d -t ci-$(date +%Y-%m-%d-%H-%M-%S)-XXXXXXXXXX)

# Clone the repository to the temporary directory
git clone $REPO_URL $TMP_DIR

# Prompt the user for the install location with a default value
read -e -p "Please enter the path to your install location (default is /blockchain): " INSTALL_PATH
INSTALL_PATH=${INSTALL_PATH:-/blockchain}

# Verify the directory exists or create it
if [ ! -d "$INSTALL_PATH" ]; then
    echo "Directory $INSTALL_PATH does not exist"
    exit 1
fi

# Get the current username and store it in the variable main_user
main_user=$(whoami)

# Replace the value of CUSTOM_PATH with the actual INSTALL_PATH in menu.sh
sed -i "/^CUSTOM_PATH=/c\CUSTOM_PATH=\"$INSTALL_PATH\"" $TMP_DIR/helper/menu.sh
sed -i "/^helper_scripts_path=/c\helper_scripts_path=\"$INSTALL_PATH/helper\"" $TMP_DIR/helper/menu.sh


cp $TMP_DIR/setup_validator.sh $INSTALL_PATH/helper
cp $TMP_DIR/setup_monitoring.sh $INSTALL_PATH/helper
cp $TMP_DIR/helper/* $INSTALL_PATH/helper/
mv $INSTALL_PATH/helper/menu.sh $INSTALL_PATH

chmod +x $INSTALL_PATH/helper/*.sh
chmod +x $INSTALL_PATH/menu.sh

chown $main_user $INSTALL_PATH/helper/*.sh
chown $main_user $INSTALL_PATH/menu.sh

# Create a symbolic link of the menu.sh file in /usr/local/bin and name it plsmenu
sudo rm /usr/local/bin/plsmenu
sudo ln -sf $INSTALL_PATH/menu.sh /usr/local/bin/plsmenu

# Remove the temporary directory
rm -rf $TMP_DIR

echo "Update completed successfully."
echo "Press Enter to quit"
read -p ""

# adding the cronjobs to restart docker-scripts here
# Define script paths
INSTALL_PATH=${INSTALL_PATH%/}
SCRIPTS=("$INSTALL_PATH/start_consensus.sh" "$INSTALL_PATH/start_execution.sh" "$INSTALL_PATH/start_validator.sh")

# Iterate over scripts and add them to crontab if they exist and are executable
for script in "${SCRIPTS[@]}"
do
    if [[ -x "$script" ]]
    then
        # Check if the script is already in the cron list
        if ! sudo crontab -l 2>/dev/null | grep -q "$script"; then
            # If it is not in the list, add script to root's crontab
            (sudo crontab -l 2>/dev/null; echo "@reboot $script > /dev/null 2>&1") | sudo crontab -
            echo "Added $script to root's cron jobs."
        else
            echo "$script is already in the cron jobs."
        fi
    else
        echo "Skipping $script - does not exist or is not executable."
    fi
done

echo "Process completed."


echo "Process completed."
exec /usr/local/bin/plsmenu
