#!/bin/bash
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
# Author: Thomas Nyman <thomas.nyman@aalto.fi> 
#
set -e

# Global variables

#######################################
# Whether or not perform a dry-run instead of actual build.
#######################################
DRY_RUN=0

#######################################
# Array variable containing errors reported during execution. 
#######################################
ERRORS=()

#######################################
# The log level used to determine which messages are displayed during execution.
#
# The following log levels are recognized:
# FATAL   0  - Unsuppressable errors only
# ERROR   1  - Log errors 
# WARNING 2  - Log warnings (the default)
# NOTICE  3  - Log notices
# DEBUG   4  - Log debug messages
# TRACE   5  - Log trace information
#
#######################################
VERBOSE=2

# Utility Functions

#######################################
# Log fatal error and immediately exit.
# Globals:
#   None
# Arguments:
#   Description of error (as variable number of string arguments).
# Outputs:
#   Writes the script name, a colon, a space, and the error message specified as
#   arguments to stderr. The output is terminated by a newline character.
#
#   The script then immediately exits with non-zero status.
#######################################
fatal() {
  printf >&2 '%b\n' "$(basename "${0}"): ${*:1}"
  exit 1
}

####################################### 
# Log that an error has occurred.
# Globals:
#   ERRORS
#   VERBOSE
# Arguments:
#   Description of error (as variable number of string arguments).
# Outputs:
#   Writes the script name, a colon, a space, and the error message specified as
#   arguments to stderr. The output is terminated by a newline character.
#
#   If the value of VERBOSE is < 1, the output to stderr is suppressed.
#
#   ERRORS is updated by concatenating the error message specified as arguments
#   to a space-separated string and appending it to the ERRORS array variable.
#    
#   If the value of VERBOSE is >= 4, the error message appended to ERRORS will
#   be followed by the function name and line number at which the error occured.
#######################################
error() {
  if [ "${VERBOSE}" -ge 1 ]; then
    printf >&2 '%b\n' "$(basename "${0}"): ${*:1}"
  fi
  
  if [ "${VERBOSE}" -ge 4 ]; then
    ERRORS+=("${@:1} at ${FUNCNAME[1]}:${BASH_LINENO[1]}")
  else
    ERRORS+=("${@:1}")
    fi
}

