#!/bin/bash
# This script is released under the GNU General Public License 3.0
# Check the COPYING file included with this distribution

# to be sourced by other scripts

##############################
## START: define constants ##
# tmp file used to backup settings of main menu
readonly SETTINGS_FILE='/tmp/.pentoo-installer'
# non-tmp file used to backup settings of main menu
readonly SETTINGS_FILE_PERMANENT='~/.pentoo-installer'
## END: define constants ##
############################

# source common variables, functions and error handling
source "${SHAREDIR}"/common.sh || exit $?

##############################
## START: utility functions ##

# settings_check()
# checks for valid settings file
#
# parameters (none)
#
# returns 0 when a valid settings file is present
#
settings_check(){
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	# look for permanent file
	if [ -f "${SETTINGS_FILE_PERMANENT}" ]; then
		# use only if tmp file not present
		if [ ! -f "${SETTINGS_FILE}" ]; then
			cp "${SETTINGS_FILE_PERMANENT}" "${SETTINGS_FILE}" || return $?
		fi
		# delete permantent file
		shred -u "${SETTINGS_FILE_PERMANENT}" || return $?
	fi
	if [ -f "${SETTINGS_FILE}" ]; then
		if [ "$(cat "${SETTINGS_FILE}" | wc -l)" -eq 3 ]; then
			return 0
		fi
		# shred wrong files
		# shred -u "${SETTINGS_FILE}" || return $?
	fi
	return 1
}

# settings_checkmount()
# checks if all partitions from a settings file can be mounted
#
# parameters (required):
#  _MOUNT_SELECTION: value for MAXSELECTION after which partitions should be mounted
#   (meaning past "Prepare harddrive")
#
# returns 0 if everything looks ok
#
settings_checkmount(){
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	local _MOUNT_SELECTION="${1}"
	local _SELECTION=
	local _MAXSELECTION=
	local _CONFIG_LIST=
	# check if partitions should be mounted
	# read lines of file
	_SELECTION="$(sed -n 1p "${SETTINGS_FILE}")" || return $?
	_MAXSELECTION="$(sed -n 2p "${SETTINGS_FILE}")" || return $?
	_CONFIG_LIST="$(sed -n 3p "${SETTINGS_FILE}")" || return $?
	# check integers
	[[ "${_SELECTION}" =~ ^[1-9][0-9]*$ ]] || return 1
	[[ "${_MAXSELECTION}" =~ ^[1-9][0-9]*$ ]] || return 1
	# check if things should be mounted
	if [ "${_MAXSELECTION}" -gt "${_MOUNT_SELECTION}" ]; then
		# Try to unmount everything
		"${SHAREDIR}"/FSspec umountall "${_CONFIG_LIST}" || return $?
		# mount everything, including cryptsetup
		"${SHAREDIR}"/FSspec mountall "${_CONFIG_LIST}" || return $?
	fi
	# looking good
	return 0
}

# settings_read()
# reads values from a settings file and prints to STDOUT
#
# parameters (required):
#  _INDEX: line number to read
#
settings_read(){
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	sed -n "${1}"p "${SETTINGS_FILE}" || return $?
	return 0
}

# settings_write()
# writes config of main menu to a temp file
#
# parameters (vars from main menu):
#  SELECTION
#  MAXSELECTION
#  CONFIG_LIST
#
# returns 0 on success
# anything else is a real error
#
settings_write(){
	# check input
	check_num_args "${FUNCNAME}" 3 $# || return $?
	echo "${1}">"${SETTINGS_FILE}" || return $?
	echo "${2}">>"${SETTINGS_FILE}" || return $?
	echo "${3}">>"${SETTINGS_FILE}" || return $?
	return 0
}

# settings_shred()
# shreds config files
#
# parameters (none)
#
# returns 0 on success
#
settings_shred(){
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	if [ -e "${SETTINGS_FILE}" ]; then
		shred -u "${SETTINGS_FILE}" || return $?
	fi
	return 0
}

## END: utility functions ##
############################
