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
# Build of a Singularity container with the dependencies required to build LLVM.
#
# Usage: ./build-image.sh [build options...]
#
#  Any options specified as arguments are passed to singularity build.
#  Please see 'singularity build --help' for list of availalble options.
#
# Author: Thomas Nyman <thomas.nyman@aalto.fi>

# Reliable way to get full path to script
# http://stackoverflow.com/questions/4774054/
readonly SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null; pwd -P )

OUTDIR=${PWD}
pushd ${SCRIPTPATH}
singularity build "$@" "${OUTDIR}/llvm-toolchain-buildhost.sif" "${SCRIPTPATH}/defs/llvm-toolchain-buildhost.def"
popd

