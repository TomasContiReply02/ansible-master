#!/bin/bash

#ACC_API_KEY=<api_key> ACC_MID=wss://<mid_ip>:<websocket_port>/ws/events bash -c "$(curl -L https://<instance URL>/api/sn_agent/agents/install_agent)"

set -e
ACC_NAME=agent-client-collector
ACC_VERSION=2.9.2
ACC_CONF=/etc/servicenow/$ACC_NAME/acc.yml
ACC_ALLOW_LIST_PATH=/etc/servicenow/$ACC_NAME/check-allow-list.json
ACC_BASE_URL=https://install.service-now.com/glide/distribution/builds/package/app-signed/
ACC_AGENT_ID=/var/cache/servicenow/$ACC_NAME/agent_now_id
ACC_AGENT_KEY_STORE=/var/cache/servicenow/$ACC_NAME/agent_now_keystore
ACC_BIN=/usr/share/servicenow/$ACC_NAME/bin/acc
EXECUTION_TYPE=INSTALL
PEM_FILE=ServiceNow_Digicert_DGST.pem

cleanup () {
  rm -f $filename
  rm -f $sigfilename
  rm -f ServiceNow_Digicert_Public.gpg
  exit $exit_code
}
trap cleanup EXIT ERR INT TERM

usage()
{
    printf "\033[36m\n* usage: install_script.sh [[-r |--remove]]\n\033[0m\n"
}

while [ "$1" != "" ]; do
    case $1 in
        -r | --remove )         shift
                                EXECUTION_TYPE=UNINSTALL
                                break
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

if [ -n "$ACC_INSTALL_DEBUG" ] && [ "$ACC_INSTALL_DEBUG" = "true" ]; then
  debug="true"
  set -xv
fi

validate_sig="1"
if [ -n "$ACC_VALIDATE_SIG" ]; then
  validate_sig=$ACC_VALIDATE_SIG
fi

if [ -z "$ACC_API_KEY" ] && [ "$EXECUTION_TYPE" = "INSTALL" ]; then
  read -p 'Please input MID Server API Key:' input_acc_api
  if [ -z "$input_acc_api" ]; then
    printf "\033[31mAPI Key must not be empty. Exiting Script.\033[0m\n"
    exit 1
  fi
  api_key=$input_acc_api
elif [ -n "$ACC_API_KEY" ]; then
  api_key=$ACC_API_KEY
fi

if [ -n "$ACC_MID" ]; then
  mid=$ACC_MID
fi

allow_list="1"
if [ -n "$ACC_ALLOW_LIST" ]; then
  allow_list=$ACC_ALLOW_LIST
fi

if [ -n "$DEV_MODE" ]; then
  ACC_VERSION="$ACC_VERSION-SNAPSHOT"
fi

if [ $(command -v curl) ]; then
  dl_cmd="curl -L -O"
else
  dl_cmd="wget"
fi

# Root user detection
if [ $(echo "$UID") = "0" ]; then
    sudo_cmd=''
else
    sudo_cmd='sudo'
fi

parse_dist () {
   content=$(cat $1)
   if [[ $content == *"Red Hat"* ]]; then
     ID=rhel
   elif [[ $content == *"CentOS"* ]]; then
     ID=centos
   fi
}

parse_version () {
   # grep command will only output the major version number
   version=$(grep -oP 'release\s+\K[0-9]+' $1)
   if [ -n $version ]; then
     VERSION_ID=$version
   fi
}

# Distribution detection
if [ -f /etc/os-release ]; then
  . /etc/os-release
elif [[ "$OSTYPE" == "darwin"* ]]; then
  ID=osx
  VERSION_ID=${OSTYPE:6}
  ACC_CONF="/Library/Application Support/ServiceNow/$ACC_NAME/acc.yml"
  ACC_ALLOW_LIST_PATH="/Library/Application Support/ServiceNow/$ACC_NAME/check-allow-list.json"
  ACC_BIN=/opt/servicenow/$ACC_NAME/bin/acc
  ACC_AGENT_KEY_STORE=/Library/Caches/servicenow/$ACC_NAME/agent_now_keystore
  ACC_AGENT_ID=/Library/Caches/servicenow/$ACC_NAME/agent_now_id
