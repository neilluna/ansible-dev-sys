#!/usr/bin/env bash

script_version=1.0.0

script_name=$(basename ${BASH_SOURCE[0]})
script_dir=$(dirname ${BASH_SOURCE[0]})
script_path=${BASH_SOURCE[0]}

function echo_usage()
{
	echo "${script_name} - Version ${script_version}"
	echo ""
	echo "Provision a virtual machine."
	echo ""
	echo "Usage: ${script_name} [options] [playbook_name]"
	echo ""
	echo "  -h, --help     Output this help information."
	echo "  -v, --verbose  Verbose output."
	echo "      --version  Output the version."
}

# ANSI color escape sequences for use in echo_color().
black='\e[30m'
red='\e[31m'
green='\e[32m'
yellow='\e[33m'
blue='\e[34m'
magenta='\e[35m'
cyan='\e[36m'
white='\e[37m'
reset='\e[0m'

# Echo color messages.
# Echoing ANSI escape codes for color works, yet tput does not.
# This may be caused by tput not being able to determine the terminal type.
# Usage: echo_color color message
function echo_color()
{
	color=${1}
	message=${2}
	echo -e "${color}${message}${reset}"
}

# Create a directory, if it does not exist.
# If created, set the mode of the new directory.
# Usage: create_dir_with_mode mode dir
function create_dir_with_mode()
{
	mode=${1}
	dir=${2}
	[ -d ${dir} ] && return
	echo_color ${cyan} "Creating ${dir} ..."
	mkdir -p ${dir}
	chmod ${mode} ${dir}
}

# Create a directory, if it does not exist.
# If created, set the mode, user, and group of the new directory.
# Usage: create_dir_with_mode_user_group mode user group dir
function create_dir_with_mode_user_group()
{
	mode=${1}
	user=${2}
	group=${3}
	dir=${4}
	[ -d ${dir} ] && return
	echo_color ${cyan} "Creating ${dir} ..."
	sudo mkdir -p ${dir}
	sudo chmod ${mode} ${dir}
	sudo chown ${user}:${group} ${dir}
}

# Attempt a command up to four times; one initial attempt followed by three reties.
# Attempts are spaced 15 seconds apart.
# Usage: retry_if_fail command args
function retry_if_fail()
{
	${*}
	if [ ${?} -ne 0 ]; then
		max_retries=3
		retry_wait=15
		retry=1
		while [ ${retry} -le ${max_retries} ]; do
			echo_color ${yellow} "- Failed. Will retry in ${retry_wait} seconds ..."
			sleep ${retry_wait}
			echo_color ${cyan} "- Retrying (${retry} of ${max_retries}) ..."
			${*} && break
			retry=$[$retry + 1]
		done
		if [ ${retry} -gt ${max_retries} ]; then
			echo_color ${red} "- Failed."
			exit 1
		fi
	fi
}

# Adds 127.0.0.1 to the known_hosts file for the specified user.
# Used to avoid prompts when Ansible uses SSH to provison the local host.
# Usage: add_localhost_to_known_hosts_for_user user
function add_localhost_to_known_hosts_for_user()
{
	user=${1}
	users_home_dir=$(eval echo ~${1})
	users_known_hosts_file=${users_home_dir}/.ssh/known_hosts
	if [ ! -f ${users_known_hosts_file} ]; then
		echo_color ${cyan} "Creating ${users_known_hosts_file} ..."
		touch ${users_known_hosts_file}
		chown ${user}:${user} ${users_known_hosts_file}
		chmod u+rw-x,go+r-wx ${users_known_hosts_file}
	fi
	ssh-keygen -F 127.0.0.1 -f ${users_known_hosts_file} > /dev/null 2>&1
	if [ ${?} -ne 0 ]; then
		echo_color ${cyan} "Adding the VM's SSH fingerprint to ${users_known_hosts_file} ..."
		ssh-keyscan -H 127.0.0.1 >> ${users_known_hosts_file}
	fi
}

# Provision directory and file modes. Keeps things private.
ASSET_DIR_MODE=u+rwx,go-rwx
ASSET_FILE_MODE=u+rw-x,go-rwx
ASSET_SCRIPT_MODE=u+rwx,go-rwx

# Use these variables instead of the string "root". "root" can be renamed.
ROOT_UID=0
ROOT_GID=0

# Command-line switch variables.
playbook_name=
verbose=no

