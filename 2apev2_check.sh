#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2086
# 2apev2_check
# Tool for see the list of tags in apev2
# \(^o^)/ 
#
# Author : Romain Barbarot
# https://github.com/Jocker666z/2ape/
# Licence : unlicense

input_ext="ape|flac|m4a|wv"

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

	start_all=$(($(date +%s%N)/1000000))

	# Reset
	source_tag=()
	source_tag_temp=()
	source_tag_temp1=()
	source_tag_temp2=()
	tag_name=()
	tag_label=()

	# FLAC
	if [[ -s "${file%.*}.flac" ]]; then
		start_flac_export=$(($(date +%s%N)/1000000))
		# Source file tags array
		mapfile -t source_tag < <( metaflac "${file%.*}.flac" --export-tags-to=- | sort )
		stop_flac_export=$(($(date +%s%N)/1000000))

	# WAVPACK
	elif [[ -s "${file%.*}.wv" ]]; then
		start_wv_export=$(($(date +%s%N)/1000000))
		# Source file tags array
		mapfile -t source_tag_temp < <( wvtag -q -l "${file%.*}.wv" \
									| grep -v -e '^[[:space:]]*$' \
									| tail -n +2 | sort )
		# Clean array
		mapfile -t source_tag_temp1 < <( printf '%s\n' "${source_tag_temp[@]}" \
										| awk -F ":" '{print $1}' )
		mapfile -t source_tag_temp2 < <( printf '%s\n' "${source_tag_temp[@]}" \
										| cut -f2- -d':' | sed 's/^ *//' )
		for i in "${!source_tag_temp[@]}"; do
			source_tag+=( "${source_tag_temp1[$i]}=${source_tag_temp2[$i]}" )
		done
		stop_wv_export=$(($(date +%s%N)/1000000))
		
	# ALAC
	elif [[ -s "${file%.*}.m4a" ]]; then
		start_m4a_export=$(($(date +%s%N)/1000000))
		# Source file tags array
		mapfile -t source_tag < <( ffprobe -v error -show_entries stream_tags:format_tags \
									-of default=noprint_wrappers=1 "${file%.*}.m4a" | sort )
		# Clean array
		for i in "${!source_tag[@]}"; do
			source_tag[$i]="${source_tag[$i]//TAG:/}"
		done
		stop_m4a_export=$(($(date +%s%N)/1000000))
	# Monkey's Audio
	elif [[ -s "${file%.*}.ape" ]]; then
		start_ape_export=$(($(date +%s%N)/1000000))
		# Source file tags array
		mapfile -t source_tag < <( ffprobe -v error -show_entries stream_tags:format_tags \
									-of default=noprint_wrappers=1 "${file%.*}.ape" )
		# Clean array
		for i in "${!source_tag[@]}"; do
			source_tag[$i]="${source_tag[$i]//TAG:/}"
		done
		stop_ape_export=$(($(date +%s%N)/1000000))
	fi

