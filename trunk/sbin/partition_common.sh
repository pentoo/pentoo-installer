#!/bin/bash
# This script is released under the GNU General Public License 3.0
# Check the COPYING file included with this distribution

# to be sourced by other scripts

source common.sh || exit $?

##############################
## START: define constants ##
## END: define constants ##
############################

########################################
## START: initialize global variables ##
## END: initialize global variables ##
######################################

##############################
## START: utility functions ##

# partition_getavaildisks()
# Get a list of available disks for use in the "Available disks" dialogs. This
# will print the disks as follows, getting size info from partition_getdisccapacity():
#   /dev/sda: 625000 MiB (610 GiB)
#   /dev/sdb: 476940 MiB (465 GiB)
#
partition_getavaildisks() {
	local _DISC=""
	local _DISC_LIST=""
	local _DISC_SIZE=""
	_DISC_LIST=$(partition_finddisks) || return $?
    for _DISC in ${_DISC_LIST}; do
        _DISC_SIZE=$(partition_getdisccapacity $_DISC) || return $?
        echo "${_DISC}: $((_DISC_SIZE / 2**20)) MiB ($((_DISC_SIZE / 2**30)) GiB)\n" || return $?
    done
	return 0
}

# partition_finddisks()
# prints devices to STDOUT
#
# returns 0 on success
# anything else is a real error
# parameters: none
#
partition_finddisks() {
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	local _DEV=""
    # ide devices
    for _DEV in $(ls /sys/block | egrep '^hd'); do
        if [ "$(cat /sys/block/${_DEV}/device/media)" = "disk" ]; then
            echo "/dev/${_DEV}"
        fi
    done
    #scsi/sata devices
    for _DEV in $(ls /sys/block | egrep '^sd'); do
        # TODO: what is the significance of 5?
        if ! [ "$(cat /sys/block/${_DEV}/device/type)" = "5" ]; then
            echo "/dev/${_DEV}"
        fi
    done
    #virtual devices
    for _DEV in $(ls /sys/block | egrep '^vd'); do
        # TODO: how to check if this is really a disk?
        if [ "$(grep -c 'DEVTYPE=disk' ${_DEV}/uevent)" = "1" ]; then
            echo "/dev/${_DEV}"
        fi
    done
    # cciss controllers
    if [ -d /dev/cciss ] ; then
        for _DEV in $(ls /dev/cciss | egrep -v 'p'); do
            echo "/dev/cciss/${_DEV}"
        done
    fi
    # Smart 2 controllers
    if [ -d /dev/ida ] ; then
        for _DEV in $(ls /dev/ida | egrep -v 'p'); do
            echo "/dev/ida/${_DEV}"
        done
    fi
	return 0
}
# end of partition_finddisks()

# partition_findpartitions()
# prints partitions to STDOUT
#
# returns 0 on success
# anything else is a real error
# parameters: none
#
partition_findpartitions() {
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	local _DEV=""
	local _DEVPATH=""
	local _DISC=
	local _PART=
	local _PARTPATH=
    for _DEVPATH in $(partition_finddisks); do
        _DISC=$(echo ${_DEVPATH} | sed 's|.*/||') || return $?
        for _PARTPATH in "/sys/block/${_DISC}/${_DISC}"*; do
			_PART="$(basename ${_PARTPATH})" || return $?
            # check if not already assembled to a raid device
            if ! cat /proc/mdstat 2>/dev/null | grep -q "${_PART}" \
				&& ! file -s /dev/"${_PART}" | grep -qi lvm2 \
				&& ! fdisk -l /dev/"${_DISC}" | grep "^/dev/${_PART}[[:space:]]" | awk '{print $6}' | grep -q 5 \
				; then
				if [ -d "${_PARTPATH}" ]; then
                    echo "/dev/${_PART}"
                fi
            fi
        done
    done
    # include any mapped devices
    for _DEVPATH in $(ls /dev/mapper 2>/dev/null | grep -v control); do
        echo "/dev/mapper/${_DEVPATH}"
    done
    # include any raid md devices
    for _DEVPATH in $(ls -d /dev/md* | grep '[0-9]' 2>/dev/null); do
        if cat /proc/mdstat | grep -qw $(echo ${_DEVPATH} | sed -e 's|/dev/||g'); then
			echo "${_DEVPATH}"
        fi
    done
    # include cciss controllers
    if [ -d /dev/cciss ] ; then
        for _DEV in $(ls /dev/cciss | egrep 'p'); do
            echo "/dev/cciss/${_DEV}"
        done
    fi
    # include Smart 2 controllers
    if [ -d /dev/ida ] ; then
        for _DEV in $(ls /dev/ida | egrep 'p'); do
            echo "/dev/ida/${_DEV}"
        done
    fi
	return 0
}
# end of partition_findpartitions()

# partition_getdisccapacity()
#
# parameters: device file
# outputs:    disc capacity in bytes
partition_getdisccapacity() {
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
    fdisk -l $1 | sed -n '2p' | cut -d' ' -f5 || return $?
	return 0
}

