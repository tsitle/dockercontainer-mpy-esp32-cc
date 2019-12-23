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

VAR_R_BASH=false
VAR_R_CLEAN=false
VAR_R_MKALL_DEF=false
VAR_R_MKALL_SRAM=false

function printUsageAndExit() {
	echo "Usage: $(basename "$0") bash|clean|mk-def|mk-spiram" >/dev/stderr
	exit 1
}

if [ $# -ne 1 ]; then
	printUsageAndExit
fi

if [ "$1" = "bash" ]; then
	VAR_R_BASH=true
elif [ "$1" = "clean" ]; then
	VAR_R_CLEAN=true
elif [ "$1" = "mk-def" ]; then
	VAR_R_MKALL_DEF=true
elif [ "$1" = "mk-spiram" ]; then
	VAR_R_MKALL_SRAM=true
else
	printUsageAndExit
fi

# ----------------------------------------------------------

LCFG_CONTAINER_NAME="mpy-esp32-cc"

LCFG_IMAGE_NAME="mpy-esp32-cc-amd64"
LCFG_IMAGE_VER="1.11"

LCFG_MNTPOINT_BASE="${VAR_MYDIR}"
LCFG_MNTPOINT_MPBUILD="${LCFG_MNTPOINT_BASE}/mpbuild"
LCFG_MNTPOINT_MPSCR="${LCFG_MNTPOINT_BASE}/mpscripts"
LCFG_MNTPOINT_MODS="${LCFG_MNTPOINT_BASE}/mods"

LCFG_MPY_SDKCONFIG_DEF="sdkconfig"
LCFG_MPY_SDKCONFIG_SRAM="sdkconfig.spiram"

LCFG_MPY_FW_OUTP_FN_TEMPL="mpy-firmware-#TYPE#.bin"

# ----------------------------------------------------------

LVAR_MPY_SDKCONFIG=""
LVAR_MPY_FW_OUTP_FN=""

# ----------------------------------------------------------

function _runCont() {
	local TMP_USER="$1"
	[ -n "$TMP_USER" ] && TMP_USER="-u $TMP_USER"

	echo "* Run '$LCFG_CONTAINER_NAME'..."
	docker run \
			--name "$LCFG_CONTAINER_NAME" \
			--rm \
			-it \
			-d \
			-v "$LCFG_MNTPOINT_MPBUILD":/esp/micropython/ports/esp32/build \
			-v "$LCFG_MNTPOINT_MPSCR":/esp/micropython/ports/esp32/scripts \
			$TMP_USER \
			"$LCFG_IMAGE_NAME":"$LCFG_IMAGE_VER" \
			bash || exit 1
	if [ "$VAR_R_MKALL_DEF" = "true" -o "$VAR_R_MKALL_SRAM" = "true" ]; then
		echo "* Copy local modules to Docker Container..."
		#docker exec "$LCFG_CONTAINER_NAME" rm -r /esp/micropython/ports/esp32/modules
		#docker exec "$LCFG_CONTAINER_NAME" tar xf /esp/modules-org.tgz -C /esp/micropython/ports/esp32
		for TMP_FN in "$LCFG_MNTPOINT_MODS"/*; do
			TMP_BFN="$(basename "$TMP_FN")"
			[ "$TMP_BFN" = "do_not_remove" ] && continue
			[ "$TMP_BFN" = ".DS_Store" ] && continue
			echo "  -$TMP_FN-"
			docker cp "$TMP_FN" "$LCFG_CONTAINER_NAME:/esp/micropython/ports/esp32/modules/" || exit 1
		done
	fi

	echo "* Run '$LCFG_CONTAINER_NAME' $2..."
	docker exec "$LCFG_CONTAINER_NAME" \
			$2
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

# ----------------------------------------------------------

LVAR_MPY_FW_OUTP_FN="$LCFG_MPY_FW_OUTP_FN_TEMPL"
if [ "$VAR_R_MKALL_SRAM" = "true" ]; then
	LVAR_MPY_SDKCONFIG="$LCFG_MPY_SDKCONFIG_SRAM"
	LVAR_MPY_FW_OUTP_FN="$(echo -n "$LVAR_MPY_FW_OUTP_FN" | sed -e "s/#TYPE#/spiram/")"
else
	LVAR_MPY_SDKCONFIG="$LCFG_MPY_SDKCONFIG_DEF"
	LVAR_MPY_FW_OUTP_FN="$(echo -n "$LVAR_MPY_FW_OUTP_FN" | sed -e "s/#TYPE#/def/")"
fi

if [ "$VAR_R_BASH" = "true" ]; then
	_runBash
	TMP_RES=$?
elif [ "$VAR_R_CLEAN" = "true" ]; then
	_runMakeClean
	TMP_RES=$?
elif [ "$VAR_R_MKALL_DEF" = "true" -o "$VAR_R_MKALL_SRAM" = "true" ]; then
	[ -f "$LVAR_MPY_FW_OUTP_FN" ] && rm "$LVAR_MPY_FW_OUTP_FN"
	_runMakeAll
	TMP_RES=$?
	if [ $TMP_RES -eq 0 -a -f mpbuild/firmware.bin ]; then
		echo "* Copy new firmware to '$LVAR_MPY_FW_OUTP_FN'..."
		cp mpbuild/firmware.bin "$LVAR_MPY_FW_OUTP_FN"
	fi
else
	echo "$VAR_MYNAME: unknown command ?!" >/dev/stderr
	TMP_RES=1
fi

exit $TMP_RES
