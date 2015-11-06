#!/bin/bash -x
# This script is released under the GNU General Public License 3.0
# Check the COPYING file included with this distribution

# to be sourced by other scripts

##############################
## START: define constants ##
readonly DESTDIR="/mnt/gentoo"
# This error code will be used when the user cancels a process
# dialog and Xdialog use 1 for cancel, Xdialog returns 255 upon closing of the box
readonly ERROR_CANCEL=64
readonly ISNUMBER='^[0-9]+$'
# use the first VT not dedicated to a running console
readonly LOG="/dev/tty8"
readonly TITLE="Pentoo Installation"
## END: define constants ##
############################

########################################
## START: initialize global variables ##
## END: initialize global variables ##
######################################

# source error handling/functions
source "${SHAREDIR}"/error.sh || exit $?

##############################
## START: utility functions ##

# add_option_label()
# Adds dummy labels to a list of strings, so it can be used by a --menu dialog
#
# returns 0 on success
#
# parameters (required):
#  list: space delimited list
#  label: the string to add as label
#
add_option_label() {
	# check input
	check_num_args "${FUNCNAME}" 2 $# || return $?
	local _ITEM=
	for _ITEM in ${1}; do
		echo "${_ITEM} ${2}"
	done
	return 0
}

# catch_menuerror()
# catch errors from sub-script/functions
#
# returns 0 when an error was given
# otherwise returns 0
#
# parameters (required):
#  _FUNCNAME: name of calling function/script
#  _SELECTION: which menu selection caused the error
#  _RETSUB: the return of the sub-function/script
#
# usage example:
#	if [ ! catch_menuerror "$(basename $0)" "${NEWSELECTION}" "${RETSUB}" ]; then
#		do_OK_action
#	fi
catch_menuerror() {
	# check input
	check_num_args "${FUNCNAME}" 3 $# || return $?
	local _FUNCNAME="${1}"
	local _SELECTION="${2}"
	local _RETSUB="${3}"
	# catch errors from sub-script/functions
	if [ "${_RETSUB}" -ne 0 ]; then
		# received CANCEL
		if [ "${_RETSUB}" -eq "${ERROR_CANCEL}" ]; then
			echo "INFO: Received CANCEL after selection of '${_SELECTION}' in $(basename $0)" 1>&2
		# received other ERROR
		else
			echo "WARNING: Received ERROR '${_RETSUB}' after selection of '${_SELECTION}' in ${_FUNCNAME}" 1>&2
			# inform user
			show_dialog --msgbox "WARNING: The last step returned an error!" 0 0
		fi
		return 0
	fi
	# no error in sub-script
	return 1
}

# chroot_mount()
# prepares target system as a chroot
#
chroot_mount() {
	# do a clean chroot-umount
	chroot_umount || return $?
	if [ ! -e "${DESTDIR}/sys" ]; then
		mkdir "${DESTDIR}/sys" || return $?
	fi
	if [ ! -e "${DESTDIR}/proc" ]; then
		mkdir "${DESTDIR}/proc" || return $?
	fi
	if [ ! -e "${DESTDIR}/dev" ]; then
		mkdir "${DESTDIR}/dev" || return $?
	fi
	mount -t sysfs sysfs "${DESTDIR}/sys" || return $?
	mount -t proc proc "${DESTDIR}/proc" || return $?
	mount -o bind /dev "${DESTDIR}/dev" || return $?
	return 0
}

# chroot_umount()
# tears down chroot in target system
#
chroot_umount() {
	sleep 1
	if mount | grep -q "${DESTDIR}/proc "; then
		umount ${DESTDIR}/proc || return $?
	fi
	if mount | grep -q "${DESTDIR}/sys "; then
		umount ${DESTDIR}/sys || return $?
	fi
	if mount | grep -q "${DESTDIR}/dev "; then
		umount ${DESTDIR}/dev || return $?
	fi
	return 0
}

# check_num_args()
# simple check for required number of input arguments of calling function
#
# returns 0 on success
# anything else is a real error
# parameters:
# required: 3
#  _FUNCNAME: name of calling function
#  _REQARGS: number of required args
#  _NUMARGS: number of received args
#
# example call for 3 required arguments:
#  check_num_args "${FUNCNAME}" 3 $# || return $?
check_num_args() {
	# simple check number of input arguments of calling function
	if [ "${2}" -ne "${3}" ]; then
		echo "${1} takes exactly ${2} arguments but received ${3}." 1>&2
		echo "Returning error 1" 1>&2
		return 1
	fi
	return 0
}

