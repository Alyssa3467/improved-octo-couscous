#! /bin/bash
# inspired by https://stackoverflow.com/questions/42022659/how-to-get-a-smaller-toolchain-from-scratch
set -euo pipefail

# export TARGET_BOARD=bcm27xx
# export TARGET_SUBTARGET=bcm2708
export TARGET_TRIPLET="arm-rpi-linux-gnueabihf-"
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

# **** Get Raspberry Pi headers ****
    [[ -d raspberry-kernel ]] || git clone https://github.com/raspberrypi/linux raspberry-kernel
    cd raspberry-kernel
    KERNEL=kernel make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH="${CROSS_PREFIX}/${OWRT_PAIR}" bcmrpi_defconfig
    KERNEL=kernel make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH="${CROSS_PREFIX}/${OWRT_PAIR}" headers_install

    echo -e "\n\nTarget headers installed\n\n"
# **********************************

wait
for tball in *.tar.gz; do
    tar -xvzvf $tball -i --keep-newer-files &
done
wait

# **** GNU binutils (native) ****
mkdir ${BUILD_DIR}/binutils -p ; cd ${BUILD_DIR}/binutils
echo -e "\n\nMoved into $PWD\n\n"
# ${SOURCE_DIR}/binutils-*/configure --prefix=${NATIVE_PREFIX} --disable-nls --disable-werror --disable-multilib
${SOURCE_DIR}/binutils-*/configure --prefix=${NATIVE_PREFIX} --enable-werror=no

# TODO: Make this a function?
if (make -j$(nproc) -Orecurse); then
    echo -e "\n\nmake binutils (native) finished (first try!)\n\n"
elif (read -p "'make binutils' (native) problem with first attempt" ; make -j1 -d); then
    echo -e "\n\nmake binutils (native) finished (second try)\n\n"
else
    echo "'make binutils' (native) Failure!"
fi
make install || make -d install || (echo "'make install' failed (binutils native)" ; return 2 )
# *******************************

# **** GNU Compilier Collection (native) ****
cd ${SOURCE_DIR}/gcc-*/
[[ -h mpfr ]] || ln -s ../mpfr-*/ mpfr
[[ -h gmp  ]] || ln -s ../gmp-*/ gmp
[[ -h mpc  ]] || ln -s ../mpc-*/ mpc

mkdir ${BUILD_DIR}/gcc -p ; cd ${BUILD_DIR}/gcc
${SOURCE_DIR}/gcc-*/configure --prefix=${NATIVE_PREFIX}
echo -e "\n\nFinished configuring gcc\n\n"

(
    Colors=('128;000;000' '255;000;000' '255;128;000' '255;255;000' '000;255;000' '000;255;255' '000;128;255' '000;000;255' '000;000;128')
    while true; do
    for i in {0..8}; do
        echo -n $'\x1B[38;2;'${Colors[$i]}"m"
        echo -n ".  "$'\x08'
        sleep 5
        echo -n ".  "$'\x08'
        sleep 5    
    done
    echo -n $'\x0D\x1B[0m'
    done
)&

if (make -j$(nproc) -Orecurse); then
    kill $!
    echo -e "\n\nFinished building native gcc(first try!)\n\n"
elif (read =p "'make gcc' (native) problem with first attempt" ; make -j1 -d V=sc); then
    kill $!
    echo -e "\n\nFinished building native gcc (second try)\n\n"
else
    kill $!
    echo "'make gcc' (native) Failure!"
    return 2
fi
make install || make -d install || echo "'make install' failed (gcc native)
# *******************************************
# done with host system

# **** GNU binutils (cross) ****
mkdir ${BUILD_DIR}/${TGT_CPU}-binutils -p ; cd ${BUILD_DIR}/${TGT_CPU}-binutils
echo "Moved into $PWD"

${SOURCE_DIR}/binutils-*/configure --prefix=${CROSS_PREFIX} --target=${TARGET_TRIPLET} --with-sysroot
if (make -j$(nproc) -Orecurse); then
    echo -e "\n\nmake binutils (cross) finished (first try!)\n\n"
elif (read -p "'make binutils' (cross) problem with first attempt" ; make -j1 -d V=sc); then
    echo -e "\n\nmake binutils (cross) finished (second try)\n\n"
else
    echo "'make binutils' (cross) Failure!"
    return 2
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
