#! /bin/bash
# inspired by https://stackoverflow.com/questions/42022659/how-to-get-a-smaller-toolchain-from-scratch
set -euo pipefail

# export TARGET_BOARD=bcm27xx
# export TARGET_SUBTARGET=bcm2708
export TARGET_TRIPLET="arm-linux-gnueabihf-"
# export TARGET_ARCH="armv6kz+fp"
# export CPU_TYPE="arm1176jzf-s+vfp"
export TGT_FLAGS="--with-float=hard"
export OWRT_TARGET="bcm27xx"
export OWRT_SUBTARGET="bcm2708"
export OWRT_PAIR="${OWRT_TARGET}/${OWRT_SUBTARGET}"
export TGT_ARCH="armv6kz"
export TGT_CPU="arm1176jzf-s+vfp"
export CROSS_PREFIX="${PWD}/output/cross"
export NATIVE_PREFIX="${PWD}/output/native"
export SOURCE_DIR="${PWD}/sources"
export BUILD_DIR="${PWD}/working"

mkdir ${SOURCE_DIR} -p ; cd ${SOURCE_DIR}

# doing this with spinning metal platters = bad idea 😅

wget -N https://ftpmirror.gnu.org/binutils/binutils-2.42.tar.gz &
wget -N https://ftpmirror.gnu.org/gcc/gcc-13.2.0/gcc-13.2.0.tar.gz &
# wget https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.12.6.tar.bz2
wget -N https://www.musl-libc.org/releases/musl-latest.tar.gz &
wget -N https://ftpmirror.gnu.org/mpfr/mpfr-4.2.1.tar.gz &
wget -N https://ftpmirror.gnu.org/gmp/gmp-6.3.0.tar.gz &
wget -N https://ftpmirror.gnu.org/mpc/mpc-1.3.1.tar.gz &

wait
for ball in *.tar.gz; do
    tar -xvzvf $ball -i --keep-newer-files &
done
wait

# **** Get Raspberry Pi headers ****
(
    [[ -d raspberry-kernel ]] || git clone https://github.com/raspberrypi/linux raspberry-kernel
    cd raspberry-kernel
    KERNEL=kernel make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH="${CROSS_PREFIX}/${OWRT_PAIR}" bcmrpi_defconfig
    KERNEL=kernel make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH="${CROSS_PREFIX}/${OWRT_PAIR}" headers_install

    echo -e "\n\nTarget headers installed\n\n"
) &
# **********************************

# **** GNU binutils (native) ****
mkdir ${BUILD_DIR}/binutils -p ; cd ${BUILD_DIR}/binutils
echo -e "\n\nMoved into $PWD\n\n"
# ${SOURCE_DIR}/binutils-*/configure --prefix=${NATIVE_PREFIX} --disable-nls --disable-werror --disable-multilib
${SOURCE_DIR}/binutils-*/configure --prefix=${NATIVE_PREFIX}

if (make -j$(nproc) -Orecurse); then
    echo -e "\n\nmake binutils (native) finished (first try!)\n\n"
elif (make -j1 -d V=sc); then
    echo -e "\n\nmake binutils (native) finished (second try)\n\n"
else
    echo "Failure!"
fi
make install
# *******************************

# **** GNU Compilier Collection (native) ****
cd ${SOURCE_DIR}/gcc-*/
[[ -h mpfr ]] || ln -s ../mpfr-*/ mpfr
[[ -h gmp  ]] || ln -s ../gmp-*/ gmp
[[ -h mpc  ]] || ln -s ../mpc-*/ mpc

mkdir ${BUILD_DIR}/gcc -p ; cd ${BUILD_DIR}/gcc
${SOURCE_DIR}/gcc-*/configure --prefix=${NATIVE_PREFIX}
echo -e "\n\nFinished configuring gcc\n\n"

if (make -j$(nproc) -Orecurse); then
    echo -e "\n\nFinished building native gcc(first try!)\n\n"
elif (make -j1 -d V=sc); then
    echo -e "\n\nFinished building native gcc (second try)\n\n"
else
    echo "Failure!"
fi
make install
# *******************************************
# done with host system

# **** GNU binutils (cross) ****
mkdir ${BUILD_DIR}/${TGT_CPU}-binutils -p ; cd ${BUILD_DIR}/${TGT_CPU}-binutils
echo "Moved into $PWD"

${SOURCE_DIR}/binutils-*/configure --prefix=${CROSS_PREFIX} --target=${TARGET_TRIPLET} --with-sysroot
if (make -j$(nproc) -Orecurse); then
    echo -e "\n\nmake binutils (cross) finished (first try!)\n\n"
elif (make -j1 -d V=sc); then
    echo -e "\n\nmake binutils (cross) finished (second try)\n\n"
else
    echo "Failure!"
fi
make install
# should be in prefix/target/bin
# ${SOURCE_DIR}/binutils-*/configure --prefix=${CROSS_PREFIX} --with-sysroot \
#     --with-cpu=${CPU_TYPE}  --target=${TARGET_TRIPLET} --prefix=${CROSS_PREFIX} --disable-nls --disable-werror --disable-multilib
# ******************************

# **** GNU Compilier Collection (cross) ****
mkdir ${BUILD_DIR}/bootstrap-${TGT_CPU}-gcc -p ; ${BUILD_DIR}/bootstrap-${TGT_CPU}-gcc
${SOURCE_DIR}/gcc-*/configure --target=${TARGET_TRIPLET} --prefix=${CROSS_PREFIX} --with-cpu=${TGT_CPU} ${TGT_FLAGS}
# ${SOURCE_DIR}/gcc-*/configure --target=${TARGET_TRIPLET} --prefix=${CROSS_PREFIX} --disable-nls --enable-languages=c --disable-multilib --disable-threads --disable-shared --with-float=hard --with-arch=${TARGET_ARCH}
# make all-gcc install-gcc
# make all-target-libgcc install-target-libgcc

# mkdir ${BUILD_DIR}/musl -p
# cd ${BUILD_DIR}/musl
# CC=${TARGET_TRIPLET}-gcc CFLAGS=-Wa,-mhard-float ../musl-*/configure --prefix=${CROSS_PREFIX}/${TARGET_TRIPLET}/ --enable-optimize CROSS_COMPILE=${TARGET_TRIPLET}-
# make
# make install