# get_supportedFS()
# prints a list of supported file systems to STDOUT
#
# returns 0 on success
# anything else is a real error
#
get_supportedFS() {
	echo -n 'ext4 ext4-nojournal'
	[ "$(which mkreiserfs 2>/dev/null)" ]	&& echo -n ' reiserfs'
	[ "$(which btrfs 2>/dev/null)" ]	&& echo -n ' btrfs'
	[ "$(which mkfs.xfs 2>/dev/null)" ]		&& echo -n ' xfs'
	[ "$(which mkfs.jfs 2>/dev/null)" ]		&& echo -n ' jfs'
	[ "$(which mkfs.vfat 2>/dev/null)" ]	&& echo -n ' vfat'
	return 0
}

# get_yesno()
# convert 0|1 to yes|no
#
# returns 0 on success
#
# parameters (required):
#  input: 0 or 1
#
get_yesno() {
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	case "${1}" in
		0) echo 'no' ;;
		1) echo 'yes' ;;
		*) echo 'ERROR: Not a boolean value of [0|1].' 1>&2
			return 1 ;;
	esac
	return 0
}

# mount_umountall()
# 1) umount -R $DESTDIR to prepare installation
# 2) swaps off devices
# 3) cleans up cryptsetup
# does a dry run and asks user for 3
#
# arguments (required):
#  _DISCLIST: List of involved discs or partitions
#
# exits: !=1 is an error
#
mount_umountall() {
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	local _DISCLIST="${1}"
	local _DISC=
	local _UMOUNTLIST=
	local _NAME=
	local _FSTYPE=
	local _MOUNTPOINT=
	local _CRYPTCLOSE=()
	local _LINE=
	# umount /mnt/gentoo and below
	# this is the only umount, anything mounted outside is the users problem
	# umount -R "${DESTDIR}" 2>/dev/null
	chroot_umount
	if lsblk -o MOUNTPOINT | grep -Eq '^/mnt/gentoo(/.*)?'; then
		umount `lsblk -o MOUNTPOINT | grep -E '^/mnt/gentoo(/.*)?' | sort -r | tr '\n' ' '` || return $?
	fi
	# do a first run, swapoff, check mountpoints and collect cryptsetup stuff
	for _DISC in ${_DISCLIST}; do
		_UMOUNTLIST="$(lsblk -lnp -o NAME,FSTYPE,MOUNTPOINT "${_DISC}")" || return $?
		while read -r _LINE; do
			_NAME=$(echo ${_LINE} | awk '{print $1}')
			# FSTYPE is only helpful for luks devices, not swap
			_FSTYPE=$(echo "${_LINE}" | awk '{print $2}')
			_MOUNTPOINT=$(echo "${_LINE}" | awk '{print $3}')
			# swapped on partition
			if [ "${_FSTYPE}" = 'swap' ] && [ "${_MOUNTPOINT}" = '[SWAP]' ]; then
				swapoff "${_NAME}" || return $?
				sleep 1
			# throw error on any other mountpoint, aka outside $DESTDIR
			elif [ -n "${_MOUNTPOINT}" ]; then
				echo "ERROR: Unexpected mountpoint '${_MOUNTPOINT}' for '${_NAME}'." 1>&2
				return 1
			fi
			# check for open cryptsetup
			# only childs, not the target partition itself
			if [ "${_NAME}" != "${_DISC}" ] && cryptsetup status "${_NAME}" &>/dev/null; then
				_CRYPTCLOSE+=("${_NAME}")
			fi
		done <<<"${_UMOUNTLIST}"
	done
	# cryptsetup open anywhere?
	if [ "${#_CRYPTCLOSE[@]}" -gt 0 ]; then
		# TODO: how is the correct term for an open cryptsetup thingy? ;)
		show_dialog --defaultno --yesno "Cryptsetup is using the names below. Do you want to close them?\n$(echo "${_CRYPTCLOSE[@]}" | tr ' ' '\n')" 0 0 || return "${ERROR_CANCEL}"
		for _NAME in ${_CRYPTCLOSE[@]}; do
				cryptsetup close "${_NAME}" || return $?
		done
	fi
	return 0
}

