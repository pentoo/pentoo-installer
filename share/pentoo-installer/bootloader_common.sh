#!/bin/bash -x
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

# getkernelparams()
# prints kernel params to STDOUT
#
# parameters (required)
#  _ROOTPART: root partition
#  _BOOTPART: boot partition
#  _CRYPTTYPE: encryption-type (should be '' or 'luks-gpg')
#  _CRYPTNAME: cryptname of root partition
#
# returns 0 on success
# anything else is a real error
#
getkernelparams() {
	# check input
	check_num_args "${FUNCNAME}" 4 $# || return $?
	local _ROOTPART="${1}"
	local _BOOTPART="${2}"
	local _CRYPTTYPE="${3}"
	local _CRYPTNAME="${4}"
	local _KERNEL_PARAMS=
	_KERNEL_PARAMS="$(parse_kernel_cmdline)" || return $?
	# encrypted root partition
	if [ "${_CRYPTTYPE}" != '' ]; then
		_KERNEL_PARAMS="root=/dev/ram0 real_root=/dev/mapper/${_CRYPTNAME} dogpg crypt_root=${_ROOTPART} root_key=/${_CRYPTNAME}.gpg root_keydev=${_BOOTPART} ${_KERNEL_PARAMS} console=tty1 net.ifnames=0 ro"
	else
		_KERNEL_PARAMS="root=/dev/ram0 real_root=${_ROOTPART} ${_KERNEL_PARAMS} console=tty1 net.ifnames=0 ro"
	fi
  #wierd hack to disable amd memory encryption when nvidia is in use
  if [ "$(uname -i)" = "AuthenticAMD" ] && grep -q nvidia /proc/modules; then
    _KERNEL_PARAMS="${_KERNEL_PARAMS} mem_encrypt=off"
  fi
	# print result
	echo "${_KERNEL_PARAMS}"
	return 0
}

# getkernelversion()
# outputs the kernel version
#
# parameters: none
# outputs:	kernel version on success
#
# returns:	0 on success
#			1 on failure
getkernelversion() {
	local _KERNVER=
	_KERNVER=$(ls "${DESTDIR}"/boot/kernel-genkernel-* | sed -e "s|kernel-genkernel||g" -e "s|${DESTDIR}/boot/||") \
		|| return 1
	echo "${_KERNVER}"
}

# parse_kernel_cmdline()
# parse kernel cmdline (only video mode for now)
# prints a string to STDOUT like 'video=whatever'
parse_kernel_cmdline() {
	local _VAR=
	local _FIRST=0
	for _VAR in $(cat /proc/cmdline); do
		case "${_VAR}" in
			video=*)
				[ "${_FIRST}" -ne 0 ] && echo -n ' '
				echo -n "${_VAR}"
				_FIRST=1
			;;
		esac
	done
}

## END: utility functions ##
############################
