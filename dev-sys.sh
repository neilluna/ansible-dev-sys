#!/usr/bin/env bash

script_version=0.2.0

script_name=$(basename ${BASH_SOURCE[0]})
script_dir=$(dirname ${BASH_SOURCE[0]})
script_path=${BASH_SOURCE[0]}

function echo_usage()
{
	echo "${script_name} - Version ${script_version}"
	echo ""
	echo "Provision a virtual machine."
	echo ""
	echo "Usage: ${script_name} [options] [tag [tag] ...]"
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

# Echo an informational message.
# Usage: echo_info message
function echo_info()
{
	message=${1}
	echo -e "${cyan}${message}${reset}"
}

# Echo a warning message.
# Usage: echo_warning message
function echo_warning()
{
	message=${1}
	echo -e "${yellow}${message}${reset}"
}

# Echo an error message.
# Usage: echo_error message
function echo_error()
{
	message=${1}
	echo -e "${red}${message}${reset}"
}

# Echo an error message and exit.
# Usage: echo_error_and_exit message
function echo_error_and_exit()
{
	echo_error "${1}"
	exit 1
}

# Create a directory, if it does not exist.
# If created, then set the mode of the new directory.
# Usage: create_dir_with_mode mode dir
function create_dir_with_mode()
{
	mode=${1}
	dir=${2}
	[ -d ${dir} ] && return
	echo_info "Creating ${dir} ..."
	mkdir -p ${dir}
	chmod ${mode} ${dir}
}

# Check if a program exists and is executable by this user.
# Echoes an error message and exits the script if the program does not exist or is not executable by this user.
# Usage: check_program program
function check_program()
{
	program=${1}
	full_path=$(which ${program})
	if [ -z "${full_path}" ] || [ ! -x "${full_path}" ]; then
		echo_error_and_exit "Cannot execute '${program}'."
	fi
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
			echo_warning "'${*}' failed. Will retry in ${retry_wait} seconds."
			sleep ${retry_wait}
			echo_info "Retrying '${*}' (${retry} of ${max_retries}) ..."
			${*} && break
			retry=$[$retry + 1]
		done
		if [ ${retry} -gt ${max_retries} ]; then
			echo_error_and_exit "'${*}' failed after $[$max_retries + 1] attempts."
		fi
	fi
}

# Provision directory and file modes.
# Keeps things very private.
# Along with other things, these modes are also used for private keys and credentials.
ASSET_DIR_MODE=u+rwx,go-rwx
ASSET_FILE_MODE=u+rw-x,go-rwx
ASSET_SCRIPT_MODE=u+rwx,go-rwx

# Use these variables instead of the string "root". "root" can be renamed.
ROOT_UID=0
ROOT_GID=0

# Command-line switch variables.
tags=
verbose=no

# NOTE: This requires GNU getopt. On Mac OS X and FreeBSD, you have to install this separately.
ARGS=$(getopt -o hv -l help,verbose,version -n ${script_name} -- "${@}")
if [ ${?} -ne 0 ]; then
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
	if [ -z "${tags}" ]; then
		tags="${1}"
	else
		tags="${tags},${1}"
	fi
	shift
done

echo_info "Script: ${script_path}"
echo_info "Current user: $(whoami)"
echo_info "Home directory: ${HOME}"
echo_info "Current directory: $(pwd)"

[ ! -z "${called_from_self_update}" ] && echo_info "Called from dev-sys self update ..."

# Make installations non-interactive.
export DEBIAN_FRONTEND=noninteractive

# Do not buffer Python stdout.
export PYTHONUNBUFFERED=TRUE

# The dev-sys assets directory.
assets_dir=${HOME}/.dev-sys

# Determine the Ansible tags to be used.
ANSIBLE_DEV_SYS_TAGS=always
dev_sys_vars_script=${assets_dir}/dev-sys-vars.sh
[ -f ${dev_sys_vars_script} ] && source ${dev_sys_vars_script}
[ -z "${tags}" ] && tags=${ANSIBLE_DEV_SYS_TAGS}
echo_info "Ansible tags: ${tags}"

# Create the dev-sys assets directory.
create_dir_with_mode ${ASSET_DIR_MODE} ${assets_dir}

# Save the Ansible tags.
echo_info "Creating ${dev_sys_vars_script} ..."
cat << EOF > ${dev_sys_vars_script}
#!/usr/bin/env bash
ANSIBLE_DEV_SYS_TAGS=${tags}
EOF
chmod ${ASSET_SCRIPT_MODE} ${dev_sys_vars_script}

echo_info "Checking dependencies ..."
check_program ssh
check_program ssh-keygen
check_program ssh-keyscan

# Create the SSH directory.
ssh_dir=${HOME}/.ssh
create_dir_with_mode ${ASSET_DIR_MODE} ${ssh_dir}

# Create the SSH keys used to run commands as the dev-sys user.
dev_sys_ssh_key_basename=id_dev-sys
dev_sys_ssh_private_key_file=${assets_dir}/${dev_sys_ssh_key_basename}
dev_sys_ssh_public_key_file=${assets_dir}/${dev_sys_ssh_key_basename}.pub
if [ ! -f ${dev_sys_ssh_private_key_file} ]; then
	echo_info "Creating new SSH keys for use by dev-sys ..."
	ssh-keygen -C ${dev_sys_ssh_key_basename} -f ${dev_sys_ssh_private_key_file} -N ""
	chmod ${ASSET_FILE_MODE} ${dev_sys_ssh_private_key_file}
	chmod ${ASSET_FILE_MODE} ${dev_sys_ssh_public_key_file}
fi
dev_sys_ssh_public_key_contents=$(cat ${dev_sys_ssh_public_key_file})
ssh_authorized_keys_file=${ssh_dir}/authorized_keys
if [ ! -f ${ssh_authorized_keys_file} ]; then
	touch ${ssh_authorized_keys_file}
	chmod ${ASSET_FILE_MODE} ${ssh_authorized_keys_file}
fi
grep -Fx "${dev_sys_ssh_public_key_contents}" ${ssh_authorized_keys_file} > /dev/null
if [ ${?} -ne 0 ]; then
	echo_info "Adding the dev-sys SSH public key to ${ssh_authorized_keys_file} ..."
	echo "${dev_sys_ssh_public_key_contents}" >> ${ssh_authorized_keys_file}
fi

# Adds 127.0.0.1 to the known_hosts file.
# This will avoid prompts when Ansible uses SSH to provison the local host.
ssh_known_hosts_file=${ssh_dir}/known_hosts
if [ ! -f ${ssh_known_hosts_file} ]; then
	echo_info "Creating ${ssh_known_hosts_file} ..."
	touch ${ssh_known_hosts_file}
	chmod u+rw-x,go+r-wx ${ssh_known_hosts_file}
fi
ssh-keygen -F 127.0.0.1 -f ${ssh_known_hosts_file} > /dev/null 2>&1
if [ ${?} -ne 0 ]; then
	echo_info "Adding the local host's SSH fingerprint to ${ssh_known_hosts_file} ..."
	ssh-keyscan -H 127.0.0.1 >> ${ssh_known_hosts_file} || exit 1
fi

echo_info "Checking SSH connectivity to the local host ..."
ssh $(whoami)@127.0.0.1 -i ${dev_sys_ssh_private_key_file} echo Ok || exit 1

echo_info "Running apt-get update ..."
retry_if_fail sudo apt-get update --yes

echo_info "Running apt-get upgrade ..."
retry_if_fail sudo apt-get upgrade --yes

echo_info "Installing or updating software-properties-common ..."
retry_if_fail sudo apt-get install --yes software-properties-common

echo_info "Installing or updating git ..."
retry_if_fail sudo apt-get install --yes git

# ansible-dev-sys: Where is it, and is it being managed by an external process?
# If ansible-dev-sys is being managed by an external process, then this script will not update it.
ANSIBLE_DEV_SYS_DIR=${assets_dir}/ansible-dev-sys
ANSIBLE_DEV_SYS_MANAGED_EXTERNALLY=false
ansible_dev_sys_vars_script=${assets_dir}/ansible-dev-sys-vars.sh
if [ -f ${ansible_dev_sys_vars_script} ]; then
	echo_info "Sourcing ${ansible_dev_sys_vars_script} ..."
	source ${ansible_dev_sys_vars_script}
fi

# If ansible-dev-sys is being managed by this script (not externally), then install or update it.
if [ ${ANSIBLE_DEV_SYS_MANAGED_EXTERNALLY} == false ]; then
	ansible_dev_sys_update_script=${assets_dir}/ansible-dev-sys-update.sh
	if [ -z "${called_from_self_update}" ]; then

		# Clone a new copy of ansible-dev-sys.
		new_ansible_dev_sys_dir=${assets_dir}/new-ansible-dev-sys
		ansible_dev_sys_url=https://github.com/neilluna/ansible-dev-sys.git
		echo_info "Cloning ${ansible_dev_sys_url} to ${new_ansible_dev_sys_dir} ..."
		retry_if_fail git clone ${ansible_dev_sys_url} ${new_ansible_dev_sys_dir}
		cd ${new_ansible_dev_sys_dir}
		if [ ! -z "${ANSIBLE_DEV_SYS_VERSION}" ]; then
			echo_info "Switching to branch ${ANSIBLE_DEV_SYS_VERSION} ..."
			git checkout ${ANSIBLE_DEV_SYS_VERSION} || exit 1
		fi
		git config core.filemode false
		new_dev_sys_script=${new_ansible_dev_sys_dir}/dev-sys.sh
		chmod ${ASSET_SCRIPT_MODE} ${new_dev_sys_script}

		# Create a separate update script.
		echo_info "Creating ${ansible_dev_sys_update_script} ..."
		cat <<-EOF > ${ansible_dev_sys_update_script}
		#!/usr/bin/env bash
		cd ${HOME}
		EOF
		if [ -d ${ANSIBLE_DEV_SYS_DIR} ]; then
			cat <<-EOF >> ${ansible_dev_sys_update_script}
			echo -e "\e[36mRemoving ${ANSIBLE_DEV_SYS_DIR} ...\e[0m"
			rm -rf ${ANSIBLE_DEV_SYS_DIR} || exit 1
			EOF
		fi
		cat <<-EOF >> ${ansible_dev_sys_update_script}
		echo -e "\e[36mMoving ${new_ansible_dev_sys_dir} to ${ANSIBLE_DEV_SYS_DIR} ...\e[0m"
		mv ${new_ansible_dev_sys_dir} ${ANSIBLE_DEV_SYS_DIR} || exit 1
		dev_sys_script=${ANSIBLE_DEV_SYS_DIR}/dev-sys.sh
		EOF
		cat <<-'EOF' >> ${ansible_dev_sys_update_script}
		echo -e "\e[36mExecuting ${dev_sys_script} ...\e[0m"
		called_from_self_update=not_blank exec $(which bash) -c "${dev_sys_script}"
		EOF
		chmod ${ASSET_SCRIPT_MODE} ${ansible_dev_sys_update_script}
		echo_info "Executing ${ansible_dev_sys_update_script} ..."
		exec $(which bash) -c ${ansible_dev_sys_update_script}
	else
		echo_info "Removing ${ansible_dev_sys_update_script} ..."
		rm -f ${ansible_dev_sys_update_script}
	fi
fi

# Create a proxy to this script.
dev_sys_proxy_script=${assets_dir}/dev-sys-proxy.sh
echo_info "Creating ${dev_sys_proxy_script} ..."
cat << EOF > ${dev_sys_proxy_script}
#!/usr/bin/env bash
dev_sys_script=${script_path}
EOF
cat << 'EOF' >> ${dev_sys_proxy_script}
exec $(which bash) -c "${dev_sys_script} ${*}"
EOF
chmod ${ASSET_SCRIPT_MODE} ${dev_sys_proxy_script}

# bash-environment: Where is it, and is it being managed by an external process?
# If bash-environment is being managed externally, then the Ansible bash-environment role will not update it.
BASH_ENVIRONMENT_DIR=${assets_dir}/bash-environment
BASH_ENVIRONMENT_MANAGED_EXTERNALLY=false
bash_environment_vars_script=${assets_dir}/bash-environment-vars.sh
if [ -f ${bash_environment_vars_script} ]; then
	echo_info "Sourcing ${bash_environment_vars_script} ..."
	source ${bash_environment_vars_script}
fi

# Install or update pyenv.
# Using pyenv will reduce the risk of corrupting the system Python.
pyenv_assets_dir=${assets_dir}/pyenv
create_dir_with_mode ${ASSET_DIR_MODE} ${pyenv_assets_dir}
if [ -z "${PYENV_ROOT}" ]; then
	echo_info "Installing the pyenv prerequisites ..."
	retry_if_fail sudo apt-get install --yes build-essential libssl-dev zlib1g-dev libbz2-dev \
	libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
	xz-utils tk-dev libffi-dev liblzma-dev python-openssl git make

	export PYENV_ROOT=${HOME}/.pyenv
	export PATH=${PYENV_ROOT}/bin:${PATH}

	pyenv_installer_script=${pyenv_assets_dir}/pyenv-installer.sh
	echo_info "Downloading ${pyenv_installer_script} ..."
	retry_if_fail curl --silent --show-error https://pyenv.run --output ${pyenv_installer_script}
	chmod ${ASSET_SCRIPT_MODE} ${pyenv_installer_script}

	# Unfortunately, the pyenv installation script may not return an error code if something goes wrong.
	# This means that prefixing it with 'retry_if_fail' does no good.
	# The best that we can do is to run pyenv doctor after the installation.
	echo_info "Installing pyenv ..."
	${pyenv_installer_script}

	# Create or update the pyenv script for bash-environment.
	pyenv_vars_script=${pyenv_assets_dir}/pyenv-vars.sh
	echo_info "Creating ${pyenv_vars_script} ..."
	cat <<-EOF > ${pyenv_vars_script}
	#!/usr/bin/env bash
	export PYENV_ROOT="${PYENV_ROOT}"
	EOF
	cat <<-'EOF' >> ${pyenv_vars_script}
	PATH="${PYENV_ROOT}/bin:${PATH}"
	eval "$(pyenv init -)"
	eval "$(pyenv virtualenv-init -)"
	EOF
	chmod ${ASSET_SCRIPT_MODE} ${pyenv_vars_script}

	echo_info "Sourcing ${pyenv_vars_script} ..."
	source ${pyenv_vars_script}

	echo_info "Checking pyenv ..."
	pyenv doctor --cpython || exit 1
else
	echo_info "Updating pyenv ..."
	retry_if_fail pyenv update
fi

# Install an isolated instance of Python for use by the dev-sys tools and Ansible.
python_version=3.8.3
if [ ! -d ${PYENV_ROOT}/versions/${python_version} ]; then
	echo_info "Installing Python ${python_version} for the dev-sys Python virtual environment ..."
	retry_if_fail pyenv install ${python_version}
fi

# Create or replace the dev-sys Python virtual environment.
if [ ! -d ${PYENV_ROOT}/versions/${python_version}/envs/dev-sys ]; then
	if [ ! -z "$(pyenv virtualenvs | awk '/^\*? +/ && ($1 == "*" ? $2 : $1) == "dev-sys"')" ]; then
		echo_info "Removing the old dev-sys Python virtual environment ..."
		pyenv virtualenv-delete --force dev-sys
	fi
	echo_info "Creating the dev-sys Python virtual environment ..."
	pyenv virtualenv ${python_version} dev-sys
fi
echo_info "Activating the dev-sys Python virtual environment ..."
export PYENV_VERSION=dev-sys 

# Install or update Ansible.
if [ -z "$(pip list --disable-pip-version-check 2>/dev/null | awk '$1 == "ansible"')" ]; then
	echo_info "Installing Ansible ..."
	retry_if_fail pip install ansible --disable-pip-version-check
else
	echo_info "Updating Ansible ..."
	retry_if_fail pip install ansible --upgrade --disable-pip-version-check
fi

# Create the Ansible provisioning directory.
# This is where Ansible-related files will be stored.
ansible_assets_dir=${assets_dir}/ansible
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_assets_dir}

