# 2ape

Various lossless to Monkey's Audio while keeping the tags.

Lossless audio source supported: ALAC, FLAC, WAV, WAVPACK

--------------------------------------------------------------------------------------------------
## Install & update
`curl https://raw.githubusercontent.com/Jocker666z/2ape/master/2ape.sh > /home/$USER/.local/bin/2ape && chmod +rx /home/$USER/.local/bin/2ape`

## Dependencies
`ffmpeg flac monkeys-audio wavpack`

## Use
Processes all compatible files in the current directory and his three subdirectories.
```
Options:
  --alac_only             Compress only ALAC source.
  --flac_only             Compress only FLAC source.
  --wav_only              Compress only WAV source.
  --wavpack_only          Compress only WAVPACK source.
  --16bits_only           Compress only 16bits source.
  -v, --verbose           More verbose, for debug.
```
Default compression is `-c5000`.
