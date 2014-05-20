#!/bin/bash
#
# GENI PROJECT LICENSE
# http://www.geni.net/wp-content/uploads/2009/02/geniprojlic.pdf
#
# Copyright (c) 2014 RENCI
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and/or hardware specification (the "Work"), to deal in the Work including the rights to use, copy,
# modify, merge, publish, distribute, and sublicense, for non-commercial use, copies of the Work,
# and to permit persons to whom the Work is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Work.
#
# The Work can only be used in connection with the execution of a project which is authorized by
# the GENI Project Office (whether or not funded through the GENI Project Office).
# THE WORK IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE WORK OR THE USE OR OTHER DEALINGS
# IN THE WORK.
#

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# initialize flag vars
name=   dest=   size=2G   blocksize=4096

seek () {

  case "$size" in
    *T* | *TB*)
        d=$(echo "$size" | awk -F'T' '{print $1}')
        let "seek=($d << 40)/$blocksize"
        ;;
    *G* | *GB*)
        d=$(echo "$size" | awk -F'G' '{print $1}')
        let "seek=($d << 30)/$blocksize"
        ;;
    *M* | *MB*)
        d=$(echo "$size" | awk -F'M' '{print $1}')
        let "seek=($d << 20)/$blocksize"
        ;;
    *)
	break
	;;
  esac
  echo "$seek";
}

create () {
  if type dd >/dev/null
  then
    dd if=/dev/zero of=$dest/filesystem bs=$blocksize seek=$seek count=0
  else
    exit 1
  fi
}

format () {
  if type mkfs.ext4 >/dev/null
  then
    mkfs.ext4 -F -j $dest/filesystem >/dev/null
  elif type mkfs.ext3 >/dev/null
  then
    mkfs.ext3 -F -j $dest/filesystem >/dev/null
  elif type mkfs.ext2 >/dev/null
  then
    mkfs.ext2 -F -j $dest/filesystem >/dev/null
  else
    exit 1
  fi
}

copy () {
cd /; find . ! -path "./tmp/*" ! -path "./proc/*" ! -path "./sys/*" \
  ! -path "./mnt/*" ! -path "./etc/ssh/ssh_host_*" \
  ! -path "./var/lib/iscsi/*" ! -path "/root/.ssh/*" \
  ! -path "./etc/udev/rules.d/70-persistent-net.rules" \
  | cpio -pmdv /mnt/tmp
}

finished () {

if type neuca-get-public-ip >/dev/null
then
  IP=$(neuca-get-public-ip)
elif type curl >/dev/null
then
  IP=$(curl icanhazip.com)
  RETVAL=$?
  if [ $RETVAL -ne 0 ]; then
    IP=$(curl ifconfig.me)
  fi
else
  IP=`hostname`
fi
  

cat << HELP
The following files have been created:

$dest/${name}.tgz
$dest/${name}.aki
$dest/${name}.ari
$dest/${name}.xml

To download them and preserve the sparseness of the disk image, we recommend running
the following command from your own workstation:

  ssh -i ~/.ssh/<id_rsa> root@$IP 'cd $dest; tar cfS - ${name}.*' | tar xvfS -

where <id_rsa> is the actual name of the ssh private key file that you used with Flukes.

HELP
}

meta () {
cat > $dest/${name}.xml << EOF
<images>
     <image>
          <type>ZFILESYSTEM</type>
          <signature>$(sha1sum $dest/${name}.tgz | cut -d' ' -f 1)</signature>
          <url>http://www.your-own-webserver.edu/images/${name}.tgz</url>
     </image>
     <image>
          <type>KERNEL</type>
          <signature>$(sha1sum $dest/${name}.aki | cut -d' ' -f 1)</signature>
          <url>http://www.your-own-webserver.edu/images/${name}.aki</url>
     </image>
     <image>
          <type>RAMDISK</type>
          <signature>$(sha1sum $dest/${name}.ari | cut -d' ' -f 1)</signature>
          <url>http://www.your-own-webserver.edu/images/${name}.ari</url>
     </image>
</images>
EOF
}

usage () {
echo "Usage: $0 [-v] [-n name] [-d destination] [-s size (M|MB|G|GB|T|TB)]" >&2
}


if [ $# -lt 2 ]; then
  usage
  exit 1
fi






# leading colon is so we do error handling
while getopts :vn:d:b:s: opt
do
        case $opt in
        v)      set -x  ;;
        n)      name=$OPTARG    ;;
        d)      dest=$OPTARG    ;;
	b)	blocksize=$OPTARG ;;
        s)      size=$OPTARG
		seek=$(seek) 
		if [ -z "$seek" ]; then
			echo "Please specify size in units of M|MB|G|GB|T|TB"
			exit 1
		fi
		;;
        *)      echo "$0: invalid option" >&2
		usage
		exit
		;;
        esac
done
shift $((OPTIND - 1))   # Remove options, leave arguments

# validate destination directory for image
if [ -z "$dest" ]; then
  if type neuca-get >/dev/null
  then
    dest=$(neuca-get storage dev0 | awk -F':' '{print $11}')
  else
    dest="/tmp"
  fi
fi
# Ensure destination exists
[ -d $dest ] || (echo "$dest does not exist" && exit 1)

if [ -z "$name" ]; then
  if type neuca-get >/dev/null
  then
    name=$(neuca-get slice_name)
  else
    name="`hostname`"
  fi
fi

create || (echo "Failed to create disk image." && exit 1)
format || (echo "Failed to locate mkfs.  Could not format disk image." && exit 1)
[ ! -d /mnt/tmp ] && mkdir /mnt/tmp
mount -o loop $dest/filesystem /mnt/tmp
copy
umount /mnt/tmp || (echo "Failed to unmount image file." && exit 1)
cp -a $(grep `uname -r` <<< "$(ls /boot/*)" | grep vmlin) $dest/${name}.aki
cp -a $(grep `uname -r` <<< "$(ls /boot/*)" | grep initr) $dest/${name}.ari
tar -Sczvf ${dest}/${name}.tgz  -C $dest filesystem
meta

# Print some hints
finished
