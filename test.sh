#!/usr/bin/bash

grade() {
	echo "== Grading Lab $1 =="
	sleep 1
	git checkout origin/$1
	make clean
	make grade
	sleep 1
	make clean
	git switch main
}

cd `dirname "$0"`

if [ -z "$1" ]; then
	echo "WARN: You are going to run ALL the tests. It is estimated to cost MORE THAN TEN MINITES!!!"
	echo "Proceed? [y/n]"
	read ans
	if [ $ans == "y" ]; then
		grade "util"
		grade "syscall"
		grade "pgtbl"
		grade "traps"
		grade "cow"
		grade "thread"
		grade "net"
		grade "lock"
		grade "fs"
                grade "mmap"
	else
		echo "Operation Cancelled"
		exit
	fi
fi

while [ -n "$1" ]; do
	if [[ $1 =~ ^(util|syscall|pgtbl|traps|cow|thread|net|lock|fs|mmap)$ ]]; then
		grade $1
	else
		echo "EOORO: Unknown lab name: $1"
		echo "Usage: \$ ./test.sh [labname] ..."
		echo "current labs: "
		echo util
		echo syscall
		echo pgtbl
		echo traps
		echo cow
		echo thread
		echo net
		echo lock
		echo fs
                echo mmap
	fi
	shift
done
