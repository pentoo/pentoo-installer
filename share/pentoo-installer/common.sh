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
readonly LOG="/dev/tty8"
# location of other scripts to source
# readonly SHAREDIR="/usr/share/pentoo-installer"
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
# parameters:
# required: 3
#  _FUNCNAME: name of calling function/script
#  _SELECTION: which menu selection caused the error
#  _RETSUB: the return of the sub-function/script
#
# usage example:
#  	if [ ! catch_menuerror "$(basename $0)" "${NEWSELECTION}" "${RETSUB}" ]; then
#     do_OK_action
#   fi
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

# show_dialog()
# uses dialogSTDOUT
# an el-cheapo dialog wrapper
# parameters: see dialog(1) and Xdialog(1
# STDOUT and STDERR is switched compared to 'dialog' and 'Xdialog'
# usage: MYVAR=`show_dialog .......`
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
	local _BOXOPTION=
	local _INDEX_BOX=0
	local _WHICHDIALOG='dialog'
	local ANSWER=
	local _DIALOGRETURN=
	local _XDIALOG_AUTOSIZE_PERCENTAGE=33
	# copy aray of arguments so we can write to it
	_ARGUMENTS=("$@") || return $?
	# let's support Xdialog for the fun of it
	if [ ! $(type "Xdialog" &> /dev/null) ] && [ -n "${DISPLAY}" ]; then
		_WHICHDIALOG='Xdialog'
	fi
	# for Xdialog: autosize does not work well with a title, use percentage of max-size
	if [ "${_WHICHDIALOG}" = 'Xdialog' ]; then
		# loop arguments and search for the box option
		while [ "${_INDEX_BOX}" -lt "${#_ARGUMENTS[@]}" ]; do
			case "${_ARGUMENTS[$_INDEX_BOX]}" in
				# all of these have the format: --<boxoption> text height width
				'--calendar' | '--checklist' | '--dselect' | '--editbox' | '--form' | '--fselect' | '--gauge' | '--infobox' | '--inputbox' | '--inputmenu' | '--menu' | '--mixedform' | '--mixedgauge' | '--msgbox' | '--passwordbox' | '--passwordform' | '--pause' | '--progressbox' | '--radiolist' | '--tailbox' | '--tailboxbg' | '--textbox' | '--timebox' | '--yesno')
					_BOXOPTION="${_ARGUMENTS[$_INDEX_BOX]}"
					break ;;
				*) ;;
			esac
			_INDEX_BOX="$((_INDEX_BOX+1))" || return $?
		done
		# check if box option was found
		if [ -z "${_BOXOPTION}" ]; then
			echo "ERROR: Cannot find box option. Exiting with an error!" 1>&2
			return 1
		fi
		if [ "$((${_INDEX_BOX}+3))" -gt "$#" ]; then
			echo "ERROR: cannot find height and width for box option '"${_BOXOPTION}"'. Exiting with an error!" 1>&2
			return 1
		fi
		# only fix width/height for these box options
		case "${_BOXOPTION}" in
			'--menu')
				_HEIGHT="${_ARGUMENTS[$((_INDEX_BOX+2))]}" || return $?
				_WIDTH="${_ARGUMENTS[$((_INDEX_BOX+3))]}" || return $?
				# check if width/height were found
				if [ -z "${_HEIGHT}" ] || [ -z "${_WIDTH}" ]; then
					echo "ERROR: Did not find box option with height/width. Exiting with an error" 1>&2
					return 1
				fi
				# use defined percentage of max-size
				if [ "${_HEIGHT}" -eq 0 ] && [ "${_WIDTH}" -eq 0 ]; then
					_HEIGHT=$("${_WHICHDIALOG}" --print-maxsize 2>&1 | tr -d ',' | awk '{print $2}') || return $?
					_WIDTH=$("${_WHICHDIALOG}" --print-maxsize 2>&1 | tr -d ',' | awk '{print $3}') || return $?
					_HEIGHT=$((${_HEIGHT} * ${_XDIALOG_AUTOSIZE_PERCENTAGE} / 100)) || return $?
					_WIDTH=$((${_WIDTH} * ${_XDIALOG_AUTOSIZE_PERCENTAGE} / 100)) || return $?
					# write new values to copy of arguments array
					_ARGUMENTS[$((_INDEX_BOX+2))]="${_HEIGHT}" || return $?
					_ARGUMENTS[$((_INDEX_BOX+3))]="${_WIDTH}" || return $?
				fi
				;;
			*) ;;
		esac
	fi
	# switch STDOUT and STDERR and execute 'dialog' or Xdialog'
	_ANSWER=$("${_WHICHDIALOG}" --backtitle "${TITLE}" --aspect 15 "${_ARGUMENTS[@]}" 3>&1 1>&2 2>&3)
	_DIALOGRETURN=$?
	# check if user clicked cancel or closed the box
	if [ "${_DIALOGRETURN}" -eq "1" ] ||  [ "${_DIALOGRETURN}" -eq "255" ]; then
		return ${ERROR_CANCEL}
	elif [ "${_DIALOGRETURN}" -ne "0" ]; then
		return "${_DIALOGRETURN}"
	fi
	# no error or cancel, echo to STDOUT
	echo -n "${_ANSWER}"
	return 0
}

## END: utility functions ##
############################
