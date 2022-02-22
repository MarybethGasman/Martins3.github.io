#!/bin/bash
set -eu

use_32bit=true

# ----------------------- 配置区 -----------------------------------------------
kernel_dir=/home/maritns3/core/ubuntu-linux
if [[ $use_32bit == true ]]; then
  kernel_dir=/home/maritns3/core/ld/guest-src/linux-4.4.142
fi

# 可以直接使用系统中安装的 QEMU, 也就是 qemu-system-x86_64
qemu=/home/maritns3/core/kvmqemu/build/qemu-system-x86_64
qemu=/home/maritns3/core/xqm/build/x86_64-softmmu/qemu-system-x86_64
if [[ $use_32bit == true ]]; then
  qemu=/home/maritns3/core/xqm/32bit/i386-softmmu/qemu-system-i386
fi
initrd=/home/maritns3/core/5000/ld/DuckBuBi/image/test.cpio.gz
# bios 镜像的地址，可以不配置，将下面的 arg_seabios 定位为 "" 就是使用默认的
seabios=/home/maritns3/core/5000/ld/DuckBuBi/seabios/out/bios.bin
seabios=/home/maritns3/core/seabios/out/bios.bin
alpine_img_url=https://alpinelinux.org/downloads/
# ------------------------------------------------------------------------------

abs_loc=$(dirname "$(realpath "$0")")

kernel=${kernel_dir}/arch/x86/boot/bzImage

iso=${abs_loc}/alpine.iso
disk_img=${abs_loc}/alpine.qcow2
ext4_img1=${abs_loc}/img1.ext4
ext4_img2=${abs_loc}/img2.ext4
share_dir=${abs_loc}/share

debug_qemu=
debug_kernel=
LAUNCH_GDB=false

# 必选参数
arg_img="-drive \"file=${disk_img},format=qcow2\""
arg_initrd="-initrd ${initrd}"
arg_initrd=""

arg_kernel_args="root=/dev/sda3 nokaslr console=ttyS0"
if [[ $use_32bit == true ]]; then
  arg_kernel_args="nokaslr console=ttyS0 root=/dev/ram rdinit=/hello.out"
fi
arg_kernel="--kernel ${kernel} -append \"${arg_kernel_args}\""
arg_monitor="-monitor stdio"

arg_monitor="-nographic"

if [[ $use_32bit == true ]]; then
  arg_monitor="-nographic"
fi

# 可选参数
arg_mem="-m 128m -smp 1"
arg_share_dir="-virtfs local,path=${share_dir},mount_tag=host0,security_model=mapped,id=host0"
arg_machine="-machine pc,accel=kvm,kernel-irqchip=on" # q35
# arg_cpu="-cpu host"
arg_cpu=""
arg_seabios="-chardev file,path=/tmp/seabios.log,id=seabios -device isa-debugcon,iobase=0x402,chardev=seabios -bios ${seabios}"
arg_nvme="-device nvme,drive=nvme1,serial=foo -drive file=${ext4_img1},format=raw,if=none,id=nvme1"
arg_nvme2="-device virtio-blk-pci,drive=nvme2,iothread=io0 -drive file=${ext4_img2},format=raw,if=none,id=nvme2"
arg_iothread="-object iothread,id=io0"
arg_qmp="-qmp unix:${abs_loc}/test.socket,server,nowait"
arg_qmp=""
arg_tmp=""
# -soundhw pcspk

show_help() {
  echo "------ 配置参数 ---------"
  echo "kernel=${kernel}"
  echo "qemu=${qemu}"
  echo "seabios=${seabios}"
  echo "alpine image url=${alpine_img_url}"
  echo "-------------------------"
  echo ""
  echo "-h 展示本消息"
  echo "-s 调试内核，启动 QEMU 部分"
  echo "-k 调试内核，启动 gdb 部分"
  echo "-t 使用 tcg 作为执行引擎而不是 kvm"
  echo "-d 调试 QEMU"
  exit 0
}

while getopts "dskthp" opt; do
  case $opt in
  d) debug_qemu="gdb --args" ;;
  p) debug_qemu="perf record -F 1000" ;;
  s) debug_kernel="-S -s" ;;
  k) LAUNCH_GDB=true ;;
  t) arg_machine="--accel tcg,thread=single" arg_cpu="" ;;
  h) show_help ;;
  *) exit 0 ;;
  esac
done

sure() {
  read -r -p "$1? (y/n)" yn
  case $yn in
  [Yy]*) return ;;
  [Nn]*) exit ;;
  *) echo "Please answer yes or no." ;;
  esac
}

if [ ! -f "$iso" ]; then
  echo "${iso} not found! Download it from ${alpine_img_url}"
  exit 0
fi

# 创建额外的两个 disk 用于测试 nvme
if [ ! -f "$ext4_img1" ]; then
  sure "create ${ext4_img1}"
  dd if=/dev/null of="${ext4_img1}" bs=1M seek=100
  mkfs.ext4 -F "${ext4_img1}"
  exit 0
fi

if [ ! -f "$ext4_img2" ]; then
  sure "create ${ext4_img1}"
  dd if=/dev/null of="${ext4_img2}" bs=1M seek=100
  mkfs.ext4 -F "${ext4_img2}"
  exit 0
fi

if [ ! -f "${disk_img}" ]; then
  sure "install alpine image"
  qemu-img create -f qcow2 "${disk_img}" 10G
  qemu-system-x86_64 \
    -cdrom "$iso" \
    -cpu host \
    -hda "${disk_img}" \
    -enable-kvm \
    -m 2G \
    -smp 2
  exit 0
fi

mkdir -p "${share_dir}"

if [ $LAUNCH_GDB = true ]; then
  echo "debug kernel"
  cd ${kernel_dir}
  gdb vmlinux -ex "target remote :1234" -ex "hbreak start_kernel" -ex "continue"
  exit 0
fi

cmd="${debug_qemu} ${qemu} ${debug_kernel} ${arg_img} ${arg_mem} ${arg_cpu} \
  ${arg_kernel} ${arg_seabios} ${arg_nvme} ${arg_nvme2} ${arg_iothread} \
  ${arg_share_dir} ${arg_machine} ${arg_monitor} ${arg_qmp} ${arg_initrd} \
  ${arg_tmp}"
echo "$cmd"
eval "$cmd"

# mount -t 9p -o trans=virtio,version=9p2000.L host0 /mnt/9p
# 内核参数 : pci=nomsi

# x86 上运行运行 32bit 内核
# 1 编译出来对应的 qemu
# mkdir 32bit
# cd 32bit
# ../configure --target-list=i386-softmmu
# kernel_dir=/home/maritns3/core/ld/guest-src/linux-4.4.142 # 指向 32bit 内核
# qemu=/home/maritns3/core/xqm/32bit/i386-softmmu/qemu-system-i386 # 使用 32bit 的 qemu
