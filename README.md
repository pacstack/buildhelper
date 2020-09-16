
       ___      ___      ___      ___   ___      ___      ___      ___   ___       __      ___
      /\  \    /\__\    /\  \    /\__\ /\  \    /\__\    /\  \    /\__\ /\  \    /\  \    /\  \  
     /::\  \  /:/ _/_  _\:\  \  /:/  //::\  \  /:/__/_  /::\  \  /:/  //::\  \  /::\  \  /::\  \ 
    /::\:\__\/:/_/\__\/\/::\__\/:/__//:/\:\__\/::\/\__\/::\:\__\/:/__//::\:\__\/::\:\__\/::\:\__\
    \:\::/  /\:\/:/  /\::/\/__/\:\  \\:\/:/  /\/\::/  /\:\:\/  /\:\  \\/\::/  /\:\:\/  /\;:::/  /
     \::/  /  \::/  /  \:\__\   \:\__\\::/  /   /:/  /  \:\/  /  \:\__\  \/__/  \:\/  /  |:\/__/ 
      \/__/    \/__/    \/__/    \/__/ \/__/    \/__/    \/__/    \/__/          \/__/    \|__|


The buildhelper script performs repeat builds of LLVM toolchains in a reproducible environment.
The build itself is performed in a Singularity container.

## Quick Setup Guide

The buildhelper scripts requires a Linux host with:
- [Git](https://git-scm.com/) version 2.5 or above, and 
- [Singularity](https://sylabs.io/singularity/) version 3.5 or above installed.

Ubuntu users can follow the Singularity **Quick Start** guide at:
[https://sylabs.io/guides/3.5/user-guide/quick_start.html](https://sylabs.io/guides/3.5/user-guide/quick_start.html)

Once dependencies have been installed, clone the buildhelper repository and
build the Singularity container for performing builds:

    $ git clone https://github.com/pointer-authentication/buildhelper
    $ cd ./buildhelper
    $ sudo ./build-image.sh

**Note:** `build-image.sh` must be run with as root as Singularity requires root
privileges when building containers from recipes. If your Singularity
installation has the [fakeroot feature](https://sylabs.io/guides/3.5/user-guide/fakeroot.html) enabled, then `build-image.sh` can be run as a regular user.
In this case pass the `--fakeroot` option to `build-image.sh`:

    $ ./build-image.sh --fakeroot

This feature requires at minimum kernel version >=3.8, but >=3.18 is recommended
and that user and group mappings have been setup using `singularity config fakeroot`.
Please see the [Singularity documentation for more information](singularity config fakeroot).

The `build-image.sh` script produces `llvm-toolchain-buildhost.sif` in the current working directory.

**Note:** the container build process requires ≈ 600MB of free space in the `/tmp` filesystem.

After the buildhost container has been successfully built, LLVM builds are
started by invoking `build.sh` and passing it a corresponding manifest file.

Currently the following manifests are supported:

- PACStack LLVM 9.0.1 cross compiler for Aarch64 ( _Release_ ): `x86_64.aarch64-linux-gnu-pacstack-llvm-9.0.1-release-manifest.txt`
- PACStack LLVM 9.0.1 cross compiler for Aarch64 ( _Debug_ ):   `x86_64.aarch64-linux-gnu-pacstack-llvm-9.0.1-debug-manifest.txt`

Most users will prefer _Release_ builds, as they are faster to compile and have
better performance. To build PACStack LLVM 9.0.1 in _Release_ configuration use
the following command:

    $ ./build.sh manifest/x86_64.aarch64-linux-gnu-pacstack-llvm-9.0.1-release-manifest.txt

This will download all necessary dependencies, build LLVM and automatically run
regression tests on binaries produced by the new compiler. Once the build has
completed successfully the PACStack toolchain can be found in
`llvm-9.0.1-pacstack-release/destdir/aarch64-linux-gnu/`.

## Detailed usage instructions

    Usage: build.sh [-i|--interactive] [-r|--release] [-s|--shell] MANIFEST|URL ...

    positional arguments:
    
    MANIFEST  Manifest file with component data and build steps understood by
              SCRIPTDIR/build-from-manifest.sh. If the MANIFEST is not found in
              the directory that is specified by the MANIFESTDIR environment
              variable a copy of the MANIFEST is created in MANIFESTDIR.
 
    URL       If a URL to the manifest is specified, the manifest will be
              downloaded to the directory specifed by the MANIFESTDIR
              environment variable.

    optional arguments:
      -i, --interactive      Prompt before overwriting existing MANIFEST
      
      -r, --release RELEASE  Override release specified in MANIFEST

      -s, --shell            Run a shell within buildhost container

     Additional arguments are passed directly to scripts/build-from-manifest.sh.

The `build-from-manifest.sh` is a script that performs the build inside the
buidlhost container. It is not recommended to invoke it directly, but it is 
documented here for completeness: 

    Usage: build-from-manifest.sh [-v|--verbose|-q|--quiet] [--release] 
                                  [--workspace] [--with-git-reference-dir] MANIFEST 

    positional arguments:
    
    MANIFEST  Manifest file with component data and build steps.
    
    optional arguments:
      -v, --verbose                 Increase verbosity level
      
      -q, --quiet                   Decrease verbosity level
      
      -r, --release RELEASE         Override release specified in MANIFEST

      --workspace DIR               Path to workspace directory to use
      
      --with-git-reference-dir DIR  Look for Git reference repositories and
                                    tarballs in DIR before fetching online

## Environmental variables

`build.sh` respects the following environment variables:

- `SCRIPTDIR`    Pathname to directory containing the scripts required to be
               available inside the container during the build. It will be
               bind-mounted to `/scripts` in the container.
               Defaults to `$SCRIPTPATH/scripts`.  

- `MANIFESTDIR`  Pathname to directory containing the MANIFEST file. It will be
               bind-mounted to /manifests in the container.
               Defaults to `$SCRIPTPATH/manifests`.  

- `SNAPSHOTDIR`  Pathname to directory containing source tarballs and/or git
               reference repositories on the local machine. It will be
               bind-mounted to /snapshots in the container.
               Defaults to `$PWD/snapshots`.  
 
- `WORKSPACE`    Pathname to directory to be used as the workspace inside the
               container during the build. It will be bind-mounted to `/workspace`
               inside the the container. If unset, `build.sh` will create a new
               directory named after the release specified in the manifest.  

- `TMPDIR`       Pathname to directory which will be used for `/tmp`, `/var/tmp` and
               `$HOME` inside the container. If unset, `build.sh` will create a
               new temporary directory in the host `/tmp` which will be 
               automatically cleaned after the build is finished.
               Specifying an alternate directory by setting this environment
               variable will cause any auxiliary files to be left in the
               specified directory.  

- `SIFPATH`      Pathname to Singularity image to be used for build.
               Defaults to `$PWD/linaro-toolchain-buildhost.sif.`  

## License

> Copyright 2020 Aalto University Secure Systems Group
>
> Licensed under the Apache License, Version 2.0 (the "License");
> you may not use this file except in compliance with the License.
> You may obtain a copy of the License at
>
>    http://www.apache.org/licenses/LICENSE-2.0
>
> Unless required by applicable law or agreed to in writing, software
> distributed under the License is distributed on an "AS IS" BASIS,
> WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
> See the License for the specific language governing permissions and
> limitations under the License.
