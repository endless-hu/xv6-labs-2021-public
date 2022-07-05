# Lab 6 - Multithreading

[Here](https://pdos.csail.mit.edu/6.S081/2021/labs/thread.html) is the original lab specifics.

## Task 1

### Specification

Come up with a plan to create threads and save/restore registers to switch between threads, and implement that plan.

You will need to add code to `thread_create()` and `thread_schedule()` in [`user/uthread.c`](user/uthread.c), and `thread_switch` in [`user/uthread_switch.S`](user/uthread_switch.S). One goal is ensure that when `thread_schedule()` runs a given thread for the first time, the thread executes the function passed to `thread_create()`, on its own stack. Another goal is to ensure that `thread_switch` saves the registers of the thread being switched away from, restores the registers of the thread being switched to, and returns to the point in the latter thread's instructions where it last left off. You will have to decide where to save/restore registers; modifying `struct thread` to hold registers is a good plan. You'll need to add a call to `thread_switch` in `thread_schedule`; you can pass whatever arguments you need to `thread_switch`, but the intent is to switch from thread `t` to `next_thread`.

### Solution

1. Add `struct context` definition in [`user/uthread.c`](user/uthread.c) (it's the same as the definition in the kernel). And add the context to the `struct thread`.
2. Since the switching process is all the same in `xv6`, just copy the [`kernel/swtch.S`](kernel/swtch.S) is enough to implement the [`user/uthread_switch.S`](user/uthread_switch.S).
3. In `thread_schedule()`, when it's going to switch threads, call `thread_switch(&old_thread->context, &new_thread->context)`.
4. In `thread_create()`, add code to set its `context.ra` to the address of the function passed in, and set its `context.sp` to its own stack. NOTE `sp` SHOULD POINT TO THE END ADDRESS OF ITS STACK!!!

## Task 2

### Specification

#### Background

[`notxv6/ph.c`](notxv6/ph.c) implements a hash table. Initially, when you type:

```
$ make ph
$ ./ph 1
```

The Makefile uses **your OS's `gcc`**, **not the 6.S081 tools**, to build `ph.c`. The argument to `ph` specifies the number of threads that execute put and get operations on the the hash table. After running for a little while, `ph 1` will produce output similar to this:

```
100000 puts, 3.991 seconds, 25056 puts/second
0: 0 keys missing
100000 gets, 3.981 seconds, 25118 gets/second
```

`ph` runs two benchmarks. First it adds lots of keys to the hash table by calling `put()`, and prints the achieved rate in puts per second. The it fetches keys from the hash table with `get()`. It prints the number keys that should have been in the hash table as a result of the puts but are missing (zero in this case), and it prints the number of gets per second it achieved.

Try `ph 2`:

```
$ ./ph 2
100000 puts, 1.885 seconds, 53044 puts/second
1: 16579 keys missing
0: 16579 keys missing
200000 gets, 4.322 seconds, 46274 gets/second
```

It reports that the hash table lost many keys. Reasons can be seen at [Appendix](#Appendix: Answer to Question In Task 2).

#### Task

Add locks to [`notxv6/ph.c`](notxv6/ph.c) so that the hash table will work correctly in parallel situation.

At the same time, utilize parallelism to maximize the performance. (*two threads* yield **at least** 1.25 times as many puts/second as *one thread*.)

### Solution

1. Add `mutex` to the entry of `table` like this:

   ```c
   struct entry {
     int key;
     int value;
     struct entry *next;
   };
   struct safe_entry {
     struct entry *begin;
     pthread_mutex_t lock;
   };
   struct safe_entry table[NBUCKET];
   ```

2. Add the lock to the corresponding hash bucket before `put()` starts to read the table.

3. Adjust other parts of the code accordingly.

## Task 3

### Specification

The file `notxv6/barrier.c` contains a broken barrier.

```
$ make barrier
$ ./barrier 2
barrier: notxv6/barrier.c:42: thread: Assertion `i == t' failed.
```

The 2 specifies the number of threads that synchronize on the barrier ( `nthread` in `barrier.c`). Each thread executes a loop. In each loop iteration a thread calls `barrier()` and then sleeps for a random number of microseconds. The assert triggers, because one thread leaves the barrier before the other thread has reached the barrier. The desired behavior is that each thread blocks in `barrier()` until all `nthreads` of them have called `barrier()`.

Your goal is to achieve the desired barrier behavior.

### Solution

It's too easy. See my code in [`notxv6/barrier.c:barrier()`](notxv6/barrier.c) directly. 



## Appendix: Answer to Question In Task 2

### Question

Why are there missing keys with 2 threads, but not with 1 thread? Identify a sequence of events with 2 threads that can lead to a key being missing. 

### Answer

  For example, assume that there are 2 threads.

  According to the code:

  ```c
  put_thread(void *xa)
  {
  int n = (int) (long) xa; // thread number
  int b = NKEYS/nthread;   // in this situation, b = 5000

    for (int i = 0; i < b; i++) {
      put(keys[b*n + i], n);
    }

  return NULL;
  }
  ```

  Also assume that in the first round (i.e. `i == 0`), `thread 0` wants to put `keys[0] = 5` into the hash table, while `thread 1` wants to put `keys[5000] = 10` into the hash table. They call `put()` almost at the same time.

In the function `put()`:

```c
static
void put(int key, int value)
{
  int i = key % NBUCKET;

  // is the key already present?
  struct entry *e = 0;
  for (e = table[i]; e != 0; e = e->next) {
    if (e->key == key)
      break;
  }
  if(e){
    // update the existing key.
    e->value = value;
  } else {
    // the new is new.
    insert(key, value, &table[i], table[i]);
  }
```

We assume that the hash table is empty now. Both threads will hash their keys into `0`, so they all want to insert a key value pair into `table[0]`.

Assume `thread 0` goes first. At `line 17`, when it is about to insert `{5, 0}` into `table[0]`, it is switched to the `thread 1`. 

Now `thread 1` also want to insert `{10, 1}` into `table[0]`, so it looks at the `table[0]` and find it empty. Again at `line 17`, when `thread 1` is about to insert `{10, 1}` into `table[0]`, it is switched back to `thread 0`.

`thread 0` continues inserting `{5, 0}`. Look at the code `insert()`:

```c
static void 
insert(int key, int value, struct entry **p, struct entry *n)
{
  struct entry *e = malloc(sizeof(struct entry));
  e->key = key;
  e->value = value;
  e->next = n;
  *p = e;
}
```

Assume when `e->next = n;` at `line 7` got executed, it got switched to `thread 1`. 

Now the `e` in `thread 0` is `e = {key = 5, value = 0, next = NULL}`, while `table[0] = NULL`.

Assume `thread 1` executed all of the instructions before it is switched to `thread 0`. Therefore, when `thread 0` continue to execute, `table[0]` points to `e = {key = 10, value = 1, next = NULL}` in `thread 1`.

`thread 0` completes its insertion, but now `table[0]` points to `e = {key = 5, value = 0, next = NULL}`, the `e` in `thread 0`.

Therefore, we can see that the key-value pair created by `thread 1` got lost.