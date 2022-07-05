# Lab 3 - Page Table

[Here](https://pdos.csail.mit.edu/6.S081/2021/labs/pgtbl.html) is the original lab specifics

## Test

The project provides **2 user tests** inside xv6. They are:

- `pgtbltest` in `user/pgtbltest.c`
- `usertests` in `user/usertests.c`

They can be executed by `make qemu` then type their names in the shell of xv6.

Additionally, it offers `$ make grade` for grading the whole lab. 

### Results

#### 2021/10/29

**I RECEIVED FULL SCORE IN `$ make grade`**. The two problems of my previous implementations are that:

1. *In `proc_freepagetable()`, I should just unmap the user page instead of unmapping and freeing it by calling `uvmunmap(pagetable, USYSCALL, 1)`.* This problem caused the test `execout()` to `panic: kerneltrap`.
2. *I should call `kfree()` to free the user page in `freeproc()` before it calls `proc_freepagetable()`.* This problem caused the `usertests` loss of free pages because it did not free the user page. 

In a word, the free of the page and the unmap of the page should be separated. 

I cannot explain it for now. In the code, `uvmunmap()` will call `kfree()` to free the unmapped page if I want it to do so. 

#### 2021/10/28

**I PASSED ALL TESTS FOR THE THREE TASK**, but there are some potential errors in my implementation of *Task 1*, so `usertests` fails. 

**`usertests::execout()`**, which is to test whether the system will behave normally when the memory is full, crashes because of the potential errors.

It prompts `panic: kerneltrap`. But I have not learned trap yet, so I do not know how to debug it. When the next lab is finished, I'll go back here to fix the problem.

## Task  1 - Speed up system calls

### Specifics

Some operating systems (e.g., Linux) speed up certain system calls by sharing data in a read-only region between userspace and the kernel. This eliminates the need for kernel crossings when performing these system calls. To help you learn how to insert mappings into a page table, your first task is to implement this optimization for the `getpid()` system call in xv6.

When each process is created, map one read-only page at USYSCALL (a VA defined in `memlayout.h`). At the start of this page, store a `struct usyscall` (also defined in `memlayout.h`), and initialize it to store the PID of the current process. For this lab, `ugetpid()` has been provided on the userspace side and will automatically use the USYSCALL mapping. You will receive full credit for this part of the lab if the `ugetpid` test case passes when running `pgtbltest`.

Some hints:

- You can perform the mapping in `proc_pagetable()` in `kernel/proc.c`.
- Choose permission bits that allow userspace to only read the page.
- You may find that `mappages()` is a useful utility.
- Don't forget to allocate and initialize the page in `allocproc()`.
- Make sure to free the page in `freeproc()`.

**Question**: Which other xv6 system call(s) could be made faster using this shared page? Explain how.

### Solution

1. In `allocproc()`, before it calls `proc_pagetable()` to set up its page table, allocate a page for the user page in `struct proc :: struct usyscall *shared_page`
2. In `proc_pagetable()`, call `mappages()` to map the allocated page to `USYSCALL`
3. In `proc_freepagetable()`, call `uvmunmap()` to unmap and free the allocated page

See my code in [`kernel/proc.c`](./kernel/proc.c).

### Pitfalls

#### UPDATE AFTER COMPLETE THE LAB

**The hint is right.** The page should be freed in `freeproc()`, then unmapped in `proc_freepagetable()`. If only unmap it in `proc_freepagetable()` and want it to be freed by `uvmunmap()`, the system will suffer loss of free pages.

#### ORIGINAL THOUGHTS

**The last hint is misleading.** I free the page in `proc_freepagetable()` instead of `freeproc()`.

When the system boot up, it will call `allocproc()`, which will allocate and map the use page. After that, `free_pagetable()` will be called to free the page table created by `allocproc()`. Therefore, if I free the user page in `freeproc()`, the user page will not be freed in the process of booting up, and it will cause panic `freewalk: leaf`. **In a word, if I free the user page only in `freeproc()`, the system will not successfully boot up.**

Besides, if I unmap the user page in `freeproc()`, the system will boot up as normal. But if I call the test, it will run into the problem "repeated free". Because when the process is going to terminate, the `freeproc()` will be called to free its structure.  However, `freeproc()` itself will call `proc_freepagetable()` to free its page table. If I perform the operation of freeing the user page in `freeproc()`, it is doomed to free the user page twice, which is an error. 

### Answer To Question

**Question**: Which other xv6 system call(s) could be made faster using this shared page? Explain how.

**Answer**: I think `fstat()` can also be made faster. We can add `struct fstat` in `strcut usyscall` and retrieve it from `struct usyscall` directly. 



## Task 2 - Print a page table

To help you visualize RISC-V page tables, and perhaps to aid future debugging, your second task is to write a function that prints the contents of a page table.

Define a function called `vmprint()`. It should take a `pagetable_t` argument, and print that pagetable in the format described below. Insert `if(p->pid==1) vmprint(p->pagetable)` in exec.c just before the `return argc`, to print the first process's page table. You receive full credit for this part of the lab if you pass the `pte printout` test of `make grade`.

Now when you start xv6 it should print output like this, describing the page table of the first process at the point when it has just finished `exec()`ing `init`:

```
page table 0x0000000087f6e000
 ..0: pte 0x0000000021fda801 pa 0x0000000087f6a000
 .. ..0: pte 0x0000000021fda401 pa 0x0000000087f69000
 .. .. ..0: pte 0x0000000021fdac1f pa 0x0000000087f6b000
 .. .. ..1: pte 0x0000000021fda00f pa 0x0000000087f68000
 .. .. ..2: pte 0x0000000021fd9c1f pa 0x0000000087f67000
 ..255: pte 0x0000000021fdb401 pa 0x0000000087f6d000
 .. ..511: pte 0x0000000021fdb001 pa 0x0000000087f6c000
 .. .. ..509: pte 0x0000000021fdd813 pa 0x0000000087f76000
 .. .. ..510: pte 0x0000000021fddc07 pa 0x0000000087f77000
 .. .. ..511: pte 0x0000000020001c0b pa 0x0000000080007000
  
```

The first line displays the argument to `vmprint`. After that there is a line for each PTE, including PTEs that refer to page-table pages deeper in the tree. Each PTE line is indented by a number of `" .."` that indicates its depth in the tree. Each PTE line shows the PTE index in its page-table page, the pte bits, and the physical address extracted from the PTE. Don't print PTEs that are not valid. In the above example, the top-level page-table page has mappings for entries 0 and 255. The next level down for entry 0 has only index 0 mapped, and the bottom-level for that index 0 has entries 0, 1, and 2 mapped.

Your code might emit different physical addresses than those shown above. The number of entries and the virtual addresses should be the same.

Some hints:

- You can put `vmprint()` in `kernel/vm.c`.
- Use the macros at the end of the file kernel/riscv.h.
- The function `freewalk` may be inspirational.
- Define the prototype for `vmprint` in kernel/defs.h so that you can call it from exec.c.
- Use `%p` in your printf calls to print out full 64-bit hex PTEs and addresses as shown in the example.

**Question**: Explain the output of `vmprint` in terms of Fig 3-4 from the text. What does page 0 contain? What is in page 2? When running in user mode, could the process read/write the memory mapped by page 1? What does the third to last page contain?

### Solution

Actually, the function `freewalk()` already told me how to do this. Just some modifications on `freewalk()` is enough to implement `vmprint()`. 

Basic idea:

1. Iterate PTEs through the given `pagetable`
2. If the page table is the bottom level table, then print all of its valid PTEs(which points to pages)
3. Otherwise, if the PTE is valid and its read, write and execute bits are not set, which indicates that the PTE points to next level of a page table, recursively call the `vmprint()`

See my code in [`kernel/vm.c: vmprint()`](./kernel/vm.c).

### Answer To Question

**Question**: Explain the output of `vmprint` in terms of Fig 3-4 from the text. What does page 0 contain? What is in page 2? When running in user mode, could the process read/write the memory mapped by page 1? What does the third to last page contain?

**Answer**: Page 0 contains 2 PTEs:

```
 ..0: pte 0x0000000021fda801 pa 0x0000000087f6a000
 ..255: pte 0x0000000021fdb401 pa 0x0000000087f6d000
```

Page 2 is the bottom level of the first page, there are 3 PTEs pointing to pages:

```
 .. .. ..0: pte 0x0000000021fdac1f pa 0x0000000087f6b000
 .. .. ..1: pte 0x0000000021fda00f pa 0x0000000087f68000
 .. .. ..2: pte 0x0000000021fd9c1f pa 0x0000000087f67000
```

There's only one PTE in page 1: ` .. ..0: pte 0x0000000021fda401 pa 0x0000000087f69000`. And the risc-v manual told me that the **fourth** bit of a PTE indicates whether the page can be accessed in user mode. Here the bit is **0**, so it cannot be accessed by user mode process.

Page 3 contains:

```
 .. ..511: pte 0x0000000021fdb001 pa 0x0000000087f6c000
```

Page 4, which is the last page, contains:

```
 .. .. ..509: pte 0x0000000021fdd813 pa 0x0000000087f76000
 .. .. ..510: pte 0x0000000021fddc07 pa 0x0000000087f77000
 .. .. ..511: pte 0x0000000020001c0b pa 0x0000000080007000
```



### Task 3 - Detecting which pages have been accessed

Some garbage collectors (a form of automatic memory management) can benefit from information about which pages have been accessed (read or write). In this part of the lab, you will add a new feature to xv6 that detects and reports this information to userspace by inspecting the access bits in the RISC-V page table. The RISC-V hardware page walker marks these bits in the PTE whenever it resolves a TLB miss.

Your job is to implement `pgaccess()`, a system call that reports which pages have been accessed. The system call takes three arguments. First, it takes the starting virtual address of the first user page to check. Second, it takes the number of pages to check. Finally, it takes a user address to a buffer to store the results into a bit mask (a data structure that uses one bit per page and where the first page corresponds to the least significant bit). You will receive full credit for this part of the lab if the `pgaccess` test case passes when running `pgtbltest`.

Some hints:

- Start by implementing `sys_pgaccess()` in `kernel/sysproc.c`.
- You'll need to parse arguments using `argaddr()` and `argint()`.
- For the output bitmask, it's easier to store a temporary buffer in the kernel and copy it to the user (via `copyout()`) after filling it with the right bits.
- It's okay to set an upper limit on the number of pages that can be scanned.
- `walk()` in `kernel/vm.c` is very useful for finding the right PTEs.
- You'll need to define `PTE_A`, the access bit, in `kernel/riscv.h`. Consult the RISC-V manual to determine its value.
- Be sure to clear `PTE_A` after checking if it is set. Otherwise, it won't be possible to determine if the page was accessed since the last time `pgaccess()` was called (i.e., the bit will be set forever).
- `vmprint()` may come in handy to debug page tables.

### Solutions

1. Use `argint()` and `argaddr()` to get *the starting virtual address*, *the number of pages to check*, and *the user address to a buffer*.
2. Iterate through all pages, check their access bit*(the sixth bit in a PTE, defined as `#define PTE_A (1L << 6)` in `kernel/riscv.h`)*. 
3. If the bit is set, unset it and set corresponding bit in the user buffer. Otherwise do nothing.

See my code in [`kernel/sysproc.c: sys_pgaccess()`](./kernel/sysproc.c).
