#!/bin/bash
#set -x

PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH

KERN_ARR=
INIT_ARR=

list_kernel () {
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

  if [ ${#KERN_ARR[@]} -ne ${#INIT_ARR[@]} ]; then
	echo "WARNING: You do not have the same number of kernels & initrds;"
	echo "This may not work..."
  fi
}

select_kernel () {
echo ""
echo "Select an available kernel by number from below:"
list_kernel
read -t 30 ANSWER
KERN="/boot/${KERN_ARR[${ANSWER}]}"
INITRD="/boot/${INIT_ARR[${ANSWER}]}"

confirm_kernel
}

confirm_kernel() {
echo "Your chosen kernel is $KERN.  Is this correct? (Y|n)"
echo ""
read -t 30 CONFIRM
case "$CONFIRM" in
	"y" | "Y" | "")
		echo "Using kernel ${KERN_ARR[${ANSWER}]} and initrd ${INIT_ARR[${ANSWER}]}..."
	;;

        "n" | "N")
		echo "Let's try again..."
		select_kernel
		
	;;
esac
}


select_kernel