# seteditor()
# sets a system editor in chroot environment
# chroot must be prepared outside this function!
#
# parameters (none)
#
# returns $ERROR_CANCEL=64 on user cancel
# anything else is a real error
# reason: show_dialog() needs a way to exit "Cancel"
#
seteditor(){
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	local _EDITOR=
	local _MENU_ITEMS=()
	local _RET_SUB=
	# parse the output of 'eselect editor list' so it can be used as menu options
	_MENU_ITEMS=("$(chroot "${DESTDIR}" eselect editor list | tail -n +2 | grep -v '\(free form\)' | sed -r 's/[[:space:]]+\*[[:space:]]*$//' | sed -r -e 's/^[[:space:]]*//g' -e "s/\[([[:digit:]]+)\][[:space:]]+/\1 /" | tr '\n' ' ')") || return $?
	# ask user for editor
	_EDITOR="$(show_dialog --menu "Select a text editor to use (nano is easier)" \
		0 0 0 ${_MENU_ITEMS[@]})" \
		|| return $?
	# set new editor
	chroot ${DESTDIR} /bin/bash <<EOF
eselect editor set "${_EDITOR}" 1>&2 || exit $?
source /etc/profile || exit $?
EOF
	_RET_SUB=$?
	[ "${_RET_SUB}" -ne 0 ] && return "${_RET_SUB}"
	# read new editor
	_EDITOR="$(chroot "${DESTDIR}" eselect editor show | tail -n +2 | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g')" || return $?
	# print editor to STDOUT
	echo "${_EDITOR}"
	return 0
}

# geteditor()
# get system editor from chroot, prints to SDTOUT
# if not set: asks user to choose one
# chroot must be prepared outside this function!
#
# parameters (none)
#
# returns $ERROR_CANCEL=64 on user cancel
# anything else is a real error
# reason: show_dialog() needs a way to exit "Cancel"
#
geteditor(){
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	local _EDITOR=
	# read current editor
	_EDITOR="$(chroot "${DESTDIR}" eselect editor show | tail -n +2 | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e 's/[[:space:]]*$//g')" || return $?
	# check if not set
	if [ "${_EDITOR}" = '(none)' ]; then
		_EDITOR="$(seteditor)" || return $?
	fi
	# print editor to STDOUT
	echo "${_EDITOR}"
	return 0
}

# get_dialog()
# prints used dialog programm: 'dialog' or 'Xdialog'
#
get_dialog() {
	# let's support Xdialog for the fun of it
	#if [ ! $(type "Xdialog" &> /dev/null) ] && [ -n "${DISPLAY}" ]; then
	#	echo 'Xdialog'
	#else
		echo 'dialog'
	#fi
	return 0
}