# NOTE: This requires GNU getopt. On Mac OS X and FreeBSD, you have to install this separately.
ARGS=$(getopt -o hv -l help,verbose,version -n ${script_name} -- "${@}")
if [ ${?} != 0 ]; then
	exit 1
fi

# The quotes around "${ARGS}" are necessary.
eval set -- "${ARGS}"

# Parse the command line arguments.
while true; do
	case "${1}" in
		-h | --help)
			echo_usage
			exit 0
			;;
		-v | --verbose)
			verbose=yes
			shift
			;;
		--version)
			echo "${script_version}"
			exit 0
			;;
		--)
			shift
			break
			;;
	esac
done
while [ ${#} -gt 0 ]; do
	if [ -z "${playbook_name}" ]; then
		playbook_name=${1}
	else
		echo "${script_name}: Error: Invalid argument: ${1}" >&2
		echo_usage
		exit 1
	fi
	shift
done
if [ -z "${playbook_name}" ]; then
	playbook_name=common
fi

echo_color ${cyan} "Script: '${script_path}', playbook: '${playbook_name}'"
echo_color ${cyan} "Current user: '$(whoami)', home: '${HOME}'"
echo_color ${cyan} "Current directory: '$(pwd)'"

# Make installations non-interactive.
export DEBIAN_FRONTEND=noninteractive

# Create /opt if it is missing.
create_dir_with_mode_user_group u+rwx,go+rx-w ${ROOT_UID} ${ROOT_GID} /opt

echo_color ${cyan} "Running apt-get update ..."
retry_if_fail sudo apt-get update --yes

echo_color ${cyan} "Running apt-get upgrade ..."
retry_if_fail sudo apt-get upgrade --yes

echo_color ${cyan} "Installing or updating software-properties-common ..."
retry_if_fail sudo apt-get install --yes software-properties-common

echo_color ${cyan} "Installing or updating git ..."
retry_if_fail sudo apt-get install --yes git

# Create the provisioning assets directory.
assets_dir=${HOME}/.dev-sys
create_dir_with_mode ${ASSET_DIR_MODE} ${assets_dir}

# Install or update pyenv.
# Using pyenv will reduce the risk of corrupting the system Python.
pyenv_assets_dir=${assets_dir}/pyenv
create_dir_with_mode ${ASSET_DIR_MODE} ${pyenv_assets_dir}
if [ -z "${PYENV_ROOT}" ]; then
	echo_color ${cyan} "Installing the pyenv prerequisites ..."
	retry_if_fail sudo apt-get install --yes build-essential libssl-dev zlib1g-dev libbz2-dev \
	libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
	xz-utils tk-dev libffi-dev liblzma-dev python-openssl git make

	export PYENV_ROOT=${HOME}/.pyenv
	export PATH=${PYENV_ROOT}/bin:${PATH}

	pyenv_installer_script=${pyenv_assets_dir}/pyenv-installer.sh
	echo_color ${cyan} "Downloading ${pyenv_installer_script} ..."
	retry_if_fail curl --silent --show-error https://pyenv.run --output ${pyenv_installer_script}
	chmod ${ASSET_SCRIPT_MODE} ${pyenv_installer_script}

	echo_color ${cyan} "Installing pyenv ..."
	${pyenv_installer_script}
else
	echo_color ${cyan} "Updating pyenv ..."
	retry_if_fail pyenv update
fi

# Create or update the pyenv shell profile scriptlet.
pyenv_vars_script=${pyenv_assets_dir}/pyenv-vars.sh
echo_color ${cyan} "Creating ${pyenv_vars_script} ..."
cat << EOF > ${pyenv_vars_script}
#!/usr/bin/env bash
export PYENV_ROOT="${PYENV_ROOT}"
EOF
cat << 'EOF' >> ${pyenv_vars_script}
PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
chmod ${ASSET_SCRIPT_MODE} ${pyenv_vars_script}

echo_color ${cyan} "Sourcing ${pyenv_vars_script} ..."
source ${pyenv_vars_script}

# Install an isolated instance of Python for use by the dev-sys tools and Ansible.
python_version=3.8.0
if [ -z "$(pyenv versions | awk -v pyver=${python_version} '/^\*?\s+/ && ($1 == "*" ? $2 : $1) == pyver')" ]; then
	echo_color ${cyan} "Installing Python ${python_version} for the dev-sys Python virtual environment ..."
	retry_if_fail pyenv install ${python_version} || exit 1
fi

# Create the dev-sys Python virtual environemnt.
if [ -z "$(pyenv versions | awk '/^\*?\s+/ && ($1 == "*" ? $2 : $1) == "dev-sys"')" ]; then
	echo_color ${cyan} "Creating the dev-sys Python virtual environment ..."
	pyenv virtualenv ${python_version} dev-sys
fi
echo_color ${cyan} "Setting ${assets_dir} to use the dev-sys Python virtual environment ..."
cd ${assets_dir}
pyenv local dev-sys

export ANSIBLE_DEV_SYS_DIR=${assets_dir}/ansible-dev-sys
ansible_dev_sys_dir_script=${assets_dir}/ansible-dev-sys-dir.sh
if [ -f ${ansible_dev_sys_dir_script} ]; then
	echo_color ${cyan} "Sourcing ${ansible_dev_sys_dir_script} ..."
	source ${ansible_dev_sys_dir_script}
fi

# Clone or update ansible-dev-sys.
ansible_dev_sys_url=https://github.com/neilluna/ansible-dev-sys.git
if [ ! -d ${ANSIBLE_DEV_SYS_DIR} ]; then
	echo_color ${cyan} "Cloning ${ansible_dev_sys_url} to ${ANSIBLE_DEV_SYS_DIR} ..."
	retry_if_fail git clone ${ansible_dev_sys_url} ${ANSIBLE_DEV_SYS_DIR} || exit 1
	cd ${ANSIBLE_DEV_SYS_DIR}
	git config core.filemode false
elif [ -d ${ANSIBLE_DEV_SYS_DIR}/.git ]; then
	cd ${ANSIBLE_DEV_SYS_DIR}
	echo_color ${cyan} "Updating ${ANSIBLE_DEV_SYS_DIR} ..."
	retry_if_fail git pull
fi

# Install or update Ansible.
cd ${assets_dir}
if [ -z "$(pip list --disable-pip-version-check 2>/dev/null | awk '$1 == "ansible"')" ]; then
	echo_color ${cyan} "Installing Ansible ..."
	retry_if_fail pip install ansible --disable-pip-version-check
else
	echo_color ${cyan} "Updating Ansible ..."
	retry_if_fail pip install ansible --upgrade --disable-pip-version-check
fi

# Create the Ansible provisioning directory.
# This is where Ansible-related files will be stored.
ansible_assets_dir=${assets_dir}/ansible
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_assets_dir}

# Create the Ansible action plugins directory.
# This is where Ansible action plugins will be stored.
ansible_action_plugins_dir=${ansible_assets_dir}/action_plugins
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_action_plugins_dir}

