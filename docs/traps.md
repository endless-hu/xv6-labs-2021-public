# Lab 4 - Traps

[Here](https://pdos.csail.mit.edu/6.S081/2021/labs/traps.html) is the original lab specifics.

## Test

The project provides **2 user tests** inside xv6. They are:

- `bttest` in `user/bttest.c`
- `alarmtest` in `user/alarmtest.c`
- `usertests` in `user/usertests.c`

(**NOTE**: *`usertests` is time-consuming!*)

They can be executed by `$ $make qemu` then type their names in the shell of xv6.

Additionally, it offers `$ make grade` for grading the whole lab.

## Task 1 - RISC-V assembly

See the questions and **my answers** in [`answers-traps.txt`](answers-traps.txt).

## Task 2 - Backtrace

### Description

For debugging it is often useful to have a backtrace: a list of the function calls on the stack above the point at which the error occurred.

Implement a `backtrace()` function in `kernel/printf.c`. Insert a call to this function in `sys_sleep`, and then run `bttest`, which calls `sys_sleep`. Your output should be as follows:

```
backtrace:
0x0000000080002cda
0x0000000080002bb6
0x0000000080002898
```

After `bttest` exit qemu. In your terminal: the addresses may be slightly different but if you run `addr2line -e kernel/kernel` (or `riscv64-unknown-elf-addr2line -e kernel/kernel`) and cut-and-paste the above addresses as follows:

```
    $ addr2line -e kernel/kernel
    0x0000000080002de2
    0x0000000080002f4a
    0x0000000080002bfc
    Ctrl-D
```

You should see something like this:

```
    kernel/sysproc.c:74
    kernel/syscall.c:224
    kernel/trap.c:85
```

The compiler puts in each stack frame a frame pointer that holds the address of the caller's frame pointer. Your `backtrace` should use these frame pointers to walk up the stack and print the saved return address in each stack frame.

Some hints:

- Add the prototype for backtrace to `kernel/defs.h` so that you can invoke `backtrace` in `sys_sleep`.

- The GCC compiler stores the frame pointer of the currently executing function in the register`s0`. Add the following function to`kernel/riscv.h`:

  ```
  static inline uint64
  r_fp()
  {
    uint64 x;
    asm volatile("mv %0, s0" : "=r" (x) );
    return x;
  }
  ```

  and call this function in`backtrace` to read the current frame pointer. This function uses in-line assembly to read `s0`.

- These [lecture notes](https://pdos.csail.mit.edu/6.828/2021/lec/l-riscv-slides.pdf) have a picture of the layout of stack frames. Note that the return address lives at a fixed offset (-8) from the frame pointer of a stackframe, and that the saved frame pointer lives at fixed offset (-16) from the frame pointer.

- Xv6 allocates one page for each stack in the xv6 kernel at PAGE-aligned address. You can compute the top and bottom address of the stack page by using `PGROUNDDOWN(fp)` and `PGROUNDUP(fp)` (see `kernel/riscv.h`. These number are helpful for `backtrace` to terminate its loop.

Once your `backtrace` is working, call it from `panic` in `kernel/printf.c` so that you see the kernel's `backtrace`when it panics.

### Solution

In `backtrace()`:

1. Use `r_fp()` to get the current frame pointer;

2. Check if the top address of the current stack frame equals to the return address

   2.1. If it does, then it is the last stack frame, so terminate the loop;

   2.2. Else, print out the return address, which can be obtained by `*(fp-8)`. Then assign the previous stack frame pointer, which can be obtained by `*(fp-16)`, to `fp`.

3. Finally, print out the return address of the last stack frame.

See my code in [`kernel/printf.c: backtrace()`](kernel/printf.c).

## Task 3 - Alarm

### Description

In this exercise you'll add a feature to xv6 that periodically alerts a process as it uses CPU time. This might be useful for compute-bound processes that want to limit how much CPU time they chew up, or for processes that want to compute but also want to take some periodic action. More generally, you'll be implementing a primitive form of user-level interrupt/fault handlers; you could use something similar to handle page faults in the application, for example. Your solution is correct if it passes `alarmtest` and `usertests`.

You should add a new `sigalarm(interval, handler)` system call. If an application calls `sigalarm(n, fn)`, then after every `n` "ticks" of CPU time that the program consumes, the kernel should cause application function `fn` to be called. When `fn` returns, the application should resume where it left off. A tick is a fairly arbitrary unit of time in xv6, determined by how often a hardware timer generates interrupts. If an application calls `sigalarm(0, 0)`, the kernel should stop generating periodic alarm calls.

You'll find a file `user/alarmtest.c` in your xv6 repository. Add it to the Makefile. It won't compile correctly until you've added `sigalarm` and `sigreturn` system calls (see below).

`alarmtest` calls `sigalarm(2, periodic)` in `test0` to ask the kernel to force a call to `periodic()` every 2 ticks, and then spins for a while. You can see the assembly code for `alarmtest` in `user/alarmtest.asm`, which may be handy for debugging. Your solution is correct when `alarmtest` produces output like this and `usertests` also runs correctly:

```
$ alarmtest
test0 start
........alarm!
test0 passed
test1 start
...alarm!
..alarm!
...alarm!
..alarm!
...alarm!
..alarm!
...alarm!
..alarm!
...alarm!
..alarm!
test1 passed
test2 start
................alarm!
test2 passed
$ usertests
...
ALL TESTS PASSED
$
```

When you're done, your solution will be only a few lines of code, but it may be tricky to get it right. We'll test your code with the version of `alarmtest.c` in the original repository. You can modify `alarmtest.c` to help you debug, but make sure the original `alarmtest` says that all the tests pass.

### Solution

1. Add the members `int time_since_last_call`, `int alarm_interval`, `uint64 fn`(the handler's address) and `struct trapframe *shadow_frame` to the `struct proc`.

2. Both in `usertrap()` and `kerneltrap()`, add the code to the time interrupt handling block(`which_dev == 2` indicates that the current interrupt is time interrupt) to increase the count of `time_since_last_call` in the current process.

3. Check if `p->time_since_last_call` equals to `p->alarm_interval`;

   4.1.1 If it does, then it's time to set off alarm.

      4.1.2 Before setting off alarm, first check if we are handling an alarm(re-entrance of alarm is not allowed) by checking whether `p->shadow_frame` is `NULL`(0). 

      (**NOTE:** `p->shadow_frame` stores the current trapframe so that when we returned from handler, we can restore everything before we jumped to the handler)

   ​    4.1.2.1 Allocate space for `p->shadow_frame`, save the current `p->trapframe` to `p->shadow_frame`, then set the `p->trapframe->epc` to the address of the handler(i.e. `p->fn`)

   ​    (**NOTE:** the handler will be executed after `usertrapret()`, which will return to where `p->trapframe->epc` points to in the user space)

   4.2 Else we just return.

4. In `kernel/sysproc.c`, we set up the alarm interval and the address of the handler function in `sys_sigalarm()`; and in the `sys_sigreturn()`, if `p->shadow_frame` exists, we restore `p->trapframe` and free `p->shadow_frame`.

There's other miscellaneous staffs like adding declarations in `user/user.h`, adding entries in `user/usys.pl`, adding `user/alarmtest` to `Makefile`, adding `syscall numbers` in `kernel/syscall.h` and entries in `kernel/syscall.c`.



