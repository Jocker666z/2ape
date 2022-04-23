# 2ape

Various lossless to Monkey's Audio while keeping the tags.

Lossless audio source supported: ALAC, FLAC, WAVPACK

--------------------------------------------------------------------------------------------------
## Install & update
`curl https://raw.githubusercontent.com/Jocker666z/2ape/master/2ape.sh > /home/$USER/.local/bin/2ape && chmod +rx /home/$USER/.local/bin/2ape`

## Dependencies
`ffmpeg flac monkeys-audio wavpack`
Note: gnu-sed is used in the script with patterns which are not necessarily compatible with other systems than gnu-linux.

## Use
Launch `2ape` command in directory with source files, the search depth is tree child directories.
