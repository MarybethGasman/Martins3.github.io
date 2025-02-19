# linux Memory Management

<!-- vim-markdown-toc GitLab -->

* [introduction](#introduction)
* [page allocator](#page-allocator)
    * [page free](#page-free)
* [page ref](#page-ref)
* [page fault](#page-fault)
    * [cow](#cow)
    * [page table](#page-table)
* [virtual memory](#virtual-memory)
    * [fork](#fork)
    * [paging](#paging)
    * [copy_from_user](#copy_from_user)
* [mm_struct](#mm_struct)
* [mmap](#mmap)
    * [brk](#brk)
    * [mmap layout](#mmap-layout)
    * [page walk](#page-walk)
    * [process vm access](#process-vm-access)
* [compaction](#compaction)
    * [compact deferred](#compact-deferred)
* [tlb](#tlb)
* [hugetlb](#hugetlb)
* [compound page](#compound-page)
* [THP](#thp)
    * [THP admin manual](#thp-admin-manual)
    * [THP kernel](#thp-kernel)
    * [THP khugepaged](#thp-khugepaged)
    * [THP split](#thp-split)
* [page cache](#page-cache)
* [address_space](#address_space)
* [address_space_operations](#address_space_operations)
    * [page writeback](#page-writeback)
    * [watermark](#watermark)
    * [truncate](#truncate)
    * [readahead](#readahead)
* [buffer cache](#buffer-cache)
* [migrate](#migrate)
* [numa](#numa)
    * [mempolicy](#mempolicy)
* [madvise && fadvise](#madvise-fadvise)
* [highmem](#highmem)
* [pmem](#pmem)
    * [vmemmap](#vmemmap)
* [mmio](#mmio)
* [physical memory initialization](#physical-memory-initialization)
* [memory zone](#memory-zone)
* [shmem](#shmem)
* [swap](#swap)
    * [swap cache](#swap-cache)
    * [swapfile](#swapfile)
* [out of memory killer](#out-of-memory-killer)
* [vmstate](#vmstate)
* [mlock](#mlock)
* [lock](#lock)
* [hot plug](#hot-plug)
* [ioremap](#ioremap)
* [mremap](#mremap)
* [debug](#debug)
    * [page owner](#page-owner)
    * [KASAN](#kasan)
    * [kmemleak](#kmemleak)
* [dmapool](#dmapool)
* [mempool](#mempool)
* [virtual machine](#virtual-machine)
    * [mmu notifier](#mmu-notifier)
    * [balloon compaction](#balloon-compaction)
* [hmm](#hmm)
* [CMA](#cma)
* [zsmalloc](#zsmalloc)
* [z3fold](#z3fold)
* [zud](#zud)
* [memory control group](#memory-control-group)
* [page poison](#page-poison)
* [msync](#msync)
* [mpage](#mpage)
* [memblock](#memblock)
* [malloc](#malloc)
    * [jemalloc](#jemalloc)
* [profiler](#profiler)
* [skbuff](#skbuff)
* [struct page](#struct-page)
* [hardware](#hardware)
* [idel page](#idel-page)
* [mprotect](#mprotect)
* [vma](#vma)
    * [vm_ops](#vm_ops)
    * [vm_flags](#vm_flags)
    * [page_flags](#page_flags)
* [vmalloc](#vmalloc)
* [mincore](#mincore)
* [pageblock](#pageblock)
* [user address space](#user-address-space)
* [kaslr](#kaslr)
* [memfd](#memfd)
* [DAX](#dax)
* [CXL](#cxl)

<!-- vim-markdown-toc -->

布局: introduction 写一个综述，然后 reference 各个 section 和 subsection 中间的内容。

// TODO 经过讲解PPT的内容之后，可以整体框架重做为 物理内存，虚拟内存，page cache 和 swap cache 四个部分来分析

## introduction
大致分析一下和内存相关的syscall
https://thevivekpandey.github.io/posts/2017-09-25-linux-system-calls.html
1. mmap munmap mremap mprotec brk
2. shmget shmat shmctl
3. membarrier
4. madvise msync mlock munlock mincore
5. mbind set_mempoliyc get_mempolicy


1. 一个干净的地址空间 : virtual memory。
    1. 历史上存在使用段式，现代操作系统使用页式虚实映射，x86对于段式保持兼容，为了节省物理内存，所以虚实翻译是一个多级的。
    2. 访存需要进行一个page walk ，原先一次访存，现在需要进行多次，所以存在TLB加快速度。为了减少TLB miss rate，使用 superpage 是一种补救方法。
2. 加载磁盘的内容到内存的时机，linux 使用page fault 机制，当访问到该页面在加载内存(demand paging)。
2. 哪一个物理页面是空闲，哪一个物理页面正在被使用: buddy allocator
    1. 伙伴系统的分配粒度是 : 2^n * page size 的，但是内核需要更小粒度的分配器，linux 使用 slub slob slab 分配器
    2. 物理内存碎片化会导致即使内存充足，但是buddy allocator 依据无法分配足够的内存，因此需要 [compaction](#compaction) 机制和 [page reclaim](#page-reclaim) 机制
    3. 当缺乏连续的物理页面，可以通过修改内核page table 的方法获取虚拟的连续地址，这是通过 vmalloc 实现的。
2. 不同的程序片段的属性不同，代码，数据等不同，linux 使用vma 来描述。
3. 程序需要访问文件，内存比磁盘快很多，所以需要使用内存作为磁盘的缓存: [page cache](#page-cache)
    1. dirty 缓存什么时候写回磁盘，到底让谁写回到内存。
    4. 如果不加控制，缓存将会占据大量的物理内存，所以需要 page reclaim 机制释放一些内存出来。
4. 当内存不够的时候，利用磁盘进行缓存。
    1. 物理页面可能被多个进程共享，当物理页面被写回磁盘的时候，linux 使用反向映射的机制来告知所有的内存。
    2. 不仅仅可以使用disk进行缓存，也可以使用一些异构硬件或者压缩内存的方法
5. 不同进程之间需要进行信息共享，利用内存进行共享是一个高效的方法，linux 支持Posix 和 sysv 的 shmem。
    1. 父子进程之间由于 fork 也会进行内存共享，使用 cow 机制实现更加高效的拷贝(没有拷贝就是最高效的拷贝)
6. 访存带宽和访存延迟是虚拟机的关键，内存模块需要提供机制来为虚拟机服务。
    1. @todo 暂时完全不懂
7. 内存是关键的资源，类似于docker之类的容器技术需要利用内核提供的 cgroup 技术来限制一个容器内内存使用。

硬件对于内存的管理提出的挑战：
1. 由于IO映射以及NUMA，内存不是连续的。linux 提供了多个内存模型来解决由于空洞导致的无效 struct page
2. NUMA 系统中间，访问非本地的内存延迟比访问本地的延迟要高，如何让CPU尽可能访问本地的内存。
    1. 内存分配器应该确立分配的优先级。
    2. 将经常访问的内存迁移过来。
3. 现在操作系统中间，每一个core 都存在自己的 local cache，为了让CPU 尽可能访问自己local cache 的内容，linux 使用 percpu 机制。
4. 内存是操作系统的运行基础，包括内存的分配，为了解决这个鸡生蛋的问题，linux 使用架构相关的代码探测内存，并且使用 memblock 来实现早期的内存管理。
5. 现代处理器处于性能的考虑，对于访存提出 memory consistency 和 cache coherence 协议，其中 memory consistency 让内核的代码需要特殊注意来避免错误。

克服内核开发人员的疏忽产生的错误:
1. kmemleak @todo
2. kasan @todo
3. vmstat 获取必要的统计数据 https://www.linuxjournal.com/article/8178

克服恶意攻击:
1. stack 随机 ?
2. cow 机制的漏洞是什么 ?
3. 内核的虚拟地址空间 和 用户的虚拟地址空间 互相分离。copy_to_user 和 copy_from_user 如何实现 ?
    1. 内核的物理地址是否也是局限于特定的范围中 ? 否则似乎难以建立linear 映射。
    2. 猜测，对于amd64, 内核虚拟地址映射了所有的物理地址，这导致其可以访问任何物理地址，而不会出现 page fault 的情况。
        1. 但是用户的看到的地址空间不仅仅包括内核(线性映射)，也包含自己
        2. 用户进程 syscall 之后，需要切换使用内核的 mm_struct 吗 ?
    3. 对于 x86 32bit 利用 highmem 到底实现了什么内容 ?

那么这些东西具有怎样的联系:(将上面的内容整理成为一个表格)
1. page fault 需要的页面可能是是被swap 出去的
2. shmem 的内存可能被 swap
3. superpage 需要被纳入到 dirty 和 page claim 中间
4. 进行 page reclaim 可以辅助完成 compaction
5. page reclaim 和 swap 都需要使用反向映射。

现在从一个物理页面的角度将上述的内容串联起来。

> 确立那些是基本要素，然后之间的交互是什么:

| virtual memory | swap | allocator | numa | multicore | hugetlb | page cache | page fault | cgroup | shmem | page reclaim | migrate |
|----------------|------|-----------|------|-----------|---------|------------|------------|--------|-------|--------------|---------|
| virtual memory |
| swap           |
| allocator      |
| numa           |

总结内容主要来自于 lwn [^3], (几本书)，wowotech ，几个试验


## page allocator
为什么 page allocator 如此复杂 ?
1. 当内存不够的时候，使用 compaction 和 page reclaim 压榨一些内存出来
2. 为了性能 :  percpu

`__alloc_pages_nodemask` 是整个 buddy allocator 的核心，各种调用的函数都是辅助，其 alloc_context 之后，然后调用两个关键
1. get_page_from_freelist : 从 freelist 直接中间获取
2. `__alloc_pages_slowpath` : 无法从 freelist 中间获取，那么调整 alloc_flags，重新使用 get_page_from_freelist 进行尝试，如果还是失败，使用
    1. `__alloc_pages_direct_reclaim` => `__perform_reclaim` => try_to_free_pages : 通过 reclaim page 进行分配
    2. `__alloc_pages_direct_compact` => try_to_compact_pages : 通过 compaction 维持生活
> 似乎整个调用路径非常清晰，但是 hugepage 和 mempolicy 的效果体现在哪里的细节还是需要深究一下。

解除疑惑 : 为什么 alloc_pages 没有 mempolicy 的参数 ?
```c
static inline struct page * alloc_pages(gfp_t gfp_mask, unsigned int order) { return alloc_pages_current(gfp_mask, order); }

/**
 *  alloc_pages_current - Allocate pages.
 *
 *  @gfp:
 *    %GFP_USER   user allocation,
 *        %GFP_KERNEL kernel allocation,
 *        %GFP_HIGHMEM highmem allocation,
 *        %GFP_FS     don't call back into a file system.
 *        %GFP_ATOMIC don't sleep.
 *  @order: Power of two of allocation size in pages. 0 is a single page.
 *
 *  Allocate a page from the kernel page pool.  When not in
 *  interrupt context and apply the current process NUMA policy.
 *  Returns NULL when no page can be allocated.
 */
struct page *alloc_pages_current(gfp_t gfp, unsigned order)
{
  struct mempolicy *pol = &default_policy;
  struct page *page;

  if (!in_interrupt() && !(gfp & __GFP_THISNODE))
    pol = get_task_policy(current);

  /*
   * No reference counting needed for current->mempolicy
   * nor system default_policy
   */
  if (pol->mode == MPOL_INTERLEAVE)
    page = alloc_page_interleave(gfp, order, interleave_nodes(pol));
    else
    page = __alloc_pages_nodemask(gfp, order,
        policy_node(gfp, pol, numa_node_id()),
        policy_nodemask(gfp, pol));

  return page;
}
EXPORT_SYMBOL(alloc_pages_current);
```

happy path : get_page_from_freelist
1. 检查一下 dirty 数量是否超标: node_dirty_ok
2. 检查内存剩余数量 : zone_watermark_fast，如果超标，使用 node_reclaim 回收.
3. 从合乎要求的 zone 里面获取页面 : rmqueue

happy path : requeue
1. 如果大小为 order 为 1，从percpu cache 中间获取: rmqueue_pcplist
2. 否则调用 `__rmqueue`，`__rmqueue` 首先进行使用 `__rmqueue_smallest`进行尝试，如果不行，调用 `__rmqueue_fallback` 在 fallback list 中间查找。
3. `__rmqueue_smallest` 就是介绍 buddy allocator 的理论实现的部分了


[LoyenWang](https://www.cnblogs.com/LoyenWang/p/11626237.html)

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191006001219745-1992148860.png)
![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191006001229047-942884289.png)

- [ ] why allocate pages per zone, but reclaim pages per node ?


- [ ] cat /proc/pagetypeinfo && cat /proc/pagetypeinfo , check it in spare time


- [ ] gfp_mask and alloc_flags
  - [ ] gfp_to_alloc_flags
  - [ ] include/linux/gfp.h contains clear comments for gfp_mask

quick and slow path of allocation:

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191006001326475-348220432.png)
![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191006001337263-1883106181.png)
![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191006001359420-1831491364.png)


- [x] So what's ALLOC_HARDER
  - gfp_to_alloc_flags() :
  - rmqueue() : will try `MIGRATE_HIGHATOMIC` type memory immediately with ALLOC_HARDER



![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191013162755767-482755655.png)

#### page free
当order = 0时，会使用Per-CPU Page Frame来释放，其中：
- MIGRATE_UNMOVABLE, MIGRATE_RECLAIMABLE, MIGRATE_MOVABLE三个按原来的类型释放；
- MIGRATE_CMA, MIGRATE_HIGHATOMIC类型释放到MIGRATE_UNMOVABLE类型中；
- MIGRATE_ISOLATE类型释放到Buddy系统中；
- 此外，在PCP释放的过程中，发生溢出时，会调用free_pcppages_bulk()来返回给Buddy系统。来一张图就清晰了：

- [ ] what if order != 0 ?

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191013162924540-1531356891.png)

## page ref
- [x] `_refcount` 和 `_mapcount` 的关系是什么 ?

[^27] : Situations where `_count` can exceed `_mapcount` include pages mapped for DMA and pages mapped into the kernel's address space with a function like get_user_pages().
Locking a page into memory with mlock() will also increase `_count`. The relative value of these two counters is important; if `_count` equals `_mapcount`,
the page can be reclaimed by locating and removing all of the page table entries. But if `_count` is greater than `_mapcount`, the page is "pinned" and cannot be reclaimed until the extra references are removed.

- [ ] so every time, we have to increase `_count` and `_mapcount` syncronizely ? That's ugly, there are something uncovered yet!

1. page_ref_sub 调查一下，为什么 swap 会使用这个机制

```c
/*
 * Methods to modify the page usage count.
 *
 * What counts for a page usage:
 * - cache mapping   (page->mapping)
 * - private data    (page->private)
 * - page mapped in a task's page tables, each mapping
 *   is counted separately
 *
 * Also, many kernel routines increase the page count before a critical
 * routine so they can be sure the page doesn't go away from under them.
 */

/*
 * Drop a ref, return true if the refcount fell to zero (the page has no users)
 */
static inline int put_page_testzero(struct page *page)
{
  VM_BUG_ON_PAGE(page_ref_count(page) == 0, page);
  return page_ref_dec_and_test(page);
}

/*
 * Try to grab a ref unless the page has a refcount of zero, return false if
 * that is the case.
 * This can be called when MMU is off so it must not access
 * any of the virtual mappings.
 */
static inline int get_page_unless_zero(struct page *page)
{
  return page_ref_add_unless(page, 1, 0);
}
```

- [ ] understand this function and it's reference
```c
static bool is_refcount_suitable(struct page *page)
{
  int expected_refcount;

  expected_refcount = total_mapcount(page);
  if (PageSwapCache(page))
    expected_refcount += compound_nr(page);

  return page_count(page) == expected_refcount;
}
```

- [ ] put_page : rather difficult than expected

1. `_mapcount` 是在 union 中间，当该页面给用户使用的时候，才有意义

## page fault
- [ ] vmf_insert_pfn : 给驱动使用的直接，在 vma 连接 va 和 pa

[TO BE CONTINUE](https://www.cnblogs.com/LoyenWang/p/12116570.html), this is a awesome post.

handle_pte_fault 的调用路径图:
1. do_anonymous_page : anon page
2. do_fault : 和 file 相关的
5. do_numa_page
3. do_swap_page
    4. do_wp_page : 如果是 cow 一个在 disk 的 page ，其实不能理解，如果 cow ，那么为什么不是直接复制 swp_entry_t ，为什么还会有别的蛇皮东西 !
    2. @todo 由于 cow 机制的存在, 岂不是需要将所有的 pte 全部标记一遍，找到证据!
4. do_wp_page


- [ ] `enum vm_fault_reason` : check it's entry one by one

- [ ] I guess the only user of `struct vm_operations_struct` is page fault

```c
static const struct vm_operations_struct xfs_file_vm_ops = {
  .fault    = xfs_filemap_fault,
  .huge_fault = xfs_filemap_huge_fault,
  .map_pages  = xfs_filemap_map_pages,
  .page_mkwrite = xfs_filemap_page_mkwrite,
  .pfn_mkwrite  = xfs_filemap_pfn_mkwrite,
};
```


#### cow
- [ ] 如果可以理解 dirty cow，应该 COW 就没有问题吧 https://dirtycow.ninja/
  - [ ] https://chao-tic.github.io/blog/2017/05/24/dirty-cow : and this one
- [ ] 理解一下文件系统的 cow 的实现e.g., btrfs

- [ ] check the code related with copying page table when cow
- 1. do_wp_page 和 do_cow_page 是什么关系 ?
    1. do_cow_page : 和 mmap 的第一次创建有关系
2. 什么时候进行 page table 的拷贝 ?

- [ ] do_swap_page is used for read page from anonymous vma, check it's usage

```
handle_pte_fault ==>
                    ==> do_wp_page ==> wp_page_copy
do_swap_page     ==>
```

- [ ] do_wp_page
  - [ ] why we should check `PageAnon(vmf->page)` especially
  - [ ] `return VM_FAULT_WRITE;` check why it need return value
  - [ ] `(unlikely((vma->vm_flags & (VM_WRITE|VM_SHARED)) == (VM_WRITE|VM_SHARED))` if a write protection fault can be triggered on the writable page.



- [x] why do_swap_page called do_wp_page ?
  - at first glance, it's unreasonable, but what if a shared page is swapped out and a process it's trying to write to it.
```c
vm_fault_t do_swap_page(struct vm_fault *vmf){
// ...
  if (vmf->flags & FAULT_FLAG_WRITE) {
    ret |= do_wp_page(vmf);
    if (ret & VM_FAULT_ERROR)
      ret &= VM_FAULT_ERROR;
    goto out;
  }
// ...
}
```

- [x] is_cow_mapping : if the page is shared in parent, it's meanless for child to cow it, just access it.
```c
static inline bool is_cow_mapping(vm_flags_t flags)
{
  return (flags & (VM_SHARED | VM_MAYWRITE)) == VM_MAYWRITE;
}
```
- https://stackoverflow.com/questions/48241187/memory-region-flags-in-linux-why-both-vm-write-and-vm-maywrite-are-needed
- https://stackoverflow.com/questions/13405453/shared-memory-pages-and-fork


This is a interesting question, if we want to protect a page being written by cow,
- if the page is writable, so we should clear the writable flags of it ?
- but if the page is not writable, so we should fail the cow page fault ?

[内存在父子进程间的共享时间及范围](https://www.cnblogs.com/tsecer/p/10487840.html)

```
sys_fork--->>>>do_fork--->>>copy_process---->>>copy_mm---->>>dup_mm---->>>dup_mmap---->>>copy_page_range---->>>>copy_pud_range---->>>copy_pmd_range---->>>copy_pte_range
---->>>copy_nonpresent_pte
---->>>copy_present_pte
    ---->>> copy_present_page
```
> mmap时它mmap的是私有的，这一点就导致is_cow_mapping中VM_SHARED是没有置位，因此函数返回值为true；对于代码段中的空间，它的VM_SHARED是满足的，所以函数返回false，进而导致父进程和子进程直接共享页面，不会设置COW属性。


- [x] copy_nonpresent_pte : copy swap entry, migration entry and device entry
- [x] copy_present_pte
- [x] copy_present_page : really simple without dma

#### page table
- [ ] https://stackoverflow.com/questions/32943129/how-does-arm-linux-emulate-the-dirty-accessed-and-file-bits-of-a-pte

## virtual memory
1. 实现地址空间的隔离是虚拟内存的目的，但是，关键位置在于如何实现在隔离的基础上共享和通信。
  1. 实现隔离的方法: page walk
  2. 实现共享 : cow + mmap(找到一下使用 mmap 的)
2. 不同虚拟内存的属性不同。vma
3. mmap 还可以用于分配内存，但是没有必要 !


// ---------- 等待处理的事情 ---------------
1. 为什么 mm_struct 中间存在这个，难道这个的实现不是标准操作吗 ?
```c
    unsigned long (*get_unmapped_area) (struct file *filp,
        unsigned long addr, unsigned long len,
        unsigned long pgoff, unsigned long flags);
```
2. vma_ops : anonymous 的不需要 vm_ops，所以 vm_ops 处理都是文件相关的内容，解释一下每个函数到底如何处理 underlying 的文件的。
    1. 找到各种 file vma 的插入 vm_ops 的过程是什么 ?

```c
static inline bool vma_is_anonymous(struct vm_area_struct *vma)
{
  return !vma->vm_ops;
}
```
3. 虚拟地址空间的结构是什么 ? amd64 的架构上，内核空间如此大，内核空间的线性地址的映射是如何完成的 ?

5. 当使用四级的 page walk 的时候，为什么可以实现 48bit 的寻址过程，中间的空洞是如何体现出来的。

6. 分析一下经典的函数 : `__pa` `__va` 和 kmap 以及 kunmap 的关系是什么 ? 似乎回到 highmem 的内容

7. 还是分不清Kernel Logical Address 和 Kernel Virtual Address 的区别是什么? 这是凭空创建出来混淆人的注意力
// ---------- 等待处理的事情 end ---------------

This hardware feature allows operating systems to map
the kernel into the address space of every process and
to have very efficient transitions from the user process
to the kernel, e.g., for interrupt handling.
1. 为什么每一个进程都需要持有内核地址空间 ?
  - 似乎 : 反正用户进程无法访问内核地址空间
  - **interrupt 的时候不用切换地址空间**，由于切换地址空间而导致的 TLB flush 都是没有必要使用的。
  - fork 会很难实现 : fork 出来的 child 需要从内核态返回，至少在返回到用户层的时候需要使用内核地址空间
  - context switch 的过程 : 进入内核态，各种切换(包括切换地址空间)，离开内核态。如果用户不包含内核态的地址空间，就需要考虑切换地址空间和进入内核空间，先后 ?，同时 ?
  > emmmmm fork 和 context switch 的内容需要重新分析

x86_64 规定了虚拟地址空间的layout[^5]
1. 4-level 和 5-level 在 layout 的区分只是 start address 和 length 的区别
2. 处于安全问题，这些地址都是加入了随机偏移
3. page_offset_base vmalloc_base vmemmap_base 含义清晰
4. 其他暂时不管
5. *只是 ioremap 的开始位置为什么和 vmalloc_base 使用的位置相同*
6. cpu_entry_area : https://unix.stackexchange.com/questions/476768/what-is-cpu-entry-area


#### fork
1. fork 的那些 flags 如何控制
2. vma 指向的内存如何控制

到底内存中间如何控制其中的




#### paging
> 准备知识
- [todo 首先深入理解 x86 paging 机制](https://cirosantilli.com/x86-paging)
- [todo](https://0xax.gitbooks.io/linux-insides/content/Theory/linux-theory-1.html)
- [todo ](https://stackoverflow.com/questions/12557267/linux-kernel-memory-management-paging-levels)

A. 到底存在多少级 ?
arch/x86/include/asm/pgtable_types.h
一共 5 级，每一级的作用都是相同的
1. 如果处理模拟的各种数量的level : CONFIG_PGTABLE_LEVELS
2. 似乎 获取 address 的，似乎各种flag 占用的 bit 数量太多了，应该问题不大，反正这些 table 的高位都是在内核的虚拟地址空间，所有都是


B. 通过分析 `__handle_mm_fault` 说明其中的机制：
由于 page walk 需要硬件在 TLB 和 tlb miss 的情况下提供额外的支持。

// 有待处理的
1. vm_fault 所有成员解释 todo
3. devmap : pud_devmap 的作用是什么 ?


```c
/*
 * By the time we get here, we already hold the mm semaphore
 *
 * The mmap_sem may have been released depending on flags and our
 * return value.  See filemap_fault() and __lock_page_or_retry().
 */
static vm_fault_t __handle_mm_fault(struct vm_area_struct *vma,
    unsigned long address, unsigned int flags)
{
  struct vm_fault vmf = {
    .vma = vma,
    .address = address & PAGE_MASK,
    .flags = flags,
    .pgoff = linear_page_index(vma, address),
    .gfp_mask = __get_fault_gfp_mask(vma),
  };
  unsigned int dirty = flags & FAULT_FLAG_WRITE;
  struct mm_struct *mm = vma->vm_mm;
  pgd_t *pgd;
  p4d_t *p4d;
  vm_fault_t ret;

  pgd = pgd_offset(mm, address); // 访问 mm_struct::pgd 以及 address 的偏移，但是可以从此处获取到
  p4d = p4d_alloc(mm, pgd, address); // 如果 pgd 指向 p4d entry 是无效的，首先分配。如果有效，只是简单的计算地址。
  if (!p4d)
    return VM_FAULT_OOM;

  vmf.pud = pud_alloc(mm, p4d, address); // vmf.pud 指向 pmd。vmf.pud 对应的映射范围 : pmd 的 entry *  page table 的 entry * PAGE_SIZE
  if (!vmf.pud)
    return VM_FAULT_OOM;
retry_pud:
  if (pud_none(*vmf.pud) && __transparent_hugepage_enabled(vma)) {
    ret = create_huge_pud(&vmf);
    if (!(ret & VM_FAULT_FALLBACK))
      return ret;
  } else {
    pud_t orig_pud = *vmf.pud;

    barrier(); // TODO 现在不清楚为什么需要添加 barrier
    if (pud_trans_huge(orig_pud) || pud_devmap(orig_pud)) {

      /* NUMA case for anonymous PUDs would go here */

      if (dirty && !pud_write(orig_pud)) {
        ret = wp_huge_pud(&vmf, orig_pud); //
        if (!(ret & VM_FAULT_FALLBACK))
          return ret;
      } else {
        huge_pud_set_accessed(&vmf, orig_pud);
        return 0;
      }
    }
  }

  vmf.pmd = pmd_alloc(mm, vmf.pud, address); // 如果处理的不是 vmf.pud 指向的不是 pgfault
  if (!vmf.pmd)
    return VM_FAULT_OOM;

  /* Huge pud page fault raced with pmd_alloc? */
  if (pud_trans_unstable(vmf.pud)) // 当线程同时在进行 page fault
    goto retry_pud;

  if (pmd_none(*vmf.pmd) && __transparent_hugepage_enabled(vma)) {
    ret = create_huge_pmd(&vmf);
    if (!(ret & VM_FAULT_FALLBACK))
      return ret;
  } else {
    pmd_t orig_pmd = *vmf.pmd;

    barrier();
    if (unlikely(is_swap_pmd(orig_pmd))) { // TODO swap 的关系是什么
      VM_BUG_ON(thp_migration_supported() &&
            !is_pmd_migration_entry(orig_pmd));
      if (is_pmd_migration_entry(orig_pmd))
        pmd_migration_entry_wait(mm, vmf.pmd);
      return 0;
    }
    if (pmd_trans_huge(orig_pmd) || pmd_devmap(orig_pmd)) {
      if (pmd_protnone(orig_pmd) && vma_is_accessible(vma))
        return do_huge_pmd_numa_page(&vmf, orig_pmd); // TODO 处理内容

      if (dirty && !pmd_write(orig_pmd)) {
        ret = wp_huge_pmd(&vmf, orig_pmd);
        if (!(ret & VM_FAULT_FALLBACK))
          return ret;
      } else {
        huge_pmd_set_accessed(&vmf, orig_pmd);
        return 0;
      }
    }
  }

  return handle_pte_fault(&vmf);
}
```

#### copy_from_user
从这里看，copy_from_user 和 copy_to_user 并不是检查 vma 的方法，而是和架构实现息息相关, TODO
https://stackoverflow.com/questions/8265657/how-does-copy-from-user-from-the-linux-kernel-work-internally


```c
ssize_t cdev_fops_write(struct file *flip, const char __user *ubuf,
                        size_t count, loff_t *f_pos)
{
    unsigned int *kbuf;
    copy_from_user(kbuf, ubuf, count);
    printk(KERN_INFO "Data: %d",*kbuf);
}
```
ubuf 用户提供的指针，在执行该函数的时候，当前的进程地址空间就是该用户的，所以使用 ubuf 并不需要什么奇怪的装换。


1. copy_from_user 和 copy_to_user


```c
size_t iov_iter_copy_from_user_atomic(struct page *page,
    struct iov_iter *i, unsigned long offset, size_t bytes)
{
  char *kaddr = kmap_atomic(page), *p = kaddr + offset;
  if (unlikely(!page_copy_sane(page, offset, bytes))) {
    kunmap_atomic(kaddr);
    return 0;
  }
  if (unlikely(iov_iter_is_pipe(i) || iov_iter_is_discard(i))) {
    kunmap_atomic(kaddr);
    WARN_ON(1);
    return 0;
  }
  iterate_all_kinds(i, bytes, v,
    copyin((p += v.iov_len) - v.iov_len, v.iov_base, v.iov_len),
    memcpy_from_page((p += v.bv_len) - v.bv_len, v.bv_page,
         v.bv_offset, v.bv_len),
    memcpy((p += v.iov_len) - v.iov_len, v.iov_base, v.iov_len)
  )
  kunmap_atomic(kaddr);
  return bytes;
}
EXPORT_SYMBOL(iov_iter_copy_from_user_atomic);
```

## mm_struct
- [ ] 并不是所有的进程存在 mm_struct 的, 应该是 kernel thread ?
```c
  for_each_process (g) {
    if(g->mm)
      pr_debug("%s ---> %lx %lx\n", g->comm, g->mm->mmap_base, g->mm->start_stack);
    else
      pr_debug("%s doesn't have mm\n", g->comm);
  }
```

## mmap
- [ ] io uring, mmap 的时候需要传入 MAP_POPULATE 参数，以防止内存被 page fault。
- [ ] https://github.com/edsrzf/mmap-go : 我们应该使用类似的方法来实现一个 C 语言版本，在 mmap 区域放置汇编代码

// TODO
1. 为什么其中的 file_operations::mmap 和 mmap 的关系是什么 ?
2. 找到 pgfault 命中到错误的位置的时候，但是范围外面，并且是如何告知用户的 ? 使用信号机制吗 ?
3. 据说其中包含了各种 vma 操纵函数，整理一下

```c
static unsigned long myfs_mmu_get_unmapped_area(struct file *file,
    unsigned long addr, unsigned long len, unsigned long pgoff,
    unsigned long flags)
{
  return current->mm->get_unmapped_area(file, addr, len, pgoff, flags);
}

const struct file_operations ramfs_file_operations = {
  .get_unmapped_area  = ramfs_mmu_get_unmapped_area, // 不是非常理解啊 !
};
```

在 do_mmap 中间的各种代码都是非常简单的，但是唯独这一行理解不了:
```c
  /* Obtain the address to map to. we verify (or select) it and ensure
   * that it represents a valid section of the address space.
   */
  addr = get_unmapped_area(file, addr, len, pgoff, flags);
```

- [x] 在 dune 的分析的时候，通过 mmap 是返回一个地址的，这个地址应该是 guest physical address，
也就是 HVA，无论是系统发送过去，从内核的角度分析，其不在乎是哪个 guest 发送的,
guest 发送的时候首先会进入到 host 中间，然后调用 syscall.
- [ ] 其实可以在进行 vmcall syscall 的时候，可以首先对于 GVA 到 GVA 之间装换

- [ ] 调查一下 mmap 如何返回用户地址的


- [ ] check flag of `MAP_HUGETLB`
```c
static void * do_mapping(void *base, unsigned long len)
{
  void *mem;

  mem = mmap((void *) base, len,
       PROT_READ | PROT_WRITE,
       MAP_FIXED | MAP_HUGETLB | MAP_PRIVATE |
       MAP_ANONYMOUS, -1, 0);

  if (mem != (void *) base) {
    // try again without huge pages
    mem = mmap((void *) base, len,
         PROT_READ | PROT_WRITE,
         MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS,
         -1, 0);
    if (mem != (void *) base)
      return NULL;
  }

  return mem;
}
```

- [ ]

#### brk

- [x] what's `[heap]` in `cat /proc/self/maps`
```
5587dad41000-5587dad62000 rw-p 00000000 00:00 0                          [heap]
```
answer: https://stackoverflow.com/questions/17782536/missing-heap-section-in-proc-pid-maps


- [ ] what's difference of brk and mmap ? So what's are the simplifications and extra of brk ?

#### mmap layout
- [ ] `mm_struct::mmap_base`
  - [ ] setup_new_exec()

- [ ] `mm_struct::stack_start`, discuss it ./mm/stack.md

```c
    // --------- huxueshi : just statistics of memory size -------------------
    unsigned long hiwater_rss; /* High-watermark of RSS usage */
    unsigned long hiwater_vm;  /* High-water virtual memory usage */

    unsigned long total_vm;    /* Total pages mapped */
    unsigned long locked_vm;   /* Pages that have PG_mlocked set */
    atomic64_t    pinned_vm;   /* Refcount permanently increased */
    unsigned long data_vm;     /* VM_WRITE & ~VM_SHARED & ~VM_STACK */
    unsigned long exec_vm;     /* VM_EXEC & ~VM_WRITE & ~VM_STACK */
    unsigned long stack_vm;    /* VM_STACK */

    // --------- huxueshi : vm flags for all vma, mainly used for mlock -------------------
    unsigned long def_flags;

    spinlock_t arg_lock; /* protect the below fields */
    unsigned long start_code, end_code, start_data, end_data;
    unsigned long start_brk, brk, start_stack;
    unsigned long arg_start, arg_end, env_start, env_end;
```

- [ ] so why we need these start and end ?


`arch/x86/mm/mmap.c:arch_pick_mmap_layout`
1. register get_unmapped_area `mm->get_unmapped_area = arch_get_unmapped_area;`
2. choose from `mmap_base` and `mmap_legacy_base`

[mmap_base](https://unix.stackexchange.com/questions/407204/program-stack-size) is top of mmap.

All right, heap grows up, mmap grows down, and stack grows down, like [this](https://lwn.net/Articles/91829/).
![](https://static.lwn.net/images/ns/kernel/mmap2.png)

- [ ] why I need `mmap_base` to `get_unmapped_area()`
#### page walk
![](https://static.lwn.net/images/ns/kernel/four-level-pt.png)

// 总结一下 pagewalk.c 中间的内容
// mincore.c 基本是利用 pagewalk.c 实现的

// TODO 其实存在很多位置走过一遍 page walk，只要需要修改 page table 的需要进行 page walk:
1. vmemmap 的填充
2. rmap
3. gup

check it 这几个概念 :
https://stackoverflow.com/questions/8708463/difference-between-kernel-virtual-address-and-kernel-logical-address

**还有非常重要的特点，那就是只要设计到 page walk，至少 2000 行**
#### process vm access
// 不同进程地址空间直接拷贝

## compaction
https://linuxplumbersconf.org/event/2/contributions/65/attachments/15/171/slides-expanded.pdf

- [ ] https://www.cnblogs.com/Linux-tech/p/13326565.html


1. 请问 isolation 和 compaction 有关联吗 ? 为什么会存在 isolation.c 这个文件啊
2. 无论是 page reclaim 还是 compaction 都是内存分配不足，需要采取的措施。非常怀疑，page compaction 和 page reclaim 的代码是对称的 ?
    1. 工作的范围 : zone
    2. 触发机制 : daemon + direct 触发

守护进程需要处理的问题在于 ：
1. 什么时候启动
2. 做到什么程度收手

共同的问题:
1. 选择那些 page 进行处理

第一种情况 : 直接触发
```c
/**
 * try_to_compact_pages - Direct compact to satisfy a high-order allocation
 * @gfp_mask: The GFP mask of the current allocation
 * @order: The order of the current allocation
 * @alloc_flags: The allocation flags of the current allocation
 * @ac: The context of current allocation
 * @prio: Determines how hard direct compaction should try to succeed
 *
 * This is the main entry point for direct page compaction.
 */
enum compact_result try_to_compact_pages(gfp_t gfp_mask, unsigned int order,
    unsigned int alloc_flags, const struct alloc_context *ac,
    enum compact_priority prio, struct page **capture)
```
1. try_to_compact_pages : 根据 alloc_context 提供的 zonelist 循环调用 compact_zone_order
2. compact_zone_order : 组装 compact_control，然后调用 compact_zone


第二种情况 : 守护进程

```c
/*
 * The background compaction daemon, started as a kernel thread
 * from the init process.
 */
static int kcompactd(void *p)
```

共同到达的情况: compact_zone_order 和 kcompactd_do_work 分别是 direct 和 kthread 两种情况，组装 compact_control 和 capture_control
然后调用 compact_zone.


compact_zone 的核心是调用 :
```c
  while ((ret = compact_finished(cc)) == COMPACT_CONTINUE) {
    // 通过 isolate_migratepages 确定需要搬动的 pages
    switch (isolate_migratepages(cc)) {

    }

    // 将收集到的 cc->migratepages 进行搬迁 cc->freepages 中间去
    err = migrate_pages(&cc->migratepages, compaction_alloc,
        compaction_free, (unsigned long)cc, cc->mode,
        MR_COMPACTION);
  }
```

isolate_migratepages 和 isolate_freepages 存在什么区别 ? 很类似，但是 isolate_freepages 似乎是在 isolate_migratepages 的基础上进行的。
// TODO 无论如何，可以非常清晰的知道，isolate_migratepages 就是 compaction 的核心
// 可以解释 : 到底如何扫描 memblock ，从 memblock 中间找到 free page


- [x] what's criteria to isolate page ?

alloc_contig_range => `__alloc_contig_migrate_range` => isolate_migratepages_range => isolate_migratepages_block

in function `isolate_migratepages_block()`, the answer hides.


[LoyenWang](https://www.cnblogs.com/LoyenWang/p/11746357.html)

memory compaction就是通过将正在使用的可移动页面迁移到另一个地方以获得连续的空闲页面的方法。针对内存碎片，内核中定义了migrate_type用于描述迁移类型：
- **`MIGRATE_UNMOVABLE`：不可移动，对应于内核分配的页面；**
- **`MIGRATE_MOVABLE`：可移动，对应于从用户空间分配的内存或文件；**
- **`MIGRATE_RECLAIMABLE`：不可移动，可以进行回收处理；**

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191027000343268-2022062663.png)


```c
/*
 * Determines how hard direct compaction should try to succeed.
 * Lower value means higher priority, analogically to reclaim priority.
 */
enum compact_priority {
  COMPACT_PRIO_SYNC_FULL,
  MIN_COMPACT_PRIORITY = COMPACT_PRIO_SYNC_FULL,
  COMPACT_PRIO_SYNC_LIGHT,
  MIN_COMPACT_COSTLY_PRIORITY = COMPACT_PRIO_SYNC_LIGHT,
  DEF_COMPACT_PRIORITY = COMPACT_PRIO_SYNC_LIGHT,
  COMPACT_PRIO_ASYNC,
  INIT_COMPACT_PRIORITY = COMPACT_PRIO_ASYNC
};
```
本结构用于描述memory compact的几种不同方式：
- COMPACT_PRIO_SYNC_FULL/MIN_COMPACT_PRIORITY：最高优先级，压缩和迁移以同步的方式完成；
- COMPACT_PRIO_SYNC_LIGHT/MIN_COMPACT_COSTLY_PRIORITY/DEF_COMPACT_PRIORITY：中优先级，压缩以同步方式处理，迁移以异步方式处理；
- COMPACT_PRIO_ASYNC/INIT_COMPACT_PRIORITY：最低优先级，压缩和迁移以异步方式处理。


```c
/* Return values for compact_zone() and try_to_compact_pages() */
/* When adding new states, please adjust include/trace/events/compaction.h */
enum compact_result {
  /* For more detailed tracepoint output - internal to compaction */
  COMPACT_NOT_SUITABLE_ZONE,
  /*
   * compaction didn't start as it was not possible or direct reclaim
   * was more suitable
   */
  COMPACT_SKIPPED,
  /* compaction didn't start as it was deferred due to past failures */
  COMPACT_DEFERRED,

  /* compaction not active last round */
  COMPACT_INACTIVE = COMPACT_DEFERRED,

  /* For more detailed tracepoint output - internal to compaction */
  COMPACT_NO_SUITABLE_PAGE,
  /* compaction should continue to another pageblock */
  COMPACT_CONTINUE,

  /*
   * The full zone was compacted scanned but wasn't successfull to compact
   * suitable pages.
   */
  COMPACT_COMPLETE,
  /*
   * direct compaction has scanned part of the zone but wasn't successfull
   * to compact suitable pages.
   */
  COMPACT_PARTIAL_SKIPPED,

  /* compaction terminated prematurely due to lock contentions */
  COMPACT_CONTENDED,

  /*
   * direct compaction terminated after concluding that the allocation
   * should now succeed
   */
  COMPACT_SUCCESS,
};
```

- [ ] compact_zone and try_to_compact_pages
  - [ ] compact_zone_order => compact_zone

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191027000443984-614132434.png)

```c
/*
 * MIGRATE_ASYNC means never block
 * MIGRATE_SYNC_LIGHT in the current implementation means to allow blocking
 *  on most operations but not ->writepage as the potential stall time
 *  is too significant
 * MIGRATE_SYNC will block when migrating pages
 * MIGRATE_SYNC_NO_COPY will block when migrating pages but will not copy pages
 *  with the CPU. Instead, page copy happens outside the migratepage()
 *  callback and is likely using a DMA engine. See migrate_vma() and HMM
 *  (mm/hmm.c) for users of this mode.
 */
enum migrate_mode {
  MIGRATE_ASYNC,
  MIGRATE_SYNC_LIGHT,
  MIGRATE_SYNC,
  MIGRATE_SYNC_NO_COPY,
};
```


- `compaction_suitable()`: one of caller is `compact_zone`, test whether a zone is suitable for compaction, if not, just return.

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191027000514160-767100004.png)
1. 除去申请的页面，空闲页面数将低于水印值，或者虽然大于等于水印值，但是没有一个足够大的空闲页块；
2. 空闲页面减去两倍的申请页面（两倍表明有足够多的的空闲页面作为迁移目标），高于水印值；
3. 申请的order大于PAGE_ALLOC_COSTLY_ORDER时，计算碎片指数fragindex，根据值来判断；

- [ ] I skip this part, may read it carefully

#### compact deferred

```c
struct zone {
...
  /*
   * On compaction failure, 1<<compact_defer_shift compactions
   * are skipped before trying again. The number attempted since
   * last failure is tracked with compact_considered.
   */
  unsigned int    compact_considered; //记录推迟次数
  unsigned int    compact_defer_shift; //（1 << compact_defer_shift）=推迟次数，最大为6
  int                compact_order_failed; //记录碎片整理失败时的申请order值
...
};
```

![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191027000559199-1665601872.png)

## tlb
x86/mm/tlb.c

## hugetlb
- [ ] https://lwn.net/Articles/839737/

1. 为了实现简单，那么 hugetlb 减少处理什么东西 ?

https://www.ibm.com/developerworks/cn/linux/l-cn-hugetlb/
https://www.ibm.com/developerworks/cn/linux/1305_zhangli_hugepage/index.html

总结一下 :
1. subpool, resv_map , enqueue 机制
2. hugetlb_file_setup hugetlb_fault 和对外提供的关键接口
3. 利用 sys 提供了很多接口

Huge pages can improve performance through reduced page faults (a single fault brings in a large chunk of memory at once) and by reducing the cost of virtual to physical address translation (fewer levels of page tables must be traversed to get to the physical address).

用户层 : https://lwn.net/Articles/375096/ 中间的使用首先理解清楚吧 !

https://github.com/libhugetlbfs/libhugetlbfs
> 其中包含有大量的测试
The library provides support for automatically backing text, data, heap and shared memory segments with huge pages.
In addition, this package also provides a programming API and manual pages. The behaviour of the library is controlled by environment variables (as described in the libhugetlbfs.7 manual page) with a launcher utility hugectl that knows how to configure almost all of the variables. hugeadm, hugeedit and pagesize provide information about the system and provide support to system administration. tlbmiss_cost.sh automatically calculates the average cost of a TLB miss. cpupcstat and oprofile_start.sh provide help with monitoring the current behaviour of the system. Manual pages are available describing in further detail each utility.

1. shmget() : SHM_HUGETLB
2. hugetlbfs : 似乎用户共享的，同时可以用于实现

```c
       #include <hugetlbfs.h>
       int hugetlbfs_unlinked_fd(void);
       int hugetlbfs_unlinked_fd_for_size(long page_size);
       // hugetlbfs_unlinked_fd, hugetlbfs_unlinked_fd_for_size - Obtain a file descriptor for a new unlinked file in hugetlbfs
```
> 实在是不知道 hugetlbfs 的作用是什么 ?


One important common point between them all is how huge pages are faulted and when the huge pages are allocated.
Further, there are important differences between shared and private mappings depending on the exact kernel version used. [^1]
> 重点处理的方面

1. fault
2. shared/private
3. hugetlb 不处理 swap，所以到底如何


为什么使用 superpages 无法在内核中间自动化部署，而需要用户自行配置 ?
显然，内核缺少必要的信息做决断，而这些信息是用户层次才具有的(内核在初始化的时候，会使用hugetlb 来映射内核的代码段数据段吗 ?)
1. 内核无法判断使用 hugepage 是否可以抵消维护 metadata 的开销。
2. Second, there can be architectural limitations that prevent a different page size being used within an address range once one page has been inserted.
3. TLB 的结构差异让内核无法确定使用多少hugepage


和正常大小的 page 的比较
1. hugetlb_fault

2. include/asm-generic/hugetlb.h : 如果架构含有关于 page table 的不同处理，
那么就可以使用

- [ ] 了解一下，从 mmap 的进入到 hugetlb
  - [ ] 似乎还可以在 hugetlb 的文件系统中间创建文件，然后 open ?

[HugeTLB Pages](https://www.kernel.org/doc/html/latest/admin-guide/mm/hugetlbpage.html) 的阅读结果 ：

- [ ] /proc/meminfo /proc/sys/vm/nr_hugepages /proc/sys/vm/nr_overcommit_hugepages /sys/kernel/mm/hugepages /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/ /sys/kernel/
/sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 都是一些什么东西 :
检查以下这些参数的作用
  - [ ] /proc/meminfo 的 HugePages_Rsvd 的含义是什么 ? 下面的代码，为什么不会导致 HugePages_Free 减少，而是 HugePages_Rsvd 增加
```c
#include <stdio.h>
#include <stdlib.h> // malloc
#include <sys/mman.h>
#include <asm/mman.h>
#include <sys/types.h>
#include <unistd.h> // sleep

int main(int argc, char *argv[]) {
  size_t SIZE_2M = 1 << 21;
  char *addr = (char *)mmap(0, SIZE_2M, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE | MAP_HUGETLB, -1, 0);
  if (addr == MAP_FAILED) {
    perror("mmap");
    exit(1);
  }
  for (int i = 0; i < SIZE_2M; ++i) {
    addr[i] = 'a';
  }
  sleep(100);
  return 0;
}
```



> /proc/sys/vm/nr_hugepages indicates the current number of “persistent” huge pages in the kernel’s huge page pool. “Persistent” huge pages will be returned to the huge page pool when freed by a task. A user with root privileges can dynamically allocate more or free some persistent huge pages by increasing or decreasing the value of nr_hugepages.
>
> Pages that are used as huge pages are reserved inside the kernel and **cannot** be used for other purposes. Huge pages cannot be swapped out under memory pressure.
>
> Once a number of huge pages have been pre-allocated to the kernel huge page pool, a user with appropriate privilege can use either the mmap system call or shared memory system calls to use the huge pages.

- [ ]
- [ ] 是不是没有 preallocated 的 page 会导致分配失败 ？

**TO BE CONTINUE**
- [ ] 这个文档还是没有看完的，感觉 hugetlb 设计有点问题
- [ ] issue #14 的检查一下


## compound page
- [An introduction to compound pages](https://lwn.net/Articles/619514/)
> A compound page is simply a grouping of two or more physically contiguous pages into a unit that can, in many ways, be treated as a single, larger page. They are most commonly used to create huge pages, used within hugetlbfs or the transparent huge pages subsystem, *but they show up in other contexts as well*. *Compound pages can serve as anonymous memory or be used as buffers within the kernel*; *they cannot, however, appear in the page cache, which is only prepared to deal with singleton pages.*

- [x] so why page cache is only prepared to deal with singleton pages ? I think it's rather reasonable to use huge page as backend for page cache.
  - https://lwn.net/Articles/619738/ suggests page cache can use thp too.


- [ ] find the use case the compound page is buffer within the kernel
- [ ] 是不是 compound_head 出现的位置，就是和 huge memory 相关的 ?

> Allocating a compound page is a matter of calling a normal memory allocation function like alloc_pages() with the `__GFP_COMP` allocation flag set and an order of at least one
> The difference is that creating a compound page involves the creation of a fair amount of metadata; much of the time, **that metadata is unneeded so the expense of creating it can be avoided.**

> Let's start with the page flags. The first (normal) page in a compound page is called the "head page"; it has the PG_head flag set. All other pages are "tail pages"; they are marked with PG_tail. At least, that is the case on systems where page flags are not in short supply — 64-bit systems, in other words. On 32-bit systems, there are no page flags to spare, so a different scheme is used; all pages in a compound page have the PG_compound flag set, and the tail pages have PG_reclaim set as well. The PG_reclaim bit is normally used by the page cache code, but, since compound pages cannot be represented in the page cache, that flag can be reused here.
>
> Head and tail pages can be distinguished, should the need arise, with PageHead() and PageTail().

- [ ] verify the complications in 32bit in PageHead() and PageTail()

> Every tail page has a pointer to the head page stored in the `first_page` field of struct page. This field occupies the same storage as the private field, the spinlock used when the page holds page table entries, or the slab_cache pointer used when the page is owned by a slab allocator. The `compound_head()` helper function can be used to find the head page associated with any tail page.

- [ ] 了解一下函数 : PageTransHuge，以及附近的定义，似乎 hugepagefs 和 transparent hugepage 谁采用使用 compound_head 的

- [Minimizing the use of tail pages](https://lwn.net/Articles/787388/)

- [] read the article

## THP
- [ ] PageDoubleMap
- [ ] THP only support PMD ? so can it support more than 2M space (21bit) ?
- [ ] https://gist.github.com/shino/5d9aac68e7ebf03d4962a4c07c503f7d, check references in it
- [ ] 提供的硬件支持是什么 ?
    - [ ] 除了在 pml4 pud pmd 的 page table 上的 flags
        - [ ] /sys/kernel/mm/transparent_hugepage/hpage_pmd_size 的含义看，实际上，内核只是支持一共大小的 hugepage
    - [ ] 需要提供 TLB 知道自己正在访问虚拟地址是否被 hugetlb 映射

transparent hugepage 和 swap 是相关的
使用 transparent hugepage 的原因:
1. TLB 的覆盖更大，可以降低TLB miss rate
2. page fault 的次数更少，可以忽略不计
3. hugepage 的出现让原先的 page walk 的路径变短了

几个 THP 需要考虑的核心问题:
1. swap
2. reference 的问题
3. split 和 merge


#### THP admin manual
[用户手册](https://www.kernel.org/doc/html/latest/admin-guide/mm/transhuge.html)

The THP behaviour is controlled via `sysfs` interface and using `madvise(2)` and `prctl(2)` system calls.

- [ ] how madvise and prctl control the THP

Currently THP **only works for** anonymous memory mappings and tmpfs/shmem. But in the future it can expand to other filesystems.

- [ ] so page cache can't work with THP ?

THP 相对于 hugetlbfs 的优势:
- Transparent Hugepage Support maximizes the usefulness of free memory if compared to the reservation approach of hugetlbfs by allowing all unused memory to be used as cache or other movable (or even unmovable entities).
- It doesn’t require reservation to prevent hugepage allocation failures to be noticeable from userland. *It allows paging and all other advanced VM features to be available on the hugepages.*
- It requires no modifications for applications to take advantage of it.

- [x] 在 hugepage 上可以使用 paging 等 advanced VM feaures. ( Paging is a mechanism that translates a linear memory address to a physical address.)
    - [x] paging sometimes meaning page fault

interface in sysfs :
1. /sys/kernel/mm/transparent_hugepage : always madvise never
2. /sys/kernel/mm/transparent_hugepage/defrag : always defer defer + madvise madvise never
3. You can control hugepage allocation policy in tmpfs with mount option huge=. It can have following values: always never advise deny force

- [ ] 应该按照手册，将手册中间的说明在内核中间一个个的找到
  - [ ] /sys/kernel/mm/transparent_hugepage
    - [ ] always 指的是任何位置都需要 hugepage 处理吗?
  - [ ] /sys/kernel/mm/transparent_hugepage/defrag 的 always 无法理解，或者说，什么时候应该触发 defrag, 不是分配的时候就是决定了吗 ?
- [ ] THP has to defrag pages, so check the compaction.c and find out how thp deal with it !
  - [ ] how defrag wake kcompactd ?

- [x] mmap 添加上 hugepage 的参数，是不是几乎等价于普通 mmap，然后 madvice
  - 不是，一个是 madvise， 一个是 thp

#### THP kernel
- mmap 和配合 hugetlb 使用的

- [ ] huge_memory.c 用于处理 split 和 各种参数
- [ ] khugepaged.c 用于 scan page 将 base page 转化为 hugepage

- [ ] 本 section 分析一般的 kernel 问题

- [ ] 内核态分析: 透明的性质在于 `__handle_mm_fault` 中间就开始检查是否可以 由于 hugepage 会修改 page walk ，所以 pud_none 和 `__transparent_hugepage_enabled`
  - [ ] 检查更多的细节


- [ ] 从 madvise 到启动 THP
    - [ ] hugepage_vma_check : 到底那些 memory 不适合 thp
    - [x] `__khugepaged_enter` : 将所在的 mm_struct 放到 list 上，等待之后 khugepaged 会将该区域清理赶紧

- [ ] collapse_file : 处理 page cache / shmem / tmpfs
  - [ ] *caller*
      - [ ] khugepaged_scan_file
          - [ ] khugepaged_scan_mm_slot

- [ ] /sys/kernel/mm/transparent_hugepage 的真正含义 ?
    - [x] khugepaged_enter : 这是判断是否将该区域用于 transparent 的开始位置，[Transparent huge pages for filesystems](https://lwn.net/Articles/789159/) 中来看，现在支持 THP 只有 transparent hugepage 和 tmp memory 了
        - [x] do_huge_pmd_anonymous_page : 在 page fault 的时候，会首先进行 hugepage 检查，如果是 always, 那么**所有的 vma 都会被转换为 transparent hugepage**
            - [x] create_huge_pmd <= `__handle_mm_fault`

- [ ] 好吧，transparent hugepage 只是支持 pmd(从 /proc/meminfo 的 HugePagesize 和 /sys/kernel/mm/transparent_hugepage/hpage_pmd_size)，但是实际上 pud 也是支持的.

关键问题 A : do_huge_pmd_anonymous_page
1. 检查是否 vma 中间是否可以容纳 hugepage
2. 假如可以使用 zero page 机制
3. 利用 alloc_hugepage_direct_gfpmask 计算出来 buddy allocator 处理分配 hugepage 的找不到之后的策略，到底是等待，还是立刻失败，还是
4. prep_transhuge_page @todo 不知道干嘛的
5. `__do_huge_pmd_anonymous_page` : 将分配的 page 和 page table 组装
> 1. 进行分配的核心在于 : mempolicy.c 中间

关键问题 B : split_huge_page_to_list

不关键问题 A : vm_operations_struct::huge_fault 和 DAX 的关系不一般
不关键问题 A2 : vm_operations_struct 几乎没有一个可以理解的

khugepaged.c 中间的 hugepage 守护进程的工作是什么 ?

[Transparent huge page reference counting](https://lwn.net/Articles/619738/)

> In particular, he has eliminated the hard separation between normal and huge pages in the system. In current kernels, a specific 4KB page can be treated as an individual page, or it can be part of a huge page, but not both. If a huge page must be split into individual pages, it is split completely for all users, the compound page structure is torn down, and the huge page no longer exists. The fundamental change in Kirill's patch set is to allow a huge page to be split in one process's address space, while remaining a huge page in any other address space where it is found.

- [ ] what's the flag in PMD page table entry used to suggest the page is huge page ? verify it in intel manual.

- [ ] page_trans_huge_mapcount
- [ ] total_mapcount

[Transparent huge pages for filesystems](https://lwn.net/Articles/789159/)

> It is using the [Binary Optimization and Layout Tool (BOLT)](https://github.com/facebookincubator/BOLT) to profile its code in order to identify the hot functions. Those functions are collected up into an 8MB region in the generated executable.


// ------------- split huge page ---------------- begin

// ------------- split huge page ---------------- end


#### THP khugepaged
- [ ] if `kcompactd` compact pages used by hugepage, and defrag pages by `split_huge_page_to_list`, so what's the purpose of khugepaged ?

1. /sys/kernel/mm/transparent_hugepage/enabled => start_stop_khugepaged => khugepaged => khugepaged_do_scan => khugepaged_scan_mm_slot => khugepaged_scan_pmd
2. in `khugepaged_scan_pmd`, we will check pages one by one, if enough base pages are found,  call `collapse_huge_page` to merge base page to huge page
3. `collapse_huge_page` = `khugepaged_alloc_page` + `__collapse_huge_page_copy` + many initialization for huge page + `__collapse_huge_page_isolate` (free base page)

- [x] it seems khugepaged scan pages and collapse it into huge pages, so what's difference between kcompactd
  - khugepaged is consumer of hugepage, it's scan base pages and collapse them
  - [ ] khugepaged 是用于扫描 base page 的 ? It’s the responsibility of khugepaged to then install the THP pages.

#### THP split
这几个文章都是讲解两种方案，很烦!
[Transparent huge pages in the page cache](https://lwn.net/Articles/686690/)
> Finally, a file may be used without being mapped into process memory at all, while anonymous memory is always mapped. So any changes to a filesystem to support transparent huge page mapping must not negatively impact normal read/write performance on an unmapped file.

- [x] 无论是在内核态和用户态中间，一个 huge page 都是可以随意拆分的，在用户态每个人都是不同的映射。在内核态，总是线性映射，pmd page table entry 的修改其实没有任何意义。
- [x] swap cache 的实现根本挑战在于区间的可以随意变化

[Improving huge page handling](https://lwn.net/Articles/636162/)

[Transparent huge page reference counting](https://lwn.net/Articles/619738/)
> In many other situations, Andrea placed a call to split_huge_page(), a function which breaks a huge page down into its component small pages.

> In other words, if split_huge_page() could be replaced by a new function, call it split_huge_pmd(), that would only split up a single process's mapping of a huge page, code needing to deal with individual pages could often be accommodated while preserving the benefits of the huge page for other processes. But, as noted above, the kernel currently does not support different mappings of huge pages; all processes must map the memory in the same way. This restriction comes down to how various parameters — reference counts in particular — are represented in huge pages.

> it must be replaced by a scheme that can track both the mappings to the huge page as a whole and the individual pages that make up that huge page.


```c
#define split_huge_pmd(__vma, __pmd, __address)       \
  do {                \
    pmd_t *____pmd = (__pmd);       \
    if (is_swap_pmd(*____pmd) || pmd_trans_huge(*____pmd) \
          || pmd_devmap(*____pmd))  \
      __split_huge_pmd(__vma, __pmd, __address, \
            false, NULL);   \
  }  while (0)
```

- [ ] split_huge_page_to_list
  - [ ] ` __split_huge_page` : 不对劲，似乎 hugepage 只是体现在 struct page 上，而没有体现在 pmd 上
      - [x] 在 huge page 中间拆分出来几个当做其他的 page 正常使用, 虽然从中间抠出来的页面不可以继续当做内核，但是可以给用户使用
          - [ ] 是否存在 flag 说明那些页面可以分配给用户，那些是内核 ?



- [ ] `__split_huge_pmd` : 处理各种 lock 包括 pmd_lock
  - [ ] `__split_huge_pmd_locked`
    - 取回 pmd_huge_pte，向其中填充 pte, 然后将 pmd entry 填充该位置
  - `pgtable_t page::(anonymous union)::(anonymous struct)::pmd_huge_pte`
      - [ ]  从 `__split_huge_pmd_locked` 的代码: `pgtable_trans_huge_withdraw` 看，这一个 page table 从来没有被删除过

## page cache
1. 对于数据库，为什么需要绕过 page cache
https://www.scylladb.com/2018/07/26/how-scylla-data-cache-works/
2. 当一个文件被关闭之后，其 page cache 会被删除吗 ?
3. 当一个设备被 umount 的时候，其关联的所有的数据需要全部落盘，找到对应实现的代码！


| aspect | page cache             | cache                    |
|--------|------------------------|--------------------------|
| why    | cache disk             | cache memroy             |
| evict  | lru by software        | lru by hardware          |
| locate | radix tree             | physical address and tag |
| dirty  | page writeback control | cache coherency          |

page cache 处理:
1. page cache 位于 vfs 和 fs 之间
    1. file_operations : 处理 vfs 到 page cache 之间的:
        1. @todo 有什么需要做的: 维护读写文件的各种动态信息
    2. address_space_operations :
        1. @todo 将工作交给 buffer.c

2. page cache 内部处理: **可不可以说，其实 page cache 是内存的提供给文件系统的一个工具箱和接口，而文件系统需要利用这个工具箱完成其任务**
    1. radix tree : 基本功能直接使用就可以了 filemap.c
    3. dirty : page-writeback.c fs-writeback.c
    4. page reclaim : vmscan.c
或者说，可以使用 page cache，但是需要处理好。
上面说过的，处理的位置 :
file_operations::write :: write 的 将 page 标记为 dirty，告诉 page reclaim 机制写过的 page 如何
address_space_operations::write 的 将 page 标记为 dirty



解释几个问题:
1. 从 file_operations::write_iter 如何进入到 address_space_operations::wreitepage: 其实这个问题就是向知道，文件系统如何穿过 page cache

generic_file_write_iter => `__generic_file_write_iter` => generic_perform_write

generic_perform_write 的流程:
```c
a_ops->write_begin
iov_iter_copy_from_user_atomic
a_ops->write_end
```
使用 ext2 作为例子:
ext2_write_begin => block_write_begin // 进入到 buffer.c 中间
  1. grab_cache_page_write_begin : Find or create a page at the given pagecache position. Return the locked page. This function is specifically for buffered writes.
      1. pagecache_get_page : 可以找到就返回 page cache 中间的 page，找不到就创建 page cache
  2. `__block_write_begin` : `__block_write_begin_int` 将需要读取的 block 读入到 page cache 中间
ext2_write_end => block_write_end => `__block_commit_write` : set_buffer_uptodate 和 mark_buffer_dirty 更新一下状态

而 file_operations::wreitepage 的实现:
ext2_writepage => block_write_full_page => `__block_write_full_page` : 将 dirty buffer 写回
其调用位置在 page-writeback.c 和 fs-writeback.c 中间。

所以，file_operations::write_iter 首先将 page 写入到 page cache 中间，
在 buffer.c 中间，ll_rw_block 会读取由于没有 block 需要加载的 disk 页面，并且初始化或者更新 buffer cache 的各种。
而写回工作，需要等到 page-writeback.c 和 fs-writeback.c 中间当 flusher 启动的时候，会调用 address_space_operations::writepage 进行
由此得出的结论 : **为了使用 page cache, fs 需要提供的两套接口，file_operations::write_begin file_operations::write_iter 加入到 page cache 中间
通过 address_space_operations::writepage 将 page 从 page cache 发送出去。**


2. 从 file_operations::read_iter => generic_file_read_iter => generic_file_buffered_read => address_space_operations::readpage


3. How `__x64_sys_write` ==> file_operations::write_iter ?

(hint: read_write.c)


- [ ] trace it : pagecache_write_begin

## address_space


## address_space_operations
address_space 和 address_space_operations
// TODO 整理解释其中每一个内容
1. 能够区分 writepage 和 write_begin/write_end 之间的关系是什么 ?
2. freepage 和 releasepage 的关系

```c
struct address_space_operations {
  int (*writepage)(struct page *page, struct writeback_control *wbc);
  int (*readpage)(struct file *, struct page *);

  /* Write back some dirty pages from this mapping. */
  int (*writepages)(struct address_space *, struct writeback_control *);

  /* Set a page dirty.  Return true if this dirtied it */
  int (*set_page_dirty)(struct page *page);

  /*
   * Reads in the requested pages. Unlike ->readpage(), this is
   * PURELY used for read-ahead!.
   */
  int (*readpages)(struct file *filp, struct address_space *mapping,
      struct list_head *pages, unsigned nr_pages);

  int (*write_begin)(struct file *, struct address_space *mapping,
        loff_t pos, unsigned len, unsigned flags,
        struct page **pagep, void **fsdata);
  int (*write_end)(struct file *, struct address_space *mapping,
        loff_t pos, unsigned len, unsigned copied,
        struct page *page, void *fsdata);

  /* Unfortunately this kludge is needed for FIBMAP. Don't use it */
  sector_t (*bmap)(struct address_space *, sector_t);
  void (*invalidatepage) (struct page *, unsigned int, unsigned int);
  int (*releasepage) (struct page *, gfp_t);
  void (*freepage)(struct page *);
  ssize_t (*direct_IO)(struct kiocb *, struct iov_iter *iter);
  /*
   * migrate the contents of a page to the specified target. If
   * migrate_mode is MIGRATE_ASYNC, it must not block.
   */
  int (*migratepage) (struct address_space *,
      struct page *, struct page *, enum migrate_mode);
  bool (*isolate_page)(struct page *, isolate_mode_t);
  void (*putback_page)(struct page *);
  int (*launder_page) (struct page *);
  int (*is_partially_uptodate) (struct page *, unsigned long,
          unsigned long);
  void (*is_dirty_writeback) (struct page *, bool *, bool *);
  int (*error_remove_page)(struct address_space *, struct page *);

  /* swapfile support */
  int (*swap_activate)(struct swap_info_struct *sis, struct file *file,
        sector_t *span);
  void (*swap_deactivate)(struct file *file);
};
```

- [ ] fgp_flags : just flags, it seems find a page in pagecache and swap cache is more tricky than expected
  - [ ] find_get_page
  - [ ] pagecache_get_page

#### page writeback
1. fs-writeback.c 和 page-writeback 的关系是上下级的，但是实际上，不是，fs-writeback.c 只是为了实现整个 inode 写回，以及 metadata 的写回。
2. page writeback 没有 flusher 机制，而是靠 flusher 机制维持生活


// TOOD http://www.wowotech.net/memory_management/327.html
里面的配图，让人感到不安:
虽然，后面 workqueue 相关的内容基本都是错误的，但是到达的路线基本都是正确的
1. laptop_mode 无法解释
2. 居然将 page reclaim 的


// TODO 的内容
9. 搞清楚 fs-writeback 和 page-writeback 各自的作用
    1. laptop_mode 的含义
    2. radix tag 的作用
    3. ratio 的触发
    4. diff 的整理
        1. wb_wakeup_delayed : 看上去是 wakeup 实际上是 queue
        2. 线程都是怎么 spawn 的 以及 杀死的

// TODO
dirty page 的 flag　的操控总结一下
1. inode_operations::dirty_inode
2. vm_operations_struct::page_mkwrite
3. address_space_operations::set_page_dirty
还有让人感到绝对恶心的，page dirty flags
以及辅助函数 set_page_dirty，请问和 address_space_operations::set_page_dirty 的关系是什么

我想知道，page 如何被 dirty，以及如何被 clean ?

dirty 和 update 的关系是什么 ? 各自的管理策略是什么 ?

1. 核心写回函数
```c
int do_writepages(struct address_space *mapping, struct writeback_control *wbc)
{
  int ret;

  if (wbc->nr_to_write <= 0)
    return 0;
  while (1) {
    if (mapping->a_ops->writepages)
      ret = mapping->a_ops->writepages(mapping, wbc); // 有点窒息的地方在于，ext4 的 writepages 注册就是 generic_writepages
    else
      ret = generic_writepages(mapping, wbc); // 调用 address_space::writepage 一个个的写入
    if ((ret != -ENOMEM) || (wbc->sync_mode != WB_SYNC_ALL))
      break;
    cond_resched();
    congestion_wait(BLK_RW_ASYNC, HZ/50);
  }
  return ret;
}
```

2. 各种计算 dirty rate 以及 提供给 proc 的 handler
// 能不能搞清楚，几个 proc 的作用

3. balance_dirty_pages_ratelimited : 任何产生 dirty page 都需要调用此函数，调用位置为:
    1. fault_dirty_shared_page
    2. generic_perform_write :  被调用，`__generic_file_write_iter`，便是唯一的入口。

```c
/**
 * balance_dirty_pages_ratelimited - balance dirty memory state
 * @mapping: address_space which was dirtied
 *
 * Processes which are dirtying memory should call in here once for each page
 * which was newly dirtied.  The function will periodically check the system's
 * dirty state and will initiate writeback if needed.
 *
 * On really big machines, get_writeback_state is expensive, so try to avoid
 * calling it too often (ratelimiting).  But once we're over the dirty memory
 * limit we decrease the ratelimiting by a lot, to prevent individual processes
 * from overshooting the limit by (ratelimit_pages) each.
 */
void balance_dirty_pages_ratelimited(struct address_space *mapping)
  if (unlikely(current->nr_dirtied >= ratelimit)) // 只有超过 ratelimit 的时候才会进行真正的 balance_dirty_pages 的工作
    balance_dirty_pages(wb, current->nr_dirtied); // 很长的函数，在其中触发 fs-writeback.c 的 flusher 维持生活
```


4. `__set_page_dirty_nobuffers` : 被注册为 address_space_operations::set_page_dirty
既然 balance_dirty_pages_ratelimited 被所有的可能的 dirty 的位置注册，那么为什么需要 set_page_dirty
在 balance_dirty_pages_ratelimited 中间调用 `__set_page_dirty_nobuffers` 不就结束了 ?
其实 set_page_dirty 的真实作用是 : 让某些 page 被 writeback skip
```c
/*
 * For address_spaces which do not use buffers.  Just tag the page as dirty in
 * the xarray.
 *
 * This is also used when a single buffer is being dirtied: we want to set the
 * page dirty in that case, but not all the buffers.  This is a "bottom-up"
 * dirtying, whereas __set_page_dirty_buffers() is a "top-down" dirtying.
 *
 * The caller must ensure this doesn't race with truncation.  Most will simply
 * hold the page lock, but e.g. zap_pte_range() calls with the page mapped and
 * the pte lock held, which also locks out truncation.
 */
int __set_page_dirty_nobuffers(struct page *page)

/*
 * For address_spaces which do not use buffers nor write back.
 */
int __set_page_dirty_no_writeback(struct page *page)
{
  if (!PageDirty(page))
    return !TestSetPageDirty(page);
  return 0;
}
```

#### watermark
- [x] page writeback 如何利用 watermark 机制来触发写回的
    1. watermark 的初始化 : 根据探测的物理内存，然后确定 watermark
    2. 提供给用户调节 watermark 的机制
    3. page allocator 中间检测和触发

- [ ] file:///home/shen/Core/linux/Documentation/output/admin-guide/mm/concepts.html?highlight=watermark
内核介绍的核心概念，务必逐个分析

[LoyenWang](https://www.cnblogs.com/LoyenWang/p/11708255.html)

- `WMARK_MIN` : 内存不足的最低点，如果计算出的可用页面低于该值，则无法进行页面计数；
- `WMARK_LOW` : 默认情况下，该值为WMARK_MIN的125%，此时kswapd将被唤醒，可以通过修改watermark_scale_factor来改变比例值；
- `WMARK_HIGH` : 默认情况下，该值为WMARK_MAX的150%，此时kswapd将睡眠，可以通过修改watermark_scale_factor来改变比例值；
![](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191020172801277-1235981981.png)

**TO BE CONTINUE, read LoyenWang**


#### truncate
- [ ] 阅读一下源代码

#### readahead
// 阅读一下源代码 readahead.c 的
// 居然还存在一个 readahead syscall

请问一般的文件的 readahead 和 swap 的 readahead 存在什么区别 ?

## buffer cache
如果 fs/buffer.c 中间是完成写入工作，那么 fs/read_write.c 中间是做什么的 ?
fs/read_write.c 提供的接口是用户层的接口封装。

Buffer cache is a kernel subsystem that handles caching (both read and write) blocks from block devices. The base entity used by cache buffer is the struct buffer_head structure. The most important fields in this structure are:

- `b_data`, pointer to a memory area where the data was read from or where the data must be written to
- `b_size`, buffer size
- `b_bdev`, the block device
- `b_blocknr`, the number of block on the device that has been loaded or needs to be saved on the disk
- `b_state`, the status of the buffer

// 这些函数可以详细调查一下:
There are some important functions that work with these structures:
- `__bread()` : reads a block with the given number and given size in a buffer_head structure; in case of success returns a pointer to the buffer_head structure, otherwise it returns NULL;
- `sb_bread()` : does the same thing as the previous function, but the size of the read block is taken from the superblock, as well as the device from which the read is done;
- `mark_buffer_dirty()` : marks the buffer as dirty (sets the BH_Dirty bit); the buffer will be written to the disk at a later time (from time to time the bdflush kernel thread wakes up and writes the buffers to disk);
- `brelse()` :  frees up the memory used by the buffer, after it has previously written the buffer on disk if needed;
- `map_bh()` :  associates the buffer-head with the corresponding sector.


这两个函数有什么区别吗 ?

```c
set_buffer_dirty();
mark_buffer_dirty();
```

`ext2->writepage` 最终会调用到此处


// TODO
// nobh 的含义是什么 ?
// ext2_direct_IO 和 dax 似乎完全不是一个东西 ?
```c
const struct address_space_operations ext2_aops = {
  .readpage   = ext2_readpage,
  .readpages    = ext2_readpages,
  .writepage    = ext2_writepage,
  .write_begin    = ext2_write_begin,
  .write_end    = ext2_write_end,
  .bmap     = ext2_bmap,
  .direct_IO    = ext2_direct_IO,
  .writepages   = ext2_writepages,
  .migratepage    = buffer_migrate_page,
  .is_partially_uptodate  = block_is_partially_uptodate,
  .error_remove_page  = generic_error_remove_page,
};

const struct address_space_operations ext2_nobh_aops = {
  .readpage   = ext2_readpage,
  .readpages    = ext2_readpages,
  .writepage    = ext2_nobh_writepage,
  .write_begin    = ext2_nobh_write_begin,
  .write_end    = nobh_write_end,
  .bmap     = ext2_bmap,
  .direct_IO    = ext2_direct_IO,
  .writepages   = ext2_writepages,
  .migratepage    = buffer_migrate_page,
  .error_remove_page  = generic_error_remove_page,
};
```


## migrate
- [ ] make_migration_entry()， 看来 migrate 的类型甚至可以出现在 pte 上，看来 migrate 不是简单的复制粘贴了

1. migrate 并不是为了实现 numa 而设计的，其实在numa节点之间迁移并没有什么难度，
虽然 numa 系统在访问速度上存在区别，但是寻址空间都是同一个，
所以完成迁移的工作只是拷贝而已。
2. 为了用户可以控制分配的内存，系统调用move_pages(2) 和 migrate_pages
3. 在 migrate 实现 compaction 的基础

内核文档讲解的很清晰 : [^11]

migrate 什么类型的 page ?
1. 如果这个 page 是被内核数据，比如 page cache，inode cache 之类的 ? 应该没有办法 migrate 吧 ?
    1. 这不是透明，但是 page cache 之类的不能迁移还是太浪费了，但是需要 address_space_operations::migratepage 和 address_space_operations::isolate_page 辅助

看似只是拷贝，但是为什么写了好几千行
1. 解除一个 page 的联系，并且重新建立。
    1. page 可能在 TLB 中间，应该需要 invalid 特定地址上的 tlb
    2. page table 需要修改
2. hugepage 如何迁移 (似乎)[^10]


核心函数 A : migrate_pages 被 compaction 使用:
```c
/*
 * migrate_pages - migrate the pages specified in a list, to the free pages
 *       supplied as the target for the page migration
 *
 * @from:   The list of pages to be migrated.
 * @get_new_page: The function used to allocate free pages to be used
 *      as the target of the page migration.
 * @put_new_page: The function used to free target pages if migration
 *      fails, or NULL if no special handling is necessary.
 * @private:    Private data to be passed on to get_new_page()
 * @mode:   The migration mode that specifies the constraints for
 *      page migration, if any.
 * @reason:   The reason for page migration.
 *
 * The function returns after 10 attempts or if no pages are movable any more
 * because the list has become empty or no retryable pages exist any more.
 * The caller should call putback_movable_pages() to return pages to the LRU
 * or free list only if ret != 0.
 *
 * Returns the number of pages that were not migrated, or an error code.
 */
int migrate_pages(struct list_head *from, new_page_t get_new_page,
    free_page_t put_new_page, unsigned long private,
    enum migrate_mode mode, int reason)
// 调用 : unmap_and_move_huge_page 或者 unmap_and_move 维持一下生活
```
其实可以对于函数调用进行

对于实现 isolate 的猜测:
1. 按照 pageblock 的单位进行标记: 系统初始化的时候，其中的内容早就标记好了
2. 其他的 pageblock 根据 alloc_page 的 flags 确定。
> 不知道是否会选择合适的 pageblock 进行

```c
// 几乎是唯一初始化 ac->migratetype 的地方
// 另一个在 unreserve_highatomic_pageblock
static inline int gfpflags_to_migratetype(const gfp_t gfp_flags) {
  return (gfp_flags & GFP_MOVABLE_MASK) >> GFP_MOVABLE_SHIFT;
}
```

// --------------- 需要处理的事情 -----------------
```c
enum migratetype {
  MIGRATE_UNMOVABLE,
  MIGRATE_MOVABLE,     // 需要难受
  MIGRATE_RECLAIMABLE, // 想必这应该是最简单的，将其释放或者flush 掉即可
  MIGRATE_PCPTYPES, /* the number of types on the pcp lists */ // todo 为什么PCP 只需要前面的三种 ? 为什么 PCP 需要区分这些内容 ?
  MIGRATE_HIGHATOMIC = MIGRATE_PCPTYPES,
#ifdef CONFIG_CMA
  /*
   * MIGRATE_CMA migration type is designed to mimic the way
   * ZONE_MOVABLE works.  Only movable pages can be allocated
   * from MIGRATE_CMA pageblocks and page allocator never
   * implicitly change migration type of MIGRATE_CMA pageblock.
   *
   * The way to use it is to change migratetype of a range of
   * pageblocks to MIGRATE_CMA which can be done by
   * __free_pageblock_cma() function.  What is important though
   * is that a range of pageblocks must be aligned to
   * MAX_ORDER_NR_PAGES should biggest page be bigger then
   * a single pageblock.
   */
  MIGRATE_CMA,
#endif
#ifdef CONFIG_MEMORY_ISOLATION
  MIGRATE_ISOLATE,  /* can't allocate from here */
#endif
  MIGRATE_TYPES
};
```
// --------------- 需要处理的事情 -----------------


- [ ] comments below in /home/maritns3/core/linux/include/linux/page-flags.h
  - [ ] PAGE_MAPPING_MOVABLE : I think all anon page is movable

```c
/*
 * On an anonymous page mapped into a user virtual memory area,
 * page->mapping points to its anon_vma, not to a struct address_space;
 * with the PAGE_MAPPING_ANON bit set to distinguish it.  See rmap.h.
 *
 * On an anonymous page in a VM_MERGEABLE area, if CONFIG_KSM is enabled,
 * the PAGE_MAPPING_MOVABLE bit may be set along with the PAGE_MAPPING_ANON
 * bit; and then page->mapping points, not to an anon_vma, but to a private
 * structure which KSM associates with that merged page.  See ksm.h.
 *
 * PAGE_MAPPING_KSM without PAGE_MAPPING_ANON is used for non-lru movable
 * page and then page->mapping points a struct address_space.
 *
 * Please note that, confusingly, "page_mapping" refers to the inode
 * address_space which maps the page from disk; whereas "page_mapped"
 * refers to user virtual address space into which the page is mapped.
 */
#define PAGE_MAPPING_ANON 0x1
#define PAGE_MAPPING_MOVABLE  0x2
#define PAGE_MAPPING_KSM  (PAGE_MAPPING_ANON | PAGE_MAPPING_MOVABLE)
#define PAGE_MAPPING_FLAGS  (PAGE_MAPPING_ANON | PAGE_MAPPING_MOVABLE)
```

```diff
 History:        #0
 Commit:         bda807d4445414e8e77da704f116bb0880fe0c76
 Author:         Minchan Kim <minchan@kernel.org>
 Committer:      Linus Torvalds <torvalds@linux-foundation.org>
 Author Date:    Wed 27 Jul 2016 06:23:05 AM CST
 Committer Date: Wed 27 Jul 2016 07:19:19 AM CST

 mm: migrate: support non-lru movable page migration

 We have allowed migration for only LRU pages until now and it was enough
 to make high-order pages.  But recently, embedded system(e.g., webOS,
 android) uses lots of non-movable pages(e.g., zram, GPU memory) so we
 have seen several reports about troubles of small high-order allocation.
 For fixing the problem, there were several efforts (e,g,.  enhance
 compaction algorithm, SLUB fallback to 0-order page, reserved memory,
 vmalloc and so on) but if there are lots of non-movable pages in system,
 their solutions are void in the long run.

 So, this patch is to support facility to change non-movable pages with
 movable.  For the feature, this patch introduces functions related to
 migration to address_space_operations as well as some page flags.

 If a driver want to make own pages movable, it should define three
 functions which are function pointers of struct
 address_space_operations.

 1. bool (*isolate_page) (struct page *page, isolate_mode_t mode);

 What VM expects on isolate_page function of driver is to return *true*
 if driver isolates page successfully.  On returing true, VM marks the
 page as PG_isolated so concurrent isolation in several CPUs skip the
 page for isolation.  If a driver cannot isolate the page, it should
 return *false*.

 Once page is successfully isolated, VM uses page.lru fields so driver
 shouldn't expect to preserve values in that fields.

 2. int (*migratepage) (struct address_space *mapping,
    struct page *newpage, struct page *oldpage, enum migrate_mode);

 After isolation, VM calls migratepage of driver with isolated page.  The
 function of migratepage is to move content of the old page to new page
 and set up fields of struct page newpage.  Keep in mind that you should
 indicate to the VM the oldpage is no longer movable via
 __ClearPageMovable() under page_lock if you migrated the oldpage
 successfully and returns 0.  If driver cannot migrate the page at the
 moment, driver can return -EAGAIN.  On -EAGAIN, VM will retry page
 migration in a short time because VM interprets -EAGAIN as "temporal
 migration failure".  On returning any error except -EAGAIN, VM will give
 up the page migration without retrying in this time.

 Driver shouldn't touch page.lru field VM using in the functions.

 3. void (*putback_page)(struct page *);

 If migration fails on isolated page, VM should return the isolated page
 to the driver so VM calls driver's putback_page with migration failed
 page.  In this function, driver should put the isolated page back to the
 own data structure.

 4. non-lru movable page flags

 There are two page flags for supporting non-lru movable page.

 * PG_movable

 Driver should use the below function to make page movable under
 page_lock.

  void __SetPageMovable(struct page *page, struct address_space *mapping)

 It needs argument of address_space for registering migration family
 functions which will be called by VM.  Exactly speaking, PG_movable is
 not a real flag of struct page.  Rather than, VM reuses page->mapping's
 lower bits to represent it.

  #define PAGE_MAPPING_MOVABLE 0x2
  page->mapping = page->mapping | PAGE_MAPPING_MOVABLE;

 so driver shouldn't access page->mapping directly.  Instead, driver
 should use page_mapping which mask off the low two bits of page->mapping
 so it can get right struct address_space.

 For testing of non-lru movable page, VM supports __PageMovable function.
 However, it doesn't guarantee to identify non-lru movable page because
 page->mapping field is unified with other variables in struct page.  As
 well, if driver releases the page after isolation by VM, page->mapping
 doesn't have stable value although it has PAGE_MAPPING_MOVABLE (Look at
 __ClearPageMovable).  But __PageMovable is cheap to catch whether page
 is LRU or non-lru movable once the page has been isolated.  Because LRU
 pages never can have PAGE_MAPPING_MOVABLE in page->mapping.  It is also
 good for just peeking to test non-lru movable pages before more
 expensive checking with lock_page in pfn scanning to select victim.

 For guaranteeing non-lru movable page, VM provides PageMovable function.
 Unlike __PageMovable, PageMovable functions validates page->mapping and
 mapping->a_ops->isolate_page under lock_page.  The lock_page prevents
 sudden destroying of page->mapping.

 Driver using __SetPageMovable should clear the flag via
 __ClearMovablePage under page_lock before the releasing the page.

 * PG_isolated

 To prevent concurrent isolation among several CPUs, VM marks isolated
 page as PG_isolated under lock_page.  So if a CPU encounters PG_isolated
 non-lru movable page, it can skip it.  Driver doesn't need to manipulate
 the flag because VM will set/clear it automatically.  Keep in mind that
 if driver sees PG_isolated page, it means the page have been isolated by
 VM so it shouldn't touch page.lru field.  PG_isolated is alias with
 PG_reclaim flag so driver shouldn't use the flag for own purpose.

 [opensource.ganesh@gmail.com: mm/compaction: remove local variable is_lru]
   Link: http://lkml.kernel.org/r/20160618014841.GA7422@leo-test
 Link: http://lkml.kernel.org/r/1464736881-24886-3-git-send-email-minchan@kernel.org
 Signed-off-by: Gioh Kim <gi-oh.kim@profitbricks.com>
 Signed-off-by: Minchan Kim <minchan@kernel.org>
 Signed-off-by: Ganesh Mahendran <opensource.ganesh@gmail.com>
 Acked-by: Vlastimil Babka <vbabka@suse.cz>
 Cc: Sergey Senozhatsky <sergey.senozhatsky@gmail.com>
 Cc: Rik van Riel <riel@redhat.com>
 Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
 Cc: Mel Gorman <mgorman@suse.de>
 Cc: Hugh Dickins <hughd@google.com>
 Cc: Rafael Aquini <aquini@redhat.com>
 Cc: Jonathan Corbet <corbet@lwn.net>
 Cc: John Einar Reitan <john.reitan@foss.arm.com>
 Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
 Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
```




## numa
1. 创建的内存最好是就是在附近 ：buddy 和 slub 分配器的策略，这些策略被整理成为 mempolicy.c
2. 运行过程中间发生变化 : migrate.c

首先分析一波 numa 的基础知识 [^6]

用户层次:
Available policies are
1. **page interleaving** (i.e., allocate in a round-robin fashion from all, or a subset, of the nodes on the system), inorder to overload the initial boot node with boot-time allocations.
2. **preferred node allocation** (i.e., preferably allocate on a particular node),
3. **local allocation** (i.e., allocate on the node on which the task is currently executing), or
4. **allocation only on specific nodes** (i.e., allocate on some subset of the available nodes).  It is also possible to bind tasks to specific nodes.

分析 syscall :
1. get_mempolicy
2. mbind
3. migrate_page




#### mempolicy
读一下文档: [^7] (文档很清晰)
1. Memory policies are a programming interface that a NUMA-aware application can take advantage of. (**所以向用户提供了什么 interface **)
2. cpusets which is an administrative mechanism for restricting the nodes from which memory may be allocated by a set of processes.  cpuset 和 numa mempolicy 同时出现的时候，cpuset 优先(**cpuset 是什么**)
3. 一共四个模式 和 两个flags MPOL_F_STATIC_NODES 和 MPOL_F_RELATIVE_NODES (**flag 的作用有点迷**)
4. 还分析了一下 mol_put 和 mol_get 的问题

```c
// 获取 vma 对应的 policy ，解析出来 preferred_nid 和 nodemask 然后
struct page * alloc_pages_vma(gfp_t gfp, int order, struct vm_area_struct *vma, unsigned long addr, int node, bool hugepage)
```
> 感觉 mempolicy 并没有什么特殊的地方，只是提供一个syscall 给用户。

## madvise && fadvise
madvise 告知内核该范围的内存如何访问
fadvise 告知内核该范围的文件如何访问，内核从而可以调节 readahead 的参数，或者清理掉该范围的page cache

问题:
1. madvice 如何影响 hugepage 的
2. 还有在文件系统中间对称的 fadvise


fadvise 很简单，阅读
1. Man fadvise(2)
2. fadvise.c 的源代码

## highmem
1. 为什么内核虚拟地址需要映射所有的物理地址 ?
猜测: a. gup 很容易实现，利用 kmap 可以很容易访问所有的。
2. 真的所有物理地址的 page table 全部填充了吗 ?


2. 为什么需要将内核地址空间和用户地址空间分离开 ?
A 32-bit system has the ability to address 4GB of virtual memory; while user space and the kernel could have distinct 4GB address spaces, arranging things that way imposes a significant performance cost resulting from the need for frequent translation lookaside buffer flushes. [^2]

To avoid paying this cost, Linux used the same address space for both kernel and user mode, with the memory protections set to prevent user space from accessing the kernel's portion of the shared space. This arrangement saved a great deal of CPU time — at least, until the **Meltdown vulnerability** hit and forced the isolation of the kernel's address space.
> 什么 ?

为什么曾经需要 highmen ?
内核的虚拟地址空间 和 用户的虚拟地址空间不能重叠，
在 32bit 的地址空间，面对 4G 的物理内存的时候，内核虚拟地址空间无法覆盖所有的物理内存。
linux 规定 KVAS 映射 3G~4G 的虚拟地址空间，那么如果需要访问 0G-3G 的物理内存，那么就需要修改 page table
1. 为什么内核不可以使用 0G-3G 的虚拟地址空间 ? (只要出现一丢丢重叠，那么同一个虚拟地址就是可以映射到两个物理地址上的，那么用户和内核之间的切换就必须进行 TLB flush)
2. 虽然 0G-3G 的空间不可以映射，但是通过在 KVAS 中间的内核虚拟地址空的 page struct 数组，还是可以对于所有的物理内存进行管理。

gup 的作用 : 将用户的 page 直接固定到内核态，不用使用 copy_from_user 之类智障操作，
从用户提供的虚拟地址(get_user_pages 的参数 mm 说明是哪一个用户)得到物理页面。
然后获取该物理页面在内核虚拟地址空间的地址，然后就可以直接访问了。

Consider, for example, all of the calls to kmap() and kmap_atomic(); they do nothing on 64-bit systems, but are needed to access high memory on smaller systems. And, sometimes, high memory affects development decisions being made today. [^2]

kmap 和 kmap_atomic 在 64bit 是不是完全相同的:
```c
 static inline void *kmap(struct page *page)
 {
  might_sleep();
  return page_address(page);
 }

 static inline void kunmap(struct page *page)
 {
 }

 static inline void *kmap_atomic(struct page *page)
 {
  preempt_disable();
  pagefault_disable();
  return page_address(page);
 }
 #define kmap_atomic_prot(page, prot) kmap_atomic(page)

 static inline void __kunmap_atomic(void *addr)
 {
  pagefault_enable();
  preempt_enable();
 }
```
并不是完全相同的，应该只是历史遗留产物吧 !

## pmem
DAX 设置 : 到时候在分析吧!
1. https://www.intel.co.uk/content/www/uk/en/it-management/cloud-analytic-hub/pmem-next-generation-storage.html
2. https://nvdimm.wiki.kernel.org/
3. https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/storage_administration_guide/ch-persistent-memory-nvdimms

目前观察到的generic_file_read_iter 和 file_operations::mmap 的内容对于 DAX 区分对待的，但是内容远远不该如此，不仅仅可以越过 page cache 机制，而且 page reclaim 全部可以跳过。

#### vmemmap

## mmio
https://gist.github.com/Measter/2108508ba25ebe3978a6c10a1e01b9ad

- [] mmio 的建立和 pcie 的关系
- [] mmio 和 kvm

## physical memory initialization
1. 探测
2. memblock

[LoyenWang](https://www.cnblogs.com/LoyenWang/p/11568481.html)
[LoyenWang](https://www.cnblogs.com/LoyenWang/p/11523678.html)

整体完成的工作也比较简单，将所有Node中可用的zone全部添加到各个Node中的zonelist中，也就是对应的struct pglist_data结构体中的struct zonelist node_zonelists字段。 这一步之后，准备工作基本就绪，进行页面申请的工作就可以开始了。
![loading](https://img2018.cnblogs.com/blog/1771657/201910/1771657-20191006001313609-398829452.png)

## memory zone
产生 node 的原因 : numa
产生 zone 的原因 : DMA highmem 等原因，不同

居然存在 mmzone.c

有待搞清楚的问题:
1. 理解这个宏
```c
 /**
  * for_each_zone_zonelist - helper macro to iterate over valid zones in a zonelist at or below a given zone index
  * @zone - The current zone in the iterator
  * @z - The current pointer within zonelist->zones being iterated
  * @zlist - The zonelist being iterated
  * @highidx - The zone index of the highest zone to return
  *
  * This iterator iterates though all zones at or below a given zone index.
  */
 #define for_each_zone_zonelist(zone, z, zlist, highidx) \
  for_each_zone_zonelist_nodemask(zone, z, zlist, highidx, NULL)
```

TODO 等待分析: zone 功能不同，甚至 swap cache 到 page cache 需要靠拷贝的方法维持生活 ?
```c
/*
 * When a page is moved from swapcache to shmem filecache (either by the
 * usual swapin of shmem_getpage_gfp(), or by the less common swapoff of
 * shmem_unuse_inode()), it may have been read in earlier from swap, in
 * ignorance of the mapping it belongs to.  If that mapping has special
 * constraints (like the gma500 GEM driver, which requires RAM below 4GB),
 * we may need to copy to a suitable page before moving to filecache.
 *
 * In a future release, this may well be extended to respect cpuset and
 * NUMA mempolicy, and applied also to anonymous pages in do_swap_page();
 * but for now it is a simple matter of zone.
 */
static bool shmem_should_replace_page(struct page *page, gfp_t gfp)
{
  // 如果 swap cache 的 page_zonenum，
  return page_zonenum(page) > gfp_zone(gfp);
}
```

## shmem
- [ ] [^28] : read it carefully and throughly

- [x] why linux need shmem ?

[^28]
When pages within a VMA are backed by a file on disk, the interface used is straight-forward. To read a page during a page fault, the required nopage() function is found `vm_area_struct->vm_ops`. To write a page to backing storage, the appropriate `writepage()` function is found in the `address_space_operations` via `inode->i_mapping→a_ops` or alternatively via `page->mapping->a_ops`. When normal file operations are taking place such as mmap(), read() and write(), the struct file_operations with the appropriate functions is found via `inode->i_fop` and so on. These relationships were illustrated in Figure 4.2.

This is a very clean interface that is conceptually easy to understand but it does not help anonymous pages as there is no file backing. To keep this nice interface, Linux creates an artifical file-backing for anonymous pages using a RAM-based filesystem where each VMA is backed by a “file” in this filesystem.

huxueshi : I think with this correct and clean perspective, we can shmem easily and use it correct misunderstandings of other parts.

总结:
1. 为了 tmpfs 建立的配套机制
2. fallocate : hole
3. 和 swap 的紧密联系
4. transparent huge page


问题1: shmem 和 swap 的联系有哪些 ?
1. shmem_swapin_page : 如果 lookup_swap_cache 找不到，那么 shmem_swapin，找到 shmem_add_to_page_cache + delete_from_swap_cache

问题2: shmem 上是如何构建 /tmp 的 ?
问题3: shmem 定义了大量齐全的文件系统的接口，为什么是这样的 ?

问题4: 为什么 minfs 和 myfs 都是没有注册 vm_operations_struct 的，但是依旧可以正常的工作 ? 是不是因为 vm_operations_struct 仅仅限于 mmap 以及其延伸的 page fault ?
> 并不是，使用的是 generic_file_mmap，所以整个机制都是采用

问题6: sysv 和 posix 如何利用 shmem 实现的 ?
问题7: 是不是 ramfs 和 shmem 的唯一区别在于，ramfs 不会将其数据备份到 swap 中间 ?  比较一下 ramfs 和 getpage 和 shmem_getpage !


问题分析1: pgfault 的流程，由于 page fault 不需要访问磁盘，所以其过程只是需要分配 page 物理页面即可。
1. shmem_falloc // TODO 有点难以理解
2. shmem_getpage_gfp - find page in cache, or get from swap, or allocate.

问题分析2: 为什么 shmem 依旧需要 page cache ？ 因为从一般来说，page cache 用于加速访问磁盘，可以 shmem 是基于内存的呀 ?
需要 page cache 提供的基础设施，比如两个进程的 vma 映射了同一个 /tmp/a.md 的内容，那么第一个 page fault 创建了文件，第二个就可以从 page cache 提供的 radix tree 中间找到需要的 page
如果不需要加速访问，那么提供一个一个蛇皮的 file_operations 和 address_space_operations，不进行 page writeback 操作即可。
shmem_writepage : get_swap_page 获取 swp_entry_t，将 page 和 swp_entry_t 添加到 add_to_swap_cache，并且调用 swap_writepage 将其写入到 swap 中间。(这么说，swap 可以实现 /tmp 的内容永久存在)
```c
static const struct address_space_operations shmem_aops = {
    // TODO 为什么没有 readpage ?
  .writepage  = shmem_writepage,
  .set_page_dirty = __set_page_dirty_no_writeback,
#ifdef CONFIG_TMPFS
  // 为了实现 generic_file_write_iter，在进行拷贝前后使用，用于从 page cache 中间找到正确的 page
  .write_begin  = shmem_write_begin, // shmem_getpage
  .write_end  = shmem_write_end, // SetPageUptodate set_page_dirty
#endif
#ifdef CONFIG_MIGRATION
  .migratepage  = migrate_page,
#endif
  .error_remove_page = generic_error_remove_page,
};

// shmem 的基础配置可以实现什么功能 ?
// posix 以及 sysv  的 shmem，但是它们是靠什么函数进行 IO 的 ?
// 难道 /tmp 和 ramfs 的功能不是重复的吗 ? line 4085 的 CONFIG_SHMEM 似乎说明了很多东西
static const struct file_operations shmem_file_operations = {
  .mmap   = shmem_mmap,
  .get_unmapped_area = shmem_get_unmapped_area,
#ifdef CONFIG_TMPFS
  .llseek   = shmem_file_llseek,
  .read_iter  = shmem_file_read_iter,// shmem_getpage + copy_page_to_iter
  .write_iter = generic_file_write_iter, // 就是通用的写操作
  .fsync    = noop_fsync,
  .splice_read  = generic_file_splice_read,
  .splice_write = iter_file_splice_write,
  .fallocate  = shmem_fallocate, // TODO 又是这个
#endif
};
```
总结，shmem_getpage 是核心，read 使用从 page cache 或者 swap cache ，甚至 swap 中间找。

问题分析3: tmpfs 的文件操作，看上去和 ext2 没有什么区别啊!

- [ ] 问题分析4: shmem 如何使用 transparent hugepage
    - [ ] https://lwn.net/Articles/679804/

Huge page is represented by HPAGE_PMD_NR entries in radix-tree.


## swap

// 从 swapOn 的部分开始分析就可以了，所以为什么 shmem 中间存在一堆内容
// 经典函数收集，尤其是 page swap 中间的
// 4. swap_slots 的工作原理是什么 ?


swap 应该算是是历史遗留产物，之所以阅读之，是因为不看的话，其他的部分看不懂。
1. shmem 以及基于 shmem 实现的 /tmp 中间的内容可以被swap 到磁盘
2. 匿名映射的内存，比如用户使用syscall brk 分配的，可以被 swap 到磁盘
3. 当进行swap 机制开始回收的时候，一个物理页面需要被清楚掉，但是映射到该物理页面的pte_t的需要被重写为swp_entry_t的内容，由于可能共享，所以需要rmap实现找到这些pte，
4. page reclaim 机制可能需要清理 swap cache 的内容
5. hugetlb 和 transparent hugetlb 的页面能否换出，如何换出 ?

swap 机制主要组成部分是什么 :
    0. swap cache 来实现其中
    1. page 和 设备上的 io : page-io.c
    2. swp_entry_t 空间的分配 : swapfile.c
    3. policy :
        1. 确定那些页面需要被放到 swap 中间
        2. swap cache 的页面如何处理
    4. 特殊的swap

在 mm/ 文件夹下涉及到 swap 的文件，和对于 swap 的作用:
| Name        | description                 |
|-------------|-----------------------------|
| swapfile    |                             |
| swap_state  | 维护 swap cache，swap 的 readahead                           |
| swap        | pagevec 和 lrulist 的操作，其实和 swap 的关系不大 |
| swap_slot   |                             |
| page_io     | 进行通往底层的io                             |
| mlock       |                             |
| workingset  |                             |
| frontswap   |                             |
| zswap       |                             |
| swap_cgroup |                             |

struct page 的支持
1. `page->private` 用于存储 swp_entry_t.val，表示其中的
2. TODO 还有其他的内容吗

#### swap cache

swap_state.c 主要内容:
| Function name               | desc                                                                                 |
|-----------------------------|--------------------------------------------------------------------------------------|
| `read_swap_cache_async`     |                                                                                      |
| `swap_cluster_readahead`    | @todo 为什么readahead不是利用page cache 中间的公共框架，最终调用在 do_swap_page 中间 |
| `swap_vma_readahead`        | 另一个readahead 策略，swapin_readahead 中间被决定                                    |
| `total_swapcache_pages`     | 返回所有的 swap 持有的 page frame                                                    |
| `show_swap_cache_info`      | 打印 swap_cache_info 以及 swapfile 中间的                                            |
| `add_to_swap_cache`       | 将page 插入到 radix_tree 中间                                                        |
| `add_to_swap`               | 利用 `swap_slots.c` 获取 get_swap_page 获取空闲swp_entry                             |
| `__delete_from_swap_cache`  | 对称操作                                                                             |
| `delete_from_swap_cache`    |                                                                                      |
| `free_swap_cache`           | 调用swapfile.c try_to_free_swap @todo swapfile.c 的内容比想象的多得多啊 !            |
| `free_page_and_swap_cache`  |                                                                                      |
| `free_pages_and_swap_cache` |                                                                                      |
| `lookup_swap_cache`         | find_get_page 如果不考虑处理 readahead 机制的话                                      |
| `__read_swap_cache_async`   |                                                                                      |
| `swapin_nr_pages`           | readahead 函数的读取策略 @todo                                                       |
| `init_swap_address_space`   | swapon syscall 调用，初始化swap                                                      |
1. /sys/kernel/mm/swap/vma_ra_enabled 来控制是否 readahead
2. 建立 radix_tree 的过程，多个文件，多个分区，各自大小而且不同 ? init_swap_address_space 中说明的，对于一个文件，每64M创建一个 radix_tree，至于其来自于那个文件还是分区，之后寻址的时候不重要了。init_swap_address_space 被 swapon 唯一调用
```c
struct address_space *swapper_spaces[MAX_SWAPFILES] __read_mostly;
static unsigned int nr_swapper_spaces[MAX_SWAPFILES] __read_mostly;
```
3. 谁会调用 add_to_swap 这一个东西 ?
    1. 认为 : 当 anon page 发生 page fault 在 swap cache 中间没有找到的时候，创建了一个page，于是乎将该 page 通过 add_to_swap 加入到 swap cache
    2. 实际上 : 只有 shrink_page_list 调用，这个想法 `__read_swap_cache_async` 实现的非常不错。
    3. 猜测 : 当一个 page 需要被写会的时候，首先将其添加到 swap cache 中间
```c
/**
 * add_to_swap - allocate swap space for a page
 * @page: page we want to move to swap
 *
 * Allocate swap space for the page and add the page to the
 * swap cache.  Caller needs to hold the page lock.
 */
int add_to_swap(struct page *page)
    get_swap_page     // 分配 swp_entry_t // todo 实现比想象的要复杂的多，首先进入到 swap_slot.c 但是 swap_slot.c 中间似乎根本不处理什么具体分配，而是靠 swapfile.c 的 get_swap_pages // todo 获取到 entry.val != 0 说明 page 已经被加入到 swap 中间 ?
    add_to_swap_cache // 将 page 和 swp_entry_t 链接起来，形成
    set_page_dirty // todo 和 page-writeback.c 有关，line 240 的注释看不懂
    put_swap_page // Called after dropping swapcache to decrease refcnt to swap entries ，和 get_swap_page 对称的函数，核心是调用 free_swap_slot

// 从 get_swap_page 和 put_swap_page 中间，感觉 swp_entry_t 存在引用计数 ? 应该不可能呀 !
```
4. 利用 swap_cache_info 来给管理员提供信息
```c
static struct {
  unsigned long add_total;
  unsigned long del_total;
  unsigned long find_success;
  unsigned long find_total;
} swap_cache_info;
```


问题:
1. 两种的 readahead 机制 swap_cluster_readahead 和 swap_vma_readahead 的区别 ?
```c
/**
 * swapin_readahead - swap in pages in hope we need them soon
 * @entry: swap entry of this memory
 * @gfp_mask: memory allocation flags
 * @vmf: fault information
 *
 * Returns the struct page for entry and addr, after queueing swapin.
 *
 * It's a main entry function for swap readahead. By the configuration,
 * it will read ahead blocks by cluster-based(ie, physical disk based)
 * or vma-based(ie, virtual address based on faulty address) readahead.
 */
struct page *swapin_readahead(swp_entry_t entry, gfp_t gfp_mask,
        struct vm_fault *vmf)
{
  return swap_use_vma_readahead() ?
      swap_vma_readahead(entry, gfp_mask, vmf) :
      swap_cluster_readahead(entry, gfp_mask, vmf);
}
```
2. 什么时候使用 readahead，什么时候使用 page-io.c:swap_readpage ?<br/> memory.c::do_swap_page 中间说明
3. add_to_swap 和 add_to_swap_cache 的关系是什么 ?<br/> add_to_swap 首先调用 swap_slot.c::get_swap_page 分配 swap slot，然后调用 add_to_swap_cache 将 page 和 swap slot 关联起来。
4. swap cache 的 page 和 page cache 的 page 在 page reclaim 机制中间有没有被区分对待 ? TODO
5. swap cache 不复用 page cache ? <br/>两者只是使用的机制有点类似，通过索引查询到 page frame，但是 swap cache 的 index 是 swp_entry_t，而page cache 的 index 是文件的偏移量。对于每一个文件，都是存在一个 radix_tree 来提供索引功能，对于 swap，

page-io.c 主要内容:
| Function                    | description                                                                                                                       |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| `swap_writepage`            | 封装 `__swap_writepage`
| `__swap_writepage`          |
| `swap_readpage`             | 如果 swap 建立在文件系统上的，那么调用该文件系统的 `aops->readpage`，如果 swap 直接建立在 blockdev 上的，使用 bdev_read_page 进行 |
| `swap_set_page_dirty`       |
| `get_swap_bio`              |
| `end_swap_bio_write`        |
| `end_swap_bio_read`         |
| `swap_slot_free_notify`     |
| `generic_swapfile_activate` |
| `swap_page_sector`          |
| `count_swpout_vm_event`     |
问题:
1. 请问 page-io.c 实现的内容，在 ext2 是对应的哪里实现的 ?<br/>page-io.c 中间实现的就是 readpage 和 writepage 的功能，其对应的 ext2 部分无非是 ext2 的 readpage 和 writepage。page-io.c 的主要作用正确的将IO工作委托给下层的fs或者blkdev.
2. 为什么 swap_readpage 和 swap_writepage 使用不是对称的 ?
    1. swap_aops 到底如何最后调用其中的 writepage 的 ? TODO 既然利用了 address_space ，那么 swap cache 放到 swap cache 中间统一管理。
    2. 为什么 ext2 不是直接使用 readpage ，这这里是直接使用的 ?<br/> 因为 swap 其实可以当做一个文件系统，所以没有必要经过一个通用的 address_space_operations::readpage，对于 swap 的 IO 是没有 file operation 的，而是直接进行在 page 的层次的，所以 swap_state 提供的操作是在 generic_file_buffered_read 后面部分的工作。
> TODO 等等，什么 file operation 的 direct IO 是什么情况 ?


swap_slot.c 主要内容:
```c
static DEFINE_PER_CPU(struct swap_slots_cache, swp_slots);
struct swap_slots_cache {
  bool    lock_initialized;
  struct mutex  alloc_lock; /* protects slots, nr, cur */
  swp_entry_t *slots;
  int   nr;
  int   cur;
  spinlock_t  free_lock;  /* protects slots_ret, n_ret */
  swp_entry_t *slots_ret;
  int   n_ret;
};

// 两个对外提供的接口
int free_swap_slot(swp_entry_t entry);
swp_entry_t get_swap_page(struct page *page)
```
当 get_swap_page 将 cache 耗尽之后，会调用 swapfile::get_swap_pages 来维持生活
也就是 swap_slots.c 其实是 slots cache 机制。
#### swapfile
// 管理其中的结构，关键机制在 cluster 和 extents 即可，基本的 IO 交给下层的 file，所以 swapfile 的功能和 ext2 的功能一致，负责下层的磁盘的布局

// 等待分析的函数
delete_from_swap_cache => put_swap_page => .....
try_to_free_swap

// 机制
1. cluster
2. extents
3. 全局的 swap_active_head
4. avail_lists : 为什么需要给每一个 node 提供孤儿
```c
/*
 * all active swap_info_structs
 * protected with swap_lock, and ordered by priority.
 */
PLIST_HEAD(swap_active_head); // TODO 是不是首先按照 swap_info_struct，然后按照 cluster


static void __del_from_avail_list(struct swap_info_struct *p)
{
  int nid;

  for_each_node(nid)
    plist_del(&p->avail_lists[nid], &swap_avail_heads[nid]);
}

static void del_from_avail_list(struct swap_info_struct *p)
{
  spin_lock(&swap_avail_lock);
  __del_from_avail_list(p);
  spin_unlock(&swap_avail_lock);
}
```



结构:
1. 一个 swapfile 对应 swap_info_struct
2. 一个 swapfile 对应多个 cluster，并且使用 cluster_info 描述


回答问题:

0. 当一个文件被设置为 swapfile 的时候，如何阻止被访问。
1. 这几个函数看似都是 free，各自的作用是什么 ?
```c
/*
 * Caller has made sure that the swap device corresponding to entry
 * is still around or has not been recycled.
 */
void swap_free(swp_entry_t entry)


/*
 * If swap is getting full, or if there are no more mappings of this page,
 * then try_to_free_swap is called to free its swap space.
 */
int try_to_free_swap(struct page *page)

// TODO 很奇怪，swap 机制为什么和 vma 联系到一起了，这不是曾经的反向映射
/*
 * We completely avoid races by reading each swap page in advance,
 * and then search for the process using it.  All the necessary
 * page table adjustments can then be made atomically.
 *
 * if the boolean frontswap is true, only unuse pages_to_unuse pages;
 * pages_to_unuse==0 means all pages; ignored if frontswap is false
 */
int try_to_unuse(unsigned int type, bool frontswap,
     unsigned long pages_to_unuse)

static int claim_swapfile(struct swap_info_struct *p, struct inode *inode)
```
从 shmem_swapin_page 的内容看，
首先调用 delete_from_swap_cache，然后调用 swap_free，前者应该是处理 swap cache 的 radix tree 维护，后者处理 swap slot 的问题。


关键函数分析，这两个函数到时候看书(ULK) 进行补充一下
1. swapon : 似乎不难，处理各种机制的建立过程
2. swapoff : 如果彻底理解 swapon，那么不难，关键 : try_to_unuse 调用两个函数
    1. shmem_unuse
    2. unuse_mm : 逐个清理

## out of memory killer

- [ ] oom reaper

- [ ] cgroup

- [ ] dump

- out_of_memory

- [ ] `__oom_kill_process`



## vmstate
// 搞清楚如何使用这个代码吧 !

`vmstat.h/vmstat.c`
```c
static inline void count_vm_event(enum vm_event_item item)
{
  this_cpu_inc(vm_event_states.event[item]);
}
// @todo 以此为机会找到内核实现暴露接口的位置
```

```c
    __mod_zone_page_state(page_zone(page), NR_MLOCK,
            hpage_nr_pages(page));
    count_vm_event(UNEVICTABLE_PGMLOCKED);
    // 两个统计的机制，但是并不清楚各自统计的内容是什么包含什么区别
```

## mlock
- [ ] 那么 mlock 可以自动 让原来没有建立映射映射的虚拟地址建立映射。mlock 保证其对应的页面没有换出，如果本身就是不存在，不换出的意义在于什么地方啊!

// 首先了解 mlock 的内容
// @todo read this https://lwn.net/Articles/286485/ 完全解释了vm_flags 是VM_LOCKED 以及 unevictable 的含义


mlock 施加影响的位置:
1. page reclaim 和 swap 模块
2. mlock 可以施加于 hugemem 吗 ?

- [ ] mlock is more complex than expected, because it has to handle isolation ?

## lock
- [ ] mm_take_all_locks

## hot plug

## ioremap
1. maps device physical address(device memory or device registers) to kernel virtual address [^25]
2. Like user space, the kernel accesses memory through page tables; as a result, when kernel code needs to access memory-mapped I/O devices, it must first set up an appropriate kernel page-table mapping. [^26]
  - [ ] memremap 是 ioremap 的更好的接口.

因为内核也是运行在虚拟地址空间上的，而访问设备是需要物理地址，为了将访问设备的物理地址映射到虚拟地址空间中，所以需要 ioremap，当然 pci 访问带来的各种 cache coherency 问题也是需要尽量考虑的:
```c
#0  ioremap (phys_addr=1107312640, size=56) at arch/loongarch/mm/ioremap.c:95
#1  0x90000000008555c0 in pci_iomap_range (dev=<optimized out>, bar=<optimized out>, offset=<optimized out>, maxlen=<optimized out>) at lib/pci_iomap.c:46
#2  0x9000000000962150 in map_capability (dev=0x900000027d75b000, off=<optimized out>, minlen=56, align=4, start=0, size=56, len=0x0) at drivers/virtio/virtio_pci_modern.c:134
#3  0x9000000000962950 in virtio_pci_modern_probe (vp_dev=0x900000027da3e800) at drivers/virtio/virtio_pci_modern.c:652
#4  0x900000000096311c in virtio_pci_probe (pci_dev=0x900000027d75b000, id=<optimized out>) at drivers/virtio/virtio_pci_common.c:546
#5  0x90000000008c28c0 in local_pci_probe (_ddi=0x900000027cd33c58) at drivers/pci/pci-driver.c:306
#6  0x9000000000235030 in work_for_cpu_fn (work=0x900000027cd33c08) at kernel/workqueue.c:4908
#7  0x9000000000238ce0 in process_one_work (worker=0x900000027c08fc00, work=0x900000027cd33c08) at kernel/workqueue.c:2152
#8  0x9000000000239220 in process_scheduled_works (worker=<optimized out>) at kernel/workqueue.c:2211
```
## mremap

## debug
> 从内核的选项来看，对于 debug 一无所知啊 !
- Extend memmap on extra space for more information on page
- Debug page memory allocations
- Track page owner
- Poison pages after freeing
- Enable tracepoint to track down page reference manipulation
- Testcase for the marking rodata read-only
- Export kernel pagetable layout to userspace via debugfs
- Debug object operations
- SLUB debugging on by default
- Enable SLUB performance statistics
- Kernel memory leak detector
- Stack utilization instrumentation
- Detect stack corruption on calls to schedule()
- Debug VM
- Debug VM translations
- Debug access to per_cpu maps
- KASAN: runtime memory debugger

#### page owner

page owner is for the tracking about who allocated each page.

#### KASAN
Finding places where the kernel accesses memory that it shouldn't is the goal for the kernel address sanitizer (KASan).

#### kmemleak
Kmemleak provides a way of detecting possible kernel memory leaks in a way similar to a tracing garbage collector, with the difference that the orphan objects are not freed but only reported via /sys/kernel/debug/kmemleak. [^18]


## dmapool
https://lwn.net/Articles/69402/

Some very obscure driver bugs have been traced down to cache coherency problems with structure fields adjacent to small DMA areas. [^17]
> DMA 为什么会导致附近的内存的 cache coherency 的问题 ?

- [ ] dma_pool_create() - Creates a pool of consistent memory blocks, for dma.

- [ ] https://www.kernel.org/doc/html/latest/driver-api/dmaengine/index.html#dmaengine-documentation
- [ ] https://www.kernel.org/doc/html/latest/core-api/index.html#memory-management
- [ ] https://www.kernel.org/doc/Documentation/DMA-API-HOWTO.txt

## mempool
使用 mempool 的目的:
The purpose of mempools is to help out in situations where a memory allocation must succeed, but sleeping is not an option. To that end, mempools pre-allocate a pool of memory and reserve it until it is needed. [^16]

## virtual machine
https://lwn.net/Kernel/Index/#Memory_management-Virtualization

#### mmu notifier
[^24] is worth reading !

- some notifier triggers:
  - try_to_unmap_one
  - ptep_clear_flush_notify

- [ ] how kvm work with mmu notifier ?

- [ ] mmu_notifier.rst

- [x] so why kvm need mmu notifier ?
[Integrating KVM with the Linux Memory Management](https://www.linux-kvm.org/images/3/33/KvmForum2008%24kdf2008_15.pdf)

Guest ram is mostly allocated by user process with `memalign()` and
kvm get physical memory with `get_user_pages`.

> The 'MMU Notifier' functionality can be also used
by other subsystems like GRU and XPMEM to
export the user virtual address space of
computational tasks to other nodes

> This will also allow KVM guest physical ram itself
to be exported to other nodes through GRU and
XPMEM or any other RDMA engine

- TODO really interesting RDMA and XPMEM

> - The KVM page fault is the one that instantiates the shadow pagetables
> - Shadow pagetables works similarly to a TLB
> - They translate a virtual (or physical with EPT/NPT) guest address to a physical host address
> - They can be discarded at any time and they will be recreated later as new KVM page fault triggers, just like the primary CPU TLB can be flushed at any time and the CPU will refill it from the ptes
> - The sptes are recreated by the KVM page fault by calling get_user_pages (i.e. looking at the Linux ptes) to translate a guest physical address (the malloced region) to a host physical address

------------  function calling chain -------------------------- begin ---

- [ ] *unless we can understand hugetlb and thp, we can't understand mmu_notifier*

```
mmu_notifier_invalidate_range_start
  --> __mmu_notifier_invalidate_range_start
    --> mn_itree_invalidate
    --> mn_hlist_invalidate_range_start : call list one by one
```

```
mmu_notifier_invalidate_range_end
  --> __mmu_notifier_invalidate_range_end
    --> mn_itree_inv_end
    --> mn_hlist_invalidate_end
```

```
__mmu_notifier_register :
1. if mm->notifier_subscriptions is NULL, alloc and init one for it
2. is parameter subscription is not NULL, add it to mm->notifier_subscriptions list, mm->notifier_subscriptions->has_itree = true; otherwise
  mm_drop_all_locks(mm);
```
------------  function calling chain -------------------------- begin ---



------------ critical struct -------------------------- begin ---
```c
/*
 * The notifier chains are protected by mmap_lock and/or the reverse map
 * semaphores. Notifier chains are only changed when all reverse maps and
 * the mmap_lock locks are taken.
 *
 * Therefore notifier chains can only be traversed when either
 *
 * 1. mmap_lock is held.
 * 2. One of the reverse map locks is held (i_mmap_rwsem or anon_vma->rwsem).
 * 3. No other concurrent thread can access the list (release)
 */
struct mmu_notifier {
  struct hlist_node hlist;
  const struct mmu_notifier_ops *ops;
  struct mm_struct *mm;
  struct rcu_head rcu;
  unsigned int users;
};

/**
 * struct mmu_interval_notifier_ops
 * @invalidate: Upon return the caller must stop using any SPTEs within this
 *              range. This function can sleep. Return false only if sleeping
 *              was required but mmu_notifier_range_blockable(range) is false.
 */
struct mmu_interval_notifier_ops {
  bool (*invalidate)(struct mmu_interval_notifier *interval_sub,
         const struct mmu_notifier_range *range,
         unsigned long cur_seq);
};

struct mmu_interval_notifier {
  struct interval_tree_node interval_tree;
  const struct mmu_interval_notifier_ops *ops;
  struct mm_struct *mm;
  struct hlist_node deferred_item;
  unsigned long invalidate_seq;
};


struct mmu_notifier_range {
  struct vm_area_struct *vma;
  struct mm_struct *mm;
  unsigned long start;
  unsigned long end;
  unsigned flags;
  enum mmu_notifier_event event;
  void *migrate_pgmap_owner;
};

/*
 * The mmu_notifier_subscriptions structure is allocated and installed in
 * mm->notifier_subscriptions inside the mm_take_all_locks() protected
 * critical section and it's released only when mm_count reaches zero
 * in mmdrop().
 */
struct mmu_notifier_subscriptions {
  /* all mmu notifiers registered in this mm are queued in this list */
  struct hlist_head list;
  bool has_itree;
  /* to serialize the list modifications and hlist_unhashed */
  spinlock_t lock;
  unsigned long invalidate_seq;
  unsigned long active_invalidate_ranges;
  struct rb_root_cached itree;
  wait_queue_head_t wq;
  struct hlist_head deferred_list;
};
```

- `mmu_notifier` and `mmu_interval_notifier` are chained into `mmu_notifier_subscriptions`
- `mmu_notifier_range` is interface for memory management part
------------ critical struct -------------------------- end ---

#### balloon compaction
// 参考一下 vmware 的论文


## hmm
Provide infrastructure and helpers to integrate non-conventional memory (device memory like GPU on board memory) into regular kernel path, with the cornerstone of this being specialized struct page for such memory.
HMM also provides optional helpers for SVM (Share Virtual Memory) [^19]

## CMA
Movable pages are, primarily, page cache or anonymous memory pages; they are accessed via page tables and the page cache radix tree. The contents of such pages can be moved somewhere else as long as the tables and tree are updated accordingly. Reclaimable pages, instead, might possibly be given back to the kernel on demand; they hold data structures like the inode cache. Unmovable pages are usually those for which the kernel has direct pointers; memory obtained from kmalloc() cannot normally be moved without breaking things, for example.

In other words, memory which is marked for use by CMA remains available to the rest of the system with the one restriction that it can only contain movable pages. [^21]

To keep pages with the same migrate type together, the buddy allocator groups pages into "pageblocks," each having a migrate type assigned to it. The allocator then tries to allocate pages from pageblocks with a type corresponding to the request. If that's not possible, however, it will take pages from different pageblocks and may even change a pageblock's migrate type. This means that a non-movable page can be allocated from a MIGRATE_MOVABLE pageblock which can also result in that pageblock changing its migrate type. This is undesirable for CMA, so it introduces a MIGRATE_CMA type which has one important property: only movable pages can be allocated from a MIGRATE_CMA pageblock. [^12]

- [ ] track function : `alloc_contig_pages`

[TO BE CONTINUE](https://www.cnblogs.com/LoyenWang/p/12182594.html)

https://zhuanlan.zhihu.com/p/105745299
## zsmalloc
slub 分配器处理size > page_size / 2 会浪费非常多的内容，zsmalloc 就是为了解决这个问题 [^20]

## z3fold
z3fold is a special purpose allocator for storing compressed pages. [^23]

## zud
和 z3fold 类似的东西

## memory control group
```c
obj-$(CONFIG_MEMCG) += memcontrol.o vmpressure.o
```

## page poison
https://lwn.net/Articles/753261/

## msync
存在系统调用 msync，实现应该很简单吧!

## mpage
fs/mpage.c : 为毛是需要使用这个机制 ? 猜测其中的机制是为了实现

```c
static int ext2_readpage(struct file *file, struct page *page)
{
  return mpage_readpage(page, ext2_get_block);
}

static int
ext2_readpages(struct file *file, struct address_space *mapping,
    struct list_head *pages, unsigned nr_pages)
{
  return mpage_readpages(mapping, pages, nr_pages, ext2_get_block);
}

/*
 * This is the worker routine which does all the work of mapping the disk
 * blocks and constructs largest possible bios, submits them for IO if the
 * blocks are not contiguous on the disk.
 *
 * We pass a buffer_head back and forth and use its buffer_mapped() flag to
 * represent the validity of its disk mapping and to decide when to do the next
 * get_block() call.
 */
static struct bio *do_mpage_readpage(struct mpage_readpage_args *args)
```
> 无论是 ext2_readpage 还是 ext2_readpages 最后都是走到 do_mpage_readpage

## memblock


## malloc
似乎存在一堆自定义的 malloc
1. https://github.com/microsoft/mimalloc
2. https://github.com/jemalloc/jemalloc
    1. https://stackoverflow.com/questions/1624726/how-does-jemalloc-work-what-are-the-benefits
3. https://github.com/plasma-umass/Mesh


1. 可以将 glibc 的直接替换为这些自定义的吗 ?
2. 这些东西主要考虑的设计因素是什么

- [ ] how memalign implemented ?

#### jemalloc
tls_cache 层次，是 per thread 的:
| small               | larget              |
|---------------------|---------------------|
| tcache_alloc_small  | tcache_alloc_large  |
| tcache_dalloc_small | tcache_dalloc_large |

arena 是 concurrent 的:

| small : bin           | larget       |
|-----------------------|--------------|
| arena_bin_malloc_hard | large_malloc |
| nonfull_slab_get      | large_dalloc |
| arena_slab_reg_dalloc |              |
| arena_slab_dalloc|              |

| extent                      |
|-----------------------------|
| extent_alloc_default        |
| extent_pruge_lazy_default   |
| extent_purge_forced_default |

https://www.facebook.com/notes/facebook-engineering/scalable-memory-allocation-using-jemalloc/480222803919
https://people.freebsd.org/~jasone/jemalloc/bsdcan2006/jemalloc.pdf
http://applicative.acm.org/2015/applicative.acm.org/speaker-JasonEvans.html

使用的数据结构:
1. pairing head
2. radix tree

jemalloc 是 metadata 和 userdata 相互分开的

tls : (使用什么优化，但是看不懂，JEMALLOC_TLS_MODEL)
1. https://software.intel.com/content/www/us/en/develop/blogs/the-hidden-performance-cost-of-accessing-thread-local-variables.html
2. --disable-initial-exec-tls

extend 主要完成从 kernel 获取的内存地址页的管理，由 per arena 的三个数据结构管理

分配使用是 mmap ，但是释放使用的是 madvise(MADV_FREE 和 MADV_DONTNEED)

## profiler
用户层的:
1. https://github.com/KDE/heaptrack
2. https://github.com/koute/memory-profiler

## skbuff

## struct page
- [ ] TODO read it and write a article about it : https://lwn.net/Articles/565097/

## hardware
https://people.freebsd.org/~lstewart/articles/cpumemory.pdf

1. RAM hardware design (speed and parallelism).
2. Memory controller designs.
3. CPU caches.
4. Direct memory access (DMA) for devices

- [ ] 内存控制器的代码在哪里可以找到， 如何实现查找对应

## idel page
- [ ] page_is_young()


## mprotect
[changing memory protection](https://perception-point.io/changing-memory-protection-in-an-arbitrary-process/)

> - The `vm_area_struct` contains the field `vm_flags` which represents the protection flags of the memory region in an architecture-independent manner, and `vm_page_prot` which represents it in an architecture-dependent manner.

> After some reading and digging into the kernel code, we detected the most essential work needed to really change the protection of a memory region:
> - Change the field `vm_flags` to the desired protection.
> - Call the function `vma_set_page_prot` to update the field vm_page_prot according to the vm_flags field.
> - Call the function `change_protection` to actually update the protection bits in the page table.

check the code in `mprotect.c:mprotect_fixup`, above claim can be verified

- except what three steps meantions above, mprotect also splitting and joining memory regions by their protection flags

## vma
[TO BE CONTINUE](https://www.cnblogs.com/LoyenWang/p/12037658.html)

1. 内核地址空间存在 vma 吗 ? TODO
  - 应该是不存在的，不然，该 vma 放到哪里呀 ? 挂到各种用户的 mm_struct 上吗 ?


了解一下 vmacache.c 中间的内容

virtual memory area : 内核管理进程的最小单位。

和其他版块的联系:
1. rmap


细节问题的解释:
- [ ] vma 的 vm_flags 是做什么的
2. mprotect


#### vm_ops
- [ ] `vm_ops->page_mkwrite`

#### vm_flags
in fact, we have already understand most of them

- VM_WIPEONFORK : used by madvise, wipe content when fork, check the function in `dup_mmap`, child process will copy_page_range without it

#### page_flags
- I believe, but have find the evidence yet
  - [ ] pte_mkold / pte_mkyoung is used for access page
  - [ ] arm / mips has to use pgfault to set page access mask

page_flags 除了 PG_slab, PG_slab 等 flags 可以使用，还可以用于标记 node zone LAST_CPUID(numa 平衡算法使用)
```c
static inline void set_page_zone(struct page *page, enum zone_type zone)
{
  page->flags &= ~(ZONES_MASK << ZONES_PGSHIFT);
  page->flags |= (zone & ZONES_MASK) << ZONES_PGSHIFT;
}

static inline void set_page_node(struct page *page, unsigned long node)
{
  page->flags &= ~(NODES_MASK << NODES_PGSHIFT);
  page->flags |= (node & NODES_MASK) << NODES_PGSHIFT;
}
```



## vmalloc
[TO BE CONTINUE](https://www.cnblogs.com/LoyenWang/p/11965787.html)

## mincore

## pageblock
https://richardweiyang-2.gitbook.io/kernel-exploring/00-memory_a_bottom_up_view/13-physical-layer-partition


## user address space
/home/maritns3/core/vn/hack/lab/proc-self-maps/main.c
```
00400000-00401000 r--p 00000000 103:02 13252000                          /home/maritns3/core/vn/hack/lab/proc-self-maps/main.out
00401000-00402000 r-xp 00001000 103:02 13252000                          /home/maritns3/core/vn/hack/lab/proc-self-maps/main.out
00402000-00403000 r--p 00002000 103:02 13252000                          /home/maritns3/core/vn/hack/lab/proc-self-maps/main.out
00403000-00404000 r--p 00002000 103:02 13252000                          /home/maritns3/core/vn/hack/lab/proc-self-maps/main.out
00404000-00405000 rw-p 00003000 103:02 13252000                          /home/maritns3/core/vn/hack/lab/proc-self-maps/main.out
007fa000-0081b000 rw-p 00000000 00:00 0                                  [heap]
7fd3e0f16000-7fd3e0f19000 rw-p 00000000 00:00 0
7fd3e0f19000-7fd3e0f3e000 r--p 00000000 103:02 4982896                   /usr/lib/x86_64-linux-gnu/libc-2.31.so
7fd3e0f3e000-7fd3e10b6000 r-xp 00025000 103:02 4982896                   /usr/lib/x86_64-linux-gnu/libc-2.31.so
7fd3e10b6000-7fd3e1100000 r--p 0019d000 103:02 4982896                   /usr/lib/x86_64-linux-gnu/libc-2.31.so
7fd3e1100000-7fd3e1101000 ---p 001e7000 103:02 4982896                   /usr/lib/x86_64-linux-gnu/libc-2.31.so
7fd3e1101000-7fd3e1104000 r--p 001e7000 103:02 4982896                   /usr/lib/x86_64-linux-gnu/libc-2.31.so
7fd3e1104000-7fd3e1107000 rw-p 001ea000 103:02 4982896                   /usr/lib/x86_64-linux-gnu/libc-2.31.so
7fd3e1107000-7fd3e110b000 rw-p 00000000 00:00 0
7fd3e110b000-7fd3e111a000 r--p 00000000 103:02 4982898                   /usr/lib/x86_64-linux-gnu/libm-2.31.so
7fd3e111a000-7fd3e11c1000 r-xp 0000f000 103:02 4982898                   /usr/lib/x86_64-linux-gnu/libm-2.31.so
7fd3e11c1000-7fd3e1258000 r--p 000b6000 103:02 4982898                   /usr/lib/x86_64-linux-gnu/libm-2.31.so
7fd3e1258000-7fd3e1259000 r--p 0014c000 103:02 4982898                   /usr/lib/x86_64-linux-gnu/libm-2.31.so
7fd3e1259000-7fd3e125a000 rw-p 0014d000 103:02 4982898                   /usr/lib/x86_64-linux-gnu/libm-2.31.so
7fd3e125a000-7fd3e125c000 rw-p 00000000 00:00 0
7fd3e1273000-7fd3e1274000 r--p 00000000 103:02 4982891                   /usr/lib/x86_64-linux-gnu/ld-2.31.so
7fd3e1274000-7fd3e1297000 r-xp 00001000 103:02 4982891                   /usr/lib/x86_64-linux-gnu/ld-2.31.so
7fd3e1297000-7fd3e129f000 r--p 00024000 103:02 4982891                   /usr/lib/x86_64-linux-gnu/ld-2.31.so
7fd3e12a0000-7fd3e12a1000 r--p 0002c000 103:02 4982891                   /usr/lib/x86_64-linux-gnu/ld-2.31.so
7fd3e12a1000-7fd3e12a2000 rw-p 0002d000 103:02 4982891                   /usr/lib/x86_64-linux-gnu/ld-2.31.so
7fd3e12a2000-7fd3e12a3000 rw-p 00000000 00:00 0
7ffcb622f000-7ffcb6250000 rw-p 00000000 00:00 0                          [stack]
7ffcb6374000-7ffcb6377000 r--p 00000000 00:00 0                          [vvar]
7ffcb6377000-7ffcb6378000 r-xp 00000000 00:00 0                          [vdso]
ffffffffff600000-ffffffffff601000 --xp 00000000 00:00 0                  [vsyscall]
```

- [ ] why there are more section for `main.out` than expected ? There are five entry whose path is `proc-self-maps/main.out`.
  - [ ] check the main.out with section header
  - [ ] why two entry has same offset ? third and forth

- [x] why text segment start at 0x40000 ?
  - [ ] read this : https://stackoverflow.com/questions/39689516/why-is-address-0x400000-chosen-as-a-start-of-text-segment-in-x86-64-abi

- [ ] why some area with no names ?

- [x] check inode
  - [ ] https://unix.stackexchange.com/questions/35292/quickly-find-which-files-belongs-to-a-specific-inode-number
    - In fact, we can find file name with inode by checking file one by one, but **debufs** impressed my

- [ ] `[vvar]`

- [ ] `[vdso]`

- [ ] `[vsyscall]`


## kaslr
- [ ] https://unix.stackexchange.com/questions/469016/do-the-virtual-address-spaces-of-all-the-processes-have-the-same-content-in-thei
  - [ ] https://en.wikipedia.org/wiki/Kernel_page-table_isolation
  - [ ] https://lwn.net/Articles/738975/

- [ ] https://bneuburg.github.io/
  - [ ] he has writen three post about it

- [ ] https://lwn.net/Articles/569635/


- [ ] Sometimes /proc/$pid/maps show text address start at 0x400000, sometimes 0x055555555xxx,
maybe because of user space address randomization
    - [  ] https://www.theurbanpenguin.com/aslr-address-space-layout-randomization/

## memfd
https://mp.weixin.qq.com/s/ZLXAz8dAdcqS52MzmXU_YA

## DAX
面试的时候被问了好几次
- `O_DIRECT` 和 DAX 的差别
- 是不是，直接读写 blockdev 是绕过了 fs，但是没有绕过 page cache?

## CXL
- CXL 2.0的基本概念: https://www.zhihu.com/question/531720207/answer/2521601976
- 显存为什么不能当内存使？内存、Cache和Cache一致性: https://zhuanlan.zhihu.com/p/63494668

[^1]: [lwn : Huge pages part 1 (Introduction)](https://lwn.net/Articles/374424/)
[^2]: [lwn : An end to high memory?](https://lwn.net/Articles/813201/)
[^3]: [lwn#memory management](https://lwn.net/Kernel/Index/#Memory_management)
[^5]: [Complete virtual memory map of x86_64](https://www.kernel.org/doc/html/latest/x86/x86_64/mm.html)
[^6]: [NUMA (Non-Uniform Memory Access): An Overview](https://queue.acm.org/detail.cfm?id=2513149)
[^7]: [kernel doc : numa memory policy](https://www.kernel.org/doc/html/latest/admin-guide/mm/numa_memory_policy.html)
[^8]: [kernel doc : pin_user_pages() and related calls](https://www.kernel.org/doc/html/latest/core-api/pin_user_pages.html)
[^9]: [lwn : Explicit pinning of user-space pages](https://lwn.net/Articles/807108/)
[^10]: [stackoverflow : Using move_pages() to move hugepages?](https://stackoverflow.com/questions/59726288/using-move-pages-to-move-hugepages)
[^11]: [kernel doc : page migratin](https://www.kernel.org/doc/html/latest/vm/page_migration.html)
[^13]: [lwn : Smarter shrinkers](https://lwn.net/Articles/550463/)
[^14]: [kernel doc : page owner: Tracking about who allocated each page](https://www.kernel.org/doc/html/latest/vm/page_owner.html)
[^16]: [kernel doc : Driver porting: low-level memory allocation](https://lwn.net/Articles/22909/)
[^17]: [stackoverflow : Why do we need DMA pool ?](https://stackoverflow.com/questions/60574054/why-do-we-need-dma-pool)
[^18]: [kernel doc : Kernel Memory Leak Detector](https://www.kernel.org/doc/html/latest/dev-tools/kmemleak.html)
[^19]: [kernel doc : Heterogeneous Memory Management (HMM)](https://www.kernel.org/doc/html/latest/vm/hmm.html)
[^20]: [lwn : The zsmalloc allocator](https://lwn.net/Articles/477067/)
[^21]: [lwn : A reworked contiguous memory allocator](https://lwn.net/Articles/447405/)
[^22]: [lwn : A deep dive into dma](https://lwn.net/Articles/486301/)
[^23]: [kernel doc : z3fold](https://www.kernel.org/doc/html/latest/vm/z3fold.html)
[^24]: [lwn : Memory management notifiers](https://lwn.net/Articles/266320/)
[^25]: [kernelnewbies : ioremap vs mmap](https://lists.kernelnewbies.org/pipermail/kernelnewbies/2016-September/016814.html)
[^26]: [lwn: ioremap and memremap](https://lwn.net/Articles/653585/)
[^27]: https://lwn.net/Articles/619738/
[^28]: https://www.kernel.org/doc/gorman/html/understand/understand015.html
[^29]: https://my.oschina.net/u/3857782/blog/1854548