else
  # handle older versions of RHEL and CentOS
    file=""
    if [ -f /etc/redhat-release ]; then
      file="/etc/redhat-release"
    elif [ -f /etc/issue ]; then
      file="/etc/issue"
    fi

    if [ -n "$file" ]; then
      printf "\033[36m\n* Parsing OS information from file $file\n\033[0m\n"
      parse_dist $file
      parse_version $file
    else
      printf "\033[31mUnable to parse OS information from known system files.\033[0m\n"
    fi
fi

printf "Distro: $ID\n"
printf "Version: $VERSION_ID\n"

if [ "$ID" = "osx" ]; then
  os_arch=$($sudo_cmd uname -m)
  sed_cmd="sed -i ''"
else
  os_arch=$($sudo_cmd arch)
  sed_cmd="sed -i"
fi

if [ "$ID" = "osx" ] && [ "$EXECUTION_TYPE" = "INSTALL" ]; then
  if [ -n "$ACC_INSTALL_USR" ] && [ -n "$ACC_INSTALL_USR_GRP" ]; then
    # If both USR and GRP are passed set env variable and proceed with install
    printf "\033[36m\n* Installation pkg with User=$ACC_INSTALL_USR and Group=$ACC_INSTALL_USR_GRP \n\033[0m\n"
    $sudo_cmd launchctl setenv ACC_INSTALL_USR $ACC_INSTALL_USR
    $sudo_cmd launchctl setenv ACC_INSTALL_USR_GRP $ACC_INSTALL_USR_GRP
  elif [ -n "$ACC_INSTALL_USR" ] || [ -n "$ACC_INSTALL_USR_GRP" ]; then
    # if the customer passes only USR or GRP abort install.
    printf "\033[31m Both ACC_INSTALL_USR and ACC_INSTALL_USR_GRP needs to be set to continue. Installation aborted!.\033[0m\n"
    exit;
  else #else set defaults and proceed with install as _servernoe as user/group
    #Since the installer post and pre script looks for these env variables
    #making sure they are not set, otherwise it might cause unexpected install failure.
    $sudo_cmd launchctl unsetenv ACC_INSTALL_USR
    $sudo_cmd launchctl unsetenv ACC_INSTALL_USR_GRP

    printf "\033[36m\n* ACC_INSTALL_USR and ACC_INSTALL_USR_GRP not set. Using defaults for user/group _servicenow\n\033[0m\n"
    ACC_INSTALL_USR="_servicenow"
    ACC_INSTALL_USR_GRP="_servicenow"
  fi
else
  ACC_INSTALL_USR="servicenow"
  ACC_INSTALL_USR_GRP="servicenow"
fi

if [ $os_arch = "x86_64" ]; then
  printf "CPU Architecture: $os_arch\n"
else
  printf "\033[31mCPU Architecture [$os_arch] is not supported by this install script.\033[0m\n"
  exit 1
fi
$sudo_cmd test -f "$ACC_BIN"  || isBinExsist=$? || true