# Install or update, and configure the ansible-merge-vars plugin.
if [ -z "$(pip list --disable-pip-version-check 2>/dev/null | awk '$1 == "ansible-merge-vars"')" ]; then
	echo_color ${cyan} "Installing ansible_merge_vars ..."
	retry_if_fail pip install ansible_merge_vars --disable-pip-version-check
else
	echo_color ${cyan} "Updating ansible_merge_vars ..."
	retry_if_fail pip install ansible_merge_vars --disable-pip-version-check --upgrade
fi
merge_vars_action_plugin=${ansible_action_plugins_dir}/merge_vars.py
echo_color ${cyan} "Creating ${merge_vars_action_plugin} ..."
cat << EOF > ${merge_vars_action_plugin}
from ansible_merge_vars import ActionModule
EOF
chmod ${ASSET_SCRIPT_MODE} ${merge_vars_action_plugin}

# Create the SSH keys used to run commands as the dev-sys user.
dev_sys_ssh_key_basename=id_dev-sys
dev_sys_ssh_private_key_file=${assets_dir}/${dev_sys_ssh_key_basename}
dev_sys_ssh_public_key_file=${dev_sys_ssh_private_key_file}.pub
if [ ! -f ${dev_sys_ssh_private_key_file} ]; then
	echo_color ${cyan} "Creating new SSH keys for dev-sys use ..."
	ssh-keygen -C ${dev_sys_ssh_key_basename} -f ${dev_sys_ssh_private_key_file} -N ""
	chmod ${ASSET_FILE_MODE} ${dev_sys_ssh_private_key_file}
	chmod ${ASSET_FILE_MODE} ${dev_sys_ssh_public_key_file}
fi
dev_sys_ssh_public_key_contents=$(cat ${dev_sys_ssh_public_key_file})
dev_sys_authorized_keys_file=${HOME}/.ssh/authorized_keys
grep -Fx "${dev_sys_ssh_public_key_contents}" ${dev_sys_authorized_keys_file} > /dev/null
if [ ${?} -ne 0 ]; then
	echo_color ${cyan} "Adding the dev-sys SSH public key to ${dev_sys_authorized_keys_file} ..."
	echo "${dev_sys_ssh_public_key_contents}" >> ${dev_sys_authorized_keys_file}
