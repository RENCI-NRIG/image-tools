#!/bin/bash
#
# GENI PROJECT LICENSE
# http://www.geni.net/wp-content/uploads/2009/02/geniprojlic.pdf
#
# Copyright (c) 2017 RENCI
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and/or hardware specification
# (the "Work"), to deal in the Work including the rights to use,
# copy, modify, merge, publish, distribute, and sublicense, for
# non-commercial use, copies of the Work, and to permit persons to
# whom the Work is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Work.
#
# The Work can only be used in connection with the execution of a
# project which is authorized by the GENI Project Office (whether or
# not funded through the GENI Project Office). THE WORK IS PROVIDED
# "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
# SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT
# OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE WORK
# OR THE USE OR OTHER DEALINGS IN THE WORK.
#

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# initialize flag vars
name=
size=2G
blocksize=4096
dest="/tmp"
KERN_ARR=  INIT_ARR=  KERN=  INITRD=
url="http://www.your-own-webserver.edu/images"

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
        # Current ExoGENI racks have e2fsprogs that can't handle
        # the "64bit" feature.
        mkfs.ext4 -O ^64bit -F -j $dest/filesystem >/dev/null 2>&1
        RC=$?
        if [ ${RC} -ne 0 ]; then
            # 64bit flag probably unrecognized; give it another shot without.
            mkfs.ext4 -F -j $dest/filesystem >/dev/null
        fi
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
    SELINUX_STATUS=$(getenforce)
    if [ "$SELINUX_STATUS" != "Permissive" ]; then
        setenforce 0
    fi
    # We don't want /vagrant, /home/vagrant, /home/ubuntu, or
    # ${dest} present in the final image; hence, we use the -prune
    # syntax.
    # If we ever start supporting a *nix that uses a static /dev
    # again, this will need to be modified...
    cd /; find . \
               ! -path "./dev/*" \
               ! -path "./proc/*" \
               ! -path "./sys/*" \
               ! -path "./selinux/*" \
               ! -path "./mnt/*" \
               ! -path "./tmp/*" \
               ! -path "./etc/ssh/ssh_host_*" \
               ! -path "./etc/sudoers.d/vagrant" \
               ! -path "./var/spool/mail/vagrant" \
               ! -path "./var/lib/iscsi/*" \
               ! -path "./root/.ssh/*" \
               ! -path "./root/.bash_history" \
               ! -path "./etc/udev/rules.d/70-persistent-net.rules" \
               ! -path "./etc/udev/rules.d/*neuca-persistent*" \
               ! \( -path ./${dest} -prune \) \
               ! \( -path ./vagrant -prune \) \
               ! \( -path ./home/vagrant -prune \) \
               ! \( -path ./home/ubuntu -prune \) \
               ! \( -type f -a -path "./var/lib/neuca/*" -prune \) \
               -print0 \
        | tar -c --selinux --acls --no-recursion --null -T - \
        | tar -C ${dest}/mnt-image -xv --selinux --acls
    if [ "$SELINUX_STATUS" != "Permissive" ]; then
        setenforce 1
    fi
}

fix_debian_ssh () {
cat > ${dest}/mnt-image/etc/rc.local << EOF
#!/bin/bash
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# Regenerate ssh host keys
dpkg-reconfigure openssh-server

exit 0
EOF
}

