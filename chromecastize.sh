#!/bin/bash
# uncomment the following if you want to output every line
#set -x

# the ffmpeg options were taken from the following webpage : 
# http://superuser.com/questions/724204/optimum-parameters-for-ffmpeg-to-keep-file-size
# the ffmpeg progress bar is inspired from the following webpage : 
# https://gist.github.com/MarcosBL/9568091
# this is a forkof the chromecastize repo from bc-petrkotek : 
# https://github.com/bc-petrkotek/chromecastize

# Config
TEMPDIR="/tmp/chromecastize"
HOME=~/.chromecastize
SUPPORTED_EXTENSIONS=('mkv' 'avi' 'mp4' '3gp' 'mov' 'mpg' 'mpeg' 'qt' 'wmv' 'm2ts' 'flv')

# Initialization
APPDIR=`dirname "${BASH_SOURCE[0]}"`
. $APPDIR/common.sh
CURRENTDIR=`pwd`
CURRENTIFS=$IFS
IFS=$(echo -en "\n\b")
DRYRUN=false
AUTODELETE=false
SHOWIGNORED=false
CLEANHOME=false
SCRIPT_START_TIME=`date +%s`
TotalSizeTranscoded=0
TotalSizeInflation=0
TotalNbFileTranscoded=0
if ! [ -d "$HOME" ]; then
	mkdir $HOME
fi
touch $HOME/transcode_failed.log
touch $HOME/transcode_success.log
touch $HOME/check_and_remove.sh
chmod +x $HOME/check_and_remove.sh
trap ctrl_c INT

function ctrl_c() {
	echo -e "\n$bldwht$bakred Trapped CTRL-C. Doing some cleanup before quitting...$txtrst"

	# kill ffmpeg if it's running
	if [ -e /proc/$PID ]; then
		echo -e "$bldred Killing ffmpeg..\c"
		while [ -e /proc/$PID ]; do
			echo -e ".\c"
			kill $PID
			sleep 3
		done
		echo -e "$txtrst\n"
	fi

	# remove incomplete transcoded file
	if [ -f $OUTPUT ] ; then
		rm -f $OUTPUT
		echo -e "$bldred Removed incomplete transcoded file ($bldgrn$OUTPUT$bldred).$txtrst"
	fi

	# Cleaning temp directory
	echo -e "$bldred Cleaning temp directory.$txtrst"
	cleanup_temp

	echo -e "$bldwht$bakred Cleanup complete. Exiting.$txtrst"
	exit 1
}

is_supported_ext() {
	EXT=`echo $1 | tr '[:upper:]' '[:lower:]'`
	in_array "$EXT" "${SUPPORTED_EXTENSIONS[@]}"
}

cleanup_temp() {
	if [ -d "$TEMPDIR" ]; then
		rm -f $TEMPDIR/*
	else 
		mkdir $TEMPDIR
	fi
}

is_supported_vcodec() {
	vcodec=$(ffprobe "$1" 2>&1|grep Video:|sed "s/.*Video: \([^[:blank:]]*\) .*/\1/")

	if [[ "$vcodec" == "h264" ]]; then
		return 0
	else
		return 1
	fi
}

is_supported_acodec() {
	acodec=$(ffprobe "$1" 2>&1|grep Audio:|sed "s/.*Audio: \([^[:blank:]]*\) .*/\1/")
	if [[ "$acodec" == "aac" ]]; then
		return 0
	else
		return 1
	fi
}

