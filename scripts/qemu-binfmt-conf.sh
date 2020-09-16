#!/bin/sh
#
# Copyright (c) 2016-2018 Laurent Vivier <laurent@vivier.eu>
# Copyright (c) 2020 Aalto University Secure Systems Group                          
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with dogtag.  If not, see <http://www.gnu.org/licenses/>.
#
# This file was originally part of QEMU (https://github.com/qemu/qemu/)
#
# Modified for buildhelper by Thomas Nyman <thomas.nyman@aalto.fi>
#
# Register qemu-user-static as interpreter for non-native binaries with
# binfmt_misc.
#
qemu_target_list="aarch64 aarch64_be"

aarch64_magic='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00'
aarch64_mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'
aarch64_family=arm

aarch64_be_magic='\x7fELF\x02\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7'
aarch64_be_mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff'
aarch64_be_family=armeb

qemu_get_family() {
    cpu=${HOST_ARCH:-$(uname -m)}
    case "$cpu" in
    amd64|i386|i486|i586|i686|i86pc|BePC|x86_64)
        echo "i386"
        ;;
    mips*)
        echo "mips"
        ;;
    "Power Macintosh"|ppc64|powerpc|ppc)
        echo "ppc"
        ;;
    ppc64el|ppc64le)
        echo "ppcle"
        ;;
    arm|armel|armhf|arm64|armv[4-9]*l|aarch64)
        echo "arm"
        ;;
    armeb|armv[4-9]*b|aarch64_be)
        echo "armeb"
        ;;
    sparc*)
        echo "sparc"
        ;;
    riscv*)
        echo "riscv"
        ;;
    *)
        echo "$cpu"
        ;;
    esac
}

usage() {
    cat <<EOF
Usage: qemu-binfmt-conf.sh [--qemu-path PATH][--debian][--systemd CPU]
                           [--help][--credential yes|no][--exportdir PATH]
                           [--persistent yes|no][--qemu-suffix SUFFIX]

       Configure binfmt_misc to use qemu interpreter

       --help:        display this usage
       --qemu-path:   set path to qemu interpreter ($QEMU_PATH)
       --qemu-suffix: add a suffix to the default interpreter name
       --debian:      don't write into /proc,
                      instead generate update-binfmts templates
       --systemd:     don't write into /proc,
                      instead generate file for systemd-binfmt.service
                      for the given CPU. If CPU is "ALL", generate a
                      file for all known cpus
       --exportdir:   define where to write configuration files
                      (default: $SYSTEMDDIR or $DEBIANDIR)
       --credential:  if yes, credential and security tokens are
                      calculated according to the binary to interpret
       --persistent:  if yes, the interpreter is loaded when binfmt is
                      configured and remains in memory. All future uses
                      are cloned from the open file.

    To import templates with update-binfmts, use :

        sudo update-binfmts --importdir ${EXPORTDIR:-$DEBIANDIR} --import qemu-CPU

    To remove interpreter, use :

        sudo update-binfmts --package qemu-CPU --remove qemu-CPU $QEMU_PATH

    With systemd, binfmt files are loaded by systemd-binfmt.service

    The environment variable HOST_ARCH allows to override 'uname' to generate
    configuration files for a different architecture than the current one.

    where CPU is one of:

        $qemu_target_list

EOF
}

qemu_check_access() {
    if [ ! -w "$1" ] ; then
        echo "ERROR: cannot write to $1" 1>&2
        exit 1
    fi
}

qemu_check_bintfmt_misc() {
    # load the binfmt_misc module
    if [ ! -d /proc/sys/fs/binfmt_misc ]; then
      if ! /sbin/modprobe binfmt_misc ; then
          exit 1
      fi
    fi
    if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
      if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
          exit 1
      fi
    fi

    qemu_check_access /proc/sys/fs/binfmt_misc/register
}

installed_dpkg() {
    dpkg --status "$1" > /dev/null 2>&1
}

qemu_check_debian() {
    if [ ! -e /etc/debian_version ] ; then
        echo "WARNING: your system is not a Debian based distro" 1>&2
    elif ! installed_dpkg binfmt-support ; then
        echo "WARNING: package binfmt-support is needed" 1>&2
    fi
    qemu_check_access "$EXPORTDIR"
}

