#!/bin/bash
# This script is released under the GNU General Public License 3.0
# Check the COPYING file included with this distribution

# to be sourced by other scripts

# source common variables, functions and error handling
source "${SHAREDIR}"/common.sh || exit $?

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
			fdisk -l /dev/"${_DISC}" | grep "^/dev/${_PART}[[:space:]]" | awk '{print $5}' 1>&2
            # check if not already assembled to a raid device
            if ! cat /proc/mdstat 2>/dev/null | grep -q "${_PART}" \
				&& ! file -s /dev/"${_PART}" | grep -qi lvm2 \
				&& ! fdisk -l /dev/"${_DISC}" | grep "^/dev/${_PART}[[:space:]]" | awk '{print $5}' | grep -q 5 \
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
    fdisk -l "${1}" | sed -n '2p' | cut -d' ' -f5 || return $?
	return 0
}

# partition_getdisccapacity_formatted()
# outputs formatted disc capacity
# Example:
#  625000 MiB (610 GiB)
#
# parameters: device file
#
partition_getdisccapacity_formatted() {
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	local _DISC_SIZE=""
	_DISC_SIZE=$(partition_getdisccapacity "${1}") || return $?
	_DISC_SIZE="$((_DISC_SIZE / 2**20)) MiB ($((_DISC_SIZE / 2**30)) GiB)" || return $?
	echo -n "${_DISC_SIZE}"
	return 0
}

# partition_selectdisk()
# displays disks so user can select one
# prints disk to STDOUT
#
# exits: !=1 is an error
#
partition_selectdisk() {
    local _DISC=
    local _DISCS=
	local _MENU_ITEMS=()
	_DISCS="$(partition_finddisks)" || return $?
	for _DISC in ${_DISCS}; do
		# add disc and description to array
		_MENU_ITEMS+=("${_DISC}" "$(partition_getdisccapacity_formatted "${_DISC}")") \
			|| return $?
	done
	_MENU_ITEMS+=('OTHER' '-')
	# expand array below
	_DISC="$(show_dialog --menu "Select the disk you want to use" \
			0 0 7 "${_MENU_ITEMS[@]}")" \
			|| return $?
	if [ "${_DISC}" = "OTHER" ]; then
		_DISC="$(show_dialog --inputbox "Enter the full path to the device you wish to use" \
		0 0 "/dev/sda")" || return $?
		# validate _DISC
		if [ ! -b "${_DISC}" ] \
			|| ! lsblk -dn -o TYPE "${_DISC}" | grep -q disk; then
			show_dialog --msgbox "Device '${_DISC}' is not valid" 0 0
			return "${ERROR_CANCEL}"
		fi
	fi
	# everything ok, print result to STDOUT
	echo "${_DISC}"
	return 0
}

# partition_selectpartition()
# displays partitions so user can select one
# prints partition to STDOUT
#
# exits: !=1 is an error
#
partition_selectpartition() {
    local _PART=
    local _PARTS=
    local _DISC=
    local _DISCS=
	local _MSG=
	_DISCS="$(partition_finddisks)" || return $?
	# compose dialog message
	_MSG="Available Disks:\n"
	for _DISC in ${_DISCS}; do
		# add disc and description to message
		_MSG="${_MSG}\n${_DISC} $(partition_getdisccapacity_formatted "${_DISC}")" \
			|| return $?
	done
	_MSG="${_MSG}\n\nSelect the partition you want to use"
	_PARTS="$(partition_findpartitions)" || return $?
	_PARTS="$(add_option_label "${_PARTS}" '-')" || return $?
    _PARTS="${_PARTS} OTHER -"
	_PART="$(show_dialog --menu "${_MSG}" \
			0 0 7 ${_PARTS})" \
			|| return $?
	if [ "${_PART}" = "OTHER" ]; then
		_PART="$(show_dialog --inputbox "Enter the full path to the device you wish to use" \
		0 0 "/dev/sda1")" || return $?
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

## END: utility functions ##
############################