show_prog_bar() {
  local c="$1" # Character to use to draw progress bar
  local v=$2 # Percentage 0<= value <=100
  local t=$3 # Text before
  local pbl=50 # Progress bar length in characters
  local r=`expr 100 / $pbl` # Ratio between percentage value and progress bar length
  local p="$v%" # Percentage value to display in the middle of progress bar
  local l=${#p} # Length of string to display
  local pbs="" # Progress bar string
  local k=`expr \( $pbl - $l \) / 2` # Position where to substitute in progress bar string
  local n1=`expr $v / $r`
  local n2=`expr $pbl - $n1`
  for (( i=0; i<$pbl; i++ )); do
    pbs="${pbs}${c}"
  done
  pbs=`echo "$pbs" | sed 's/^\(.\{'"${k}"'\}\)\(.\{'"${l}"'\}\)\(.*$\)/\1'"${p}"'\3/'`
  printf "\r\e[0m${t} \e[1;42m%s\e[1;41m%s\e[0m%s" "${pbs:0:$n1}" "${pbs:$n1:$n2}" "${c}"
}
 
display () {
START=$(date +%s); FR_CNT=0; ETA=0; ELAPSED=0
while [ -e /proc/$PID ]; do                         # Is FFmpeg running?
    sleep 1
#    VSTATS=$(awk -W interactive '{gsub(/frame=/, "")}/./{line=$1-1} END{print line}' $TEMPDIR/vstats) # Parse vstats file.
	VSTATS="init"
	if [ -f $TEMPDIR/vstats ] ; then 
		VSTATS=`cat $TEMPDIR/vstats | tail -1 | sed 's/\r/\n/g' | tail -1 | sed "s/.*frame=\( *\)\([^[:blank:]]*\) .*/\2/" | tail -1`
	fi
	re='^[0-9]+$'
	if [[ $VSTATS =~ $re ]] ; then
		if [ $VSTATS -gt $FR_CNT ]; then                # Parsed sane or no?
		    FR_CNT=$VSTATS
		    PERCENTAGE=$(( 100 * FR_CNT / TOT_FR ))     # Progbar calc.
		    ELAPSED=$(( $(date +%s) - START )); echo $ELAPSED > $TEMPDIR/elapsed.value
		    ETA=$(date -d @$(awk 'BEGIN{print int(('$ELAPSED' / '$FR_CNT') * ('$TOT_FR' - '$FR_CNT'))}') -u +%H:%M:%S)   # ETA calc.
		fi
	    show_prog_bar " " $PERCENTAGE "\tFrame: $FR_CNT / $TOT_FR - Done: $(date -d @$ELAPSED -u +%H:%M:%S) Remaining: $ETA"
	fi
done
}

process_file() {
	# initialization
	cleanup_temp
	ARGFILE="$@"
	FILE=`$REALPATH "$ARGFILE"`
	BASENAME=$(basename "$ARGFILE")
	EXTENSION="${BASENAME##*.}"
	FOLDER=$(dirname "$FILE")
	TRANSCODEVIDEO=true
	TRANSCODEAUDIO=true
	TRANSCODE=true
	FIRSTPASSSUCCESS=false
	SECONDPASSSUCCESS=false
	SINGLEPASSSUCCESS=false
	
	# test extension
	if ! is_supported_ext "$EXTENSION"; then
		if ($SHOWIGNORED); then
			echo -e "$bldlbl===========Ignored file$bldgrn $BASENAME$bldlbl since it is$bldpur not a supported extension.$bldlbl ( file is in $bldgrn$FOLDER$bldlbl folder) $txtrst"
		fi
		continue
	fi

	now=`date +%s`
	currentRunningTime=$(($now-$SCRIPT_START_TIME))
	now=`date`

	echo -e "$bldlbl==========="
	echo -e "Processing: $bldgrn $BASENAME$txtlbl (in $FOLDER) - $now - script has been running for $(convertsecs $currentRunningTime)$txtrst"

	# test video codec
	if is_supported_vcodec "$FILE"; then
		echo -e "$txtgrn -$bldgrn video$txtgrn format is$bldgrn already correct$txtgrn (h264), no transcode required for video$txtrst"
		TRANSCODEVIDEO=false
	else
		vcodec=$(ffprobe "$FILE" 2>&1|grep Video:|sed "s/.*Video: \([^[:blank:]]*\) .*/\1/")
		echo -e "$txtgrn -$bldgrn video$txtgrn needs to be transcoded from$bldgrn $vcodec to h264$txtrst"
		TRANSCODEVIDEO=true
	fi

	# test audio codec
	if is_supported_acodec "$FILE"; then
		echo -e "$txtgrn -$bldgrn audio$txtgrn format is$bldgrn already correct$txtgrn (aac), no transcode required for video$txtrst"
		TRANSCODEAUDIO=false
	else
		acodec=$(ffprobe "$FILE" 2>&1|grep Audio:|sed "s/.*Audio: \([^[:blank:]]*\) .*/\1/")
		echo -e "$txtgrn -$bldgrn audio$txtgrn needs to be transcoded from$bldgrn $acodec to aac$txtrst"
		TRANSCODEAUDIO=true
	fi

	if ( ($TRANSCODEVIDEO) || ($TRANSCODEAUDIO) ); then
		echo -e "$txtgrn + file needs to be transcoded$txtrst"
		TRANSCODE=true
	else
		echo -e "$txtgrn + file$bldgrn does not need$txtgrn to be transcoded$txtrst"
		TRANSCODE=false
		continue
	fi
	
	OUTPUT="$FOLDER/${BASENAME%.*}.mp4"

	if [ -f "$OUTPUT" ]; then
		echo -e "$txtylw The output$bldylw file already exists.$txtylw ($OUTPUT)$bldylw Skipping$txtylw this file.$txtrst"
		if ($DRYRUN); then
			echo -e "$txtylw This is a$bldylw DRYRUN$txtylw so we will continue. Otherwise, we would havestopped here.$txtrst"
		else
			continue
		fi
	fi

	
	# obtaining video and audio bitrate to achieve same file size.
	# try to obtain bitrate of the video only :
	VIDEOBITRATE=$(ffprobe "$FILE" 2>&1|grep Video:|sed "s/.* \([0-9]*\) \([km]*\)b\/s.*/\1\2/")
	# if we can't get the bitrate of the video, let's fallback to the overall bitrate
	if [[ $VIDEOBITRATE == *"Video"* ]]
	then
		VIDEOBITRATE=$(ffprobe "$FILE" 2>&1|grep bitrate |sed "s/.*bitrate: \([0-9]*\) \([km]*\).*/\1\2/")
	fi
	# and finish with obtaining the audio bitrate
	AUDIOBITRATE=$(ffprobe "$FILE" 2>&1|grep Audio:|sed "s/.* \([0-9]*\) \([km]*\)b\/s.*/\1\2/")
	
	if ($TRANSCODEVIDEO); then # we'll take the "long" 2 pass method

		echo -e "$txtylw Starting$bldylw First Pass$txtrst"
		start_time=`date +%s`
		cd "$TEMPDIR"
		if ($DRYRUN); then
			echo -e "$txtylw This is a$bldylw DRYRUN$txtylw so we will not transcode the file. Otherwise, we would have executed :$txtrst"
			echo -e ffmpeg  -i \'"$FILE"\' -c:v libx264 -profile:v high -level 5 -preset slow -b:v $VIDEOBITRATE -an -pass 1 \'"$OUTPUT"\' -loglevel fatal
			FIRSTPASSSUCCESS=true
		else
			# Get duration and PAL/NTSC fps then calculate total frames.
			FPS=$(ffprobe "$FILE" 2>&1 | sed -n "s/.*, \(.*\) tbr.*/\1/p")
			DUR=$(ffprobe "$FILE" 2>&1 | sed -n "s/.* Duration: \([^,]*\), .*/\1/p")
			HRS=$(echo $DUR | cut -d":" -f1)
			MIN=$(echo $DUR | cut -d":" -f2)
			SEC=$(echo $DUR | cut -d":" -f3)
			TOT_FR=$(echo "($HRS*3600+$MIN*60+$SEC)*$FPS" | bc | cut -d"." -f1)
			ffmpeg -vstats_file $TEMPDIR/vstats -i "$FILE" -c:v libx264 -profile:v high -level 5 -preset slow -b:v $VIDEOBITRATE -an -pass 1 "$OUTPUT" 2>/dev/null &
	        PID=$! &&
	        echo -e "\tPID of ffmpeg = $PID - Duration: $DUR - Frames: $TOT_FR"
	        display                               # Show progress.
			if [ -f $OUTPUT ] ; then
				FIRSTPASSSUCCESS=true
			else 
				FIRSTPASSSUCCESS=false
			fi
		fi
		firstpass_endtime=`date +%s`
		firstpass_duration=$(($firstpass_endtime-$start_time))

		if ! ($FIRSTPASSSUCCESS) ; then
			echo -e "$bldred First pass has failed ! Doing some cleanup and skipping.$txtrst";
			if [ -f "$OUTPUT" ]; then
				rm -f "$OUTPUT"
			fi
			echo "$BASENAME ; FIRST pass failed ; $FILE" >> $HOME/transcode_failed.log
			continue
		fi

		echo -e "$bldylw Fist pass completed$txtylw in $(convertsecs $firstpass_duration).$txtrst"
		echo -e "$txtylw Starting$bldylw Second Pass$txtrst"
		secondpass_starttime=`date +%s`
	
		if ($DRYRUN); then
			echo -e "$txtylw This is a$bldylw DRYRUN$txtylw so we will not transcode the file. Otherwise, we would have executed :$txtrst"
			echo -e ffmpeg -y -i \'"$FILE"\' -c:v libx264 -profile:v high -level 5 -preset slow -b:v $VIDEOBITRATE -b:a $AUDIOBITRATE -pass 2 \'"$OUTPUT"\' -loglevel fatal
			SECONDPASSSUCCESS=true
		else
			#some cleanup from firstpass : 
			rm -f $TEMPDIR/vstats
			rm -f $TEMPDIR/elapsed.value

			# Get duration and PAL/NTSC fps then calculate total frames.
			FPS=$(ffprobe "$FILE" 2>&1 | sed -n "s/.*, \(.*\) tbr.*/\1/p")
			DUR=$(ffprobe "$FILE" 2>&1 | sed -n "s/.* Duration: \([^,]*\), .*/\1/p")
			HRS=$(echo $DUR | cut -d":" -f1)
			MIN=$(echo $DUR | cut -d":" -f2)
			SEC=$(echo $DUR | cut -d":" -f3)
			TOT_FR=$(echo "($HRS*3600+$MIN*60+$SEC)*$FPS" | bc | cut -d"." -f1)
			ffmpeg -vstats_file $TEMPDIR/vstats -y -i "$FILE" -c:v libx264 -profile:v high -level 5 -preset slow -b:v $VIDEOBITRATE -b:a $AUDIOBITRATE -pass 2 "$OUTPUT" 2>/dev/null &
	        PID=$! &&
	        echo -e "\tPID of ffmpeg = $PID - Duration: $DUR - Frames: $TOT_FR"
	        display                               # Show progress.
			if [ -f $OUTPUT ] ; then
				SECONDPASSSUCCESS=true
			else 
				SECONDPASSSUCCESS=false
			fi
		fi

		if ! ($SECONDPASSSUCCESS) ; then
			echo -e "$bldred Second pass has failed ! Doing some cleanup and skipping.$txtrst";
			if [ -f "$OUTPUT" ]; then
				rm -f "$OUTPUT"
			fi
			echo "$BASENAME ; SECOND pass failed ; $FILE" >> $HOME/transcode_failed.log
			continue
		fi


		cd "$CURRENTDIR"
		end_time=`date +%s`
	
		secondpass_duration=$(($end_time-$firstpass_endtime))
		total_duration=$(($end_time-$start_time))


		echo -e "$bldylw Second pass completed$txtylw in $(convertsecs $secondpass_duration).$txtrst"
		echo -e "$bldgrn Total transcoding time is $(convertsecs $total_duration)."

		TotalNbFileTranscoded=$(($TotalNbFileTranscoded + 1))
		sizeoriginal=0
		sizetranscoded=0
		if [ -f $FILE ] ; then
			sizeoriginal=$(($(stat -c%s "$FILE")/1024/1024))
			if [ -f $OUTPUT ] ; then
				sizetranscoded=$(($(stat -c%s "$OUTPUT")/1024/1024))
			else
				sizeoriginal=0
				sizetranscoded=0
			fi
		else
			sizeoriginal=0
			sizetranscoded=0
		fi
		TotalSizeInflation=$(($sizetranscoded - $sizeoriginal))
		TotalSizeTranscoded=$(($TotalSizeTranscoded + $sizeoriginal))

	else # video does not need to be transcoded in this else
		echo -e "$bldylw Doing a single pass since video does not need to be transcoded.$txtrst"
		start_time=`date +%s`

		if ($DRYRUN); then
			echo -e "$txtylw This is a$bldylw DRYRUN$txtylw so we will not transcode the file. Otherwise, we would have executed :$txtrst"
			echo -e ffmpeg -y -i \'"$FILE"\' -c:v copy -level 5 -preset slow -b:a $AUDIOBITRATE -pass 2 \'"$OUTPUT"\' -loglevel fatal
			SINGLEPASSSUCCESS=true
		else
			FPS=$(ffprobe "$FILE" 2>&1 | sed -n "s/.*, \(.*\) tbr.*/\1/p")
			DUR=$(ffprobe "$FILE" 2>&1 | sed -n "s/.* Duration: \([^,]*\), .*/\1/p")
			HRS=$(echo $DUR | cut -d":" -f1)
			MIN=$(echo $DUR | cut -d":" -f2)
			SEC=$(echo $DUR | cut -d":" -f3)
			TOT_FR=$(echo "($HRS*3600+$MIN*60+$SEC)*$FPS" | bc | cut -d"." -f1)
			ffmpeg -y -i "$FILE" -c:v copy -level 5 -preset slow -b:a $AUDIOBITRATE "$OUTPUT" 2>$TEMPDIR/vstats &
	        PID=$! &&
	        echo -e "\tPID of ffmpeg = $PID - Duration: $DUR - Frames: $TOT_FR"
			display                               # Show progress.    
			if [ -f $OUTPUT ] ; then
				SINGLEPASSSUCCESS=true
			else 
				SINGLEPASSSUCCESS=false
			fi
		fi

		if ! ($SINGLEPASSSUCCESS) ; then
			echo -e "$bldred Single (first) pass has failed ! Doing some cleanup and skipping.$txtrst";
			if [ -f "$OUTPUT" ]; then
				rm -f "$OUTPUT"
			fi
			echo "$BASENAME ; SINGLE first pass failed ; $FILE" >> $HOME/transcode_failed.log
			continue
		fi

		end_time=`date +%s`
		total_duration=$(($end_time-$start_time))
		echo -e "$bldgrn Total (single pass) transcoding time is $(convertsecs $total_duration)."

		TotalNbFileTranscoded=$(($TotalNbFileTranscoded + 1))
		sizeoriginal=$(($(stat -c%s "$FILE")/1024/1024))
		if ($DRYRUN); then
			sizetranscoded=$sizeoriginal
		else
			sizetranscoded=$(($(stat -c%s "$OUTPUT")/1024/1024))
		fi
		TotalSizeInflation=$(($sizetranscoded - $sizeoriginal))
		TotalSizeTranscoded=$(($TotalSizeTranscoded + $sizeoriginal))
	fi

	if [ -f "$OUTPUT" ]; then

		echo "# $BASENAME ; File Has been Transcoded. New file is : ; $OUTPUT" >> $HOME/transcode_success.log

		# Delete old file if autodelete is enabled
		if ($AUTODELETE); then
			if [ -f "$FILE" ]; then
				rm -f "$FILE"
				echo -e "$bldlbl Old file has been deleted ($bldgrn$FILE$bldlbl) due to autodelete beeing on.$txtrst"
			fi
		else # we don't want to delete the old file, so build a script to check the new file and offer to delete the old one.
			echo "echo -e \"$bldwht =========================================================\"		" >> $HOME/check_and_remove.sh
			echo "echo -e \"$txtrst File successfully transcoded : \"								" >> $HOME/check_and_remove.sh
			echo "echo -e \" File 		: $bldgrn$BASENAME$txtrst\"									" >> $HOME/check_and_remove.sh
			echo "echo -e \" Orifinal file 	: $bldgrn$FILE$txtrst\"									" >> $HOME/check_and_remove.sh
			echo "echo -e \" New File 	: $bldgrn$OUTPUT$txtrst\"									" >> $HOME/check_and_remove.sh
			echo "echo -e \"$bldlbl Launching playback of the transcoded file ($bldgrn$OUTPUT$bldlbl)$txtrst\"	" >> $HOME/check_and_remove.sh
			echo "mplayer -really-quiet \"$OUTPUT\"													" >> $HOME/check_and_remove.sh
			echo "del=\"\"																			" >> $HOME/check_and_remove.sh
			echo "while true ; do																	" >> $HOME/check_and_remove.sh
			echo "	if ([[ \"\$del\" == \"y\" ]] || [[ \"\$del\" == \"n\" ]]); then					" >> $HOME/check_and_remove.sh
			echo "		break																		" >> $HOME/check_and_remove.sh
			echo "	else																			" >> $HOME/check_and_remove.sh
			echo "		echo -e \"$txtylw Can we$bldylw delete the original$txtylw file ?$bldylw (y|n)$bldgrn$bakred \c\"" >> $HOME/check_and_remove.sh
			echo "		read -n 1 del																" >> $HOME/check_and_remove.sh
			echo "	fi																				" >> $HOME/check_and_remove.sh
			echo "done																				" >> $HOME/check_and_remove.sh
			echo "if [[ \"\$del\" == \"y\" ]] ; then												" >> $HOME/check_and_remove.sh
			echo "	rm -f \"$FILE\"																	" >> $HOME/check_and_remove.sh
			echo "	echo -e \"$txtrst\\n$bldred Original file has been deleted ($bldgrn$FILE$bldred)$txtrst\"" >> $HOME/check_and_remove.sh
			echo "else																				" >> $HOME/check_and_remove.sh
			echo "	dell=\"\"																		" >> $HOME/check_and_remove.sh
			echo "	while true ; do																	" >> $HOME/check_and_remove.sh
			echo "		if ([[ \"\$dell\" == \"y\" ]] || [[ \"\$dell\" == \"n\" ]]); then			" >> $HOME/check_and_remove.sh
			echo "			break																	" >> $HOME/check_and_remove.sh
			echo "		else																		" >> $HOME/check_and_remove.sh
			echo "			echo -e \"$txtrst\\n$txtcyn Since you want to keep the old file, should we$bldcyn delete the new$txtcyn (badly?) transcoded file ?$bldcyn (y|n)$bldgrn$bakred \c\"" >> $HOME/check_and_remove.sh
			echo "			read -n 1 dell															" >> $HOME/check_and_remove.sh
			echo "		fi																			" >> $HOME/check_and_remove.sh
			echo "	done																			" >> $HOME/check_and_remove.sh
			echo "	if [[ \"\$dell\" == \"y\" ]] ; then												" >> $HOME/check_and_remove.sh
			echo "		rm -f \"$OUTPUT\"															" >> $HOME/check_and_remove.sh
			echo "		echo -e \"$txtrst\\n$bldred New transcoded file has been deleted ($bldgrn$OUTPUT$bldred)$txtrst\"" >> $HOME/check_and_remove.sh
			echo "	else																			" >> $HOME/check_and_remove.sh
			echo "		echo -e \"$txtrst\\n$bldlbl No file has been deleted.$txtrst\"							" >> $HOME/check_and_remove.sh
			echo "	fi																				" >> $HOME/check_and_remove.sh
			echo "fi																				" >> $HOME/check_and_remove.sh
			echo "echo \" =========================================================\"				" >> $HOME/check_and_remove.sh
			#	echo "# $BASENAME ; File Has been Transcoded. Check and delete the old file : ; $FILE\"					" >> $HOME/check_and_remove.sh
		fi # $AUTODELETE
	else # $OUTPUT does not exist in this else
		echo -e "$bldred !!! FAILED to transcode the video !!! (output file were not found)$txtrst"
		echo "$BASENAME ; Failed to transcode the video (output not found after transcoding) ; $FILE" >> $HOME/transcode_failed.log
	fi # $OUTPUT EXISTS

	
	cleanup_temp

}

print_help() {
	echo -e "$bldlbl Usage: $txtred chromecastize.sh$txtylw [--dryrun] [--showignored] [--autodelete] [--cleanhome] $txtred<videofile1> $txtylw[ videofile2 ... ]$txtrst"
}


################
# MAIN PROGRAM #
################

# test if `ffprobe` is available
FFPROBE=`which ffprobe`
if [ -z $FFPROBE ]; then
	echo -e "$bldred ffprobe$txtred is not available, please install it$txtrst"
	exit 1
fi

# test if `ffmpeg` is available
FFMPEG=`which avconv || which ffmpeg`
if [ -z $FFMPEG ]; then
	echo -e "$bldred avconv$txtred (or$bldred ffmpeg$txtred) is not available, please install it"
	exit 1
fi

# test if `grealpath` or `realpath` is available
REALPATH=`which realpath || which grealpath`
if [ -z $REALPATH ]; then
	echo -e "$bldred grealpath$txtred (or$bldred realpath$txtred) is not available, please install it"
	exit 1
fi

# check number of arguments
if [ $# -lt 1 ]; then
	print_help
	exit 1
fi


for FILENAME in "$@"; do
	if [ "$FILENAME" = "--dryrun" ]; then
		DRYRUN=true
	elif [ "$FILENAME" = "--showignored" ]; then
		SHOWIGNORED=true
	elif [ "$FILENAME" = "--autodelete" ]; then
		AUTODELETE=true
	elif [ "$FILENAME" = "--cleanhome" ]; then
		echo "" > $HOME/transcode_failed.log
		echo "" > $HOME/transcode_success.log
		echo "" > $HOME/check_and_remove.sh
	elif ! [ -e "$FILENAME" ]; then
		echo -e "$bldred File not found ($bldgrn$FILENAME$bldred). Skipping...$txtrst"
	elif [ -d "$FILENAME" ]; then
		ENTRIES=$(find "$FILENAME" -type f)
		for ENTRY in $ENTRIES ; do
			process_file $ENTRY
		done
	elif [ -f "$FILENAME" ]; then
		process_file $FILENAME
	else
		echo -e "$bldredInvalid file ($bldgrn$FILENAME$bldred). Skipping...$txtrst"
	fi
done


SCRIPT_END_TIME=`date +%s`
SCRIPT_DURATION=$(($SCRIPT_END_TIME-$SCRIPT_START_TIME))
echo -e "$bldgrn Script completed in in $(convertsecs $SCRIPT_DURATION)$bldgrn.$txtrst"
echo -e "$bldgrn The script has transcoded $bldred$TotalNbFileTranscoded$bldgrn files for a total of $bldred$TotalSizeTranscoded MB$bldgrn with $bldred$TotalSizeInflation MB$bldgrn inflation.$txtrst"

IFS=$CURRENTIFS