qemu_check_systemd() {
    if ! systemctl -q is-enabled systemd-binfmt.service ; then
        echo "WARNING: systemd-binfmt.service is missing or disabled" 1>&2
    fi
    qemu_check_access "$EXPORTDIR"
}

qemu_generate_register() {
    flags=""
    if [ "$CREDENTIAL" = "yes" ] ; then
        flags="OC"
    fi
    if [ "$PERSISTENT" = "yes" ] ; then
        flags="${flags}F"
    fi

    echo ":qemu-$cpu:M::$magic:$mask:$qemu:$flags"
}

qemu_register_interpreter() {
    echo "Setting $qemu as binfmt interpreter for $cpu"
    qemu_generate_register > /proc/sys/fs/binfmt_misc/register
}

qemu_generate_systemd() {
    echo "Setting $qemu as binfmt interpreter for $cpu for systemd-binfmt.service"
    qemu_generate_register > "$EXPORTDIR/qemu-$cpu.conf"
}

qemu_generate_debian() {
    cat > "$EXPORTDIR/qemu-$cpu" <<EOF
package qemu-$cpu
interpreter $qemu
magic $magic
mask $mask
credential $CREDENTIAL
EOF
}

qemu_set_binfmts() {
    # probe cpu type
    host_family=$(qemu_get_family)

    # register the interpreter for each cpu except for the native one

    for cpu in ${qemu_target_list} ; do
        magic=$(eval echo \$${cpu}_magic)
        mask=$(eval echo \$${cpu}_mask)
        family=$(eval echo \$${cpu}_family)

        if [ "$magic" = "" ] || [ "$mask" = "" ] || [ "$family" = "" ] ; then
            echo "INTERNAL ERROR: unknown cpu $cpu" 1>&2
            continue
        fi

        qemu="$QEMU_PATH/qemu-$cpu"
        if [ "$cpu" = "i486" ] ; then
            qemu="$QEMU_PATH/qemu-i386"
        fi

        qemu="$qemu$QEMU_SUFFIX"
        if [ "$host_family" != "$family" ] ; then
            $BINFMT_SET
        fi
    done
}

CHECK=qemu_check_bintfmt_misc
BINFMT_SET=qemu_register_interpreter

SYSTEMDDIR="/etc/binfmt.d"
DEBIANDIR="/usr/share/binfmts"

QEMU_PATH=/usr/bin
CREDENTIAL=no
PERSISTENT=no
QEMU_SUFFIX="-static"

options=$(getopt -o ds:Q:S:e:hc:p: -l debian,systemd:,qemu-path:,qemu-suffix:,exportdir:,help,credential:,persistent: -- "$@")
eval set -- "$options"

while true ; do
    case "$1" in
    -d|--debian)
        CHECK=qemu_check_debian
        BINFMT_SET=qemu_generate_debian
        EXPORTDIR=${EXPORTDIR:-$DEBIANDIR}
        ;;
    -s|--systemd)
        CHECK=qemu_check_systemd
        BINFMT_SET=qemu_generate_systemd
        EXPORTDIR=${EXPORTDIR:-$SYSTEMDDIR}
        shift
        # check given cpu is in the supported CPU list
        if [ "$1" != "ALL" ] ; then
            for cpu in ${qemu_target_list} ; do
                if [ "$cpu" = "$1" ] ; then
                    break
                fi
            done

            if [ "$cpu" = "$1" ] ; then
                qemu_target_list="$1"
            else
                echo "ERROR: unknown CPU \"$1\"" 1>&2
                usage
                exit 1
            fi
        fi
        ;;
    -Q|--qemu-path)
        shift
        QEMU_PATH="$1"
        ;;
    -F|--qemu-suffix)
        shift
        QEMU_SUFFIX="$1"
        ;;
    -e|--exportdir)
        shift
        EXPORTDIR="$1"
        ;;
    -h|--help)
        usage
        exit 1
        ;;
    -c|--credential)
        shift
        CREDENTIAL="$1"
        ;;
    -p|--persistent)
        shift
        PERSISTENT="$1"
        ;;
    *)
        break
        ;;
    esac
    shift
done

$CHECK
qemu_set_binfmts
