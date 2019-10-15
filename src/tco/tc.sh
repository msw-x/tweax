#!/bin/bash

mount_path="/mnt/tc/"
containers_path="/media/$USER/msw-ssd/.o/"

if [ "$#" -eq 2 ]; then
	name=$2
	file=$(ls $containers_path -1 | egrep -o "^$name.*" -m 1)
	mount="$mount_path$name"
	container="$containers_path$file"

	mount_readwrite="$container --keyfiles= --protect-hidden=no $mount"
	mount_readonly="$container --keyfiles= --protect-hidden=no -m readonly $mount"
fi

if [ "$#" -eq 0 ]
then
	truecrypt -l
else
	if [ "$1" == "l" ]
	then
		truecrypt -l -v
	elif [ "$1" == "m" ]
	then
		echo "mount [$name]"
		sudo mkdir -p $mount
		truecrypt $mount_readwrite
	elif [ "$1" == "mr" ]
	then
		echo "mount [$name] read-only"
		sudo mkdir -p $mount
		truecrypt $mount_readonly
	elif [ "$1" == "d" ]
	then
		if [ "$#" -eq 1 ]
		then
			echo "dismount all"
			truecrypt -d
		else
			echo "dismount [$name]"
			truecrypt $container -d
		fi
	fi
fi