validateInstall (){
  if [ "$ID" != "osx" ]; then #mac is .pkg which is signed and no need to unzip
    if [ $(command -v unzip) ]; then
        $sudo_cmd unzip $sigfilename
    else
        printf "\033[31mMissing validation dependency for unzip and ability to run it\033[0m\n"
        exit 1
    fi
  fi
  if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ] ; then
    if [ $(command -v gpg) ]; then
      printf "\033[31mImporting ServiceNow Certificate\033[0m\n"
      res=$($sudo_cmd gpg --import ServiceNow_Digicert_Public.gpg 2>&1)
      if [[ ${res} != *"Total number processed: 1"* && (${res} != *"unchanged: 1"*  || ${res} != *"imported: 1"*) ]]; then
        printf "\033[31mUnable to successfully import Certificate\033[0m\n"
        exit;
      fi
    else
      printf "\033[31mMissing validation dependency on gpg and ability to run it\033[0m\n"
      exit 1
    fi
    if [ $(command -v dpkg-sig) ]; then
      printf "\033[31mVerifying Agent Client Collector Signature\033[0m\n"
      res=$($sudo_cmd dpkg-sig --verify $filename 2>&1)
      if [[ "$res" != *"GOODSIG"* ]]; then
        printf "\033[31mUnable to successfully validate Agent Client Collector Certificate\033[0m\n"
        exit;
      fi
    else
      printf "\033[31mMissing validation dependency on dpkg-sig and ability to run it\033[0m\n"
      exit 1
    fi
  elif [ "$ID" = "rhel" ] || [ "$ID" = "centos" ] || [ "$ID" = "redhat" ] || [ "$ID" = "sles" ] || [ "$ID" = "amzn" ] || [ "$ID" = "ol" ] ; then
    if [ $(command -v openssl) ]; then
      printf "\033[31mVerifying Agent Client Collector Signature\033[0m\n"
      res=$($sudo_cmd openssl dgst -sha256 -verify $PEM_FILE -signature $ACC_NAME-$ACC_VERSION-el7-x86_64.bin $filename)
      if [[ "$res" != "Verified OK" ]]; then
        printf "\033[31mUnable to successfully validate Agent Client Collector Certificate\033[0m\n"
        exit;
      fi
    else
      printf "\033[31mMissing validation dependency on openssl and ability to run it\033[0m\n"
      exit 1
    fi
  elif [ "$ID" = "osx" ]; then
    pkgUtilResult=$(pkgutil --check-signature $filename 2>&1)
    if [[ "$pkgUtilResult" != *"signed by a developer certificate issued by Apple for distribution"* || "$pkgUtilResult" != *"Developer ID Installer: ServiceNow Inc."* ]]; then
      printf "\033[31mUnable to successfully validate Agent Client Collector Certificate\033[0m\n"
      exit;
    fi
    ## Adding this for future once we have the pkg Notarized we can enable this
#    spctlResult=$(spctl -a -vv -t install $filename 2>&1)
#    if [[ "$spctlResult" != *"accepted"* || "$spctlResult" != *"Notarized Developer ID"* || "$spctlResult" != *"ServiceNow Inc."* ]]; then
#      printf "\033[31mNotarization: Unable to successfully validate Agent Client Collector\033[0m\n"
#      exit;
#    fi
  else
    printf "\033[31mYour OS or distribution are not supported by this install script.\033[0m\n"
    exit;
  fi
}

uninstall_osx (){
  # remove plist file
  $sudo_cmd rm /Library/LaunchDaemons/com.sn.acc.plist

  cleanup_app_folder "/opt/servicenow"
  cleanup_app_folder "/Library/Caches/servicenow"
  cleanup_app_folder "/var/run/servicenow"
  cleanup_app_folder "/var/log/servicenow"
  cleanup_app_folder "/Library/Application Support/servicenow"

  # remove pkg receipt
  $sudo_cmd pkgutil --forget com.servicenow.agent-client-collector

  # remove _servicenow user and group
  if [ $(id -u "_servicenow") ]; then
    $sudo_cmd /usr/bin/dscl . -delete /Users/_servicenow
  fi
  if [ $(dscl . -list /Groups | grep "_servicenow") ]; then
    $sudo_cmd /usr/bin/dscl . -delete /Groups/_servicenow
  fi

}

# make sure we only remove servicenow folder if only acc app present inside
cleanup_app_folder (){
  # echo "$1/agent-client-collector"
  $sudo_cmd rm -rf "$1/agent-client-collector"
  if [ -z "$(ls -A "$1")" ]; then
    $sudo_cmd rm -rf "$1"
  fi
}