# Create the Ansible inventories directory.
ansible_inventories_dir=${ansible_assets_dir}/inventories
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_inventories_dir}

# Create the Ansible host variables for this system.
ansible_host_vars_dir=${ansible_inventories_dir}/host_vars
create_dir_with_mode ${ASSET_DIR_MODE} ${ansible_host_vars_dir}
ansible_host_vars_file=${ansible_host_vars_dir}/$(hostname).yml
echo_info "Creating ${ansible_host_vars_file} ..."
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
echo_info "Creating ${ansible_group_vars_file} ..."
cat << EOF > ${ansible_group_vars_file}
---
EOF
chmod ${ASSET_FILE_MODE} ${ansible_group_vars_file}

# Determine if the Ansible bash-environment role needs to run its "install" script.
# The "install" script only needs to be is run if bash-environment changes.
# If bash-environment is being managed by this script (not externally),
#   then the Ansible bash-environment role will detect changes to bash-environment. Nothing is done here.
# If bash-environment is being managed externally,
#   then changes to bash-environment are detected with hashes of the directory's contents. That is done here.
bash_environment_run_install=false
if [ ${BASH_ENVIRONMENT_MANAGED_EXTERNALLY} == true ]; then
	cd ${BASH_ENVIRONMENT_DIR}
	echo_info "Computing the hash of ${BASH_ENVIRONMENT_DIR} ..."
	bash_environment_hash=$(find . -type f | sort | xargs sha1sum | sha1sum | awk '{ print $1}')

	bash_environment_previous_hash_script=${assets_dir}/bash-environment-previous-hash.sh
	if [ -f ${bash_environment_previous_hash_script} ]; then
		echo_info "Sourcing ${bash_environment_previous_hash_script} ..."
		source ${bash_environment_previous_hash_script}
		if [ "${bash_environment_hash}" != "${bash_environment_previous_hash}" ]; then
			bash_environment_run_install=true
		fi
	else
		bash_environment_run_install=true
	fi

	echo_info "Creating ${bash_environment_previous_hash_script} ..."
	cat <<-EOF > ${bash_environment_previous_hash_script}
	#!/usr/bin/env bash
	bash_environment_previous_hash=${bash_environment_hash}
	EOF
	chmod ${ASSET_SCRIPT_MODE} ${bash_environment_previous_hash_script}
