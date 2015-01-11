#!/bin/bash

# Colors :
txtblk='\e[0;30m' # Black - Regular
txtred='\e[0;31m' # Red
txtgrn='\e[0;32m' # Green
txtylw='\e[0;33m' # Yellow
txtblu='\e[0;34m' # Blue
txtlbl='\e[0;94m' # LightBlue
txtpur='\e[0;35m' # Purple
txtcyn='\e[0;36m' # Cyan
txtwht='\e[0;37m' # White
bldblk='\e[1;30m' # Black - Bold
bldred='\e[1;31m' # Red
bldgrn='\e[1;32m' # Green
bldylw='\e[1;33m' # Yellow
bldblu='\e[1;34m' # Blue
bldlbl='\e[1;94m' # LightBlue
bldpur='\e[1;35m' # Purple
bldcyn='\e[1;36m' # Cyan
bldwht='\e[1;37m' # White
unkblk='\e[4;30m' # Black - Underline
undred='\e[4;31m' # Red
undgrn='\e[4;32m' # Green
undylw='\e[4;33m' # Yellow
undblu='\e[4;34m' # Blue
undlbl='\e[4;94m' # LightBlue
undpur='\e[4;35m' # Purple
undcyn='\e[4;36m' # Cyan
undwht='\e[4;37m' # White
bakblk='\e[40m' # Black - Background
bakred='\e[41m' # Red
bakgrn='\e[42m' # Green
bakylw='\e[43m' # Yellow
bakblu='\e[44m' # Blue
baklbl='\e[104m' # LightBlue
bakpur='\e[45m' # Purple
bakcyn='\e[46m' # Cyan
bakwht='\e[47m' # White
txtrst='\e[0m' # Text Reset

convertsecs() {
	h=$(($1/3600))
	d=$(($h/24))
	h=$((($1/3600)-$d*24))
	m=$((($1/60)%60))
	s=$(($1%60))
	if [ "$d" -ge 1 ]
	then
		printf "${txtlbl}%02d${bldgrn}day ${txtlbl}%02d${bldgrn}h${txtlbl}%02d${bldgrn}m${txtlbl}%02d${bldgrn}s${txtrst}" $d $h $m $s
	else
		if [ "$h" -ge 1 ]
		then
			printf "${txtlbl}%02d${bldgrn}h ${txtlbl}%02d${bldgrn}min${txtlbl}%02d${bldgrn}sec${txtrst}" $h $m $s
		else
			if [ "$m" -ge 1 ]
			then
				printf "${txtlbl}%02d${bldgrn}min ${txtlbl}%02d${bldgrn}sec${txtrst}" $m $s
			else 
				printf "${txtlbl}%02d${bldgrn}sec${txtrst}" $s
			fi
		fi
	fi
}

in_array() {
	local hay needle=$1
	shift
	for hay; do
		[[ $hay == $needle ]] && return 0
	done
	return 1
}
