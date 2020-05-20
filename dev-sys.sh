#!/usr/bin/env bash

script_version=1.0.0

script_name=$(basename ${BASH_SOURCE[0]})
script_dir=$(dirname ${BASH_SOURCE[0]})

function echo_usage()
{
	echo "${script_name} - Version ${script_version}"
	echo ""
	echo "Provision a VirtualBox virtual machine."
	echo ""
	echo "Usage: ${script_name} [options]"
	echo ""
	echo "  -h, --help     Output this help information and exit successfully."
	echo "      --version  Output the version and exit successfully."
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
PROVISIONING_DIR_MODE=u+rwx,go-rwx
PROVISIONING_FILE_MODE=u+rw-x,go-rwx
PROVISIONING_SCRIPT_MODE=u+rwx,go-rwx

# Use these variables instead of the string "root". "root" can be renamed.
ROOT_UID=0
ROOT_GID=0

# NOTE: This requires GNU getopt. On Mac OS X and FreeBSD, you have to install this separately.
ARGS=$(getopt -o h -l help,version -n ${script_name} -- "${@}")
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

echo_color ${cyan} "Script: '${script_name}', Script directory: '${script_dir}'"
echo_color ${cyan} "Current user: '$(whoami)', Home directory: '${HOME}', Current directory: '$(pwd)'"

# Create /opt if it is missing.
create_dir_with_mode_user_group u+rwx,go+rx-w ${ROOT_UID} ${ROOT_GID} /opt

echo_color ${cyan} "Running apt-get update ..."
retry_if_fail sudo apt-get update --yes

echo_color ${cyan} "Running apt-get upgrade ..."
retry_if_fail sudo apt-get upgrade --yes

echo_color ${cyan} "Installing software-properties-common ..."
retry_if_fail sudo apt-get install --yes software-properties-common

echo_color ${cyan} "Installing git ..."
retry_if_fail sudo apt install --yes git

# Create the provisioning directory.
# This is where dev-sys files will be stored.
provisioning_dir=${HOME}/.dev-sys-provisioning
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${provisioning_dir}

# Create the git provisioning directory.
# This is where git-related files will be stored.
git_provisioning_dir=${provisioning_dir}/git
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${provisioning_dir}

# Install ~/.gitconfig.
git_config_file=${git_provisioning_dir}/gitconfig
if [ -f ${git_config_file} ]; then
	if [ ! -f ~/.gitconfig ]; then
		echo_color ${cyan} "Installing ~/.gitconfig ..."
		cp ${git_config_file} ~/.gitconfig
		chmod u+rw-x,go+r-rw ~/.gitconfig
	else
		echo_color ${cyan} "~/.gitconfig already exists. Assuming that it is correct."
	fi
fi
if [ ! -f ~/.gitconfig ]; then
	echo_color ${yellow} "~/.gitconfig does not exist. You should create one."
fi

# Install the git configuration script.
git_vars_script=${git_provisioning_dir}/git-vars.sh
echo_color ${cyan} "Creating ${git_vars_script} ..."
if [ -f ${git_vars_script} ]; then
	rm -f ${git_vars_script}
fi
git_ssh_private_key_file=${git_provisioning_dir}/id_git
cat << EOF > ${git_vars_script}
#!/usr/bin/env bash
[ -f "${git_ssh_private_key_file}" ] && export GIT_SSH_COMMAND='ssh -i ${git_ssh_private_key_file}'
EOF
chmod ${PROVISIONING_SCRIPT_MODE} ${git_vars_script}

echo_color ${cyan} "Sourcing ${git_vars_script} ..."
source ${git_vars_script}

# Install or update pyenv.
# Using pyenv will reduce the risk of corrupting the system Python.
pyenv_provisioning_dir=${provisioning_dir}/pyenv
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${pyenv_provisioning_dir}
if [ -z "${PYENV_ROOT}" ]; then
	echo_color ${cyan} "Installing the pyenv prerequisites ..."
	retry_if_fail sudo apt-get install --yes build-essential libssl-dev zlib1g-dev libbz2-dev \
	libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
	xz-utils tk-dev libffi-dev liblzma-dev python-openssl git make

	export PYENV_ROOT=${HOME}/.pyenv
	export PATH=${PYENV_ROOT}/bin:${PATH}

	pyenv_installer_script=${pyenv_provisioning_dir}/pyenv-installer.sh
	echo_color ${cyan} "Downloading ${pyenv_installer_script} ..."
	retry_if_fail curl --silent --show-error https://pyenv.run --output ${pyenv_installer_script}
	chmod ${PROVISIONING_SCRIPT_MODE} ${pyenv_installer_script}

	echo_color ${cyan} "Installing pyenv ..."
	${pyenv_installer_script}
else
	echo_color ${cyan} "Updating pyenv ..."
	retry_if_fail pyenv update
fi

# Create or update the pyenv shell profile scriptlet.
pyenv_vars_script=${pyenv_provisioning_dir}/pyenv-vars.sh
echo_color ${cyan} "Creating ${pyenv_vars_script} ..."
if [ -f ${pyenv_vars_script} ]; then
	rm -f ${pyenv_vars_script}
fi
cat << EOF > ${pyenv_vars_script}
#!/usr/bin/env bash
export PYENV_ROOT="${PYENV_ROOT}"
EOF
cat << 'EOF' >> ${pyenv_vars_script}
PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
chmod ${PROVISIONING_SCRIPT_MODE} ${pyenv_vars_script}

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
echo_color ${cyan} "Setting ${provisioning_dir} to use the dev-sys Python virtual environment ..."
cd ${provisioning_dir}
pyenv local dev-sys

# Clone or update ansible-dev-sys.
ansible_dev_sys_url=https://github.com/neilluna/ansible-dev-sys.git
ansible_dev_sys_dir=${provisioning_dir}/ansible-dev-sys
if [ ! -d ${ansible_dev_sys_dir} ]; then
	echo_color ${cyan} "Cloning ${ansible_dev_sys_url} to ${ansible_dev_sys_dir} ..."
	retry_if_fail git clone ${ansible_dev_sys_url} ${ansible_dev_sys_dir} || exit 1
	cd ${ansible_dev_sys_dir}
	git config core.autocrlf false
	git config core.filemode false
	ansible_dev_sys_script=${git_provisioning_dir}/ansible-dev-sys.sh
	if [ -f ${ansible_dev_sys_script} ]; then
		echo_color ${cyan} "Sourcing ${ansible_dev_sys_script} ..."
		source ${ansible_dev_sys_script}
		echo_color ${cyan} "Changing to branch ${DEV_SYS_ANSIBLE_DEV_SYS_BRANCH} ..."
		git checkout ${DEV_SYS_ANSIBLE_DEV_SYS_BRANCH}
	fi
else
	cd ${ansible_dev_sys_dir}
	echo_color ${cyan} "Updating ${ansible_dev_sys_dir} ..."
	retry_if_fail git pull
fi

# Install or update Ansible.
cd ${provisioning_dir}
if [ -z "$(pip list --disable-pip-version-check 2>/dev/null | awk '$1 == "ansible"')" ]; then
	echo_color ${cyan} "Installing Ansible ..."
	retry_if_fail pip install ansible --disable-pip-version-check
else
	echo_color ${cyan} "Updating Ansible ..."
	retry_if_fail pip install ansible --upgrade --disable-pip-version-check
fi

# Create the Ansible provisioning directory.
# This is where Ansible-related files will be stored.
ansible_provisioning_dir=${provisioning_dir}/ansible
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${ansible_provisioning_dir}

# Create the Ansible action plugins directory.
# This is where Ansible action plugins will be stored.
ansible_action_plugins_dir=${ansible_provisioning_dir}/action_plugins
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${ansible_action_plugins_dir}

# Install or update, and configure the ansible-merge-vars plugin.
if [ -z "$(pip list --disable-pip-version-check 2>/dev/null | awk '$1 == "ansible-merge-vars"')" ]; then
	echo_color ${cyan} "Installing the ansible-merge-vars plugin ..."
	retry_if_fail pip install ansible_merge_vars --disable-pip-version-check
else
	echo_color ${cyan} "Updating the ansible-merge-vars plugin ..."
	retry_if_fail pip install ansible_merge_vars --disable-pip-version-check --upgrade
fi
merge_vars_action_plugin=${ansible_action_plugins_dir}/merge_vars.py
cat << EOF > ${merge_vars_action_plugin}
from ansible_merge_vars import ActionModule
EOF
chmod ${PROVISIONING_SCRIPT_MODE} ${merge_vars_action_plugin}

ansible_user=$(whoami)

# Create the SSH keys used for Ansible self-provisioning.
ansible_ssh_private_key_file=${ansible_provisioning_dir}/id_ansible
ansible_ssh_public_key_file=${ansible_ssh_private_key_file}.pub
if [ ! -f ${ansible_ssh_private_key_file} ]; then
	echo_color ${cyan} "Creating new SSH keys for Ansible self-provisioning ..."
	ssh-keygen -C id_ansible -f ${ansible_ssh_private_key_file} -N ""
	chmod u+rw-x,go-rwx ${ansible_ssh_private_key_file}
	chmod u+rw-x,go+r-wx ${ansible_ssh_public_key_file}
fi
ansible_ssh_public_key_contents=$(cat ${ansible_ssh_public_key_file})
authorized_keys_file=${HOME}/.ssh/authorized_keys
grep -Fx "${ansible_ssh_public_key_contents}" ${authorized_keys_file} > /dev/null
if [ ${?} -ne 0 ]; then
	echo_color ${cyan} "Adding the new Ansible SSH public key to ${authorized_keys_file} ..."
	echo "${ansible_ssh_public_key_contents}" >> ${authorized_keys_file}
fi
add_localhost_to_known_hosts_for_user ${ansible_user}

# Create the Ansible inventories directory.
# This is where Ansible inventory and variable files will be stored.
ansible_inventories_dir=${ansible_provisioning_dir}/inventories
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${ansible_inventory_dir}

# Create the Ansible host variables for this system.
ansible_host_vars_dir=${ansible_inventories_dir}/host_vars
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${ansible_host_vars_dir}
ansible_host_vars_file=${ansible_host_vars_dir}/$(hostname).yml
echo_color ${cyan} "Creating ${ansible_host_vars_file} ..."
cat << EOF > ${ansible_host_vars_file}
---
ansible_connection: ssh
ansible_host: 127.0.0.1
ansible_python_interpreter: $(PYENV_VERSION=system pyenv which python3)
ansible_user: ${ansible_user}
ansible_ssh_private_key_file: ${ansible_ssh_private_key_file}
EOF
chmod ${PROVISIONING_FILE_MODE} ${ansible_host_vars_file}

# Create the Ansible group variables for this system.
ansible_group_vars_dir=${ansible_inventories_dir}/group_vars
create_dir_with_mode ${PROVISIONING_DIR_MODE} ${ansible_group_vars_dir}
ansible_group_vars_file=${ansible_group_vars_dir}/dev_sys.yml
echo_color ${cyan} "Creating ${ansible_host_vars_file} ..."
cat << EOF > ${ansible_group_vars_file}
---
EOF
chmod ${PROVISIONING_FILE_MODE} ${ansible_group_vars_file}

# Add the bash-environment variables to the Ansible group variables.
echo_color ${cyan} "Adding the bash-environment variables to ${ansible_group_vars_file} ..."
cat << EOF >> ${ansible_group_vars_file}
bash_environment:
  dest: ~/.dev-sys-provisioning/bash-environment
EOF
bash_environment_script=${git_provisioning_dir}/bash-environment.sh
if [ -f ${bash_environment_script} ]; then
	echo_color ${cyan} "Sourcing ${bash_environment_script} ..."
	source ${bash_environment_script}
	echo "  version: ${DEV_SYS_BASH_ENVIRONMENT_BRANCH}" >> ${ansible_group_vars_file}
fi

# Create the Ansible inventory file.
ansible_inventory_file=${ansible_inventories_dir}/inventory.yml
echo_color ${cyan} "Creating ${ansible_inventory_file} ..."
cat << EOF > ${ansible_inventory_file}
---
dev_sys:
  hosts:
    $(hostname)
EOF
chmod ${PROVISIONING_FILE_MODE} ${ansible_inventory_file}

# Create the Ansible configuration file.
ansible_config_file=${ansible_provisioning_dir}/ansible.cfg
echo_color ${cyan} "Creating ${ansible_config_file} ..."
cat << EOF > ${ansible_config_file}
[defaults]
action_plugins = ${ansible_action_plugins_dir}
force_color = True
inventory = ${ansible_inventory_file}
roles_path = ${ansible_dev_sys_dir}/ansible/roles
EOF
chmod ${PROVISIONING_FILE_MODE} ${ansible_config_file}

ansible_vars_script=${ansible_provisioning_dir}/ansible-vars.sh
echo_color ${cyan} "Creating ${ansible_vars_script} ..."
cat << EOF > ${ansible_vars_script}
#!/usr/bin/env bash
export ANSIBLE_CONFIG=${ansible_config_file}
export PYTHONUNBUFFERED=1
EOF
chmod ${PROVISIONING_FILE_MODE} ${ansible_vars_script}

echo_color ${cyan} "Sourcing ${ansible_vars_script} ..."
source ${ansible_vars_script}

ansible_play_script=${ansible_provisioning_dir}/ansible-play.sh
ansible_playbook=${ansible_dev_sys_dir}/ansible/dev-sys.yml
echo_color ${cyan} "Creating ${ansible_play_script} ..."
cat << EOF > ${ansible_play_script}
#!/usr/bin/env bash
ansible-playbook ${ansible_playbook} || exit 1
exit 0
EOF
chmod ${PROVISIONING_SCRIPT_MODE} ${ansible_play_script}

echo_color ${cyan} "Running ${ansible_play_script} ..."
${ansible_play_script} || exit 1

exit 0
