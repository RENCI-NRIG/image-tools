#!/bin/bash
#set -x

PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH

KERN_ARR=
INIT_ARR=

show_kern () {
  KERNS=$(ls /boot/vmlin* | sort -r | cut -d '/' -f 3)
  INITS=$(ls /boot/init* | sort -r | cut -d '/' -f 3)
  num=1
  for i in $INITS
  do
	  INIT_ARR[${num}]=$i
	  num=$((num+1))
  done;

  num=1
  for i in $KERNS
  do
	  echo -e "\t$num)\t$i"
	  KERN_ARR[${num}]=$i
	  num=$((num+1))
  done;
}



echo ""
echo "Select an available kernel by number from below:"
show_kern
read ANSWER
KERN="/boot/${KERN_ARR[${ANSWER}]}"
INITRD="/boot/${INIT_ARR[${ANSWER}]}"

echo "Your chosen kernel is $KERN"
echo "Your chosen ramdisk is $INITRD"
