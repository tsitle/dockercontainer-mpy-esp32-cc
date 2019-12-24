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

LCFG_IMAGE_NAME="mpy-esp32-cc-amd64"

LCFG_CONTAINER_NAME="mpy-esp32-cc-$(echo -n "$OPT_MPY_FW_VERS" | tr -d .)"

LCFG_MNTPOINT_BASE="${VAR_MYDIR}"
LCFG_MNTPOINT_MPBUILD_TEMPL="${LCFG_MNTPOINT_BASE}/${OPT_MPY_FW_VERS}/#TYPE#/mpbuild"
LCFG_MNTPOINT_MPSCR_TEMPL="${LCFG_MNTPOINT_BASE}/${OPT_MPY_FW_VERS}/#TYPE#/mpscripts"

LCFG_PATH_MODS="${VAR_MYDIR}/mods"

LCFG_MPY_SDKCONFIG_DEF="sdkconfig"
LCFG_MPY_SDKCONFIG_SRAM="sdkconfig.spiram"

LCFG_MPY_FW_OUTP_FN_TEMPL="${VAR_MYDIR}/mpy-firmware-${OPT_MPY_FW_VERS}-#TYPE#.bin"

# ----------------------------------------------------------

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
			-v "$LVAR_MNTPOINT_MPBUILD":/esp/micropython/ports/esp32/build \
			-v "$LVAR_MNTPOINT_MPSCR":/esp/micropython/ports/esp32/scripts \
			$TMP_USER \
			"$LCFG_IMAGE_NAME":"$OPT_MPY_FW_VERS" \
			bash || exit 1
	if [ "$OPT_R_MKALL" = "true" ]; then
		echo "* Copy local modules to Docker Container..."
		#docker exec "$LCFG_CONTAINER_NAME" rm -r /esp/micropython/ports/esp32/modules
		#docker exec "$LCFG_CONTAINER_NAME" tar xf /esp/modules-org.tgz -C /esp/micropython/ports/esp32
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
	echo "* Using Board Definition '$LVAR_MPY_SDKCONFIG'"
	_runCont "" "make SDKCONFIG=boards/${LVAR_MPY_SDKCONFIG}"
}

function _runBash() {
	_runCont "root" "bash"
}

# Outputs the path to a mountpoint
#
# @param string $1 Path template
function _getMpPath() {
	local TMP_TYPESTR="def"
	[ "$OPT_FWTYPE_SRAM" = "true" ] && TMP_TYPESTR="spiram"
	echo -n "$1" | sed -e "s/#TYPE#/$TMP_TYPESTR/"
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
LVAR_MPY_FW_OUTP_FN="$(_getFwOutpFn)"
if [ "$OPT_FWTYPE_SRAM" = "true" ]; then
	LVAR_MPY_SDKCONFIG="$LCFG_MPY_SDKCONFIG_SRAM"
else
	LVAR_MPY_SDKCONFIG="$LCFG_MPY_SDKCONFIG_DEF"
fi

if [ "$OPT_R_BASH" = "true" ]; then
	_runBash
	TMP_RES=$?
elif [ "$OPT_R_CLEAN" = "true" ]; then
	_removeFwFile
	#
	_runMakeClean
	TMP_RES=$?
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
