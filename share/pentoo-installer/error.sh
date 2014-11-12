#!/bin/bash
# This script is released under the GNU General Public License 3.0
# Check the COPYING file included with this distribution

# to be sourced by other scripts

####################################
## START: error handling settings ##

# These are not without drawbacks!
set -o pipefail  # trace ERR through pipes
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   # set -u : exit the script if you try to use an uninitialised variable
# this is really 'tricky' thus diabled
# set -o errexit   # set -e : exit the script if any statement returns a non-true return value

## END: error handling settings ##
##################################

#####################################
## START: error handling functions ##

# error_exit()
# This function is used to cleanly exit any script. It does this displaying a
# given error message, and exiting with an error code.
# parameters:
#
error_exit() {
	echo
	echo "${@}"
	exit 1
}

# Trap the killer signals so that we can exit with a good message.
# TODO: dump remove the basename below
trap 'error_exit ''"$(basename $0)" Received signal SIGHUP''' SIGHUP
trap 'error_exit ''"$(basename $0)" Received signal SIGINT''' SIGINT
trap 'error_exit ''"$(basename $0)" Received signal SIGTERM''' SIGTERM

# Alias the function so that it will print a message with the following format:
# prog-name(@line#): message
# We have to explicitly allow aliases, we do this because they make calling the
# function much easier.
shopt -s expand_aliases
alias die='error_exit "Error ${0}(@`echo $(( ${LINENO} - 1 ))`):"'

## END: error handling functions ##
###################################