fi
echo_info "bash_environment_run_install = ${bash_environment_run_install}"

# Add the bash-environment variables to the Ansible group variables.
echo_info "Adding the bash-environment variables to ${ansible_group_vars_file} ..."
cat << EOF >> ${ansible_group_vars_file}
bash_environment_dir: ${BASH_ENVIRONMENT_DIR}
bash_environment_managed_externally: ${BASH_ENVIRONMENT_MANAGED_EXTERNALLY}
bash_environment_run_install: ${bash_environment_run_install}
EOF
if [ ! -z "${BASH_ENVIRONMENT_VERSION}" ]; then
	echo "bash_environment_version: '${BASH_ENVIRONMENT_VERSION}'" >> ${ansible_group_vars_file}
fi

# Create the Ansible inventory file.
ansible_inventory_file=${ansible_inventories_dir}/inventory.ini
echo_info "Creating ${ansible_inventory_file} ..."
cat << EOF > ${ansible_inventory_file}
[dev_sys]
$(hostname)
EOF
chmod ${ASSET_FILE_MODE} ${ansible_inventory_file}

# Create the Ansible configuration file.
ansible_config_file=${ansible_assets_dir}/ansible.cfg
echo_info "Creating ${ansible_config_file} ..."
cat << EOF > ${ansible_config_file}
[defaults]
force_color = True
inventory = ${ansible_inventory_file}
roles_path = ${ANSIBLE_DEV_SYS_DIR}/ansible/roles
EOF
chmod ${ASSET_FILE_MODE} ${ansible_config_file}
export ANSIBLE_CONFIG=${ansible_config_file}

echo_info "Running the Ansible playbook ..."
ansible-playbook ${ANSIBLE_DEV_SYS_DIR}/ansible/dev-sys.yml --tags ${tags} || exit 1

exit 0
