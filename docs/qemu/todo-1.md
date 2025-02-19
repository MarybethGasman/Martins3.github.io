# None pci device
有趣的 80 : https://stackoverflow.com/questions/6793899/what-does-the-0x80-port-address-connect-to

- i8257 : 最爱的 DMA 控制器
- mc146818rtc : 时钟
- kvm-i8259 : 中断控制器
- i8042 : 接入到 isa 总线上的

- [ ] pc_superio_init : 中间竟然处理了 a20 线
- [ ] i8042 的 ioport 是约定，还是通过 bios 告诉的

## i8257 : dma
i8257_dma_init

- [An overview of direct memory access](https://geidav.wordpress.com/2014/04/27/an-overview-of-direct-memory-access)
- [How does DMA work with PCI Express devices?](https://stackoverflow.com/questions/27470885/how-does-dma-work-with-pci-express-devices)

> Today’s computers don’t contain DMA controllers anymore.

实际操作是，通过写 pcie 设备的 mmio 空间，让设备开始进行传输，当设备传输完成之后，设备通过中断的方式加以通知。

```c
    // first reset the DMA controllers
    outb(0, PORT_DMA1_MASTER_CLEAR); // d
    outb(0, PORT_DMA2_MASTER_CLEAR); // da

    // then initialize the DMA controllers
    outb(0xc0, PORT_DMA2_MODE_REG);
    outb(0x00, PORT_DMA2_MASK_REG);
```

```txt
  0000000000000000-0000000000000007 (prio 0, i/o): dma-chan
  0000000000000008-000000000000000f (prio 0, i/o): dma-cont


  0000000000000081-0000000000000083 (prio 0, i/o): dma-page
  0000000000000087-0000000000000087 (prio 0, i/o): dma-page
  0000000000000089-000000000000008b (prio 0, i/o): dma-page
  000000000000008f-000000000000008f (prio 0, i/o): dma-page

  00000000000000c0-00000000000000cf (prio 0, i/o): dma-chan
  00000000000000d0-00000000000000df (prio 0, i/o): dma-cont
```

在 seabios 的使用位置仅仅在 dma.c 中， 因为 dma_floppy 不会调用，实际上，只有 dma_setup 被使用的

实际上，在内核中有使用:
```c
>>> p /x ((CPUX86State *)current_cpu->env_ptr)->eip
$1 = 0xffffffff81738d84
```
disass 其位置，在 fd_disable_dma 上，所以 dma 暂时不用考虑了

## port 92

## ata
- [ ] 在 info qtree 中间暂时找不到啊

## rtc
主要发生在 xqm/hw/rtc/mc146818rtc.c 中间
- [ ] qemu_system_wakeup_request
  - 既然调用到这里了，那么说明之前存在让 guest 睡眠的情况

```c
cmos: read index=0x0f val=0x00
cmos: write index=0x0f val=0x00
cmos: read index=0x38 val=0x30
cmos: read index=0x3d val=0x12
cmos: read index=0x38 val=0x30
cmos: read index=0x08 val=0x10
cmos: read index=0x5f val=0x00
cmos: read index=0x08 val=0x10
cmos: read index=0x5f val=0x00
cmos: read index=0x00 val=0x58
cmos: write index=0x0a val=0x26
cmos: read index=0x0b val=0x02
cmos: write index=0x0b val=0x02
cmos: read index=0x0c val=0x00
cmos: read index=0x0d val=0x80
cmos: read index=0x0a val=0x26
cmos: read index=0x00 val=0x58
cmos: read index=0x02 val=0x12
cmos: read index=0x04 val=0x16
cmos: read index=0x32 val=0x20
cmos: read index=0x00 val=0x58
cmos: read index=0x10 val=0x50
cmos: read index=0x00 val=0x58
cmos: read index=0x00 val=0x58
cmos: read index=0x39 val=0x01
cmos: read index=0x00 val=0x58
cmos: read index=0x0f val=0x00
cmos: read index=0x00 val=0x58
cmos: read index=0x0a val=0x26
cmos: read index=0x00 val=0x59
cmos: read index=0x02 val=0x12
cmos: read index=0x04 val=0x16
cmos: read index=0x07 val=0x31
cmos: read index=0x08 val=0x10
cmos: read index=0x09 val=0x21
cmos: read index=0x0b val=0x02
cmos: read index=0x0d val=0x80
cmos: read index=0x00 val=0x59
cmos: read index=0x0a val=0x26
cmos: read index=0x00 val=0x59
cmos: read index=0x02 val=0x12
cmos: read index=0x04 val=0x16
cmos: read index=0x07 val=0x31
cmos: read index=0x08 val=0x10
cmos: read index=0x09 val=0x21
cmos: read index=0x0b val=0x02
cmos: read index=0x0a val=0x26
cmos: read index=0x00 val=0x59
kcmos: read index=0x10 val=0x50
cmos: read index=0x10 val=0x50
```

# 分析一下可能需要模拟的设备

看来一下，感觉其实还好吧！

| Device           | Strategy             |
|------------------|----------------------|
| port92           |                      |
| ioport80         |                      |
| ioportF0         |                      |
| rtc              |                      |
| isa-debugcon     |                      |
| pci-conf-idx     |                      |
| pci-conf-data    |                      |
| fwcfg            |                      |
| fwcfg.dma        |                      |
| io               |                      |
| apm-io           |                      |
| rtc-index        |                      |
| vga              |                      |
| vbe              |                      |
| i8042-cmd        |                      |
| i8042-data       |                      |
| parallel         |                      |
| serial           |                      |
| kvmvapic         |                      |
| pcspk            | speaker 暂时不用考虑 |
| acpi-cnt         |                      |
| acpi-evt         |                      |
| acpi-gpe0        |                      |
| acpi-cpu-hotplug |                      |
| acpi-tmr         |                      |
| dma-page         |                      |
| dma-cont         |                      |
| fdc              |                      |
| e1000-io         |                      |
| piix-bmdma       |                      |
| bmdma            |                      |
| ide              |                      |

## vbe
https://wiki.osdev.org/VBE

## debugcon
创建的位置
```txt
#0  debugcon_isa_realizefn (dev=0x5555579225c0, errp=0x7fffffffcc80) at /home/maritns3/core/xqm/hw/char/debugcon.c:99
#1  0x0000555555a25435 in device_set_realized (obj=<optimized out>, value=<optimized out>, errp=0x7fffffffcda8) at /home/maritns3/core/xqm/hw/core/qdev.c:876
#2  0x0000555555bb1deb in property_set_bool (obj=0x5555579225c0, v=<optimized out>, name=<optimized out>, opaque=0x555557922480, errp=0x7fffffffcda8) at /home/maritns3
/core/xqm/qom/object.c:2078
#3  0x0000555555bb65d4 in object_property_set_qobject (obj=obj@entry=0x5555579225c0, value=value@entry=0x555557922b80, name=name@entry=0x555555db1285 "realized", errp=
errp@entry=0x7fffffffcda8) at /home/maritns3/core/xqm/qom/qom-qobject.c:26
#4  0x0000555555bb3e0a in object_property_set_bool (obj=0x5555579225c0, value=<optimized out>, name=0x555555db1285 "realized", errp=0x7fffffffcda8) at /home/maritns3/c
ore/xqm/qom/object.c:1336
#5  0x00005555559b7d01 in qdev_device_add (opts=0x55555650a4b0, errp=<optimized out>) at /home/maritns3/core/xqm/qdev-monitor.c:673
#6  0x00005555559ba4e3 in device_init_func (opaque=<optimized out>, opts=<optimized out>, errp=0x555556424eb0 <error_fatal>) at /home/maritns3/core/xqm/vl.c:2212
#7  0x0000555555cc1fa2 in qemu_opts_foreach (list=<optimized out>, func=0x5555559ba4d0 <device_init_func>, opaque=0x0, errp=0x555556424eb0 <error_fatal>) at /home/mari
tns3/core/xqm/util/qemu-option.c:1170
#8  0x000055555582b15c in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at /home/maritns3/core/xqm/vl.c:4372
```

## pit

```txt
#0  i8254_pit_init (base=64, alt_irq=0x555556a04740, isa_irq=-1, bus=0x55555667b1a0) at /home/maritns3/core/xqm/include/hw/timer/i8254.h:57
#1  pc_basic_device_init (isa_bus=0x55555667b1a0, gsi=<optimized out>, rtc_state=rtc_state@entry=0x7fffffffcf38, create_fdctrl=create_fdctrl@entry=true, no_vmport=<opt
imized out>, has_pit=<optimized out>, hpet_irqs=4) at /home/maritns3/core/xqm/hw/i386/pc.c:1433
#2  0x0000555555913c02 in pc_init1 (machine=0x55555659a000, pci_type=0x555555d75e48 "i440FX", host_type=0x555555d74f1b "i440FX-pcihost") at /home/maritns3/core/xqm/hw/
i386/pc_piix.c:235
#3  0x0000555555a2c693 in machine_run_board_init (machine=0x55555659a000) at /home/maritns3/core/xqm/hw/core/machine.c:1143
#4  0x000055555582b0b8 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at /home/maritns3/core/xqm/vl.c:4348
```

# qemu overview

- [ ] ./replay 只有 1000 行左右，值得分析一下。
- [ ] tcg 相关联的代码在什么位置 ?

## qga
生成一个运行在虚拟机中间的程序，然后和 host 之间进行通信。

## structure
- 入口应该是 ./softmmu/main.c

- virtio
  - hw/block/virtio-blk.c
  - hw/net/virtio-blk.c
  - hw/virtio

- hw/vfio


## chardev
chardev 的一种使用方法[^2][^3], 可以将在 host 和 guest 中间同时创建设备，然后 guest 和 host 通过该设备进行交互。
-chardev 表示在 host 创建的设备，需要有一个 id, -device 指定该设备

- [x] -device virtio-serial 是必须的 ?
  - [x] 和 -device virtio-serial-bus 的关系是什么 ?
    - 似乎只有存在了 virtio-serial-bus 之后才可以将  virtio console 挂载到上面去

./chardev 就是为了支持方式将 guest 的数据导出来, 但是 guest 那边的数据一般来说 virtio 设备了
./hw/char 中间是为了对于 guest 的模拟和 host 端的 virtio 实现

## blockdev
- qemu 的 image 是支持多种模式的, 而 kvmtool 只是支持一个模式，如果
- qcow2 : qemu copy on write 的 image 格式

blockdev 文件夹下为了支持各种种类 image 访问方法，甚至可以直接访问 nvme 的方法


## capstone
- 显然 capstone 是被调用过的，在 qemu 看到的代码都是直接一条条的分析的

编译方法
```plain
➜  capstone git:(master) ✗ CAPSTONE_ARCHS="x86" bear make -j10
```

和 capstone 的玩耍:
- ./capstone
- [ref](http://www.capstone-engine.org/lang_c.html)

其实每一个架构的代码是很少的

## migration
- [ ] 有意思的东西

## monitor
qmp 让 virsh 可以和 qemu 交互

- [ ] 学会使用 :  https://libvirt.org/manpages/virsh.html

## scsi
scsi 多增加了一个抽象层次，导致其性能上有稍微的损失，但是存在别的优势。[^5][^6]
> Shortcomings of virtio-blk include a small feature set (requiring frequent updates to both the host and the guests) and limited scalability. [^7]

和实际上，scsi 文件夹下和 vritio 关系不大，反而是用于 persistent reservation
https://qemu.readthedocs.io/en/latest/tools/qemu-pr-helper.html

- [ ] pr 只是利用了 scsi 机制，但是非要使用 scsi, 不知道

## trace
- [ ] 为什么需要使用 ftrace，非常的 interesting !



[^1]: https://developer.apple.com/documentation/hypervisor
[^2]: https://stackoverflow.com/questions/63357744/qemu-socket-communication
[^3]: https://wiki.qemu.org/Features/ChardevFlowControl
[^4]: https://qkxu.github.io/2019/03/24/Qemu-Guest-Agent-(QGA)%E5%8E%9F%E7%90%86%E7%AE%80%E4%BB%8B.html
[^5]: https://mpolednik.github.io/2017/01/23/virtio-blk-vs-virtio-scsi/
[^6]: https://stackoverflow.com/questions/39031456/why-is-virtio-scsi-much-slower-than-virtio-blk-in-my-experiment-over-and-ceph-r
[^7]: https://wiki.qemu.org/Features/SCSI

# smbios
- [ ] 似乎是 fw_cfg_build_smbios 制作出来一个文件 然后通过 fw_cfg 传递给 seabios 使用的吧

https://gist.github.com/smoser/290f74c256c89cb3f3bd434a27b9f64c

- fw_cfg_build_smbios
  - 然后就是各种构建 smbios 了
  - [ ] 无法理解的是，为什么需要 anchor 啊
    - [ ] smbios 也是有 anchor 的吗?

## seabios
在 seabios 的那一侧:
```c
#define QEMU_CFG_SMBIOS_ENTRIES         (QEMU_CFG_ARCH_LOCAL + 1)
```
1. qemu_cfg_init : smbios 是其中的一个文件
  - qemu_cfg_read_entry(&count, QEMU_CFG_FILE_DIR, sizeof(count));

日志:
```plain
Add romfile: etc/smbios/smbios-anchor (size=31)
Add romfile: etc/smbios/smbios-tables (size=354)
```
2. smbios_setup
  - smbios_romfile_setup
    - `f_anchor->copy(f_anchor, &ep, f_anchor->size);` : 从 QEMU 中将制作的表格读取出来
    - `f_tables->copy(f_tables, qtables, f_tables->size);`
    - smbios_new_type_0 : 填充 type 0 的表格
    - copy_smbios : 从 stack 上拷贝到一个确定的区域
  - smbios_legacy_setup : 并不会 fallback 到这里

## qemu
表格的创建 : /hw/smbios/smbios.c

- fw_cfg_build_smbios
  - smbios_get_tables : 一系列的表格制作，需要指出的是 smbios_build_type_0_table 实际上并不会执行，因为这里记录的 SeaBIOS 的信息，是让 bios 制作的
    - smbios_build_type_0_table();
    - smbios_build_type_1_table();
    - smbios_build_type_2_table();
    - smbios_build_type_3_table();
  - fw_cfg_add_file(fw_cfg, "etc/smbios/smbios-tables", smbios_tables, smbios_tables_len);
  - fw_cfg_add_file(fw_cfg, "etc/smbios/smbios-anchor", smbios_anchor, smbios_anchor_len);

存在两种格式的 smbios:
```c
/* SMBIOS Entry Point
 * There are two types of entry points defined in the SMBIOS specification
 * (see below). BIOS must place the entry point(s) at a 16-byte-aligned
 * address between 0xf0000 and 0xfffff. Note that either entry point type
 * can be used in a 64-bit target system, except that SMBIOS 2.1 entry point
 * only allows the SMBIOS struct table to reside below 4GB address space.
 */

/* SMBIOS 2.1 (32-bit) Entry Point
 *  - introduced since SMBIOS 2.1
 *  - supports structure table below 4GB only
 */
struct smbios_21_entry_point {
    uint8_t anchor_string[4];
    uint8_t checksum;
    uint8_t length;
    uint8_t smbios_major_version;
    uint8_t smbios_minor_version;
    uint16_t max_structure_size;
    uint8_t entry_point_revision;
    uint8_t formatted_area[5];
    uint8_t intermediate_anchor_string[5];
    uint8_t intermediate_checksum;
    uint16_t structure_table_length;
    uint32_t structure_table_address;
    uint16_t number_of_structures;
    uint8_t smbios_bcd_revision;
} QEMU_PACKED;

/* SMBIOS 3.0 (64-bit) Entry Point
 *  - introduced since SMBIOS 3.0
 *  - supports structure table at 64-bit address space
 */
struct smbios_30_entry_point {
    uint8_t anchor_string[5];
    uint8_t checksum;
    uint8_t length;
    uint8_t smbios_major_version;
    uint8_t smbios_minor_version;
    uint8_t smbios_doc_rev;
    uint8_t entry_point_revision;
    uint8_t reserved;
    uint32_t structure_table_max_size;
    uint64_t structure_table_address;
} QEMU_PACKED;
```

## kernel
- [ ] 内核是如何使用这些内容的 ?

## 问题

在 pc_init1 中
```c
    if (pcmc->smbios_defaults) {
        MachineClass *mc = MACHINE_GET_CLASS(machine);
        /* These values are guest ABI, do not change */
        smbios_set_defaults("QEMU", "Standard PC (i440FX + PIIX, 1996)",
                            mc->name, pcmc->smbios_legacy_mode,
                            pcmc->smbios_uuid_encoded,
                            SMBIOS_ENTRY_POINT_21);
    }
```
其最后体现出来的效果是什么啊?

- 在 seabios 中间如何使用不知道，但是


## dmidecode(8)
dmidecode is a tool for dumping a computer's DMI (some say SMBIOS ) table contents in a human-readable format. This table contains a description of the system's hardware components, as well as other useful pieces of information such as serial numbers and BIOS revision.
