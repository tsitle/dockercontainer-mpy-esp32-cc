#!/bin/bash

#
# by TS, Oct 2019
#

# @param string $1 Path
# @param int $2 Recursion level
#
# @return string Absolute path
function realpath_osx() {
	local TMP_RP_OSX_RES=
	[[ $1 = /* ]] && TMP_RP_OSX_RES="$1" || TMP_RP_OSX_RES="$PWD/${1#./}"

	if [ -h "$TMP_RP_OSX_RES" ]; then
		TMP_RP_OSX_RES="$(readlink "$TMP_RP_OSX_RES")"
		# possible infinite loop...
		local TMP_RP_OSX_RECLEV=$2
		[ -z "$TMP_RP_OSX_RECLEV" ] && TMP_RP_OSX_RECLEV=0
		TMP_RP_OSX_RECLEV=$(( TMP_RP_OSX_RECLEV + 1 ))
		if [ $TMP_RP_OSX_RECLEV -gt 20 ]; then
			# too much recursion
			TMP_RP_OSX_RES="--error--"
		else
			TMP_RP_OSX_RES="$(realpath_osx "$TMP_RP_OSX_RES" $TMP_RP_OSX_RECLEV)"
		fi
	fi
	echo "$TMP_RP_OSX_RES"
}

# @param string $1 Path
#
# @return string Absolute path
function realpath_poly() {
	case "$OSTYPE" in
		linux*) realpath "$1" ;;
		darwin*) realpath_osx "$1" ;;
		*) echo "$VAR_MYNAME: Error: Unknown OSTYPE '$OSTYPE'" >/dev/stderr; echo -n "$1" ;;
	esac
}

VAR_MYNAME="$(basename "$0")"
VAR_MYDIR="$(realpath_poly "$0")"
VAR_MYDIR="$(dirname "$VAR_MYDIR")"

# ----------------------------------------------------------

OPT_R_BASH=false
OPT_R_CLEAN=false
OPT_R_MKALL=false

OPT_FWTYPE_DEF=false
OPT_FWTYPE_SRAM=false

function printUsageAndExit() {
	echo "Usage: $VAR_MYNAME VERSION bash|[clean|mk def|spiram]" >/dev/stderr
	echo "Examples: $VAR_MYNAME 1.11 bash" >/dev/stderr
	echo "          $VAR_MYNAME 1.11 clean def" >/dev/stderr
	echo "          $VAR_MYNAME 1.11 mk def" >/dev/stderr
	echo "          $VAR_MYNAME 1.12 clean spiram" >/dev/stderr
	echo "          $VAR_MYNAME 1.12 mk spiram" >/dev/stderr
	exit 1
}

if [ $# -lt 2 ]; then
	if [ $# -gt 0 ]; then
		echo -e "Missing argument. Aborting.\n" >/dev/stderr
	fi
	printUsageAndExit
fi

OPT_MPY_FW_VERS="$1"
shift

if [ ! -d "${VAR_MYDIR}/$OPT_MPY_FW_VERS/def/mpbuild" ]; then
	echo -e "Invalid firmware version '$OPT_MPY_FW_VERS'. Aborting.\n" >/dev/stderr
	printUsageAndExit
fi

if [ "$1" = "bash" ]; then
	if [ $# -ne 1 ]; then
		echo -e "Too many arguments. Aborting.\n" >/dev/stderr
		printUsageAndExit
	fi
	OPT_R_BASH=true
else
	if [ $# -lt 2 ]; then
		echo -e "Missing argument. Aborting.\n" >/dev/stderr
		printUsageAndExit
	elif [ $# -gt 2 ]; then
		echo -e "Too many arguments. Aborting.\n" >/dev/stderr
		printUsageAndExit
	fi
	if [ "$1" = "clean" ]; then
		OPT_R_CLEAN=true
	elif [ "$1" = "mk" ]; then
		OPT_R_MKALL=true
	else
		echo -e "Invalid argument '$1'. Aborting.\n" >/dev/stderr
		printUsageAndExit
	fi
	shift
	if [ "$1" = "def" ]; then
		OPT_FWTYPE_DEF=true
	elif [ "$1" = "spiram" ]; then
		OPT_FWTYPE_SRAM=true
	else
		echo -e "Invalid argument '$1'. Aborting.\n" >/dev/stderr
		printUsageAndExit
	fi
fi

# ----------------------------------------------------------

LCFG_REPO_PREFIX="tsle"
LCFG_IMAGE_NAME="mpy-esp32-cc-amd64"

LCFG_CONTAINER_NAME="mpy-esp32-cc-$(echo -n "$OPT_MPY_FW_VERS" | tr -d .)"

LCFG_MNTPOINT_BASE="${VAR_MYDIR}"
LCFG_MNTPOINT_MPBUILD_TEMPL="${LCFG_MNTPOINT_BASE}/${OPT_MPY_FW_VERS}/#TYPE#/mpbuild"
LCFG_MNTPOINT_MPSCR_TEMPL="${LCFG_MNTPOINT_BASE}/${OPT_MPY_FW_VERS}/#TYPE#/mpscripts"

LCFG_PATH_MODS="${VAR_MYDIR}/mods"

LCFG_MPY_FW_OUTP_FN_TEMPL="${VAR_MYDIR}/mpy-firmware-${OPT_MPY_FW_VERS}-#TYPE#.bin"

# ----------------------------------------------------------

LVAR_IMAGE_VER="$OPT_MPY_FW_VERS"
LVAR_IMG_FULL="${LCFG_IMAGE_NAME}:${LVAR_IMAGE_VER}"

# ----------------------------------------------------------

# @param string $1 Docker Image name
# @param string $2 optional: Docker Image version
#
# @returns int If Docker Image exists 0, otherwise 1
function _getDoesDockerImageExist() {
	local TMP_SEARCH="$1"
	[ -n "$2" ] && TMP_SEARCH="$TMP_SEARCH:$2"
	local TMP_AWK="$(echo -n "$1" | sed -e 's/\//\\\//g')"
	#echo "  checking '$TMP_SEARCH'"
	local TMP_IMGID="$(docker image ls "$TMP_SEARCH" | awk '/^'$TMP_AWK' / { print $3 }')"
	[ -n "$TMP_IMGID" ] && return 0 || return 1
}

_getDoesDockerImageExist "$LCFG_IMAGE_NAME" "$LVAR_IMAGE_VER"
if [ $? -ne 0 ]; then
	LVAR_IMG_FULL="${LCFG_REPO_PREFIX}/$LVAR_IMG_FULL"
	_getDoesDockerImageExist "${LCFG_REPO_PREFIX}/${LCFG_IMAGE_NAME}" "$LVAR_IMAGE_VER"
	if [ $? -ne 0 ]; then
		echo "$VAR_MYNAME: Trying to pull image from repository '${LCFG_REPO_PREFIX}/'..."
		docker pull ${LVAR_IMG_FULL}
		if [ $? -ne 0 ]; then
			echo "$VAR_MYNAME: Error: could not pull image '${LVAR_IMG_FULL}'. Aborting." >/dev/stderr
			exit 1
		fi
	fi
fi

# ----------------------------------------------------------

LVAR_INTPATH_BUILDTRG=""
LVAR_MNTPOINT_MPBUILD=""
LVAR_MNTPOINT_MPSCR=""
LVAR_MPY_SDKCONFIG=""
LVAR_MPY_FW_OUTP_FN=""

# ----------------------------------------------------------

# @param string $1 Username for executing bash (optional)
# @param string $2 Command to run
function _runCont() {
	local TMP_USER="$1"
	[ -n "$TMP_USER" ] && TMP_USER="-u $TMP_USER"

	echo "* Run '$LCFG_CONTAINER_NAME'..."
	docker run \
			--name "$LCFG_CONTAINER_NAME" \
			--rm \
			-it \
			-d \
			-v "$LVAR_MNTPOINT_MPBUILD":/esp/micropython/ports/esp32/$LVAR_INTPATH_BUILDTRG \
			-v "$LVAR_MNTPOINT_MPSCR":/esp/micropython/ports/esp32/scripts \
			$TMP_USER \
			"$LVAR_IMG_FULL" \
			bash || exit 1
	if [ "$OPT_R_MKALL" = "true" ]; then
		echo "* Copy local modules to Docker Container..."
		#docker exec "$LCFG_CONTAINER_NAME" rm -r /esp/micropython/ports/esp32/modules
		#docker exec "$LCFG_CONTAINER_NAME" tar xf /esp/modules-org.tgz -C /esp/micropython/ports/esp32
		find "$LCFG_PATH_MODS" -type f -name ".DS_Store" -exec rm "{}" \;
		TMP_MYDIR_SED="$(echo -n "$VAR_MYDIR" | sed -e 's/\//\\\\\\\//g')"
		for TMP_FN in "$LCFG_PATH_MODS"/*; do
			TMP_BFN="$(basename "$TMP_FN")"
			[ \
					"$TMP_BFN" = "do_not_remove" -o \
					"$TMP_BFN" = ".DS_Store" -o \
					"$TMP_BFN" = ".gitignore" -o \
					"$TMP_BFN" = ".gitattributes" \
					] && continue
			TMP_REL_FN="$(echo -n "$TMP_FN" | sed -e 's/\//\\\//g')"
			TMP_REL_FN="$(echo -n "$TMP_REL_FN" | sed -e "s/^$TMP_MYDIR_SED/./")"
			TMP_REL_FN="$(echo -n "$TMP_REL_FN" | sed -e 's/\\//g')"
			echo "  - $TMP_REL_FN"
			docker cp \
					"$TMP_FN" \
					"$LCFG_CONTAINER_NAME:/esp/micropython/ports/esp32/modules/" || exit 1
		done
	fi

	echo "* Run '$LCFG_CONTAINER_NAME' $2..."
	if [ "$OPT_R_CLEAN" = "true" ]; then
		docker exec "$LCFG_CONTAINER_NAME" \
				$2 >/dev/null 2>&1
	else
		docker exec -it "$LCFG_CONTAINER_NAME" \
				$2
	fi
	docker stop "$LCFG_CONTAINER_NAME"
}

function _runMakeClean() {
	_runCont "" "make clean"
}

function _runMakeAll() {
	local TMP_VN=""
	local TMP_SDKCONFIG="$LVAR_MPY_SDKCONFIG"
	if [ "$OPT_MPY_FW_VERS" = "1.11" ]; then
		TMP_SDKCONFIG="boards/${TMP_SDKCONFIG}"
		TMP_VN="SDKCONFIG"
	else
		TMP_VN="BOARD"
	fi
	echo "* Using Board Definition '$TMP_SDKCONFIG'"
	_runCont "" "make ${TMP_VN}=${TMP_SDKCONFIG}"
}

function _runBash() {
	_runCont "root" "bash"
}

# Outputs the SDK/Board Config for the target ESP32 board
function _getSdkConfig() {
	if [ "$OPT_MPY_FW_VERS" = "1.11" ]; then
		if [ "$OPT_FWTYPE_SRAM" = "true" ]; then
			echo -n "sdkconfig.spiram"
		else
			echo -n "sdkconfig"
		fi
	else
		if [ "$OPT_FWTYPE_SRAM" = "true" ]; then
			echo -n "GENERIC_SPIRAM"
		else
			echo -n "GENERIC"
		fi
	fi
}

# Outputs the path to a mountpoint
#
# @param string $1 Path template
function _getMpPath() {
	local TMP_TYPESTR="def"
	[ "$OPT_FWTYPE_SRAM" = "true" ] && TMP_TYPESTR="spiram"
	echo -n "$1" | sed -e "s/#TYPE#/$TMP_TYPESTR/"
}

# Outputs the name of the subdirectory to the Docker Container's internal build directory for the specified target board
function _getInternalBuildTrgDir() {
	[ -z "$LVAR_MPY_SDKCONFIG" ] && {
		echo "LVAR_MPY_SDKCONFIG empty." >/dev/stderr
		return
	}
	if [ "$OPT_MPY_FW_VERS" = "1.11" ]; then
		echo -n "build"
	else
		echo -n "build-$LVAR_MPY_SDKCONFIG"
	fi
}

# Outputs the firmware filename
function _getFwOutpFn() {
	local TMP_TYPESTR="def"
	[ "$OPT_FWTYPE_SRAM" = "true" ] && TMP_TYPESTR="spiram"
	echo -n "$LCFG_MPY_FW_OUTP_FN_TEMPL" | sed -e "s/#TYPE#/$TMP_TYPESTR/"
}

function _removeFwFile() {
	[ -f "$LVAR_MPY_FW_OUTP_FN" ] && rm -i "$LVAR_MPY_FW_OUTP_FN"
}

# ----------------------------------------------------------

LVAR_MNTPOINT_MPBUILD="$(_getMpPath "$LCFG_MNTPOINT_MPBUILD_TEMPL")"
LVAR_MNTPOINT_MPSCR="$(_getMpPath "$LCFG_MNTPOINT_MPSCR_TEMPL")"
LVAR_MPY_SDKCONFIG="$(_getSdkConfig)"
LVAR_MPY_FW_OUTP_FN="$(_getFwOutpFn)"
LVAR_INTPATH_BUILDTRG="$(_getInternalBuildTrgDir)"

if [ -z "$LVAR_MNTPOINT_MPBUILD" -o "$LVAR_MNTPOINT_MPBUILD" = "." -o \
		"$LVAR_MNTPOINT_MPBUILD" = "./" -o "$LVAR_MNTPOINT_MPBUILD" = "/" ]; then
	echo "Invalid LVAR_MNTPOINT_MPBUILD. Aborting." >/dev/stderr
	exit 1
fi
if [ -z "$LVAR_MNTPOINT_MPSCR" -o "$LVAR_MNTPOINT_MPSCR" = "." -o \
		"$LVAR_MNTPOINT_MPSCR" = "./" -o "$LVAR_MNTPOINT_MPSCR" = "/" ]; then
	echo "Invalid LVAR_MNTPOINT_MPSCR. Aborting." >/dev/stderr
	exit 1
fi
if [ -z "$LVAR_INTPATH_BUILDTRG" -o "$LVAR_INTPATH_BUILDTRG" = "." -o \
		"$LVAR_INTPATH_BUILDTRG" = "./" -o "$LVAR_INTPATH_BUILDTRG" = "/" ]; then
	echo "Invalid LVAR_INTPATH_BUILDTRG. Aborting." >/dev/stderr
	exit 1
fi

if [ "$OPT_R_BASH" = "true" ]; then
	_runBash
	TMP_RES=$?
elif [ "$OPT_R_CLEAN" = "true" ]; then
	_removeFwFile
	#
	if [ "$OPT_MPY_FW_VERS" = "1.11" ]; then
		_runMakeClean
		TMP_RES=$?
	else
		echo "Removing '$LVAR_MNTPOINT_MPBUILD/*'..."
		rm -r "$LVAR_MNTPOINT_MPBUILD"/*
		TMP_RES=0
	fi
elif [ "$OPT_R_MKALL" = "true" ]; then
	_removeFwFile
	#
	_runMakeAll
	TMP_RES=$?
	#
	if [ $TMP_RES -eq 0 -a -f "$LVAR_MNTPOINT_MPBUILD/firmware.bin" ]; then
		echo "* Copying new firmware to '$LVAR_MPY_FW_OUTP_FN'..."
		cp "$LVAR_MNTPOINT_MPBUILD/firmware.bin" "$LVAR_MPY_FW_OUTP_FN"
	else
		echo "! Could not find new firmware binary" >/dev/stderr
	fi
else
	echo "$VAR_MYNAME: unknown command ?!" >/dev/stderr
	TMP_RES=1
fi

[ -f "$LCFG_PATH_MODS/do_not_remove" ] || touch "$LCFG_PATH_MODS/do_not_remove"
[ -f "$LVAR_MNTPOINT_MPBUILD/do_not_remove" ] || touch "$LVAR_MNTPOINT_MPBUILD/do_not_remove"
[ -f "$LVAR_MNTPOINT_MPSCR/do_not_remove" ] || touch "$LVAR_MNTPOINT_MPSCR/do_not_remove"

exit $TMP_RES
