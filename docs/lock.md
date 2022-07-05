# Bug in the original code

## Description

After running `bcachetest`, several tests in `usertests`, such as `writebig`, `bigdir`, etc, will fail. 

To pass them, the file system should be cleaned by `$ make clean`.

## Reappearance

1. Checkout **the original code** (use `$ git log` to find the commit like "initial commit")
2. In command line, type:

```
(in host)$ make clean
(in host)$ make qemu

...a lot of output...

xv6 kernel is booting

hart 1 starting
hart 2 starting
init: starting sh
$ bcachetest
start test0
test0 results:
--- lock kmem/bcache stats
lock: kmem: #test-and-set 0 #acquire() 33036
lock: bcache: #test-and-set 29750 #acquire() 65930
--- top 5 contended locks:
lock: virtio_disk: #test-and-set 136647 #acquire() 1186
lock: proc: #test-and-set 38021 #acquire() 622334
lock: proc: #test-and-set 35869 #acquire() 604117
lock: proc: #test-and-set 33544 #acquire() 624644
lock: proc: #test-and-set 33493 #acquire() 604121
tot= 29750
test0: FAIL
start test1
test1 OK
$ usertests writebig
usertests starting
test writebig: panic: balloc: out of blocks

```

## Analysis

The reason is that `bcachetest` write a lot of contents to the virtio disk, which results in insufficient disk blocks, and some of the `usertests` fail to get free blocks.

## Solution (I HAVE APPLIED IT IN MY COMMIT)

A simple way out is to increase the size *(as well as the number of disk blocks)*. To achieve it, you should **modify the macro `FSSIZE` in [kernel/param.h](kernel/param.h) from `1000` to `10000`.**

# Lab 8 - Lock

The original requirements can be found [here](https://pdos.csail.mit.edu/6.S081/2021/labs/lock.html).

## Task 1 - Memory Allocator

### Specification

The root cause of lock contention in `kalloctest` is that `kalloc()` has a single free list, protected by a single lock. 

To remove lock contention, you will have to redesign the memory allocator to avoid a single lock and list. 

The basic idea is to maintain a free list per CPU, each list with its own lock. Allocations and frees on different CPUs can run in parallel, because each CPU will operate on a different list. 

The main challenge will be to deal with the case in which one CPU's free list is empty, but another CPU's list has free memory; in that case, the one CPU must "steal" part of the other CPU's free list. Stealing may introduce lock contention, but that will hopefully be infrequent.

### Solution

The lab specification is clear enough.

To see my implementation, please check [`kernel/kalloc.c`](kernel/kalloc.c). I modified the functions `kalloc(), kfree(), kinit()`, and turned `kmem` into `kmem[NCPU]`.

#### Pit Falls

1. **YOU HAVE TO ACQUIRE BOTH LOCKS IN THE CURRENT CPU AND ANOTHER CPU WHICH YOU WANT TO STEAL MEMORY FROM. OTHERWISE YOU WILL SUFFER LOSS OF FREE PAGES.** For example, if CPU 1 is allocating its free list, while CPU 2 wants to steal a block of free memory from CPU 1, and accidentally both of the CPUs obtained the same block of memory. In another case, if CPU 1 wants to steal memory from CPU 2, at the same time CPU 2 wants to steal memory from CPU 1. These cases all potentially cause problems.
2. **BESIDES, IF NO MEMORY FOUND IN ANOTHER CPU, REMEMBER TO RELEASE THE LOCK OF CURRENT CPU. OTHERWISE YOU WILL SUFFER `panic: sched lock`**

## Task 2 - Buffer Cache

### Specification

Modify the block cache so that the number of `acquire` loop iterations for all locks in the `bcache` is close to zero when running `bcachetest`.

Modify `bget` and `brelse` so that concurrent lookups and releases for different blocks that are in the `bcache` are unlikely to conflict on locks (e.g., don't all have to wait for `bcache.lock`). 

You must maintain the invariant that at most one copy of each block is cached. When you are done, your output should be similar to that shown below (though not identical). 

Make sure `usertests` still passes. `make grade` should pass all tests when you are done.

#### Here are some hints:

- It is OK to use a fixed number of buckets and not resize the hash table dynamically. Use a prime number of buckets (e.g., 13) to reduce the likelihood of hashing conflicts.
- Searching in the hash table for a buffer and allocating an entry for that buffer when the buffer is not found must be atomic.
- <del>Remove the list of all buffers (`bcache.head` etc.) and instead time-stamp buffers using the time of their last use (i.e., using `ticks` in `kernel/trap.c`). With this change `brelse()` doesn't need to acquire the `bcache` lock, and `bget` can select the least-recently used block based on the time-stamps.</del> *I did not implement this because time stamp is error-prone. See [explanation below](#Why-Not-Time-Stamp).*
- It is OK to serialize eviction in `bget` (i.e., the part of `bget` that selects a buffer to re-use when a lookup misses in the cache).
- Your solution might need to hold two locks in some cases; for example, during eviction you may need to hold the `bcache` lock and a lock per bucket. Make sure you avoid deadlock.
- When replacing a block, you might move a `struct buf` from one bucket to another bucket, because the new block hashes to a different bucket. You might have a tricky case: the new block might hash to the same bucket as the old block. Make sure you avoid deadlock in that case.
- Some debugging tips: implement bucket locks but leave the global `bcache.lock` acquire/release at the beginning/end of `bget()` to serialize the code. Once you are sure it is correct without race conditions, remove the global locks and deal with concurrency issues. You can also run `$ make CPUS=1 qemu` to test with one core.

### Solution

Even though the lab specification suggests that use time stamp instead of linked lists to apply LRU policy, I did not use it because it is buggy and hard to debug. 

I use the strategy which is quite like the one in task 1:

1. Turn the original link list in `bcache` to an array of hash buckets, which maintain a doubly linked list by the order of LRU;
2. Assign all buffer blocks to **any ONE** bucket;
3. When `bget()` is called, it first tries finding the block in its own bucket; 
4. If not found the cached block, it will try allocating a Least Recently Used free block in its bucket;
5. If there's no free blocks, it will try stealing a free block from other buckets, also following LRU policy.

### Relevant File

- [`kernel/bio.c`](kernel/bio.c)::`binit(), bget(), brelse()`

### Why Not Time Stamp

#### Initial Thought

Initially I tried to use time stamp with a heap. It goes like this:

1. When a block is acquired or released, update its time stamp;
2. When `bget()` want to recycle an unused block, it will make a min-heap of all blocks based on their time stamp in O(n) time, and start extracting blocks with minimum time stamp;
3. If the extracted block is unused, it can be recycled by the `bget()`.

#### Result

It deadlocks. 

Sometimes in `bcachetest::test0`, and always in `bcachetest::test1`. Besides, it cannot deal with many writes, such as `usertests writebig`.