uninstall_agent (){
    svc_disable_cmd="$sudo_cmd systemctl disable acc"
    svc_stop_cmd="$sudo_cmd systemctl stop acc"
    pkg_cmd="$sudo_cmd dpkg -r $ACC_NAME"

    if [ "$ID" = "ubuntu" ]; then
      query_result="$($sudo_cmd dpkg -s $ACC_NAME 2>/dev/null)" || true
      if [[ ${#query_result} -eq 0  ||  "$isBinExsist" != "" ]]; then
        printf "\e[1;33mThe package of %s was not installed, the uninstall process aborted\e[0m\n"  "$ACC_NAME"
        exit 0
      fi
    elif [ "$ID" = "debian" ]; then
      true
    elif [ "$ID" = "rhel" ] || [ "$ID" = "centos" ] || [ "$ID" = "redhat" ] || [ "$ID" = "sles" ] || [ "$ID" = "amzn" ] || [ "$ID" = "ol" ] ; then
      quey_result="$($sudo_cmd rpm -qa | grep $ACC_NAME 2>/dev/null)" || true
      if [[ ${#quey_result} -eq 0  ||  "$isBinExsist" != ""  ]]; then
        printf "\e[1;33mThe package of %s was not installed, the uninstall process aborted\e[0m\n"  "$ACC_NAME"
        exit 0
      fi
      pkg_cmd="$sudo_cmd rpm -e $ACC_NAME"
      svc_stop_cmd="$sudo_cmd service acc stop"
      if [ "$VERSION_ID" = "6" ]; then
        svc_disable_cmd="$sudo_cmd chkconfig acc off"
      fi

    elif [ "$ID" = "osx" ]; then
      query_result="$($sudo_cmd pkgutil --pkgs | grep $ACC_NAME 2>/dev/null)" || true
      if [[ ${#query_result} -eq 0 ]]; then # will add ||  "$isBinExsist" != "" to check once osx install path is aligned to linux /usr/share
        printf "\e[1;33mThe package of %s was not installed, the uninstall process aborted\e[0m\n"  "$ACC_NAME"
        exit 0
      fi
      #Stop and Unloads the service
      svc_stop_cmd="$sudo_cmd launchctl unload -w /Library/LaunchDaemons/com.sn.acc.plist"
      pkg_cmd=uninstall_osx

    else
      printf "\033[31mYour OS or distribution are not supported by this install script.\033[0m\n"
      exit;
    fi

    if [ "$ID" = "osx" ]; then
      printf "\033[36m\n* Stop and disable agent service\n\033[0m\n"
      $svc_stop_cmd
    else
      printf "\033[36m\n* Stop agent service\n\033[0m\n"
      $svc_stop_cmd
      printf "\033[36m\n* Disable agent service\n\033[0m\n"
      $svc_disable_cmd
    fi

    printf "\033[36m\n* Uninstall agent\n\033[0m\n"
    $pkg_cmd

    printf "\033[36m\n* $ACC_NAME uninstalled successfully\n\033[0m\n"
}

if [ "$EXECUTION_TYPE" = "UNINSTALL" ]; then
  uninstall_agent
  exit 0
fi

if [ -n "$ACC_FORCE" ]; then
  force_upgrade=$ACC_FORCE
fi

if [ "$isBinExsist" == "" ]; then
    printf "\033[36m\n* Agent already installed, starting upgrade process\n\033[0m\n"
    shopt -s nocasematch
    if [ $force_upgrade ] && [ "${force_upgrade}" == "yes" ]; then
      printf "\033[36m\n* Force upgrade mode selected\n\033[0m\n"
      EXECUTION_TYPE=UPGRADE
    else
      while true; do
        read -p "Are you sure you want to upgrade?[y/n]" yn
        case $yn in
            [Yy]* ) EXECUTION_TYPE=UPGRADE; break;;
            [Nn]* ) printf "\033[36m\n* Upgrade aborted by user.\n\033[0m\n"; exit;;
            * ) printf "\033[36m\n* Please answer yes or no.\n\033[0m\n";;
        esac
      done
    fi
fi

midlist=""
add_midList_to_config() {
  #adding backendURl to the midlist since we will be using this as key to replace URLs
  printf -v midlist "backend-url:"$'\\\n '
  printf "\033[36m\n* Adding MID $mid to the agent configuration: $ACC_CONF\n\033[0m\n"
  #set comma as a delimiter and read string into an array
  IFS=',' read -a MIDS <<<"$mid"
  for url in "${MIDS[@]}"; do
    #remove spaces from the URL
    url=${url// /}
    #append cleaned URL to string variable with newline at the end
    printf -v midlist "$midlist - \"$url\""$'\\\n '
  done

  #delete the existing url's
  $sudo_cmd $sed_cmd '/"[ws|wss].*\/ws\/events\"/d' "$ACC_CONF"
  #using backendURl as key replace new midlist
  $sudo_cmd $sed_cmd 's~^backend-url:~'"$midlist"'~g' "$ACC_CONF"
}

#=================Upgrade process======================
if [ "$EXECUTION_TYPE" = "UPGRADE" ]; then
    printf "\033[36m\n* Starting agent upgrade to version [%s] \n\033[0m\n" "$ACC_VERSION"
    #============Backup Files=================
    NOW=$(date +%Y%m%d%H%M%S)
    BACKUP_FOLDER="/tmp/acc-backup-$NOW"
    $sudo_cmd mkdir -p "$BACKUP_FOLDER"
    printf "\033[36m\n* Created backup folder %s \n\033[0m\n" "$BACKUP_FOLDER"
    #Before upgrade validate if backup files exists

    if $sudo_cmd test -f "$ACC_CONF"; then
        $sudo_cmd cp -rp "$ACC_CONF" $BACKUP_FOLDER
        printf "\033[36m\n* Backuping configuration file %s \n\033[0m\n" "$ACC_CONF"
    else
        printf "ERROR: %s does not exist, Upgrade aborted\n"  "$ACC_CONF" >&2
        exit 1
    fi

    if $sudo_cmd test -f "$ACC_AGENT_ID"; then
      $sudo_cmd cp -rp $ACC_AGENT_ID $BACKUP_FOLDER
      printf "\033[36m\n* Backuping agent id file %s \n\033[0m\n" "$ACC_AGENT_ID"
    else
      printf "WARN:Can't backup, %s does not exist\n" "$ACC_AGENT_ID" >&2
    fi

    if $sudo_cmd test -f "$ACC_AGENT_KEY_STORE"; then
      $sudo_cmd cp -rp $ACC_AGENT_KEY_STORE $BACKUP_FOLDER
      printf "\033[36m\n* Backuping key file %s \n\033[0m\n" "$ACC_AGENT_KEY_STORE"
    else
      printf "WARN:Can't backup, %s does not exist\n" "$ACC_AGENT_KEY_STORE" >&2
    fi

    if $sudo_cmd test -f "$ACC_ALLOW_LIST_PATH"; then
      $sudo_cmd cp -rp "$ACC_ALLOW_LIST_PATH" $BACKUP_FOLDER
      printf "\033[36m\n* Backuping allow list file %s \n\033[0m\n" "$ACC_ALLOW_LIST_PATH"
    else
      printf "WARN:Can't backup, %s does not exist\n" "$ACC_ALLOW_LIST_PATH" >&2
    fi
    #============Backup Files ended=================
    #============Uninstall process==================
    uninstall_agent
fi #=======In case of upgrade================

svc_enable_cmd="$sudo_cmd systemctl enable acc"
svc_enable_cmd2="true"
svc_start_cmd="$sudo_cmd systemctl start acc"
pkg_cmd="$sudo_cmd dpkg -i"

if [ "$ID" = "ubuntu" ]; then
  if [[ "$VERSION_ID" = "18"* ]] || [[ "$VERSION_ID" = "19"* ]] || [[ "$VERSION_ID" = "20"* ]]; then
    filename=$ACC_NAME-$ACC_VERSION-ubuntu-1804_amd64.deb
    sigfilename=$ACC_NAME-$ACC_VERSION-ubuntu-1804_amd64-deb-deb.zip
  else
    printf "\033[36m\n* Unsupported version of Ubuntu: $VERSION_ID, will try to use 18.04 executable.\n\033[0m\n"
    sigfilename=$ACC_NAME-$ACC_VERSION-ubuntu-1804_amd64-deb-deb.zip
    filename=$ACC_NAME-$ACC_VERSION-ubuntu-1804_amd64.deb
  fi
elif [ "$ID" = "debian" ]; then
  if [ "$VERSION_ID" = "8" ]; then
    filename=$ACC_NAME-$ACC_VERSION-debian-8_amd64.deb
    sigfilename=$ACC_NAME-$ACC_VERSION-debian-8_amd64-deb-deb.zip
  elif [ "$VERSION_ID" = "9" ]; then
    filename=$ACC_NAME-$ACC_VERSION-debian-9_amd64.deb
    sigfilename=$ACC_NAME-$ACC_VERSION-debian-9_amd64-deb-deb.zip
  else
    printf "\033[36m\n* Unsupported version of Debian: $VERSION_ID, will try to use Debian 9 executable.\n\033[0m\n"
    filename=$ACC_NAME-$ACC_VERSION-debian-9_amd64.deb
    sigfilename=$ACC_NAME-$ACC_VERSION-debian-9_amd64-deb-deb.zip
  fi
elif [ "$ID" = "rhel" ] || [ "$ID" = "centos" ] || [ "$ID" = "redhat" ] || [ "$ID" = "sles" ] || [ "$ID" = "amzn" ] || [ "$ID" = "ol" ] ; then
  if [ "$VERSION_ID" = "6" ]; then
    printf "\033[31mYour OS version is no longer supported.\033[0m\n"
    exit;
  fi
  pkg_cmd="$sudo_cmd rpm -vi"
  filename=$ACC_NAME-$ACC_VERSION-el7-x86_64.rpm
  sigfilename=$ACC_NAME-$ACC_VERSION-el7-x86_64-rpm-rpm.zip
elif [ "$ID" = "osx" ]; then
  if [ "$debug" = "true" ]; then
    $sudo_cmd launchctl setenv ACC_INSTALL_DEBUG true
    pkg_cmd="$sudo_cmd installer -dumplog -target / -pkg"
  else
   pkg_cmd="$sudo_cmd installer -target / -pkg"
  fi

  # installing the PKG starts the service, so we stop and start the service
  # for the acc.yml changes to apply
  svc_stop_cmd="$sudo_cmd launchctl unload -w /Library/LaunchDaemons/com.sn.acc.plist"
  svc_start_cmd="$sudo_cmd launchctl load -w /Library/LaunchDaemons/com.sn.acc.plist"
  filename=$ACC_NAME-$ACC_VERSION-macos_x64.pkg #this pkg will be signed
else
  printf "\033[31mYour OS or distribution are not supported by this install script.\033[0m\n"
  exit;
fi

printf "\033[36m\n* Downloading $ACC_BASE_URL$filename\n\033[0m\n"
$dl_cmd $ACC_BASE_URL$filename

if [ "$validate_sig"  == "1" ] && [ -z "$DEV_MODE" ]; then
 if [ "$ID" = "osx" ]; then
   #We already downloaded the signed pkg for mac no need to down the same file again
   sigfilename=$filename
 else
   printf "\033[36m\n* Downloading $ACC_BASE_URL$sigfilename\n\033[0m\n"
   $dl_cmd $ACC_BASE_URL$sigfilename
 fi
 validateInstall
fi
$pkg_cmd $filename

if [ "$EXECUTION_TYPE" = "UPGRADE" ]; then
  #============Restore Files=================

  if $sudo_cmd test -f "$BACKUP_FOLDER/acc.yml"; then
    $sudo_cmd cp -rp "$BACKUP_FOLDER/acc.yml" "$ACC_CONF"
    printf "\033[36m\n* Configuration file %s restored\n\033[0m\n" "$ACC_CONF"
  else
    printf "WARN:Can't restore, %s does not exist\n" "$ACC_CONF" >&2
  fi

  if $sudo_cmd test -f "$BACKUP_FOLDER/agent_now_id"; then
      $sudo_cmd cp -rp "$BACKUP_FOLDER/agent_now_id" $ACC_AGENT_ID
      printf "\033[36m\n* Agent ID %s restored\n\033[0m\n" "$ACC_AGENT_ID"
  else
      printf "WARN:Can't restore, %s does not exist\n" "$ACC_AGENT_ID" >&2
  fi

  if $sudo_cmd test -f "$BACKUP_FOLDER/agent_now_keystore"; then
    $sudo_cmd cp -rp "$BACKUP_FOLDER/agent_now_keystore" $ACC_AGENT_KEY_STORE
    printf "\033[36m\n* Agent key file %s restored\n\033[0m\n" "$ACC_AGENT_KEY_STORE"
  else
    printf "WARN:Can't restore, %s does not exist\n" "$ACC_AGENT_KEY_STORE" >&2
  fi

  if ! $sudo_cmd grep -q "#allow-list:" "$ACC_CONF" && $sudo_cmd grep -q "allow-list:" "$ACC_CONF" ; then
    printf "\033[36m\n* Copying check-allow-list.json to the : $ACC_ALLOW_LIST_PATH\n\033[0m\n"
    if $sudo_cmd test -f "$BACKUP_FOLDER/check-allow-list.json"; then
      $sudo_cmd cp -rp "$BACKUP_FOLDER/check-allow-list.json" "$ACC_ALLOW_LIST_PATH"
      printf "\033[36m\n* Allow list file %s restored\n\033[0m\n" "$ACC_ALLOW_LIST_PATH"
    else
      printf "WARN:Can't restore, %s does not exist\n" "$ACC_ALLOW_LIST_PATH" >&2
      $sudo_cmd cp -p "$ACC_ALLOW_LIST_PATH.default" "$ACC_ALLOW_LIST_PATH"
    fi
    #if upgrading from a older version, set readonly on allowlist
    $sudo_cmd chmod 400 "$ACC_ALLOW_LIST_PATH"
  fi

  if $sudo_cmd test -d "$BACKUP_FOLDER"; then
    $sudo_cmd rm -rf "$BACKUP_FOLDER"
    printf "\033[36m\n* Successfully removed backup folder\n\033[0m\n"
  fi

  #if the user is changed on upgrade
  if [ "$ID" = "osx" ]; then
    $sudo_cmd chown "$ACC_INSTALL_USR":"$ACC_INSTALL_USR_GRP" "$ACC_CONF"
    $sudo_cmd chown "$ACC_INSTALL_USR":"$ACC_INSTALL_USR_GRP" "$ACC_ALLOW_LIST_PATH"
    $sudo_cmd chown "$ACC_INSTALL_USR":"$ACC_INSTALL_USR_GRP" "$ACC_AGENT_ID"
  fi

  if [ "$mid" ]; then
    add_midList_to_config
  fi

  #============Restore Files ended=================
else
  if $sudo_cmd test -f "$ACC_CONF"; then
    printf "\033[36m\n* Keeping old $CONF configuration file\n\033[0m\n"
  else
    $sudo_cmd cp "$ACC_CONF.example" "$ACC_CONF"
    $sudo_cmd chown "$ACC_INSTALL_USR":"$ACC_INSTALL_USR_GRP" "$ACC_CONF"
    #Edit the file after the ownership is changed, since on macOS the backfile will still be under root
    if [ "$mid" ]; then
      add_midList_to_config
    fi
    if [ "$api_key" ]; then
      printf "\033[36m\n* Adding API KEY to the agent configuration: $ACC_CONF\n\033[0m\n"
      $sudo_cmd $sed_cmd 's/api-key: ""/api-key: "'"$api_key"'"/g' "$ACC_CONF"
    fi
    if [ "$allow_list"  == "1" ]; then
      printf "\033[36m\n* Copying check-allow-list.json to the : $ACC_ALLOW_LIST_PATH\n\033[0m\n"
      $sudo_cmd cp -p "$ACC_ALLOW_LIST_PATH.default" "$ACC_ALLOW_LIST_PATH"
    else
      printf "\033[36m\n* Comment out the allow-list parameter in: $ACC_CONF\n\033[0m\n"
      $sudo_cmd $sed_cmd  "s/allow-list:/#allow-list:/" "$ACC_CONF"
    fi
  fi
fi


if [ "$ID" = "osx" ]; then
    #need to stop and start service to apply acc.yml changes
    printf "\033[36m\n* Stopping agent service\n\033[0m\n"
    $svc_stop_cmd
else
    printf "\033[36m\n* Enabling agent service\n\033[0m\n"
    $svc_enable_cmd
    $svc_enable_cmd2
fi

printf "\033[36m\n* Starting agent service\n\033[0m\n"
$svc_start_cmd



if [ "$EXECUTION_TYPE" = "UPGRADE" ]; then
  printf "\033[36m\n* Upgrade process completed successfully\n\033[0m\n"
else
  printf "\033[36m\n* Install process completed successfully\n\033[0m\n"
fi
printf "\033[36m\n* To view logs: tail -f /var/log/servicenow/$ACC_NAME/acc.log\n\033[0m\n"

if [ "$ID" = "osx" ]; then
    $sudo_cmd launchctl unsetenv ACC_INSTALL_USR
    $sudo_cmd launchctl unsetenv ACC_INSTALL_USR_GRP
    $sudo_cmd launchctl unsetenv ACC_INSTALL_DEBUG
fi

