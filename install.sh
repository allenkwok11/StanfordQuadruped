#!/bin/bash

# check Ubuntu version
source /etc/os-release

if [[ $UBUNTU_CODENAME != 'jammy' && $UBUNTU_CODENAME != 'noble' ]]
then
    echo "Ubuntu 22.04.1 LTS (Jammy Jellyfish) is required or Ubuntu 24.04 LTS (noble)"
    echo "You are using $VERSION"
    exit 1
fi

### Get directory where this script is installed
BASEDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

### Append to release file
echo STANFORD_VERSION=\"$(cd $BASEDIR; ~/mini_pupper_bsp/get-version.sh)\" >> ~/mini-pupper-release

ensure_repo() {
    local repo_url="$1"
    local target_dir="$2"

    if [ -d "$target_dir/.git" ]; then
        git -C "$target_dir" pull --ff-only || true
    elif [ -d "$target_dir" ]; then
        echo "Warning: $target_dir exists and is not a git repository, skipping clone"
    else
        git clone "$repo_url" "$target_dir"
    fi
}

source  ~/mini-pupper-release
if [ "$IS_RELEASE" == "YES" ]
then
    cd $BASEDIR
    TAG_COMMIT=$(git rev-list --abbrev-commit --tags --max-count=1)
    TAG=$(git describe --abbrev=0 --tags ${TAG_COMMIT} 2>/dev/null || true)
    if [ "v$STANFORD_VERSION" != "$TAG" ]
    then
        sed -i "s/IS_RELEASE=YES/IS_RELEASE=NO/" ~/mini-pupper-release
    fi
fi

sudo apt-get install -y libatlas-base-dev unzip python3-pip

PY_PKGS="numpy transforms3d pyserial"
if [[ "$UBUNTU_CODENAME" == "noble" ]]
then
    # Ubuntu 24.04 enables PEP 668, so system pip writes require this flag.
    sudo python3 -m pip install --break-system-packages $PY_PKGS
else
    sudo python3 -m pip install $PY_PKGS
fi

# add bridge to network configuration
$BASEDIR/configure_network.sh
# reconfigure network each time network configuration has changed
grep -qxF "$BASEDIR/configure_network.sh" /home/ubuntu/mini_pupper_bsp/System/check-reconfigure.sh || \
    echo "$BASEDIR/configure_network.sh" >> /home/ubuntu/mini_pupper_bsp/System/check-reconfigure.sh

cd ~
ensure_repo https://github.com/stanfordroboticsclub/PupperCommand.git ~/PupperCommand
cd PupperCommand
sed -i "s/pi/ubuntu/" joystick.service
sudo bash install.sh

cd ~
ensure_repo https://github.com/stanfordroboticsclub/UDPComms.git ~/UDPComms
cd UDPComms
sudo bash install.sh

cd ~
ensure_repo https://github.com/stanfordroboticsclub/PS4Joystick.git ~/PS4Joystick
cd PS4Joystick
sed -i "s/pi/ubuntu/" joystick.service
sudo bash install.sh

cd ~
sudo systemctl enable joystick

cd ~/StanfordQuadruped
sudo ln -sf "$(realpath ./robot.service)" /etc/systemd/system/robot.service
sudo systemctl daemon-reload
sudo systemctl enable robot
sudo systemctl start robot

if [ -f restart_joy.service ]; then
    sudo install -m 644 restart_joy.service /lib/systemd/system/restart_joy.service
fi
if [ -f joystart.sh ]; then
    sudo install -m 755 joystart.sh /sbin/joystart.sh
fi
sudo systemctl enable restart_joy
source  ~/mini-pupper-release
if [ "$MACHINE" == "x86_64" ]
then
    if [ "$HARDWARE" == "mini_pupper_2" ]
    then
        sudo systemctl start esp32-proxy &
        sudo systemctl start battery_monitor &
    else
        sudo systemctl start battery_monitor
    fi
    sudo systemctl start rc-local
    sudo systemctl start robot
fi