# show_dialog()
# uses dialogSTDOUT
# an el-cheapo dialog wrapper
# parameters: see dialog(1) and Xdialog(1
# usage: MYVAR="$(show_dialog .......)"
# returns:
# - 0 for Ok, result is written to STDOUT
# - 64 when user clicks cancel or closes the box
# - anything else is a real error
#
show_dialog() {
	# this script supports dialog and Xdialog but writes result to STDOUT
	# returns 64 if user cancels or closes the box!
	# detect auto-width and auto-height
	local _ARGUMENTS=
	local _HEIGHT=
	local _WIDTH=
	local _BOXOPTION_INDEX=
	local _INDEX=0
	local _WHICHDIALOG=
	local ANSWER=
	local _DIALOGRETURN=
	local _XDIALOG_AUTOSIZE_PERCENTAGE=33
	# copy array of arguments so we can write to it
	# also prepend our own arguments
	_ARGUMENTS=("$@") || return $?
	_ARGUMENTS=( '--backtitle' "${TITLE}" '--aspect' '15' "$@") || return $?
	# decide which dialog to use
	_WHICHDIALOG="$(get_dialog)"
	# for Xdialog: autosize does not work well with a title, use percentage of max-size
	if [ "${_WHICHDIALOG}" = 'Xdialog' ]; then
		# loop arguments and search for the box option
		# also swap --title and --backtitle
		while [ "${_INDEX}" -lt "${#_ARGUMENTS[@]}" ]; do
			case "${_ARGUMENTS[$_INDEX]}" in
				# all of these have the format: --<boxoption> text height width
				'--calendar' | '--checklist' | '--dselect' | '--editbox' | '--form' | '--fselect' | '--gauge' | '--infobox' | '--inputbox' | '--inputmenu' | '--menu' | '--mixedform' | '--mixedgauge' | '--msgbox' | '--passwordbox' | '--passwordform' | '--pause' | '--progressbox' | '--radiolist' | '--tailbox' | '--tailboxbg' | '--textbox' | '--timebox' | '--yesno')
					# prevent multiple box options
					[ -n "${_BOXOPTION_INDEX}" ] && return 1
					_BOXOPTION_INDEX="${_INDEX}"
					;;
				# swap title and backtitle for Xdialog
				'--title')
					_ARGUMENTS[${_INDEX}]='--backtitle'
					;;
				# swap title and backtitle for Xdialog
				'--backtitle')
					_ARGUMENTS[${_INDEX}]='--title'
					;;
				*) ;;
			esac
			_INDEX="$((_INDEX+1))" || return $?
		done
		# check if box option was found
		if [ -z "${_BOXOPTION_INDEX}" ]; then
			echo "ERROR: Cannot find box option. Exiting with an error!" 1>&2
			return 1
		fi
		if [ "$((${_BOXOPTION_INDEX}+3))" -ge "${#_ARGUMENTS[@]}" ]; then
			echo "ERROR: cannot find height and width for box option '"${_ARGUMENTS[${_BOXOPTION_INDEX}]}"'. Exiting with an error!" 1>&2
			return 1
		fi
		# only fix width/height for these box options
		case "${_ARGUMENTS[${_BOXOPTION_INDEX}]}" in
			'--menu' | '--gauge')
				_HEIGHT="${_ARGUMENTS[$((_BOXOPTION_INDEX+2))]}" || return $?
				_WIDTH="${_ARGUMENTS[$((_BOXOPTION_INDEX+3))]}" || return $?
				# check if width/height were found
				if [ -z "${_HEIGHT}" ] || [ -z "${_WIDTH}" ]; then
					echo "ERROR: Did not find box option with height/width. Exiting with an error" 1>&2
					return 1
				fi
				# use defined percentage of max-size
				if [ "${_HEIGHT}" -eq 0 ] && [ "${_WIDTH}" -eq 0 ]; then
					_HEIGHT=$("${_WHICHDIALOG}" --print-maxsize 2>&1 | tr -d ',' | cut -d ' ' -f2) || return $?
					_WIDTH=$("${_WHICHDIALOG}" --print-maxsize 2>&1 | tr -d ',' | cut -d ' ' -f3) || return $?
					_HEIGHT=$((${_HEIGHT} * ${_XDIALOG_AUTOSIZE_PERCENTAGE} / 100)) || return $?
					_WIDTH=$((${_WIDTH} * ${_XDIALOG_AUTOSIZE_PERCENTAGE} / 100)) || return $?
					# write new values to copy of arguments array
					_ARGUMENTS[$((_BOXOPTION_INDEX+2))]="${_HEIGHT}" || return $?
					_ARGUMENTS[$((_BOXOPTION_INDEX+3))]="${_WIDTH}" || return $?
				fi
				;;
			*) ;;
		esac
	fi
	#not sure how this redirection will work for Xdialog, but for now this makes catching logs perfect
	_ANSWER=$("${_WHICHDIALOG}" "${_ARGUMENTS[@]}" 2>&1 >/dev/tty)
	_DIALOGRETURN=$?
	# check if user clicked cancel or closed the box
	if [ "${_DIALOGRETURN}" -eq "1" ] || [ "${_DIALOGRETURN}" -eq "255" ]; then
		return ${ERROR_CANCEL}
	elif [ "${_DIALOGRETURN}" -ne "0" ]; then
		return "${_DIALOGRETURN}"
	fi
	# no error or cancel, echo to STDOUT
	echo -n "${_ANSWER}"
	return 0
}

# show_dialog_rsync()
# runs rsync, displays output as gauge dialog
# tee's log to "${LOG}"
# options to rsync should include '--progress' or the gauge will not move ;)
#
# parameters (required):
#  _OPTIONS: options for rsync
#  _SOURCE: source for rsync
#  _DESTINATION: destination for rsync
#  _MSG: message for gauge dialog
#
# returns $ERROR_CANCEL=64 on user cancel
# anything else is a real error
# reason: show_dialog() needs a way to exit "Cancel"
#
show_dialog_rsync() {
	# check input
	check_num_args "${FUNCNAME}" 4 $# || return $?
	local _OPTIONS="${1}"
	local _SOURCE="${2}"
	local _DESTINATION="${3}"
	local _MSG="${4}"
	rsync ${_OPTIONS} ${_SOURCE} ${_DESTINATION} 2>&1 \
		| tee "${LOG}" \
		| awk -f "${SHAREDIR}"/rsync.awk \
		| sed --unbuffered 's/\([0-9]*\).*/\1/' \
		| show_dialog --gauge "${_MSG}" 0 0
	_RET_SUB=$?
	if [ "${_RET_SUB}" -ne 0 ]; then
		show_dialog --msgbox "Failed to rsync '${_DESTINATION}'. See the log output for more information" 0 0
		return "${_RET_SUB}"
	fi
	return 0
}

## END: utility functions ##
############################
