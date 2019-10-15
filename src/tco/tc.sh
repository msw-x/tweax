#!/bin/bash

mount_path="/mnt/tc/"
containers_path="/media/$USER/msw-ssd/o/"

if [ "$#" -eq 0 ]
then
	truecrypt -l
else
	if [ "$1" == "l" ]
	then
		truecrypt -l -v
	elif [ "$1" == "m" ]
	then
		echo "mount [$2]"
		sudo mkdir -p "$mount_path"$2
		truecrypt "$containers_path"$2.tc -k "" --protect-hidden=no "$mount_path"$2
	elif [ "$1" == "mr" ]
	then
		echo "mount [$2] read-only"
		sudo mkdir -p "$mount_path"$2
		truecrypt "$containers_path"$2.tc -k "" --protect-hidden=no -m readonly "$mount_path"$2
	elif [ "$1" == "d" ]
	then
		if [ "$#" -eq 1 ]
		then
			echo "dismount all"
			truecrypt -d
		else
			echo "dismount [$2]"
			truecrypt "$containers_path"$2.tc -d
		fi
	fi
fi
