#chromecastize

<img src="https://cdn4.iconfinder.com/data/icons/simply-8-bits-2/96/chromecast.png"
 alt="Chromecastize icon" title="Chromecastize" align="right" />

Simple bash script to convert video files into Chromecast and Chromebook supported format.

Script identifies video and audio format of given file (using `ffprobe`) and converts it if necessary (using `ffmpeg`).

Filename of output video file is `<original_filename>.mp4`.

**Original file will not be deleted.**

Rather than deleting the video file that has been transcoded, chromecastize will generate a script in *~/.chromecastize/check_and_remove.sh*.
You can run this script after chromecastize has completed transcoding.

It will allow you to play all generated transcoded files (to check video quality and audio sync for example), and will prompt for your input to know what to do (either delete the original file or the transcoded one, or keep both.)

##Requirements
- **[ffmpeg] [ffmpeg-install]**

It has been tested by myself on Ubuntu 10.04 trusty LTS.
It assumes you have a compatible ffmpeg version, mine comes from the following ppa : https://launchpad.net/~mc3man/+archive/ubuntu/trusty-media

## Quickstart
Assuming git and **[ffmpeg] [ffmpeg-install]** are installed
```bash
 git clone https://github.com/toxic0berliner/chromecastize.git
 cd chromecastize
 ./chromecastize.sh
 # the above command will display avgailable options.
```

##Usage
```
./chromecastize.sh [--dryrun] [--showignored] [--autodelete] [--cleanhome] <videofile1> [ videofile2 ... ]
```
You can directly pass a video file to the script, or you can pass a directory, in which case it will try to transcode all videos in the given directory.

### Examples:
- `./chromecastize.sh /Volumes/MyNAS` - converts all videos on your NAS (assuming that it's mounted to `/Volumes/MyNAS`)
- `./chromecastize.sh Holiday.avi Wedding.avi` - converts specified video files

### Options:
- `--dryrun` does not convert or delete any file,just shows you what it would do without the dryrun option
- `--showignored` lists all files that it's trying to process, even non-video files or unsupported extensions
- `--autodelete` deletes the original file after successful transcoding. Does not do anything if no transcoding required for the file.
- `--cleanhome` resets all log files from ~/.chromecastize before starting (useful chen you have finished dealing with the check_and_remove.sh script from a previous run of chromecastize)

Authors
-------
- **toxic0berliner** (forked and rewrote the script to use ffmpeg in 2 pass with better ffmpeg options and bash STDOUT)
- **Petr Kotek** (did the script save you some time? donations appreciated: www.petrkotek.com)
