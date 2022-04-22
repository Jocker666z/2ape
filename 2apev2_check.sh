#!/usr/bin/env bash
# shellcheck disable=SC2086
# 2apev2_check
# Tool for see the list of tags as interpreted by 2ape
# \(^o^)/ 
#
# Author : Romain Barbarot
# https://github.com/Jocker666z/2ape/
# Licence : unlicense

mac_version="Monkey's Audio $(mac 2>&1 | head -1 | awk -F"[()]" '{print $2}')"
mac_compress_arg="-c5000"
input_ext="flac|m4a|wv"

mapfile -t lst_audio_src < <(find "$PWD" -maxdepth 2 -type f -regextype posix-egrep \
								-iregex '.*\.('$input_ext')$' 2>/dev/null | sort)

# Clean source array
for i in "${!lst_audio_src[@]}"; do
	# Keep only ALAC codec among m4a files
	if [[ "${lst_audio_src[i]##*.}" = "m4a" ]]; then
		codec_test=$(ffprobe -v error -select_streams a:0 \
			-show_entries stream=codec_name -of csv=s=x:p=0 "${lst_audio_src[i]%.*}.m4a"  )
		if [[ "$codec_test" != "alac" ]]; then
			unset "lst_audio_src[$i]"
		fi
	fi
done

for file in "${lst_audio_src[@]}"; do

	# Reset
	source_tag=()
	source_tag_temp=()

	# FLAC
	if [[ -s "${file%.*}.flac" ]]; then
		# Source file tags array
		mapfile -t source_tag < <( metaflac "${file%.*}.flac" --export-tags-to=- )

	# WAVPACK
	elif [[ -s "${file%.*}.wv" ]]; then
		# Source file tags array
		mapfile -t source_tag_temp < <( wvtag -q -l "${file%.*}.wv" \
									| grep -v -e '^[[:space:]]*$' \
									| tail -n +2 )
		# Clean array
		for i in "${!source_tag_temp[@]}"; do
			wavpack_tag_parsing_1=$(echo "${source_tag_temp[$i]}" | awk -F ":" '{print $1}')
			wavpack_tag_parsing_2=$(echo "${source_tag_temp[$i]}" | cut -f2- -d' ' | sed 's/^ *//')
			source_tag+=( "${wavpack_tag_parsing_1}=${wavpack_tag_parsing_2}" )
		done

	# ALAC
	elif [[ -s "${file%.*}.m4a" ]]; then
		# Source file tags array
		mapfile -t source_tag < <( ffprobe -v error -show_entries stream_tags:format_tags \
									-of default=noprint_wrappers=1 "${file%.*}.m4a" )
		# Clean array
		for i in "${!source_tag[@]}"; do
			source_tag[$i]="${source_tag[$i]//TAG:/}"
		done
	fi