# Tag whitelist according with:
# https://picard-docs.musicbrainz.org/en/appendices/tag_mapping.html
APEv2_whitelist=(
	'ACOUSTID_ID'
	'ACOUSTID_FINGERPRINT'
	'Album'
	'Album Artist'
	'ALBUMARTISTSORT'
	'ALBUMSORT'
	'Arranger'
	'Artist'
	'ARTISTSORT'
	'Artists'
	'ASIN'
	'Barcode'
	'BPM'
	'CatalogNumber'
	'Comment'
	'Compilation'
	'Composer'
	'COMPOSERSORT'
	'Conductor'
	'Copyright'
	'Director'
	'Disc'
	'DiscSubtitle'
	'EncodedBy'
	'EncoderSettings'
	'Engineer'
	'Genre'
	'Grouping'
	'KEY'
	'ISRC'
	'Language'
	'LICENSE'
	'Lyricist'
	'Lyrics'
	'Media'
	'DJMixer'
	'Mixer'
	'Mood'
	'MOVEMENTNAME'
	'MOVEMENTTOTAL'
	'MOVEMENT'
	'MUSICBRAINZ_ARTISTID'
	'MUSICBRAINZ_DISCID'
	'MUSICBRAINZ_TRACKID'
	'MUSICBRAINZ_ALBUMARTISTID'
	'MUSICBRAINZ_RELEASEGROUPID'
	'MUSICBRAINZ_ALBUMID'
	'MUSICBRAINZ_RELEASETRACKID'
	'MUSICBRAINZ_TRMID'
	'MUSICBRAINZ_WORKID'
	'MUSICIP_PUID'
	'Original Artist'
	'ORIGINALFILENAME'
	'ORIGINALYEAR'
	'Performer'
	'Producer'
	'Label'
	'RELEASECOUNTRY'
	'Year'
	'MUSICBRAINZ_ALBUMSTATUS'
	'MUSICBRAINZ_ALBUMTYPE'
	'MixArtist'
	'REPLAYGAIN_ALBUM_GAIN'
	'REPLAYGAIN_ALBUM_PEAK'
	'REPLAYGAIN_ALBUM_RANGE'
	'REPLAYGAIN_REFERENCE_LOUDNESS'
	'REPLAYGAIN_TRACK_GAIN'
	'REPLAYGAIN_TRACK_PEAK'
	'REPLAYGAIN_TRACK_RANGE'
	'Script'
	'SHOWMOVEMENT'
	'Subtitle'
	'Disc'
	'Track'
	'Title'
	'TITLESORT'
	'Weblink'
	'WORK'
	'Writer'
)

	# Substitution
	start_parse_substitution=$(($(date +%s%N)/1000000))

	# Remove empty tag label=
	mapfile -t source_tag < <( printf '%s\n' "${source_tag[@]}" | grep "=" )

	# Substitution
	for i in "${!source_tag[@]}"; do
		# MusicBrainz internal name
		source_tag[$i]="${source_tag[$i]//albumartistsort=/ALBUMARTISTSORT=}"
		source_tag[$i]="${source_tag[$i]//artistsort=/ARTISTSORT=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_artistid=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_albumid=/MUSICBRAINZ_ALBUMID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_artistid=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_releasegroupid=/MUSICBRAINZ_RELEASEGROUPID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_releasetrackid=/MUSICBRAINZ_RELEASETRACKID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_trackid=/MUSICBRAINZ_RELEASETRACKID=}"
		source_tag[$i]="${source_tag[$i]//originalyear=/ORIGINALYEAR=}"
		source_tag[$i]="${source_tag[$i]//replaygain_album_gain=/REPLAYGAIN_ALBUM_GAIN=}"
		source_tag[$i]="${source_tag[$i]//replaygain_album_peak=/REPLAYGAIN_ALBUM_PEAK=}"
		source_tag[$i]="${source_tag[$i]//replaygain_track_gain=/REPLAYGAIN_TRACK_GAIN=}"
		source_tag[$i]="${source_tag[$i]//replaygain_track_peak=/REPLAYGAIN_TRACK_PEAK=}"

		# vorbis
		source_tag[$i]="${source_tag[$i]//ALBUMARTIST=/Album Artist=}"
		source_tag[$i]="${source_tag[$i]//ARRANGER=/Arranger=}"
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
		# Waste fix
		source_tag[$i]="${source_tag[$i]//date=/Year=}"
		source_tag[$i]="${source_tag[$i]//DATE=/Year=}"
	done

	# Whitelist parsing
	mapfile -t tag_name < <( printf '%s\n' "${source_tag[@]}" | awk -F "=" '{print $1}' )
	mapfile -t tag_label < <( printf '%s\n' "${source_tag[@]}" | cut -f2- -d'=' )
	for i in "${!tag_name[@]}"; do
		for tag in "${APEv2_whitelist[@]}"; do
			# ape2v2 std
			if [[ "${tag_name[i],,}" = "${tag,,}" ]]; then
				source_tag[$i]="${tag}=${tag_label[i]}"
				continue 2
			# reject
			else
				unset "source_tag[i]"
			fi
		done
	done

	# Remove duplicate tags
	mapfile -t source_tag < <( printf '%s\n' "${source_tag[@]}" | sort -u )

	stop_parse_substitution=$(($(date +%s%N)/1000000))

	stop_all=$(($(date +%s%N)/1000000))

	# Calc duration in s
	diff_all=$(( stop_all - start_all ))
	diff_flac_export=$(( stop_flac_export - start_flac_export ))
	diff_wv_export=$(( stop_wv_export - start_wv_export ))
	diff_m4a_export=$(( stop_m4a_export - start_m4a_export ))
	diff_ape_export=$(( stop_ape_export - start_ape_export ))
	diff_parse_substitution=$(( stop_parse_substitution - start_parse_substitution ))

	# Print
	echo "filename: $file" | rev | cut -d'/' -f-2 | rev
	echo "Process duration:"
	echo " * all:                ${diff_all}ms"
	echo " * export flac tag:    ${diff_flac_export}ms"
	echo " * export wv tag:      ${diff_wv_export}ms"
	echo " * export m4a tag:     ${diff_m4a_export}ms"
	echo " * export ape tag:     ${diff_ape_export}ms"
	echo " * rename tags:        ${diff_parse_substitution}ms"
	echo "----------------------------------------------------------"
	echo "apev2 tags:"
	printf '%s\n' "${source_tag[@]}"
	echo "=========================================================="
	echo

	unset stop_all
	unset start_all
	unset stop_flac_export
	unset start_flac_export
	unset stop_wv_export
	unset start_wv_export
	unset stop_m4a_export
	unset start_m4a_export

done