fi
add_localhost_to_known_hosts_for_user $(whoami)

# Create the Ansible inventories directory.
ansible_inventories_dir=${ansible_assets_dir}/inventories
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_inventories_dir}

# Create the Ansible host variables for this system.
ansible_host_vars_dir=${ansible_inventories_dir}/host_vars
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_host_vars_dir}
ansible_host_vars_file=${ansible_host_vars_dir}/$(hostname).yml
echo_color ${cyan} "Creating ${ansible_host_vars_file} ..."
cat << EOF > ${ansible_host_vars_file}
---
ansible_connection: ssh
ansible_host: 127.0.0.1
ansible_python_interpreter: $(PYENV_VERSION=system pyenv which python3)
ansible_user: $(whoami)
ansible_ssh_private_key_file: ${dev_sys_ssh_private_key_file}
EOF
chmod ${ASSET_FILE_MODE} ${ansible_host_vars_file}

# Create the Ansible group variables for this system.
ansible_group_vars_dir=${ansible_inventories_dir}/group_vars
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_group_vars_dir}
ansible_group_vars_file=${ansible_group_vars_dir}/dev_sys.yml
echo_color ${cyan} "Creating ${ansible_group_vars_file} ..."
cat << EOF > ${ansible_group_vars_file}
---
EOF
chmod ${ASSET_FILE_MODE} ${ansible_group_vars_file}

export BASH_ENVIRONMENT_DIR=${assets_dir}/bash-environment
bash_environment_dir_script=${assets_dir}/bash-environment-dir.sh
if [ -f ${bash_environment_dir_script} ]; then
	echo_color ${cyan} "Sourcing ${bash_environment_dir_script} ..."
	source ${bash_environment_dir_script}
fi

# Add the bash-environment variables to the Ansible group variables.
echo_color ${cyan} "Adding the bash-environment variables to ${ansible_group_vars_file} ..."
cat << EOF >> ${ansible_group_vars_file}
bash_environment:
  dir: ${BASH_ENVIRONMENT_DIR}
EOF

# Create the Ansible inventory file.
ansible_inventory_file=${ansible_inventories_dir}/inventory.ini
echo_color ${cyan} "Creating ${ansible_inventory_file} ..."
cat << EOF > ${ansible_inventory_file}
[dev_sys]
$(hostname)
EOF
chmod ${ASSET_FILE_MODE} ${ansible_inventory_file}

# Create the Ansible configuration file.
ansible_config_file=${ansible_assets_dir}/ansible.cfg
echo_color ${cyan} "Creating ${ansible_config_file} ..."
cat << EOF > ${ansible_config_file}
[defaults]
action_plugins = ${ansible_action_plugins_dir}
force_color = True
inventory = ${ansible_inventory_file}
roles_path = ${ANSIBLE_DEV_SYS_DIR}/ansible/roles
EOF
chmod ${ASSET_FILE_MODE} ${ansible_config_file}

ansible_vars_script=${ansible_assets_dir}/ansible-vars.sh
echo_color ${cyan} "Creating ${ansible_vars_script} ..."
cat << EOF > ${ansible_vars_script}
#!/usr/bin/env bash
export ANSIBLE_CONFIG=${ansible_config_file}
export PYTHONUNBUFFERED=1
EOF
chmod ${ASSET_FILE_MODE} ${ansible_vars_script}

echo_color ${cyan} "Sourcing ${ansible_vars_script} ..."
source ${ansible_vars_script}

ansible_playbook_dir=${ANSIBLE_DEV_SYS_DIR}/ansible
ansible_play_script=${ansible_assets_dir}/ansible-play.sh
echo_color ${cyan} "Creating ${ansible_play_script} ..."
cat << EOF > ${ansible_play_script}
#!/usr/bin/env bash
ansible_playbook_dir=${ansible_playbook_dir}
EOF
cat << 'EOF' >> ${ansible_play_script}
ansible-playbook ${ansible_playbook_dir}/${1}.yml || exit 1
exit 0
EOF
chmod ${ASSET_SCRIPT_MODE} ${ansible_play_script}

echo_color ${cyan} "Running Ansible playbook '${playbook_name}' ..."
${ansible_play_script} ${playbook_name} || exit 1

exit 0
