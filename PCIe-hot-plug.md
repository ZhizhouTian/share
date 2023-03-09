---
title: PCIe hotplug learning
author: Zhizhou Tian
---

# 第一部分: PCIe手册6.8节

## 直观认识(chassis)

"Indicators may be physically located on the chassis or on the adapter"

![image](https://docs.oracle.com/cd/E55211_01/html/E55215/figures/G4311-PCIe_carrier_LEDs.png)

see: [https://docs.oracle.com/cd/E55211_01/html/E55215/z40000321568378.html]

## Indicators

the Power Indicator and the Attention Indicator

hot-plug 逻辑由upstream 组件的 downstream port 处理，如果软件没有通知 downstream port，则不能修改这个逻辑

### Attention Indicator(琥珀色)

亮的时候有问题

### Power Indicator

也叫OK灯，亮的时候有电，不能插入或者拔出，灭的时候可以拔掉

## MRL

全称是"Manually-operated Retention Latch"，用来固定PCIe设备的

MRL Sensor寄存器的report一直开启除非MRL闭合。用来控制 power，一旦开启，slot main power必须下电
如果"MRL Sensor"缺失，那么用out-of-band来控制状态

## Electromechanical Interlock

这个状态被软件设置后一直保持，除非响应接下来的软件命令，通常在下电后也仍然要保持

Slot Status register中有一个"Electromechanical Interlock Status bit"，指令下发后200ms内要做出响应

## 电源

不必关注，没有寄存器

## 与hotplug相关的寄存器

# 第二部分: pci hotplug specification

see: [http://www.drydkim.com/MyDocuments/PCI%20Spec/specifications/pcihp1_1.pdf]

# 第三部分: qemu

see: [https://www.linux-kvm.org/images/d/d7/02x07-Aspen-Michael_Roth-QEMU_Hotplug_infrastructure.pdf]

Supported via PCIe root/downstream port for x86 'q35', and ARM 'virt' (in theory

qemu -M q35 \
 -device ioh3420,multifunction=on,bus=pcie.0,id=port9-0,addr=9.0,chassis=0 \
 -device ioh3420,multifunction=on,bus=pcie.0,id=port9-1,addr=9.1,chassis=1

device_add virtio-net-pci,bus=pci.0,id=hp0
device_del hp0

```bash
PCI_CAP_ID_EXP advertised via PCI cap list

PCIe cap structure already includes registers for slot management: slot capabilities/control/status registers

Available for root/downstream ports with a slot associated (as opposed to ports that link up internal devices)

Same basic workflow as SHPC, except each slot is a bridge with it's own “SHPC” (still needed PCIe-specific drivers)
```

native pcie hotplug basic workflow:

```bash
PCI_CAP_ID_EXP advertised via PCI cap list

PCIe cap structure already includes registers for slot management: slot capabilities/control/status registers

slot select register
slot operation register: attention/power indicators, slot on/off/enable

device_add → handler->plug():
"close" MRL
"push" attention button
sends OS interrupt
OS checks that MRL is secured, card present, no power
OS powers on and enables device, sets LED
```

remove workflow:

```bash
device_del → handler->request_unplug():
"push" attention button
sends OS interrupt
OS unconfigures device, powers off device, sets LED
```

### sPAPR/pSeries是和power相关的，不关联

# 第四部分: Linux内核处理流程

see: [https://blog.csdn.net/yhb1047818384/article/details/99705972]

Linux内核共有两套流程来处理pcie hotplug。第一种是基于acpi的，第二种是基于native PCIe的。

Linux内核中相关的config有：

`CONFIG_HOTPLUG_PCI`
决定系统是否支持PCI，必须开启

`CONFIG_HOTPLUG_PCI_PCIE`
基于native PCIEe的hotplug，在不支持ACPI的系统上使用。这种情况下不支持自动的设备探测及配置，需要手动触发

`CONFIG_HOTPLUG_PCI_ACPI`
基于ACPI的hotplug。在这种情况下系统能够自动探测和配置新增的设备，是更为标准的做法

## 跟踪PCIe hotplug流程

第一步，使能ftrace的跟踪函数

```bash
echo acpi_hotplug_work_fn > set_graph_function
echo function_graph > current_tracer
cat trace_pipe
```

第二步，触发hotplug

这里要对比vfio device和vqgpu mdev的hotplug过程，因此需要两条指令

hotplug vfio pci device:
`device_add vfio-pci,host=3b:00.0,bus=rp0,id=hp0`

hotplug mdev pci device:
`device_add vfio-pci,sysfsdev=/sys/bus/mdev/devices/83b8f4f2-509f-382f-3c1e-e6bfe0fa1001,bus=rp0,id=hp0`

第三步，收集日志
见 [ftrace-vfio-pci.log]

问题解决：

```bash
qemu=/root/qemu/build/qemu-system-x86_64
#qemu=/usr/local/bin/qemu-system-x86_64
img=/data/works/images/tlinux31.img

#gdb --args                                                                     \
$qemu                                                                           \
        -machine q35,accel=kvm                                                  \   
        -m 20G                                                                  \
        -gdb tcp::1234                                                          \
        -monitor unix:/tmp/hotplug.sock,server,nowait                           \   
        -device pcie-root-port,id=rp0,slot=4,mem-reserve=32M,pref64-reserve=100G        \   
        -drive file=$img,format=qcow2,if=none,id=drive-virtio-disk0,cache=none  \
        -device virtio-blk-pci,scsi=off,bus=pcie.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 \
        -net nic        \   
        -net user,hostfwd=::930-:22,hostfwd=::931-:36001                        \   
        -D /tmp/hotplug.log     \   
        -serial mon:stdio
```

最主要就是这个`mem-reserve=32M,pref64-reserve=100G`参数，可以预留出来足够的空间给vqgpu设备

## 3月1日总结

1. 对比了vfio-pci的hotplug流程和mdev的流程，发现两者在这里有区别：

问题可以收敛到这里：从resource的sort到assign:

https://blog.csdn.net/u014100559/article/details/124831939

```c
pdev_sort_resources
        for (i = 0; i < PCI_NUM_RESOURCES; i++) {
                struct resource *r; 
                r = &dev->resource[i];
        }
        这个resource是什么时候初始化的呢? 
```

```c
__pci_bus_assign_resources
        __dev_sort_resources
        __assign_resources_sorted
                assign_requested_resources_sorted
                list_for_each_entry(dev_res, head, list) {
                        pci_assign_resource
                                _pci_assign_resource
                                        pci_bus_alloc_resource
                        pci_assign_resource
                                _pci_assign_resource
                                        pci_bus_alloc_resource
                        pci_assign_resource
                                _pci_assign_resource
                                        pci_bus_alloc_resource

```

2. 通过对比vqgpu在直通下和hotplug下两种情况的config的read、write，发现直通情况下多，hotplug下少

3. 对比nvme和vqgpu吧

```bash
b pci_read_config_byte if dev->resource[0].end == 0
b pci_read_config_dword if dev->resource[0].end == 0
b pci_read_config_word if dev->resource[0].end == 0
b pci_write_config_byte if dev->resource[0].end == 0
b pci_write_config_dword if dev->resource[0].end == 0
b pci_write_config_word if dev->resource[0].end == 0
```


__pci_read_base
pci_read_bases

dev->mmio_always_on是0, 这里为什么是0呢?

pci_write_config_word(dev, PCI_COMMAND, orig_cmd);
向这里写的一个0x3，但是被vqgpu忽略了
这里为什么

需要注意，bar3/4是没有用到，所以按照规则，应该写为0

`device_add vfio-pci,sysfsdev=/sys/bus/mdev/devices/83b8f4f2-509f-382f-3c1e-e6bfe0fa1001,bus=rp0,id=hp0`


pci_assign_resource

flag:
0x20140204

#define IORESOURCE_PREFETCH     0x00002000
#define IORESOURCE_MEM_64       0x00100000


在这里，发生resource重置:

```bash
#0  reset_resource (res=<optimized out>) at drivers/pci/setup-bus.c:200
#1  assign_requested_resources_sorted (head=0x0, fail_head=0x73de) at drivers/pci/setup-bus.c:299
#2  0xffffffff81452cb8 in __assign_resources_sorted (head=0xffffc900002e7cc0, realloc_head=0xffffc900002e7d28, fail_head=<optimized out>) at drivers/pci/setup-bus.c:473
#3  0xffffffff81454b5d in pbus_assign_resources_sorted (fail_head=<optimized out>, realloc_head=<optimized out>, bus=<optimized out>) at drivers/pci/setup-bus.c:502
#4  __pci_bus_assign_resources (bus=0xffff8885680f1800, realloc_head=<optimized out>, fail_head=<optimized out>) at drivers/pci/setup-bus.c:1349
#5  0xffffffff8146844e in enable_slot (slot=0xffff8885680b7040, bridge=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:504
#6  0xffffffff8146879c in acpiphp_check_bridge (bridge=0xffff88856800ab40) at drivers/pci/hotplug/acpiphp_glue.c:705
#7  0xffffffff81468a88 in acpiphp_check_bridge (bridge=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:685
#8  hotplug_event (context=<optimized out>, type=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:804
#9  acpiphp_hotplug_notify (adev=<optimized out>, type=0x1) at drivers/pci/hotplug/acpiphp_glue.c:828
#10 0xffffffff81490c52 in acpi_device_hotplug (adev=0xffff88856808c800, src=0x1) at drivers/acpi/scan.c:421
#11 0xffffffff8148653e in acpi_hotplug_work_fn (work=0xffff888564bdd700) at drivers/acpi/osl.c:1150
#12 0xffffffff8108f7db in process_one_work (worker=0xffff8885629da240, work=0xffff888564bdd700) at kernel/workqueue.c:2269
#13 0xffffffff8108fa08 in worker_thread (__worker=0xffff8885629da240) at kernel/workqueue.c:2415
#14 0xffffffff810951d9 in kthread (_create=0xffff88856299b400) at kernel/kthread.c:255
#15 0xffffffff81c00205 in ret_from_fork () at arch/x86/entry/entry_64.S:352
#16 0x0000000000000000 in ?? ()
```


## 分析这段代码


```bash
#0  pci_assign_resource (dev=0xffff888567b0d000, resno=0x0) at drivers/pci/setup-res.c:310
#1  0xffffffff81452900 in assign_requested_resources_sorted (head=0xffff888567b0d000, fail_head=0x0) at ./include/linux/ioport.h:207
#2  0xffffffff81452cb8 in __assign_resources_sorted (head=0xffffc900004efcc0, realloc_head=0xffffc900004efd28, fail_head=<optimized out>) at drivers/pci/setup-bus.c:473
#3  0xffffffff81454b5d in pbus_assign_resources_sorted (fail_head=<optimized out>, realloc_head=<optimized out>, bus=<optimized out>) at drivers/pci/setup-bus.c:502
#4  __pci_bus_assign_resources (bus=0xffff8885680f1800, realloc_head=<optimized out>, fail_head=<optimized out>) at drivers/pci/setup-bus.c:1349
#5  0xffffffff8146844e in enable_slot (slot=0xffff8885680b7040, bridge=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:504
#6  0xffffffff8146879c in acpiphp_check_bridge (bridge=0xffff88856800ab40) at drivers/pci/hotplug/acpiphp_glue.c:705
#7  0xffffffff81468a88 in acpiphp_check_bridge (bridge=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:685
#8  hotplug_event (context=<optimized out>, type=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:804
#9  acpiphp_hotplug_notify (adev=<optimized out>, type=0x1) at drivers/pci/hotplug/acpiphp_glue.c:828
#10 0xffffffff81490c52 in acpi_device_hotplug (adev=0xffff88856808c800, src=0x1) at drivers/acpi/scan.c:421
#11 0xffffffff8148653e in acpi_hotplug_work_fn (work=0xffff8885663bfa40) at drivers/acpi/osl.c:1150
#12 0xffffffff8108f7db in process_one_work (worker=0xffff88856069f300, work=0xffff8885663bfa40) at kernel/workqueue.c:2269
#13 0xffffffff8108fa08 in worker_thread (__worker=0xffff88856069f300) at kernel/workqueue.c:2415
#14 0xffffffff810951d9 in kthread (_create=0xffff8885663bff00) at kernel/kthread.c:255
#15 0xffffffff81c00205 in ret_from_fork () at arch/x86/entry/entry_64.S:352
#16 0x0000000000000000 in ?? ()
```

[https://www.zhihu.com/question/456457335]

这篇文章中说明了，内存地址空间，分为Low DRAM, Low MMIO, High DRAM, High MMIO四个部分

```c
pci_assign_resource
327         ret = _pci_assign_resource(dev, resno, size, align);

int pci_assign_resource(struct pci_dev *dev, int resno)
pci_assign_resource (dev=0xffff888566314000, resno=0x0) at drivers/pci/setup-res.c:310
319             align = pci_resource_alignment(dev, res);
326             size = resource_size(res);
327             ret = _pci_assign_resource(dev, resno, size, align);

static int _pci_assign_resource(struct pci_dev *dev, int resno, resource_size_t size, resource_size_t min_align)
_pci_assign_resource (dev=0xffff888566314000, resno=0x0, size=0x400000000, min_align=0x400000000) at drivers/pci/setup-res.c:295
300             while ((ret = __pci_assign_resource(bus, dev, resno, size, min_align))) {

static int __pci_assign_resource(struct pci_bus *bus, struct pci_dev *dev, int resno, resource_size_t size, resource_size_t align)
261             ret = pci_bus_alloc_resource(bus, res, size, align, min, IORESOURCE_PREFETCH | IORESOURCE_MEM_64, pcibios_align_resource, dev);
这个函数，会先查看同时满足IORESOURCE_PREFETCH | IORESOURCE_MEM_64这两个flag的bus上的resource


int pci_bus_alloc_resource(struct pci_bus *bus, struct resource *res, resource_size_t size, resource_size_t align, resource_size_t min, unsigned long type_mask, resource_size_t (*alignf)(void *, const struct resource *, resource_size_t, resource_size_t), void *alignf_data)
pci_bus_alloc_resource (bus=0xffff8885680f1800, res=0xffff888566314368, size=0x400000000, align=0x400000000, min=0xc0000000, type_mask=0x102000, alignf=0xffffffff81a0f6f0 <pcibios_align_resource>, alignf_data=0xffff888566314000) at drivers/pci/bus.c:232
237                     rc = pci_bus_alloc_from_region(bus, res, size, align, min,
238                                                    type_mask, alignf, alignf_data,
239                                                    &pci_high);
240                     if (rc == 0)
241                             return 0;
243                     return pci_bus_alloc_from_region(bus, res, size, align, min,
244                                                      type_mask, alignf, alignf_data,
245                                                      &pci_64_bit);
注意，pci_high和pci_64_bit的值，分别是从 (0x100000000ULL, 0xffffffffffffffffULL) 和 (0, 0xffffffffffffffffULL)

static int pci_bus_alloc_from_region(struct pci_bus *bus, struct resource *res, resource_size_t size, resource_size_t align, resource_size_t min, unsigned long type_mask, resource_size_t (*alignf)(void *, const struct resource *, resource_size_t, resource_size_t), void *alignf_data, struct pci_bus_region *region)
pci_bus_alloc_from_region (bus=0xffff8885680f1800, res=0xffff888566314368, size=0x400000000, align=0x400000000, min=0xc0000000, type_mask=0x102000, alignf=0xffffffff81a0f6f0 <pcibios_align_resource>, alignf_data=0xffff888566314000,
    region=0xffffffff826d3710 <pci_high>) at drivers/pci/bus.c:163
165         struct resource *r, avail;
170         pci_bus_for_each_resource(bus, r, i) {
186                     avail = *r;
(gdb) p avail
$12 = {start = 0x400000000, end = 0x400000000, name = 0xffff888566314368 "", flags = 0xffff8885680f1800, desc = 0xffffffffffffff13, parent = 0xffffffff81440a4e <pci_bus_alloc_from_region+30>, sibling = 0x10, child = 0x346}
187                     pci_clip_resource_to_region(bus, &avail, region);

static void pci_clip_resource_to_region(struct pci_bus *bus, struct resource *res, struct pci_bus_region *region)
140         struct pci_bus_region r;
142         pcibios_resource_to_bus(bus, &r, res);

void pcibios_resource_to_bus(struct pci_bus *bus, struct pci_bus_region *region, struct resource *res)
pcibios_resource_to_bus (bus=0xffff8885680f1800, region=0xffffc90000033a60, res=0xffffc90000033a70) at drivers/pci/host-bridge.c:52

```

上面这样写根本没用，对分析没好处。就得是抓住一个变量分析下来

```bash
pci_bus_alloc_resource --> pci_bus_alloc_from_region
这一步中，pci_bus_alloc_from_region是先走的pci_high这个区域


pci_bus_alloc_from_region
这个函数会遍历bus，找到一个合适的区间，能够满足type_mask
在bus上找到的这个区间，是小于4G的，应该说是这个总线的问题

再接着，linux会从pci_64_bit这里找，但是找到的区间却不足。
所以，为什么总线上的区间会这么小呢?
```

原来这个问题需要给qemu分配一个比较大的区间，之前dayizhang修复过这个问题，在i440fx上，是修复这里：

```patch
/* Keep it 2G to comply with older win32 guests */
- #define I440FX_PCI_HOST_HOLE64_SIZE_DEFAULT (1ULL << 31)
+ #define I440FX_PCI_HOST_HOLE64_SIZE_DEFAULT ((1ULL << 36) + (1ULL << 38))
```

内核中有这样的一段日志：

```bash
183 [    0.887581] PCI: Using host bridge windows from ACPI; if necessary, use "pci=nocrs" and report a bug
```

这意味着对PCIe总线上windows的保留，不体现在E820表上

但是Q35上怎么预留呢？这个文章说明的比较好：[https://bugzilla.redhat.com/show_bug.cgi?id=1529618]
如下写法，就可以添加一个20G的预留

```bash
-device pcie-root-port,id=rp0,slot=4,pref64-reserve=20G
```

在dmesg中的体现为:

```bash
[    1.010472] pci 0000:00:03.0: PCI bridge to [bus 01] 
[    1.010552] pci 0000:00:03.0:   bridge window [mem 0xfe800000-0xfe9fffff]
[    1.010630] pci 0000:00:03.0:   bridge window [mem 0x5c0000000-0xabfffffff 64bit pref]
```

但是仍然不能正常hotplug

经过调试发现， pci_bus_alloc_from_region 能够正常提供[0x5c0000000-0xabfffffff]区间出来了，但是find_resource这个函数还是不能正常返回

发现是设置的还不够大，我们总共是预留了16G，写100G

第二个bar还是有问题，大小为0x1000000

0xfe9fffff
0xfe800000
0x01000000
0x7ebfffff

pci_hole: low: 80000000, high: febfffff, size: 7ebfffff

0x400000000
0x5c0000000
0xabfffffff


## BAR的实现规则

```bash
All bits set in sz means the device isn't working properly. If the BAR isn't implemented, all bits must be 0.  If it's a
memory BAR or a ROM, bit 0 must be clear; if it's an io BAR, bit 1 must be clear.
```

最后从bar中读出来的内容，不能是全1，如果是，那就是说明设备没有正常工作。如果是全0，则说明这个bar没有实现。

## 对比

在vqgpu中, acpi_bus_init_power/device_attach被跳过了
trace_printk

第一处不同：

```c
acpiphp_hotplug_notify --> hotplug_event --> acpiphp_rescan_slot --> acpi_bus_attach

static void __dev_sort_resources(struct pci_dev *dev, struct list_head *head)
{
     if (class == PCI_CLASS_NOT_DEFINED || class == PCI_CLASS_BRIDGE_HOST)
        return;
    if (class == PCI_CLASS_SYSTEM_PIC) {
        ...
    }
}
```

vqgpu设备设置的class正是PCI_CLASS_NOT_DEFINED，导致这里直接跳过
解决方案是设置vqgpu的class，为其他的值

第二处不同:

```c
__pci_assign_resource --> pci_bus_alloc_resource
```

## 分析一下bar空间的地址是如何被分配的

## hotplug e1000e试一下

```bash
device_add e1000e,bus=rp0,id=hp1
```

可以看到e1000顺利的hotplug进来了，但是没有trace到。

handle all nostop

## pci hotplug backtrace

```bash
#0  pci_setup_device (dev=0xffff888562371000) at drivers/pci/probe.c:1715
#1  0xffffffff814b95c8 in pci_scan_device (devfn=<optimized out>, bus=<optimized out>) at drivers/pci/probe.c:2273
#2  pci_scan_single_device (devfn=<optimized out>, bus=<optimized out>) at drivers/pci/probe.c:2445
#3  pci_scan_single_device (bus=0xffff88856722a000, devfn=0) at drivers/pci/probe.c:2435
#4  0xffffffff814b9653 in pci_scan_slot (bus=0xffff88856722a000, devfn=0) at drivers/pci/probe.c:2524
#5  0xffffffff814dea6f in acpiphp_rescan_slot (slot=0xffff888567306c80) at drivers/pci/hotplug/acpiphp_glue.c:431
#6  0xffffffff814dfa08 in hotplug_event (context=<optimized out>, type=<optimized out>) at drivers/pci/hotplug/acpiphp_glue.c:803
#7  acpiphp_hotplug_notify (adev=<optimized out>, type=1) at drivers/pci/hotplug/acpiphp_glue.c:828
#8  0xffffffff81507f92 in acpi_device_hotplug (adev=0xffff8885671ab000, src=1) at drivers/acpi/scan.c:421
#9  0xffffffff814fd87e in acpi_hotplug_work_fn (work=0xffff88855d9da700) at drivers/acpi/osl.c:1150
#10 0xffffffff8109fd9f in process_one_work (worker=0xffff888562371000, work=0xffff88855d9da700) at kernel/workqueue.c:2269
#11 0xffffffff8109ffe7 in worker_thread (__worker=0xffff8885674b8780) at kernel/workqueue.c:2415
#12 0xffffffff810a64fa in kthread (_create=0xffff888566d48200) at kernel/kthread.c:255
#13 0xffffffff81e001ff in ret_from_fork () at arch/x86/entry/entry_64.S:352
#14 0x0000000000000000 in ?? ()
```

发现这个栈始终是通过acpi进行hotplug，而且挂载后挂载到了pcie-to-pci总线上：

```bash
-[0000:00]-+-00.0  Intel Corporation 82G33/G31/P35/P31 Express DRAM Controller
           +-03.0-[01]----00.0  NVIDIA Corporation TU104GL [Tesla T4]
```

03.0就是一个pcie-to-pci总线

原来这里有多种hotplug的机制：

```bash
```

```bash
touch .scmversion
grubby --set-default=/boot/vmlinuz-5.4.109-zz-tlinux4_public+
```

```bash
```

## 在vqgpu hotplug下，没有配置irq

发现在直通的情况下，是有配置 `PCI_INTERRUPT_LINE` 的，但是在hotplug的情况下就没有。
看看究竟是为什么跳过了？