# partition_selectdisk()
# displays available disks so user can select one
# prints disk to STDOUT
#
# exits: !=1 is an error
#
partition_selectdisk() {
    local _DISC=""
    local _DISCS=""
    local _DISCS_AVAILABLE=""
	_DISCS_AVAILABLE=$(partition_getavaildisks) || return $?
	_DISCS=$(partition_finddisks) || return $?
	_DISCS=$(add_option_label "${_DISCS}" '-') || return $?
    _DISCS="${_DISCS} OTHER -"
	show_dialog --msgbox "Available Disks:\n\n${_DISCS_AVAILABLE}\n" 0 0
	_DISC=`show_dialog --menu "Select the disk you want to use" \
			0 0 7 ${_DISCS}` \
			|| return $?
	if [ "${_DISC}" = "OTHER" ]; then
		_DISC="$(show_dialog --inputbox "Enter the full path to the device you wish to use" \
		0 0 "/dev/sda")" || return $?
		echo dump _DISC = "${_DISC}" 1>&2
		# validate _DISC
		if [ ! -b "${_DISC}" ] \
			|| ! lsblk -dn -o TYPE "${_DISC}" | grep -q disk; then
			echo dump2 _DISC = "${_DISC}" 1>&2
			show_dialog --msgbox "Device '${_DISC}' is not valid" 0 0
			return "${ERROR_CANCEL}"
		fi
	fi
	# sanity check
	# TODO remove for public use
	if [ "${_DISC}" = "/dev/sda" ] || [ "${_DISC}" = "/dev/sdb" ]; then
		echo "EXITING FOR SAFETY, NOT TESTING ON /dev/sd[ab]!" 1>&2
		exit 1
	fi
	# everything ok,_DISC_LIST print result to STDOUT
	echo "${_DISC}"
	return 0
}

# partition_selectpartition()
# displays available partitions so user can select one
# prints partition to STDOUT
#
# exits: !=1 is an error
#
partition_selectpartition() {
    local _PART=""
    local _PARTS=""
    local _DISCS_AVAILABLE=""
	_DISCS_AVAILABLE=$(partition_getavaildisks) || return $?
	_PARTS="$(partition_findpartitions)" || return $?
	_PARTS="$(add_option_label "${_PARTS}" '-')" || return $?
    _PARTS="${_PARTS} OTHER -"
	show_dialog --msgbox "Available Disks:\n\n${_DISCS_AVAILABLE}\n" 0 0
	_PART="$(show_dialog --menu "Select the partition you want to use" \
			0 0 7 ${_PARTS})" \
			|| return $?
	if [ "${_PART}" = "OTHER" ]; then
		_PART="$(show_dialog --inputbox "Enter the full path to the device you wish to use" \
		0 0 "/dev/sda")" || return $?
		# validate _PART
		if [ ! -b "${_PART}" ] \
			|| ! lsblk -dn -o TYPE "${_PART}" | grep -q part; then
			show_dialog --msgbox "Partition '${_PART}' is not valid" 0 0
			return "${ERROR_CANCEL}"
		fi
	fi
	# everything ok, print result to STDOUT
	echo "${_PART}"
	return 0
}

# partition_umountall()
# unmounts devices to prepare installation
# also cleans up luks stuff
#
# arguments (required):
#  disk: the disk to use, for ex.: /dev/sdc
#
# exits: !=1 is an error
#
partition_umountall() {
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	local _DISC=''
	local _FSTYPE=''
	local _MOUNTPOINT=''
	local _PARTITION=''
	local _RET=''
	local _UMOUNTLIST=''
	# umount /mnt/gentoo
	umount "${DESTDIR}" 2>/dev/null
	_DISC="${1}"
	# get list of partitions, etc. below _DISC
	_UMOUNTLIST=$(lsblk -f -l -o NAME,FSTYPE,MOUNTPOINT -p -n "${_DISC}" | tail -n +2) || return $?
    show_dialog --infobox "Disabling swapspace, unmounting already mounted disk devices..." 0 0 || return $?
	# loop over the list , get name and fstype
	while read _LINE; do
		_PARTITION=$(echo ${_LINE} | awk '{print $1}')
		_FSTYPE=$(echo "${_LINE}" | awk '{print $2}')
		_MOUNTPOINT=$(echo "${_LINE}" | awk '{print $3}')
		# swap partition
		if [ "${_FSTYPE}" = 'swap' ]; then
			swapoff "${_PARTITION}" &>/dev/null
		elif [ -n "${_MOUNTPOINT}" ]; then
			umount "${_MOUNTPOINT}" || return $?
		fi
		# clean up luks mounts
		if cryptsetup status "${_PARTITION}" &>/dev/null; then
			cryptsetup close "${_PARTITION}" || return $?
		fi
	done <<<"${_UMOUNTLIST}"
	return 0
}

## END: utility functions ##
############################