list_kernel () {
    KERNS=$(ls /boot/vmlinu[xz]* | sort -r | cut -d '/' -f 3)

    num=1
    for i in $KERNS
    do
        echo -e "\t$num)\t$i"
        KERN_ARR[${num}]=$i
        VER_STR=$(echo $i | sed 's/vmlinu[xz]-//')
        MATCHING_INITRD=$(ls /boot/*${VER_STR}* 2>/dev/null | grep init | cut -d '/' -f 3)
        if [ "$MATCHING_INITRD" != "" ]; then
            INIT_ARR[${num}]=$MATCHING_INITRD
        fi
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
    read -t 15 ANSWER

    # Choose newest kernel by default
    [ -z $ANSWER ] && ANSWER=1

    KERN="${KERN_ARR[${ANSWER}]}"
    INITRD="${INIT_ARR[${ANSWER}]}"

    confirm_kernel
}

confirm_kernel () {
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

fix_fstab () {
    if type mkfs.ext4 >/dev/null
    then
        echo  '/dev/vda / ext4 defaults 0 0' > ${dest}/mnt-image/etc/fstab
    elif type mkfs.ext3 >/dev/null
    then
        echo  '/dev/vda / ext3 defaults 0 0' > ${dest}/mnt-image/etc/fstab
    elif type mkfs.ext2 >/dev/null
    then
        echo  '/dev/vda / ext2 defaults 0 0' > ${dest}/mnt-image/etc/fstab
    else
        exit 1
    fi
}

remove_ubuntu_user_records () {
    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/passwd
    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/passwd-
    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/shadow
    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/shadow-

    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/group
    sed -i 's/,ubuntu$//' ${dest}/mnt-image/etc/group
    sed -i 's/:ubuntu$/:/' ${dest}/mnt-image/etc/group
    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/group-
    sed -i 's/,ubuntu$//' ${dest}/mnt-image/etc/group-
    sed -i 's/:ubuntu$/:/' ${dest}/mnt-image/etc/group-

    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/gshadow
    sed -i 's/,ubuntu$//' ${dest}/mnt-image/etc/gshadow
    sed -i 's/:ubuntu$/:/' ${dest}/mnt-image/etc/gshadow
    sed -i '/^ubuntu/d' ${dest}/mnt-image/etc/gshadow-
    sed -i 's/,ubuntu$//' ${dest}/mnt-image/etc/gshadow-
    sed -i 's/:ubuntu$/:/' ${dest}/mnt-image/etc/gshadow-
}

remove_vagrant_user_records () {
    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/passwd
    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/passwd-
    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/shadow
    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/shadow-

    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/group
    sed -i 's/,vagrant$//' ${dest}/mnt-image/etc/group
    sed -i 's/:vagrant$/:/' ${dest}/mnt-image/etc/group
    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/group-
    sed -i 's/,vagrant$//' ${dest}/mnt-image/etc/group-
    sed -i 's/:vagrant$/:/' ${dest}/mnt-image/etc/group-

    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/gshadow
    sed -i 's/,vagrant$//' ${dest}/mnt-image/etc/gshadow
    sed -i 's/:vagrant$/:/' ${dest}/mnt-image/etc/gshadow
    sed -i '/^vagrant/d' ${dest}/mnt-image/etc/gshadow-
    sed -i 's/,vagrant$//' ${dest}/mnt-image/etc/gshadow-
    sed -i 's/:vagrant$/:/' ${dest}/mnt-image/etc/gshadow-
}

finished () {
    type neuca-get-public-ip > /dev/null
    if [ -z $noneuca ] && [ $? eq 0 ]
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

cat << MSG
The following files have been created:
$dest/${name}.tgz
$dest/$KERN
$dest/$INITRD
$dest/${name}.xml

MSG
cat $dest/${name}.xml
}

meta () {
cat > $dest/${name}.xml << EOF
<images>
     <image>
          <type>ZFILESYSTEM</type>
          <signature>$(sha1sum $dest/${name}.tgz | cut -d' ' -f 1)</signature>
          <url>$url/${name}.tgz</url>
     </image>
     <image>
          <type>KERNEL</type>
          <signature>$(sha1sum $dest/$KERN | cut -d' ' -f 1)</signature>
          <url>$url/$KERN</url>
     </image>
     <image>
          <type>RAMDISK</type>
          <signature>$(sha1sum $dest/$INITRD | cut -d' ' -f 1)</signature>
          <url>$url/$INITRD</url>
     </image>
</images>
EOF
}

usage () {
    echo "Usage: $0 [-o (don't use neuca)] [-v (verbose)] [-n name] [-d destination] [-s size (M|MB|G|GB|T|TB)] [-u url (e.g. http://geni-images.renci.org/images)]" >&2
}


### Start of main script...

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

# leading colon is so we do error handling
while getopts :ovn:d:u:b:s: opt
do
    case $opt in
	o)	noneuca="NONEUCA" ;;
        v)      set -x  ;;
        n)      name=$OPTARG    ;;
        d)      dest=$OPTARG    ;;
	u)	url=$OPTARG	;;
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

# Ensure destination exists
if [ ! -d $dest ]; then
    echo "$dest does not exist" 
    exit 1
fi

if [ -z "$name" ]; then
    type neuca-get > /dev/null
    if [ -z $noneuca ] && [ $? -eq 0 ]
    then
        name=$(neuca-get slice_name)
    else
        name="`hostname`"
    fi
fi

select_kernel

create || (echo "Failed to create disk image." && exit 1)
format || (echo "Failed to locate mkfs.  Could not format disk image." && exit 1)

[ ! -d ${dest}/mnt-image ] && mkdir ${dest}/mnt-image
mount -o loop $dest/filesystem ${dest}/mnt-image
copy

fix_fstab
remove_ubuntu_user_records
remove_vagrant_user_records

# Address issue where debian systems fail to auto-regen ssh host keys on boot.  
[ -f ${dest}/mnt-image/etc/debian_version ] && fix_debian_ssh

umount /${dest}/mnt-image || (echo "Failed to unmount image file." && exit 1)

cp /boot/$KERN $dest/$KERN
cp /boot/$INITRD $dest/$INITRD

echo -e "Creating compressed tar archive...\n"
tar -Sczvf ${dest}/${name}.tgz  -C $dest filesystem

echo -e "Generating metadata...\n"
meta

# Print some hints
finished
