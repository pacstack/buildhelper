#!/usr/bin/env bash
# 
# Copyright 2020 Aalto University Secure Systems Group
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Build LLVM toolchain.
#
# Usage: ./build.sh MANIFEST|URL
# 
# where MANIFEST is a manifest file with component data and build steps
# understood SCRIPTDIR/build-from-manifest. If the MANIFEST is not found in the
# directory that is specified by the MANIFESTDIR environment variable a copy of
# the MANIFEST is created in MANIFESTDIR.
#
# If a URL to the manifest is specified, the manifest will be downloaded to the
# directory specifed by the MANIFESTDIR environment variable.
#
# The primary purpose of this script is to perform repeat builds of LLVM
# toolchains in a reproducible environment. The build itself is performed in a
# Singularity container. 
#
# build.sh respects the following environment variables:
#
# SCRIPTDIR    Pathname to directory containing the scripts required to be
#              available inside the container during the build. It will be
#              bind-mounted to /scripts in the container.  
#              Defaults to $SCRIPTPATH/scripts. 
#
# MANIFESTDIR  Pathname to directory containing the MANIFEST file. It will be
#              bind-mounted to /manifests in the container.
#              Defaults to $SCRIPTPATH/manifests.
#
# SNAPSHOTDIR  Pathname to directory containing source tarballs and/or git
#              reference repositories on the local machine. It will be
#              bind-mounted to /snapshots in the container.
#              Defaults to $PWD/snapshots.
# 
# WORKSPACE    Pathname to directory to be used as the workspace inside the
#              container during the build. It will be bind-mounted to /workspace
#              inside the the container. If unset, build.sh will create a new
#              directory named after the target architecture and release in the
#              specified manifest. 
#
# TMPDIR       Pathname to directory which will be used for /tmp, /var/tmp and
#              $HOME inside the container. If unset, build.sh will create a new
#              temporary directory in the host /tmp which will automatically be
#              cleaned up after the build is finished. Specifying an alternate
#              directory by setting this environment variable will cause any
#              auxiliary files to be left in the specified directory.
#
# SIFPATH      Pathname to Singularity image to be used for build.
#              Defaults to $PWD/linaro-toolchain-buildhost.sif.
#
# Author: Thomas Nyman <thomas.nyman@aalto.fi> 
#
set -e

# Reliable way to get full path to script
# http://stackoverflow.com/questions/4774054/
readonly SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null; pwd -P )

readonly SCRIPTDIR=${SCRIPTDIR:-"${SCRIPTPATH}/scripts"}
readonly MANIFESTDIR=${MANIFESTDIR:-"${PWD}/manifests"}
readonly SNAPSHOTDIR=${SNAPSHOTDIR:-"${PWD}/snapshots"}
readonly SIFPATH=${SIFPATH:-"${PWD}/llvm-toolchain-buildhost.sif"}

#######################################
# Main function.
# Globals:
#   MANIFESTDIR
#   SCRIPTPATH
#   SCRIPTDIR
#   SNAPSHOTDIR
#   SIFPATH
#   WORKSPACE
# Arguments:
#   -i, --interactive      - Prompt before overwriting existing MANIFEST    
#   -r, --release RELEASE  - Override release specified in MANIFEST
#   -s, --shell            - Run a shell within buildhost container
#   manifest               - Manifest file pathname
# Returns:
#   0 (true) if packages are build successfully.
#   1 (false) and exits if errors are encountered while building components.
#######################################
main() {
  local positional=()
  local interactive=""
  local release=""
  local triton=0
  local shell=0
  while [[ $# -gt 0 ]]
  do
    arg="$1"

    case ${arg} in
      -i|--interactive)
        interactive="${arg}"
        shift # past argument
        ;;
      -r|--release)
        release="${2}"
        shift # past value
        shift # past argument
        ;;
      -s|--shell)
        shell=1
        shift # past argument
        ;;
      -t|--triton)
        triton=1
        shift # past argument
        ;;
      *)    # unknown option
        positional+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
  done
  set -- "${positional[@]}" # restore positional parameters

  # Ensure manifest exists in MANIFESTDIR
  if [[ "${1}" = http?(s)://* ]]; then
    local url="${1%%\?*}"
    local manifest="${url##*/}"
    curl "${url}" -o "${MANIFESTDIR}/${manifest}"
  else
    local manifest="${1##*/}"
    if [[ "$(readlink -e "${1}")" != "${MANIFESTDIR}/${1##*/}" ]]; then
      cp "${interactive}" "${1}" "${MANIFESTDIR}/${manifest}"
    fi
  fi
  
  release=${release:-"$(grep -oP -m1 '(?<=release=).+' "${MANIFESTDIR}/${manifest}")"}
  
  WORKSPACE=${WORKSPACE:-"${PWD}/${release}"}
  
  mkdir -p "${WORKSPACE}"
  mkdir -p "${SNAPSHOTDIR}"
  
  if [[ -z ${TMPDIR} ]]; then
    TMPDIR="$(mktemp -d)"
    
    cleanup() {
      if [[ -d "${TMPDIR}" ]]; then
        rm -r "${TMPDIR}"
      fi
    }
  
    trap cleanup EXIT
  elif [[ ! -d "${TMPDIR}" ]]; then
    mkdir -p "${TMPDIR}"
  fi
  
  if [[ "${shell}" -ne 0 ]]; then
    singularity shell \
      --containall \
      --workdir "${TMPDIR}" \
      --bind "${SCRIPTDIR}":/scripts \
      --bind "${MANIFESTDIR}":/manifests \
      --bind "${WORKSPACE}":/workspace \
      --bind "${SNAPSHOTDIR}":/snapshots \
      "${SIFPATH}"
  elif [[ "${triton}" -ne 0 ]]; then
    srun --export ALL \
      singularity exec \
      --containall \
      --workdir "${TMPDIR}" \
      --bind "${SCRIPTDIR}":/scripts \
      --bind "${MANIFESTDIR}":/manifests \
      --bind "${SNAPSHOTDIR}":/snapshots \
      --bind "${WORKSPACE}":/workspace \
      "${SIFPATH}" \
      /bin/bash /scripts/build-from-manifest.sh "/manifests/${manifest}" \
      --release "${release}" \
      --workspace /workspace \
      --with-git-reference-dir /snapshots;
  else
    singularity exec \
      --containall \
      --workdir "${TMPDIR}" \
      --bind "${SCRIPTDIR}":/scripts \
      --bind "${MANIFESTDIR}":/manifests \
      --bind "${WORKSPACE}":/workspace \
      --bind "${SNAPSHOTDIR}":/snapshots \
      "${SIFPATH}" \
      /bin/bash /scripts/build-from-manifest.sh "/manifests/${manifest}" \
      --release "${release}" \
      --workspace /workspace \
      --with-git-reference-dir /snapshots;
  fi
}

main "$@"

