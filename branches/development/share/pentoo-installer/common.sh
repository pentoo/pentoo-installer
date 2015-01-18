#!/bin/bash
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
readonly STORDIR="/tmp/pentoo-installer"
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

# catch_menuerror()
# catch errors from sub-script/functions
#
# returns 0 when an error was given
# otherwise returns 1
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

# get_dialog()
# prints used dialog programm: 'dialog' or 'Xdialog'
#
get_dialog() {
	# let's support Xdialog for the fun of it
	if [ ! $(type "Xdialog" &> /dev/null) ] && [ -v 'DISPLAY' ] && [ -n "${DISPLAY}" ]; then
		echo 'Xdialog'
	else
		echo 'dialog'
	fi
	return 0
}

# show_dialog()
# uses dialogSTDOUT
# an el-cheapo dialog wrapper
# parameters: see dialog(1) and Xdialog(1
# STDOUT and STDERR is switched compared to 'dialog' and 'Xdialog'
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
	# switch STDOUT and STDERR and execute 'dialog' or Xdialog'
	_ANSWER=$("${_WHICHDIALOG}" "${_ARGUMENTS[@]}" 3>&1 1>&2 2>&3)
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

# storage_delete()
# deletes the temp storage
#
# returns 0 when no error occured
#
# parameters (none)
#
storage_delete() {
	# check input
	check_num_args "${FUNCNAME}" 0 $# || return $?
	if [ ! -e "${STORDIR}" ]; then
		echo >&2 "ERROR: ${STORDIR} does not exist"
		return 1
	elif ! mountpoint -q "${STORDIR}"; then
		echo >&2 "ERROR: ${STORDIR} is not mounted"
		return 1
	fi
	umount "${STORDIR}" || return $?
	rmdir "${STORDIR}" || return $?
	return 0
}

# storage_write()
# writes its input to the tmp storage
#
# returns 0 when no error occured
#
# parameters (required):
#  _FILENAME: the file to write to
#
storage_write() {
	# check input
	check_num_args "${FUNCNAME}" 1 $# || return $?
	local _FILENAME="${1}"
	if [ ! -e "${STORDIR}" ]; then
		mkdir -p "${STORDIR}" || return $?
	elif ! mountpoint -q "${STORDIR}"; then
		mount -t tmpfs tmpfs "${STORDIR}" || return $?
	elif [ -z "${_FILENAME}" ]; then
		echo >&2 "ERROR: Parameter _FILENAME cannot be empty"
		return 1
	fi
	mkdir -p "$(dirname "${STORDIR}/${_FILENAME}")" || return $?
	cat > "${STORDIR}/${_FILENAME}" || return $?
	return 0
}

## END: utility functions ##
############################
