#!/bin/bash
# ****************************************************************************
# Filename: check-stx_update.sh
#
# Description:
#
#  Script to manage the local stx_update repo.  Ensures that the update
#  scripts are always in sync with the repo.
#
# Creation Date:  October 2014
#
# Author:         Todd Roberts
#
# Do NOT modify or remove this copyright and confidentiality notice!
#
# Copyright (c) 2014 - $Date: 2014/10/23 $ Seagate Technology, LLC.
#
# The code contained herein is CONFIDENTIAL to Seagate Technology, LLC.
# Portions are also trade secret. Any use, duplication, derivation, distribution
# or disclosure of this code, for any reason, not expressly authorized is
# prohibited. All other rights are expressly reserved by Seagate Technology, LLC.
# ****************************************************************************

#------------------------------------------------------------------------------
# Clones a git repo and prepares it for checkout of selective directories
# Doesn't checkout any file only marks them
function create_cdu_stx_update()
{   SP_FILE=".git/info/sparse-checkout"

   # Create /etc/stx_update/stx_update repo if it doesn't exist
   if [ ! -d ${CUR_DIR}/${STX_REPO} ]; then

      # Clone repo
      git clone ${repo} --no-checkout &> /dev/null || true

      # Set repo up for sparse checkout
      pushd ${target} > /dev/null

      # Change fetch refspec so we still pick up all refs instead of the
      # normal set that we get with a normally cloned repo
      git config remote.origin.fetch +refs/*:refs/*

      # Turn on sparse checkout capabilities
      git config core.sparseCheckout true || true

      # Setup sparse checkout configuration file
      if [ $RUN_MODE == "server" ]; then
         # Create the sparse checkout file for this CDU
         echo "server/git_scripts/" > ${SP_FILE}
      elif [ $RUN_MODE == "swupdate" ]; then
         # Create the sparse checkout file for this CDU
         echo "swupdate/" > ${SP_FILE}
         echo "control/common/" >> ${SP_FILE}
         echo "control/cluster-type/${CLUSTER_TYPE}/" >> ${SP_FILE}
         echo "control/cdu/${CDU}/" >> ${SP_FILE}
      else
         echo "*" > ${SP_FILE}
      fi
      git read-tree -m -u "${branch}" &> /dev/null
      popd > /dev/null

   fi

} # create_cdu_stx_update()

#------------------------------------------------------------------------------
function check_git_repo_for_updates()
{
   echo "Repo [${repo}][${target}][${branch}]"

   presignfile="${SIGN_DIR}/sign"$(echo ${CUR_DIR} | tr "/" ".")".${target}.git.previous"
   if [[ -d "${target}" && -e "${CUR_DIR}/repo_signature.sh" ]]; then
      ${CUR_DIR}/repo_signature.sh --create ${target} ${presignfile}
      rstate=$(cat ${presignfile} | grep "Status:  Clean")
      if [ -z "${rstate}" ]; then
         rstate=$(cat ${presignfile} | grep "Status:  ")
         echo -e "\E[1;31m${rstate} => Cleaning Repo\E[0m"
         rm -rf ${target}
      fi
   fi

   if [ ! -d "${target}" ]; then
      # Create and filter stx_update repo
      echo -e "\E[1;31mCreating repo: ${target}\E[0m"
      create_cdu_stx_update
   fi
   if [ -d "${target}" ]; then
      echo "Checkout branch: ${branch}"
      cd ${target}
      # Switch to default branch for pull so we know we will be in a good place
      git checkout ${DEFAULT_RELEASE} &> /dev/null
      git pull &> /dev/null

      # Prune the remote and local branches/tags to get rid of deleted items
      git remote prune origin &> /dev/null
      git branch -r | awk '{print $1}' | \
         egrep -v -f /dev/fd/0 <(git branch -vv | grep origin) | \
         awk '{print $1}' | xargs git branch -d &> /dev/null
      # Delete any local tags that don't exist on the remote
      # May already be covered by the prune but it depends on the refspec
      local ofile=$(mktemp)
      git ls-remote --tags origin  &> ${ofile}
      local remote_tags=$(cat ${ofile} | sed -e '2,/--------------/d'| tail -n +2 | \
                         awk 'BEGIN {FS=" "}{print $2}' | sed "s/refs\/tags\///g")
      rm -rf ${ofile}
      if [ -n "${remote_tags}" ]; then
         local local_tags=$(git show-ref --tags | awk 'BEGIN {FS=" "}{print $2}' | sed "s/refs\/tags\///g")
         for ltag in ${local_tags[@]}
         do
            local tfound=$(echo ${remote_tags} | grep ${ltag})
            if [ ! -n "${tfound}" ]; then
               git tag -d ${ltag}
            fi
         done
      fi
      git checkout ${branch} || true
      local curbranch=$(git show-ref --head | grep ${branch} | \
                        grep $(git rev-parse HEAD))
      if [ ! -n "${curbranch}" ]; then
         echo -e "\E[1;31mERROR: Specified branch [${branch}] does not exist" \
                  " - Switching to default [${DEFAULT_RELEASE}]\E[0m"
         git checkout ${DEFAULT_RELEASE}
      fi
      cd ..
   else
      echo "ERROR: ${target} directory does not exist: git failure"
   fi

   # Make sure remote settings remain locked down to prevent commits/pushes
   if [ -d "${target}" ]; then
      cd ${target}
      git remote set-url origin ${repo}
      git remote set-url --push origin invalid-url
      if [ -d ".git" ]; then
      # For normal git repo
         echo "exit 1" > .git/hooks/update
         chmod +x .git/hooks/update
         cp .git/hooks/update .git/hooks/pre-commit
         cp .git/hooks/update .git/hooks/pre-receive
      elif [ -d "hooks" ]; then
      # For bare git repo
         echo "exit 1" > ./hooks/update
         chmod +x ./hooks/update
         cp ./hooks/update ./hooks/pre-commit
         cp ./hooks/update ./hooks/pre-receive
      fi
      cd ..
   fi

   # Grab final signature of the repo
   cursignfile="${SIGN_DIR}/sign"$(echo ${CUR_DIR} | tr "/" ".")".${target}.git.current"
   if [[ -d "${target}" ]]; then
      if [[ -e "${CUR_DIR}/repo_signature.sh" ]]; then
         ${CUR_DIR}/repo_signature.sh --create ${target} ${cursignfile}
      fi
   else
      echo "ERROR: ${target} directory does not exist: git failure"
   fi

} # check_git_repo_for_updates()

function check_rpm_for_updates()
{
   echo "Repo [${repo}][${target}][${branch}]"

   presignfile="${SIGN_DIR}/sign"$(echo ${CUR_DIR} | tr "/" ".")".${target}.rpm.previous"
   if [[ -d "${target}" && -e "${CUR_DIR}/rpm_signature.sh" ]]; then
      ${CUR_DIR}/rpm_signature.sh --create ${target} ${presignfile}
      rstate=$(cat ${presignfile} | grep "Status:  Clean")
      if [ -z "${rstate}" ]; then
         rstate=$(cat ${presignfile} | grep "Status:  ")
         echo -e "\E[1;31m${rstate} => Cleaning installation\E[0m"
         rm -rf ${target}
      fi
   fi
   
   if [ ! -d "${target}" ]; then
      # Create and filter stx_update repo
      echo -e "\E[1;31mCreating repo: ${target}\E[0m"
      mkdir -p "${target}"
   fi

   # Fetch info from installed package
   # rpm -qa ${INSTALLED_PACKAGE}

   # Fetch info from new rpm package file
   # rpm -qp ${RPM_PACKAGE}.rpm
    
   if [[ $(rpm -qa ${INSTALLED_PACKAGE}) = $(rpm -qp ${RPM_PACKAGE_SOURCE}) ]]; then
      echo "INFO: Latest version installed already. Do nothing."
      return 0
   fi

   rpm -Uvh ${RPM_PACKAGE_SOURCE}
   
   # Grab final signature of the repo
   cursignfile="${SIGN_DIR}/sign"$(echo ${CUR_DIR} | tr "/" ".")".${target}.rpm.current"
   if [[ -d "${target}" ]]; then
      if [[ -e "${CUR_DIR}/repo_signature.sh" ]]; then
         ${CUR_DIR}/repo_signature.sh --create ${target} ${cursignfile}
      fi
   else
      echo "ERROR: ${target} directory does not exist: git failure"
   fi

} # check_rpm_for_updates

#------------------------------------------------------------------------------
function copy_latest_files()
{
   # Copy the latest files over to our working directory

   # Here will will remove everything that we can so we can easily remove
   # unwanted files as the system evolves without worrying about obsolete files
   # piling up on us.  There are some files that will not be stored in the
   # update repo and/or are modified so we don't want to remove them.
   # Everything else goes.  We will keep the following:
   # *.log - as we are likely writing in them and we want to keep history
   # *.lock - preserve these since this is part of a normal run
   # *.tmp.sh - as these are the scripts that are running and we don't want
   #            them to go away out from under us
   # *.control - control file should stay to keep our state
   # cluster.cfg - as it holds our main configuration
   # puppet_cron.sh - as it is only rebuilt by puppet
   find $(pwd) -maxdepth 1 -type f \
      ! -name "*.log" \
      ! -name "*.lock" \
      ! -name "*.tmp.sh" \
      ! -name "*local.override.cfg" \
      ! -name "*.control" \
      ! -name "cluster.cfg" \
      ! -name "puppet_cron*.sh" \
      -exec rm -f {} \;

   echo "Refreshing files (${RUN_MODE})"
   cp -rf ./stx_update/${RUN_MODE}/git_scripts/* .

   # Make sure everything has the right permissions
   find $(pwd) -maxdepth 1 -type f -exec chmod 640 {} \;
   chmod 750 *.sh

   if [[ "${RUN_MODE}" == "server" ]]; then

      if [[ "${host}" =~ update* ]]; then
         # Can only manage crontab on update server (not external server)
         # We only do this for server since puppet manages the crontab
         # for the client and swupdate layers
         # Refresh crontab
         crontab -r
         crontab *.crontab
      fi

      # Remove all but our remote host config file
      find $(pwd) -maxdepth 1 -type f \
         ! -name "remote.${host}.cfg" \
           -name "remote.*.cfg" \
         -exec rm -f {} \;
   fi

} # copy_latest_files()

#------------------------------------------------------------------------------
function show_help()
{
   echo " "
   echo "$0 Usage: {--help | [--server] --show-repos | [--server] --check }"
   echo "   --help       : Display this help"
   echo "   --server     : Force server mode"
   echo "   --check      : Check for updates (Default)"
   echo "   --show-repos : Display current state of all repos"
   echo " "

} # show_help()

#------------------------------------------------------------------------------
function handle_command_line()
{
   if [ "$1" == "--help" ]; then
      show_help
      return
   fi
   if [ "$1" == "--check" ]; then
      # Nothing to do here
      return
   fi
   if [ "$1" == "--swupdate" ]; then
      return
   fi
   if [ "$1" == "--show-repos" ]; then
      if [[ -d "${target}" && -e "${CUR_DIR}/repo_signature.sh" ]]; then
         ${CUR_DIR}/repo_signature.sh --show ${target}
      fi
      if [[ -d "${target}" && -e "${CUR_DIR}/rpm_signature.sh" ]]; then
         ${CUR_DIR}/rpm_signature.sh --show ${target}
      fi
      return
   fi

   # If we got here and command line was not empty it is an error
   if [ "$1" != "" ]; then
      echo "ERROR: Unknown option"
      show_help
      return
   fi
} #

#------------------------------------------------------------------------------
# Parameters for defaults
STX_REPO="stx_update"

# Default values - These will be replaced when the system is up and running
REMOTE_REPO="ssh://git@172.31.250.1:22/swupdate"
STASH_REPO="ssh://git@dcostash.colo.seagate.com:7999/prov"

#------------------------------------------------------------------------------
# Main script
CSU_ST_TIME=$(date +%s);
user=$(whoami)

# Figure out what we need to do - let RUN_MODE override anything
if [ ! -n "${RUN_MODE}" ]; then
   if [ "$1" == "--server" ]; then
      RUN_MODE="server"
   else
      RUN_MODE="swupdate"
   fi
   export RUN_MODE
fi
if [ "${RUN_MODE}" == "server" ]; then
   RUN_USER="git"
else
   RUN_USER="swupdate"
fi
if [[ "${user}" != "root" && "${user}" != "${RUN_USER}" ]]; then
   # Only allow swupdate user to run from here
   echo -e "\E[1;31mERROR: $0 must be run as root or ${RUN_USER} user\E[0m"
   exit 1
fi
# Check to see if we are the temporary version of ourselves
if [ -z "$(basename $0 | grep ".tmp.sh")" ]; then
   # This should only happen if we are being run from command line
   # We are the base version - copy and run a temp version so we don't
   # get stepped on with the update below
   if [ "${user}" == "root" ]; then
      # Switch user
      sudo -u ${RUN_USER} cp $0 $0.tmp.sh
      sudo -u ${RUN_USER} $0.tmp.sh "$@"
      sudo -u ${RUN_USER} rm -rf $0.tmp.sh
   else
      cp $0 $0.tmp.sh
      $0.tmp.sh "$@"
      rm -rf $0.tmp.sh
   fi
   exit
fi

# Make sure we are in the right directory
base=$(echo $(basename $0 | awk 'BEGIN {FS=".sh"}{print $1}' ))
host=$(echo $HOSTNAME | awk 'BEGIN {FS="."}{print $1}')
CUR_DIR=$(pwd)

if [ -e "${base}.lock" ]; then
   echo "${base}.lock exists:  Abort"
   exit
fi

# Create lock file so we don't interrupt ourselves
echo -e "\E[1;32mScript [$0][${CUR_DIR}][${RUN_MODE}] Started: $(date)\E[0m" | tee  ${base}.lock

# Get configuration from the various .cfg files
if [ -e "./get_config.sh" ]; then
   eval $(./get_config.sh --create-plain)
fi

if [ ! -n "${UPDATE_RELEASE}" ]; then
   export UPDATE_RELEASE="development"
fi
if [ ! -n "${DEFAULT_RELEASE}" ]; then
   export DEFAULT_RELEASE="development"
fi

# Setup the repo definitions
if [ "${RUN_MODE}" == "server" ]; then
   if [ -n "${REPO_BASE}" ]; then
      repo="${REPO_BASE}/${STX_REPO}"
   else
      # Get configuration from the various .cfg files
      if [ -f "remote.${host}.cfg" ]; then
         eval $(cat remote.${host}.cfg)
         repo="${REPO_BASE}/${STX_REPO}"
      else
         repo="${STASH_REPO}/${STX_REPO}"
      fi
   fi
else
   repo="${REMOTE_REPO}/${STX_REPO}"

   # Make sure fact directory exists
   sudo mkdir -p /etc/facter/facts.d

   # update_status_run_dir.yaml with current date/time
   sudo -E bash -c 'echo "update_run_dir: ${RUN_DIR}" > /etc/facter/facts.d/update_status_run_dir.yaml'

   # update_status_release.yaml with latest releases
   sudo -E bash -c 'echo "default_release: ${DEFAULT_RELEASE}" > /etc/facter/facts.d/update_status_release.yaml'
   sudo -E bash -c 'echo "update_release: ${UPDATE_RELEASE}" >> /etc/facter/facts.d/update_status_release.yaml'

   # update_status_last_check.yaml with current date/time
   sudo -E bash -c 'echo "update_last_check: $(date)" > /etc/facter/facts.d/update_status_last_check.yaml'

   # update_status_config.yaml with current values
   sudo -E bash -c 'echo "update_local_overrides: ${LOCAL_OVERRIDES}" > /etc/facter/facts.d/update_status_config.yaml'

fi
target="${STX_REPO}"
branch="${UPDATE_RELEASE}"

if [[ "$1" == "--server" || "$1" == "--swupdate" ]]; then
   shift
fi

if [ "$1" == "" ]; then
   if [ ! -n "${SIGN_DIR}" ]; then
      export SIGN_DIR="${CUR_DIR}/signatures"
   fi
   mkdir -p "${CUR_DIR}/${SIGN_DIR}"
   if [ ! -n "${DATASTORE_DIR}" ]; then
	   export DATASTORE_DIR="${CUR_DIR}/datastore"
   fi
   mkdir -p "${CUR_DIR}/${DATASTORE_DIR}"

   # Check update repo for updates - Create it if necessary
   if [[ ${remote_type} = VPN ]];then
      check_git_repo_for_updates
   elif [[ ${remote_type} = +(USB|ISO) ]]; then
      check_rpm_for_updates
   fi

   copy_latest_files
else
   # Process command line arguments and deal with interactive options
   handle_command_line "$@"
fi

CSU_EN_TIME=$(date +%s);
CSU_PR_TIME=$(echo $((CSU_EN_TIME-CSU_ST_TIME)) | awk '{print int($1/60)"m "int($1%60)"s"}')

# Remove lock and get out
rm -rf ${base}.lock
echo -e "\E[1;32mScript [$0] Completed in ${CSU_PR_TIME} at: $(date)\E[0m"
echo " "
#------------------------------------------------------------------------------
# End of Script
#------------------------------------------------------------------------------