# Tag blacklist
# Something waste specific:
#  * ACCURATERIPRESULT
#  * ....
#  * wwww
# wavpack specific:
#  * APEv2 tag items (head of wvtag output)
# ffmpeg specific:
#  * encoder
#  * ...
#  * vendor_id
# vorbiscomment specific
# ID3v2 specific
# iTune specific
APEv2_blacklist=(
	'ACCURATERIPRESULT'
	'ALBUM ARTIST'
	'CDTOC'
	'CodingHistory'
	'ENSEMBLE'
	'OrigDate'
	'Originator'
	'OrigReference'
	'OrigTime'
	'RELEASE Year'
	'TOOL VERSION'
	'TOOL NAME'
	'TimeReference'
	'UPC'
	'wwww'
	'APEv2 tag items'
	'encoder'
	'compatible_brands'
	'language'
	'handler_name'
	'major_brand'
	'minor_version'
	'vendor_id'
	'DISCTOTAL'
	'ENCODER'
	'ENCODERSETTINGS'
	'FINGERPRINT'
	'LENGTH'
	'MUSICBRAINZ_ORIGINALARTISTID'
	'MUSICBRAINZ_ORIGINALALBUMID'
	'originaldate'
	'ORIGINALDATE'
	'TOTALDISCS'
	'TRACKTOTAL'
	'TOTALTRACKS'
	'MusicMagic Fingerprint'
	'MusicBrainz Original Artist Id'
	'MusicBrainz Original Album Id'
	'fingerprint'
	'pcst'
	'pcst'
	'purl'
	'sosn'
	'tvsh'
)

	# Remove incompatible or not desired tag
	for i in "${!source_tag[@]}"; do
		tag_label=$(echo "${source_tag[$i]}" | awk -F "=" '{print $1}')
		for tag in "${APEv2_blacklist[@]}"; do
			if [[ "$tag" = "$tag_label" ]];then
				unset "source_tag[$i]"
			fi
		done
	done

	# Add encoder ape tags
	source_tag+=( "EncodedBy=${mac_version}" )
	source_tag+=( "EncoderSettings=${mac_compress_arg}" )

	# Substitution
	for i in "${!source_tag[@]}"; do
		# Waste fix
		source_tag[$i]="${source_tag[$i]//album_artist=/Album Artist=}"
		source_tag[$i]="${source_tag[$i]//PUBLISHER=/Label=}"

		# Special case - match with the word
		source_tag[$i]=$(echo ${source_tag[$i]} | sed "s/\balbum=\b/Album=/g")
		source_tag[$i]=$(echo ${source_tag[$i]} | sed "s/\bartist=\b/Artist=/g")
		source_tag[$i]=$(echo ${source_tag[$i]} | sed "s/\bdisc=\b/Disc=/g")
		source_tag[$i]=$(echo ${source_tag[$i]} | sed "s/\btitle=\b/Title=/g")
		source_tag[$i]=$(echo ${source_tag[$i]} | sed "s/\btrack=\b/Track=/g")

		# MusicBrainz internal
		source_tag[$i]="${source_tag[$i]//replaygain_album_gain=/REPLAYGAIN_ALBUM_GAIN=}"
		source_tag[$i]="${source_tag[$i]//replaygain_album_peak=/REPLAYGAIN_ALBUM_PEAK=}"
		source_tag[$i]="${source_tag[$i]//replaygain_track_gain=/REPLAYGAIN_TRACK_GAIN=}"
		source_tag[$i]="${source_tag[$i]//replaygain_track_peak=/REPLAYGAIN_TRACK_PEAK=}"

		# vorbis
		source_tag[$i]="${source_tag[$i]//ALBUM=/Album=}"
		source_tag[$i]="${source_tag[$i]//ALBUMARTIST=/Album Artist=}"
		source_tag[$i]="${source_tag[$i]//ARRANGER=/Arranger=}"
		source_tag[$i]="${source_tag[$i]//ARTIST=/Artist=}"
		source_tag[$i]="${source_tag[$i]//ARTISTS=/Artists=}"
		source_tag[$i]="${source_tag[$i]//BARCODE=/Barcode=}"
		source_tag[$i]="${source_tag[$i]//CATALOGNUMBER=/CatalogNumber=}"
		source_tag[$i]="${source_tag[$i]//COMMENT=/Comment=}"
		source_tag[$i]="${source_tag[$i]//COMPILATION=/Compilation=}"
		source_tag[$i]="${source_tag[$i]//COMPOSER=/Composer=}"
		source_tag[$i]="${source_tag[$i]//CONDUCTOR=/Conductor=}"
		source_tag[$i]="${source_tag[$i]//COPYRIGHT=/Copyright=}"
		source_tag[$i]="${source_tag[$i]//DATE=/Year=}"
		source_tag[$i]="${source_tag[$i]//DIRECTOR=/Director=}"
		source_tag[$i]="${source_tag[$i]//DISCNUMBER=/Disc=}"
		source_tag[$i]="${source_tag[$i]//DISCSUBTITLE=/DiscSubtitle=}"
		source_tag[$i]="${source_tag[$i]//DJMIXER=/DJMixer=}"
		source_tag[$i]="${source_tag[$i]//ENCODEDBY=/EncodedBy=}"
		source_tag[$i]="${source_tag[$i]//ENGINEER=/Engineer=}"
		source_tag[$i]="${source_tag[$i]//GENRE=/Genre=}"
		source_tag[$i]="${source_tag[$i]//GROUPING=/Grouping=}"
		source_tag[$i]="${source_tag[$i]//LABEL=/Label=}"
		source_tag[$i]="${source_tag[$i]//LANGUAGE=/Language=}"
		source_tag[$i]="${source_tag[$i]//LYRICIST=/Lyricist=}"
		source_tag[$i]="${source_tag[$i]//LYRICS=/Lyrics=}"
		source_tag[$i]="${source_tag[$i]//MEDIA=/Media=}"
		source_tag[$i]="${source_tag[$i]//MIXER=/Mixer=}"
		source_tag[$i]="${source_tag[$i]//MIXER=/Mood=}"
		source_tag[$i]="${source_tag[$i]//ORGANIZATION=/Label=}"
		source_tag[$i]="${source_tag[$i]//PERFORMER=/Performer=}"
		source_tag[$i]="${source_tag[$i]//PRODUCER=/Producer=}"
		source_tag[$i]="${source_tag[$i]//RELEASESTATUS=/MUSICBRAINZ_ALBUMSTATUS=}"
		source_tag[$i]="${source_tag[$i]//RELEASETYPE=/MUSICBRAINZ_ALBUMTYPE=}"
		source_tag[$i]="${source_tag[$i]//REMIXER=/MixArtist=}"
		source_tag[$i]="${source_tag[$i]//SCRIPT=/Script=}"
		source_tag[$i]="${source_tag[$i]//SUBTITLE=/Subtitle=}"
		source_tag[$i]="${source_tag[$i]//TITLE=/Title=}"
		source_tag[$i]="${source_tag[$i]//TRACKNUMBER=/Track=}"
		source_tag[$i]="${source_tag[$i]//WEBSITE=/Weblink=}"
		source_tag[$i]="${source_tag[$i]//WRITER=/Writer=}"
		# ID3v2
		source_tag[$i]="${source_tag[$i]//Acoustid Id=/ACOUSTID_ID=}"
		source_tag[$i]="${source_tag[$i]//arranger=/Arranger=}"
		source_tag[$i]="${source_tag[$i]//description=/Comment=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Id=/MUSICBRAINZ_ALBUMID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Artist Id=/MUSICBRAINZ_ALBUMARTISTID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Status=/MUSICBRAINZ_ALBUMSTATUS=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Type=/MUSICBRAINZ_ALBUMTYPE=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Artist Id=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Artist Id=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Release Country=/RELEASECOUNTRY=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Release Group Id=/MUSICBRAINZ_RELEASEGROUPID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Release Track Id=/MUSICBRAINZ_RELEASETRACKID=}"
		source_tag[$i]="${source_tag[$i]//TBPM=/BPM=}"
		source_tag[$i]="${source_tag[$i]//TEXT=/Lyricist=}"
		# iTune
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Artist Id=/MUSICBRAINZ_ALBUMARTISTID=}"
	done

	echo "$file" | rev | cut -d'/' -f-2 | rev
	for i in "${!source_tag[@]}"; do
		echo "${source_tag[i]}"
	done
	echo
done