#######################################
# Assert whether errors have been reported.
# Globals:
#   ERRORS
# Arguments:
#   None
# Returns:
#   0 (true) if ERRORS contains recorded error messages.
#   1 (false) if ERRORS is empty.
#######################################
errors_reported() {
  [ ! ${#ERRORS[@]} -eq 0 ]
}

#######################################
# Print reported errors.
# Globals:
#   ERRORS
# Arguments:
#   None
# Outputs:
#   Writes the list of errors messages in ERRORS to stderr, one message per line.
#######################################
print_reported_errors() {
  printf >&2 '%b\n' "$(basename "${0}"): ${FUNCNAME[1]} reported the following error(s):"
  local err
  for err in "${ERRORS[@]}"; do
    echo "${err}" 1>&2
  done
}

#######################################
# Log warning message. 
# Globals:
#   VERBOSE
# Arguments:
#   Description of logged event (as variable number of string arguments).
# Outputs:
#   Writes the string "WARNING:", a space, and the warning message specified as
#   arguments to stderr. The output is terminated by a newline character.
#
#   If the value of VERBOSE is < 2, the output to stderr is suppressed.
#######################################
warning() {
  if [ "${VERBOSE}" -ge 0 ]; then
    echo "WARNING: ${*:1}" 1>&2
  fi
}

#######################################
# Log informational message. 
# Globals:
#   VERBOSE
# Arguments:
#   Description of logged event (as variable number of string arguments).
# Outputs:
#   Writes the string "NOTE:", a space, and the informational message specified
#   as arguments to stderr. The output is terminated by a newline character.
#   
#   If the value of VERBOSE is < 3, the output to stderr is suppressed.
#######################################
notice() {
  if [ "${VERBOSE}" -ge 3 ]; then
    echo "NOTE: ${*:1}" 1>&2
  fi
}

#######################################
# Run arguments as shell command. 
# Globals:
#   DRY_RUN
#   VERBOSE
# Arguments:
#   Command and arguments to be executed.
# Return:
#   The exit status of the executed command.
#
#   If DRYRUN is non-zero, the exit status is always zero (success).
# Outputs:
#   Writes the string "RUN:", and the executed command and arguments to stderr.
#   The output is terminated by a newline character.
#   
#   If the value of DRY_RUN is non-zero, the command is not executed, but the
#   command and arguments are still output to stderr. In this case, the output
#   is prepended with "DRY RUN:". 
#   
#   If the value of VERBOSE is >= 5, the output is prepended with the function
#   name and line number at which the command is invoked.
#######################################
run() { 
  if [ "${VERBOSE}" -ge 5 ]; then
    echo -n "${FUNCNAME[1]}:${BASH_LINENO{1}}: " 1>&2
  fi
  
  if [ "${DRY_RUN}" -gt 0 ]; then
    echo "DRY RUN: ${*}" 1>&2
  else
    echo "RUN: ${*}" 1>&2
    (
      set -o pipefail
      "$@"
    )
    local result=$?
    if [ ${result} -gt 0 ]; then
      warning "Previous command failed"
    fi
    return ${result}
  fi

  return 0
}

#######################################
# Read space-separated values into an array variable.
# Globals:
#   Defines an array variable into global scobe which contains as elements each
#   space-separated value contained in the strings passed as arguments.
# Arguments:
#   Name of destination array
#   Array elements (as variable number of space-separated strings)
#######################################
array_from_ssv() {
  declare -ga "${1}"
  readarray -td' ' "${1}" <<< "${*:2}"
}

#######################################
# Read package names from array of component names.
# Globals:
#   Defines an array variable called PACKAGES into global scobe which contains
#   as elements the 'package' portion of each component name (with any component
#   stages removed).
# Arguments:
#   Array of component names
#######################################
read_packages() {
  declare -ga PACKAGES
  args=("${@}")
  
  for ((i=0;i<${#args[@]};i++)); do
    PACKAGES[$i]=${args[$i]%_stage*};
  done
}

#######################################
# Assert whether SHA256 digest for file matches given digest.  
# Globals:
#   None
# Arguments:
#   SHA256 digest
#   Pathname of file to be checked.
# Returns:
#   0 (true) if the digest matches.
#   1 (false) if the digest does not match or check failed for another reason.
#######################################
check_sha256() {
  local sha256="${1}"
  local file="${2}"
  
  if [[ ! -e "${file}" ]]; then 
    error "${file}: No such file of directory"
  fi
  
  echo -e "${sha256}\t${file}" | sha256sum --status --check --
  local sha256sum_ret=$?
  
  return ${sha256sum_ret}
}

# Accessors for manifest data

#######################################
# Get a package's url.
# Globals:
#   <package>_url (sourced from manifest)
# Arguments:
#   Package name
# Outputs:
#   Writes value of the package's url to stdout.
#   If the package's url is unset or empty to output is produced.
# Returns:
#   0 (true) if the packages's url is defined and non-empty.
#   1 (false) if the package's url is unset or empty.
#######################################
get_url() {
  local url_variable="${1}_url"
  local url="${!url_variable}"
  
  if [ -z "${url}" ]; then 
    warning "${url_variable} unset or empty"
    return 1
  else
    echo "${url}"
    return 0
  fi
}

#######################################
# Get a package's filespec.
# Globals:
#   <package>_filespec (sourced from manifest)
# Arguments:
#   Package name
# Outputs:
#   Writes value of the package's filespec to stdout.
#   If the package's filespec is unset or empty no output is produced.
# Returns:
#   0 (true) if the packages's filespec is defined and non-empty.
#   1 (false) if the package's filespec is unset or empty.
#######################################
get_filespec() {
  local filespec_variable="${1}_filespec"
  local filespec="${!filespec_variable}"
  
  if [ -z "${filespec}" ]; then 
    warning "${filespec_variable} unset or empty"
    return 1
  else
    echo "${filespec}"
    return 0
  fi
}

#######################################
# Get a package's version control branch.
# Globals:
#   <package>_branch (sourced from manifest)
# Arguments:
#   Package name
# Outputs:
#   Writes value of the package's branch to stdout.
#   If the package's branch is unset or empty no output is produced.
# Returns:
#   0 (true) if the packages's branch is defined and non-empty.
#   1 (false) if the package's branch is unset or empty.
#######################################
get_branch() {
  local branch_variable="${1}_branch"
  local branch="${!branch_variable}"
  
  if [ -z "${branch}" ]; then 
    warning "${branch_variable} unset or empty"
    return 1
  else
    echo "${branch}"
    return 0
  fi
}

#######################################
# Get a package's version control revision.
# Globals:
#   <package>_revision (sourced from manifest)
# Arguments:
#   Package name
# Outputs:
#   Writes value of the package's revision to stdout.
#   If the package's revision is unset or empty no output is produced.
# Returns:
#   0 (true) if the packages's revision is defined and non-empty.
#   1 (false) if the package's revision is unset or empty.
#######################################
get_revision() {
  local revision_variable="${1}_revision"
  local revision="${!revision_variable}"
  
  if [ -z "${revision}" ]; then 
    warning "${revision_variable} unset or empty"
    return 1
  else
    echo "${revision}"
    return 0
  fi
}

#######################################
# Get a package's sha256 sum.
# Globals:
#   <package>_sha256 (sourced from manifest)
# Arguments:
#   Package name
# Outputs:
#   Writes value of the package's sha256 sum to stdout.
#   If the package's sha256 sum is unset or empty no output is produced.
# Returns:
#   0 (true) if the packages's sha256 sum is defined and non-empty.
#   1 (false) if the package's sha256 sum is unset or empty.
#######################################
get_sha256() {
  local sha256_variable="${1}_sha256"
  local sha256="${!sha256_variable}"
  
  if [ -z "${sha256}" ]; then 
    warning "${sha256_variable} unset or empty"
    return 1
  else
    echo "${sha256}"
    return 0
  fi
}

#######################################
# Get a component's source directory path.
# Globals:
#   None
# Arguments:
#   Component name
# Outputs:
#   Writes the component's source directory path to stdout.
#   If the component's filespec is unset or empty no output is produced.
#
#   If the component has been checked out via Git the source directory will 
#   have the version control branch and/or revision appended to it's name.
#
# Returns:
#   0 (true) on success.
#   1 (false) if the components's source directory cannot be determined.
#######################################
get_srcdir() {
  local component="${1}"
  local filespec
  if ! filespec=$(get_filespec "${component}"); then
    return $?
  else
    if is_tar "${1}"; then
      echo "${workspace_snapshots}/${filespec%.tar.*}"
      return 0
    else
      local branch revision suffix
      if branch=$(get_branch "${component}"); then
        # Git branch names may contain a slash (/) for hierarchical grouping.
        # Since we are using the the branch name as part of the srcdir name, we
        # replace any slashes with dashes when determining the suffix here.
        suffix="${suffix}~${branch////-}"
      fi
      if revision=$(get_revision "${component}"); then
        suffix="${suffix}_rev_${revision}"
      fi
      echo "${workspace_snapshots}/${filespec%.*}${suffix}"
      return 0
    fi
  fi
}

#######################################
# Get a component's build directory path.
# Globals:
#   None
# Arguments:
#   Component name
# Outputs:
#   Writes component's build directory path to stdout.
#   If the component's source directory cannot be determined no output is produced.
#
# Returns:
#   0 (true) on success.
#   1 (false) if the components's source directory cannot be determined.
#######################################
get_builddir() {
  local component="${1}"
  local srcdir
  
  if ! srcdir=$(get_srcdir "${component}"); then
    return $?
  else
    echo "${workspace_builds}/${srcdir##*/}"
    return 0
  fi
}

#######################################
# Get a package's destination directory.
# Globals:
#   <package>_destdir (sourced from manifest)
# Arguments:
#   Package name
# Outputs:
#   Writes value of the package's destination directory to stdout.
#   If the package's destination directory is unset or empty no output is produced.
# Returns:
#   0 (true) if the packages's destication directory is defined and non-empty.
#   1 (false) if the package's directory is unset or empty.
#######################################
get_destdir() {
  local destdir_variable="${1}_destdir"
  local destdir="${!destdir_variable}"
  
  if [ -z "${destdir}" ]; then 
    warning "${destdir_variable} unset or empty"
    return 1
  else
    echo "${destdir}"
    return 0
  fi
}

#######################################
# Get a components's CMake directory (directory containing CMakeLists.txt).
# Globals:
#   <component>_cmakedir (sourced from manifest)
# Arguments:
#   Package name
#   Component stage
# Outputs:
#   Writes value of the package's destination directory to stdout.
#   If the package's destination directory is unset or empty no output is produced.
# Returns:
#   0 (true) if the packages's destination directory is defined and non-empty.
#   1 (false) if the package's directory is unset or empty.
#######################################
get_cmakedir() {
  local package="${1}"
  local stage="${2}"
  
  local cmakedir_variable cmakedir
  
  if [ -n "${stage}" ]; then
    cmakedir_variable="${package}_${stage}_cmakedir"
  else
    cmakedir_variable="${package}_cmakedir"
  fi
  
  until [ -n "${cmakedir}" ]; do
    cmakedir="${!cmakedir_variable}"
    
    if [ "${cmakedir_variable}" != "${package}_cmakedir" ]; then
      cmakedir_variable="${package}_cmakedir"
    else
      break
    fi
  done

  if [ -z "${cmakedir}" ]; then 
    warning "${cmakedir_variable} unset or empty"
    return 1
  else
    echo "${cmakedir}"
    return 0
  fi
}

#######################################
# Get a components's CMake flags.
# Globals:
#   <component>_cmakeflags (sourced from manifest)
# Arguments:
#   Component name
# Outputs:
#   Writes the component's CMake flags to stdout.
#   If the component's CMake flags are unset or empty no output is produced.
# Returns:
#   0 (true) if the component's CMake flags is defined and non-empty.
#   1 (false) if the component's CMake flags is unset or empty.
#######################################
get_cmakeflags() {
  local package="${1}"
  local stage="${2}"
  
  local cmakeflags_variable
  if [ -z "${stage}" ]; then
    cmakeflags_variable="${package}_cmakeflags"
  else
    cmakeflags_variable="${package}_${stage}_cmakeflags"
  fi
  
  local cmakeflags="${!cmakeflags_variable}"
  
  if [ -z "${cmakeflags}" ]; then 
    warning "${cmakeflags_variable} unset or empty"
    return 1
  else
    echo "${cmakeflags}"
    return 0
  fi
}

#######################################
# Get a components's configure flags.
# Globals:
#   <component>_configure (sourced from manifest)
# Arguments:
#   Component name
# Outputs:
#   Writes the component's configure flags to stdout.
#   If the component's configure flags are unset or empty no output is produced.
# Returns:
#   0 (true) if the component's configure flags is defined and non-empty.
#   1 (false) if the component's configure flags is unset or empty.
#######################################
get_configure() {
  local package="${1}"
  local stage="${2}"
  
  local configure_variable
  if [ -z "${stage}" ]; then
    configure_variable="${package}_configure"
  else
    configure_variable="${package}_${stage}_configure"
  fi
  
  local configure="${!configure_variable}"
  
  if [ -z "${configure}" ]; then 
    warning "${configure_variable} unset or empty"
    return 1
  else
    echo "${configure}"
    return 0
  fi
}

#######################################
# Get a components's make flags.
# Globals:
#   <component>_makeflags (sourced from manifest)
# Arguments:
#   Component name
# Outputs:
#   Writes the component's make flags to stdout.
#   If the component's make flags are unset or empty no output is produced.
# Returns:
#   0 (true) if the component's make flags is defined and non-empty.
#   1 (false) if the component's make flags is unset or empty.
#######################################
get_makeflags() {
  local package="${1}"
  local stage="${2}"
  
  local makeflags_variable
  if [ -z "${stage}" ]; then
    makeflags_variable="${package}_makeflags"
  else
    makeflags_variable="${package}_${stage}_makeflags"
  fi
  
  local makeflags="${!makeflags_variable}"
  
  if [ -z "${makeflags}" ]; then 
    warning "${makeflags_variable} unset or empty"
    return 1
  else
    echo "${makeflags}"
    return 0
  fi
}

#######################################
# Assert whether a package's filespec is a tarball. 
# Globals:
#   None
# Arguments:
#   Package name
# Returns:
#   0 (true) if the package is a tarball.
#   1 (false) if the package is not a tarball.
#######################################
is_tar() {
  [[ "$(get_filespec "${1}")" = *.tar.* ]]
}

#######################################
# Assert whether a component uses CMake for building. 
# Globals:
#   None
# Arguments:
#   Package name
#   Component stage
# Returns:
#   0 (true) if the component uses CMake.
#   1 (false) if the package doesn't use CMake.
#######################################
uses_cmake() {
  [[ "$(get_cmakeflags "${1}" "${2}")" ]]
}

#######################################
# Assert whether a component uses a configure script. 
# Globals:
#   None
# Arguments:
#   Package name
#   Component stage
# Returns:
#   0 (true) if the component uses configure.
#   1 (false) if the package doesn't use configure.
#######################################
uses_configure() {
  [[ "$(get_configure "${1}" "${2}")" ]]
}

# Build logic

#######################################
# Fetch a package's tarball.
# Globals:
#   None
# Arguments:
#   Package name
# Returns:
#   0 (true) if the tarball is fetched succsfully.
#   1 (false) if the fetching the tarball failed.
#######################################
tar_fetch() {
  local package="${1}"
  
  if [ -z "${package}" ]; then
    warning "No package to fetch!"
    return 1
  fi

  local filespec url sha256
  filespec=$(get_filespec "${package}")
  url=$(get_url "${package}")
  sha256=$(get_sha256 "${package}")
  
  if [ -e "${workspace_snapshots}/${filespec}" ]; then
    notice "${filespec} already exists in ${workspace_snapshots}"
  # If a GIT_REFERENCE_DIR i specified fetch the file from there if it exists.
  elif [ -n "${GIT_REFERENCE_DIR}" ] && [ -e "${GIT_REFERENCE_DIR}/${filespec}" ]; then
    notice "Copying ${filespec} from ${GIT_REFERENCE_DIR} to ${workspace_snapshots}"
    run cp "${GIT_REFERENCE_DIR}/${filespec}" "${workspace_snapshots}/${filespec}"
    
    if [ $? -gt 0 ]; then
      error "Failed to copy ${filespec} from ${GIT_REFERENCE_DIR} to ${workspace_snapshots}"
      return 1
    fi
  # Fetch the file from remote server when a local copy cannot be found
  else
    notice "Downloading ${filespec} from ${url}/${filespec} to ${workspace_snapshots}"
    run wget --timeout=10 --tries=2 --directory-prefix="${workspace_snapshots}/" \
      -O "${workspace_snapshots}/${filespec}"  "${url}/${filespec}"
    
    if [ $? -gt 0 ]; then
      error "Failed to download ${filespec} from ${url}/${filespec} to ${workspace_snapshots}"
      return 1
    fi
  fi
  
  if [ -n "${sha256}" ]; then
    run check_sha256 "${sha256}" "${workspace_snapshots}/${filespec}"
    
    if [ $? -gt 0 ]; then
      error "Digest for ${filespec} does not match digest in manifest!"
      return 1
    fi
  else
    warning "No digest specified for ${filespec}, skipping integrity check" 
  fi
  
  # Whew!
  return 0
}

#######################################
# Extract a package's tarball.  
# Globals:
#   None
# Arguments:
#   package - Package name
# Returns:
#   0 (true) if the tarball is extracted successfully.
#   1 (false) if extracting the tarball failed.
#######################################
tar_extract() {
  local package="${1}"
  
  if [ -z "${package}" ]; then
    warning "No package to extract!"
    return 1
  fi
  
  local filespec srcdir
  filespec=$(get_filespec "${package}")
  
  # Prebuilt packages should have a destdir defined. If not, we assume the
  # package has source code which is extracted to a corresponding srcdir.
  if ! destdir="$(get_destdir "${package}")"; then
    destdir="$(get_srcdir "${package}")"
  fi
  
  local tarball="${workspace_snapshots}/${filespec}"

  # Figure out how to decompress tarball
  local taropts="x"
  case "${filespec}" in
    *.xz)
      local taropts="${taropts}J"
      ;;
    *.bz*)
      local taropts="${taropts}j"
      ;;
    *.gz)
      local taropts="${taropts}z"
      ;;
    *)
      error "Unable to determine how to extract ${filespec}"
      return 1
      ;;
  esac
  taropts="${taropts}f"
  
  notice "Extracting ${filespec} to ${destdir}."
  run mkdir -p "${destdir}"
  run tar "${taropts}" "${tarball}" -C "${destdir}" --strip-components=1
  if [ $? -gt 0 ]; then
    error "Failed to extract from ${filespec} to ${destdir}"
    return 1
  fi
  
  return 0
}

#######################################
# Clone a package's Git repository.
# Globals:
#   None
# Arguments:
#   package - Package name
# Returns:
#   0 (true) if the repository is cloned successfully.
#   1 (false) if cloning the repository failed.
#######################################
git_fetch() {
  local package="${1}"
  
  if [ -z "${package}" ]; then
    warning "No package to fetch!"
    return 1
  fi
  
  local filespec url sha256
  filespec=$(get_filespec "${package}")
  url=$(get_url "${package}")
  
  local git_remote_repository="${url}/${filespec}"
  local git_local_repository="${workspace_snapshots}/${filespec}"
  local git_reference_opt=""
  local git_reference_repository="${GIT_REFERENCE_DIR}/${filespec}"

  if [ -d "${git_local_repository}" ]; then
    notice "${filespec} already exists in ${workspace_snapshots}"
  else
    if [ -n "${GIT_REFERENCE_DIR}" ] && [ -d "${git_reference_repository}" ]; then 
      local git_reference_opt="--reference ${git_reference_repository}"
    fi
    
    notice "Cloning ${package} to ${git_local_repository}" 
    run git clone ${git_reference_opt} --bare \
      --config 'remote.origin.fetch=+refs/changes/*:refs/changes/*' \
      "${git_remote_repository}" "${git_local_repository}"

    if [ $? -gt 0 ]; then
      error "Failed to clone master branch from ${git_remote_repository} to ${git_local_repository}"
      return 1
    fi
  fi
  
  # Update local clone with all refs, pruning stale branches.
  run git -C "${git_local_repository}" fetch --all --prune --quiet
  if [ $? -gt 0 ]; then
    error "Failed to update from ${url} to ${git_local_repository}"
    return 1
  fi

  return 0
}

#######################################
# Checkout a package's Git worktree.
# Globals:
#   None
# Arguments:
#   Package name
# Outputs:
#   Writes the log message of the most recent commit in the checked out worktree
#   to stdout.
# Returns:
#   0 (true) if the worktree is checked out successfully.
#   1 (false) if checking out the worktree failed.
#######################################
git_checkout() {
  local package="${1}"
  
  local filespec branch revision srcdir
  filespec=$(get_filespec "${package}")
  branch=$(get_branch "${package}")
  revision=$(get_revision "${package}")
  srcdir="$(get_srcdir "${package}")"
  
  local git_local_repository="${workspace_snapshots}/${filespec}"
  
  if [ ! -d "${srcdir}" ]; then
    # By definition a git commit resides on a branch.  Therefore
    # specifying a branch AND a commit is redundant and potentially
    # contradictory. For this reason we only consider the commit
    # if both are present.
    if [ -n "${revision}" ]; then 
      notice "Checking out revision ${revision} for ${package} in ${srcdir}"
      run git -C "${git_local_repository}" worktree add "${srcdir}" "${revision}"
      if [ $? -gt 0 ]; then 
        error "Failed to create workdir for ${revision}"
        return 1
      fi
    else 
      notice "Checking out branch ${branch} for ${package} in ${srcdir}"
      run git -C "${git_local_repository}" worktree add "${srcdir}" "${branch}"
      if [ $? -gt 0 ]; then 
        error "Failed to create workdir for ${revision}"
        return 1
      fi
    fi
  fi
  
  # Show the most recent commit, useful when debugging (to check
  # that what we are building actually contains what we expect).
  echo "--------------------- ${package} ----------------------"
  run git --no-pager -C "${srcdir}" show --no-patch

  return 0
}

#######################################
# Perform a CMake build.
# Globals:
#   None
# Arguments:
#   package - Package's name
#   stage - Component stage
# Returns:
#   0 (true) if componet is successfully built and installed.
#   1 (false) if the build fails.
#######################################
cmake_build() {
  local package="${1}"
  local stage="${2}"
  
  local srcdir builddir cmakeflags
  srcdir=$(get_srcdir "${package}")
  builddir=$(get_builddir "${package}")
  cmakedir=$(get_cmakedir "${package}" "${stage}")
  cmakeflags=$(get_cmakeflags "${package}" "${stage}")
  makeflags=$(get_makeflags "${package}" "${stage}")
  
  if [ ! -d "${builddir}" ]; then
    run mkdir -p "${builddir}"
  fi
  
  [[ $cmakeflags =~ .*-G\ ?[\"]?([a-zA-Z ]+)[\"]? ]];
  local generator="${BASH_REMATCH[1]}"

  case "${generator}" in
    Ninja*)
      makecmd="ninja"
      ;;
    *) 
      makecmd="make"
      ;;
  esac
  
  pushd "${builddir}" > /dev/null
  run cmake ${cmakeflags} "${srcdir}/${cmakedir}"
  run ${makecmd} ${makeflags}
  run ${makecmd} install
  popd > /dev/null
      
  return 0
}

#######################################
# Perform a configure build.
# Globals:
#   None
# Arguments:
#   package - Package's name
#   stage - Component stage
# Returns:
#   0 (true) if componet is successfully built and installed.
#   1 (false) if the build fails.
#######################################
configure_build() {
  local package="${1}"
  local stage="${2}"
  
  local srcdir builddir
  srcdir=$(get_srcdir "${package}")
  builddir=$(get_builddir "${package}")
  configureflags=$(get_configure "${package}" "${stage}")
  makeflags=$(get_makeflags "${package}" "${stage}")
  
  if [ ! -d "${builddir}" ]; then
    run mkdir -p "${builddir}"
  fi
  
  if [ ! -f "${srcdir}/configure" ]; then
    if [ -f "${srcdir}/autogen.sh" ]; then
      pushd "${srcdir}" > /dev/null
        run ./autogen.sh
      popd > /dev/null
    fi
    if [ ! -f "${srcdir}/configure" ]; then
      error "No configure script found in ${srcdir}"
      return 1
    fi
  fi
  
  pushd "${builddir}" > /dev/null
  run eval "${srcdir}/configure" ${configureflags}
  run make ${makeflags}
  run make install
  popd > /dev/null
      
  return 0
}

#######################################
# Retrieve all packages defined in manifest.
# Globals:
#   None
# Arguments:
#   packages - Array of 'package' portions of components to retrieve 
#              (component name with any  stage specifiers removed).
#
# Returns:
#   0 (true) if packages are retrieved successfully.
#   1 (false) and exits if errors are encountered while retrieving packages.
#######################################
retrieve_all() {
  local packages=($@)
  
  notice "retrieve_all called for packages: ${packages[*]}"
  
  run mkdir -p "${workspace_snapshots}" || error "Failed to create ${workspace_snapshots}"
  
  local package
  for package in "${packages[@]}"; do
    if is_tar "${package}"; then
      tar_fetch "${package}" || error "Failed to retrieve ${package}"
    else
      git_fetch "${package}" || error "Failed to retrieve ${package}"
    fi
  done
  
  if errors_reported; then
    print_reported_errors
    exit 1
  fi

  notice "Retrieve all took ${SECONDS} seconds"
  
  return 0
}

#######################################
# Checkout or extract all packages defined in manifest.
# Globals:
#   None
# Arguments:
#   packages - Array of 'package' portions of components to retrieve 
#              (component name with any  stage specifiers removed).
# Returns:
#   0 (true) if packages are checked out successfully.
#   1 (false) and exits if errors are encountered while checking out packages.
#######################################
checkout_all() {
  local packages=($@)
  
  notice "checkout_all called for packages: ${packages[*]}"
  
  local package
  for package in "${packages[@]}"; do
    if is_tar "${package}"; then
      tar_extract "${package}" || error "Failed to checkout ${package}"
    else
      git_checkout "${package}" || error "Failed extract ${package}"
    fi
  done
  
  if errors_reported; then
    print_reported_errors
    exit 1
  fi
    
  notice "Checkout all took ${SECONDS} seconds"
  
  return 0
}

#######################################
# Build all components defined in manifest.
# Globals:
#   None
# Arguments:
#   components - Array of component names to build.
# Returns:
#   0 (true) if components are built successfully.
#   1 (false) and exits if errors are encountered while building components.
#######################################
build_all() {
  local components=($@)
  
  notice "build_all called for components: ${components[*]}"
  
  local component
  for component in "${components[@]}"; do
    
    if [[ ${component} =~ .*_stage[0-9]+ ]]; then
      local package="${component%_*}"
      local stage="${component##*_}"
    else
      local package="${component}"
      local stage=""
    fi
    
    if uses_cmake "${package}" "${stage}"; then
      run cmake_build "${package}" "${stage}" || error "Failed to build ${component}"
    elif uses_configure "${package}" "${stage}"; then
      run configure_build "${package}" "${stage}" || error "Failed to build ${component}"
    else
      notice "Nothing to build for ${package}, skipping"
    fi
  done
  
  if errors_reported; then
    print_reported_errors
    exit 1
  fi
    
  notice "Build all took ${SECONDS} seconds"
  
  return 0
}

#######################################
# Main function.
# Globals:
#   DRY_RUN
#   GIT_REFERENCE_DIR
#   RELEASE
#   VERBOSE
#   WORKSPACE
# Arguments:
#   -v, --verbose                 - Incease verbosity level  
#   -q, --quiet                   - Decrease verbosity level
#   --release                     - Override release specified in manifest
#   --workspace WORKSPACE         - Path to workspace directory to se
#   --with-git_reference-dir DIR  - Look for Git reference repositories and
#                                   tarballs in DIR before fetching online
#   manifest                      - Manifest file pathname 
# Returns:
#   0 (true) if packages are build successfully.
#   1 (false) and exits if errors are encountered while building components.
#######################################
main() {
  local positional=()
  while [[ $# -gt 0 ]]
  do
    arg="$1"

    case ${arg} in
      -v,--verbose)
        if [ ${VERBOSE} -lt 5 ]; then
          (( VERBOSE++ ))
        fi
        shift # past value
        ;;
      -q,--quiet)
        if [ ${VERBOSE} -gt 0 ]; then
          (( VERBOSE-- ))
        fi
        shift # past value
        ;;
      --release)
        RELEASE="${2}"
        shift # past value
        shift # past argument
        ;;
      --workspace)
        WORKSPACE="${2}"
        shift # past value
        shift # past argument
        ;;
      --with-git-reference-dir)
        GIT_REFERENCE_DIR="${2}"
        shift # past value
        shift # past argument
        ;;
      *)    # unknown option
        positional+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
  done
  set -- "${positional[@]}" # restore positional parameters
  
  if [[ $# -lt 1 ]]; then
    fatal "Usage: ${0} MANIFEST"
  fi

  local manifest release host target
  
  readonly manifest="${1}"
  readonly host=$(gcc -dumpmachine)
  target=$(grep -oP -m1 '(?<=target=).+' "${manifest}")
  
  RELEASE=${RELEASE:-"$(grep -oP -m1 '(?<=release=).+' "${manifest}")"}
  WORKSPACE=${WORKSPACE:-"${PWD}/${RELEASE}"}
  
  workspace_snapshots="${WORKSPACE}/snapshots"
  workspace_sysroots="${WORKSPACE}/sysroots"
  workspace_toolchains="${WORKSPACE}/toolchains"
  workspace_builds="${WORKSPACE}/builds"
  workspace_destdir="${workspace_builds}/destdir/"
  workspace_destdir_host="${workspace_builds}/destdir/${host}"
  workspace_destdir_target="${workspace_builds}/destdir/${target}"
  
  if [[ ! -d "${WORKSPACE}" ]]; then
    run mkdir -p "${WORKSPACE}"
  fi
  
  if [[ ! -w "${WORKSPACE}" ]]; then
    error "'${WORKSPACE}' is not writable'"
  fi
  
  # TODO: Add proper validation of manifest. Currently we simply source the
  # manifest as a shell script fragment to make the stanzas available to the
  # accessors as environment variables.    
  source "${manifest}"
  
  if [ -z "${steps}" ]; then
    error "steps unset or empty in ${manifest}"
    exit 1
  fi
  
  array_from_ssv COMPONENTS "${steps}"
  read_packages "${COMPONENTS[@]}"
  
  retrieve_all "${PACKAGES[@]}"
  checkout_all "${PACKAGES[@]}"
  build_all "${COMPONENTS[@]}"
  
  return 0
}

main "$@"

