#!/usr/bin/env bash
# shellcheck disable=SC2086
# 2ape
# Various lossless to Monkey's Audio while keeping the tags.
# \(^o^)/ 
#
# It does this:
#    Array namme
#  1 lst_audio_src              get source list
#  2 lst_audio_src_pass         source pass
#  2 lst_audio_src_rejected     source no pass
#  3 lst_audio_wav_decoded      source -> WAV
#  4 lst_audio_ape_compressed   WAV -> APE
#  5 lst_audio_ape_target_tags  TAG -> APE
#
# Author : Romain Barbarot
# https://github.com/Jocker666z/2ape/
# Licence : unlicense

# Search & populate array with source files
search_source_files() {
mapfile -t lst_audio_src < <(find "$PWD" -maxdepth 3 -type f -regextype posix-egrep \
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
}
# Verify source integrity
test_source() {
local test_counter

test_counter="0"

for file in "${lst_audio_src[@]}"; do

	# FLAC - Verify integrity
	if [[ "${file##*.}" = "flac" ]]; then
		# Tests & populate file in arrays
		## File test & error log generation
		tmp_error=$(mktemp)
		flac $flac_test_arg "$file" 2>"$tmp_error"
		if [ -s "$tmp_error" ]; then
			# Try to fix file
			flac $flac_fix_arg "$file"
			# Re-test
			flac $flac_test_arg "$file" 2>"$tmp_error"
			# If no valid 2 times exclude
			if [ -s "$tmp_error" ]; then
				cp "$tmp_error" "${file}.decode_error.log"
				lst_audio_src_rejected+=( "$file" )
			else
				lst_audio_src_pass+=( "$file" )
			fi
		else
			lst_audio_src_pass+=( "$file" )
		fi

	# WAVPACK - Verify integrity
	elif [[ "${file##*.}" = "wv" ]]; then
		# Tests & populate file in arrays
		## File test & error log generation
		tmp_error=$(mktemp)
		#wvunpack -q -v "$file" 2>"$tmp_error"
		wvunpack $wavpack_test_arg "$file" 2>"$tmp_error"
		if [ -s "$tmp_error" ]; then
			cp "$tmp_error" "${file}.decode_error.log"
			lst_audio_src_rejected+=( "$file" )
		else
			lst_audio_src_pass+=( "$file" )
		fi

	# ALAC - Verify integrity
	elif [[ "${file##*.}" = "m4a" ]]; then
		# Tests & populate file in arrays
		## File test & error log generation
		tmp_error=$(mktemp)
		ffmpeg -v error -i "$file" -max_muxing_queue_size 9999 -f null - 2>"$tmp_error"
		if [ -s "$tmp_error" ]; then
			cp "$tmp_error" "${file}.decode_error.log"
			lst_audio_src_rejected+=( "$file" )
		else
			lst_audio_src_pass+=( "$file" )
		fi
	fi

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		test_counter=$((test_counter+1))
		if [[ "${#lst_audio_src[@]}" = "1" ]]; then
			echo -ne "${test_counter}/${#lst_audio_src[@]} source file is being tested"\\r
		else
			echo -ne "${test_counter}/${#lst_audio_src[@]} source files are being tested"\\r
		fi
	fi

done

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if (( "${#lst_audio_src_rejected[@]}" )); then
		if [[ "${#lst_audio_src[@]}" = "1" ]]; then
			echo "${test_counter} source file tested ~ ${#lst_audio_src_rejected[@]} in error (log generated)"
		else
			echo "${test_counter} source files tested ~ ${#lst_audio_src_rejected[@]} in error (log generated)"
		fi
	else
		if [[ "${#lst_audio_src[@]}" = "1" ]]; then
			echo "${test_counter} source file tested"
		else
			echo "${test_counter} source files tested"
		fi
	fi
fi
}
# Decode source
decode_source() {
local decode_counter

decode_counter="0"

# FLAC - Decode
for file in "${lst_audio_src_pass[@]}"; do
	if [[ "${file##*.}" = "flac" ]]; then
		(
		flac $flac_decode_arg "$file"
		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi

		# Progress
		if ! [[ "$verbose" = "1" ]]; then
			decode_counter=$((decode_counter+1))
			if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
				echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file is being decoded"\\r
			else
				echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files are being decoded"\\r
			fi
		fi
	fi
done
wait

# WAVPACK - Decode
for file in "${lst_audio_src_pass[@]}"; do
	if [[ "${file##*.}" = "wv" ]]; then
		(
		wvunpack $wavpack_decode_arg "$file"
		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi

		# Progress
		if ! [[ "$verbose" = "1" ]]; then
			decode_counter=$((decode_counter+1))
			if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
				echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
			else
				echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
			fi
		fi
	fi
done
wait

# ALAC - Decode
for file in "${lst_audio_src_pass[@]}"; do
	if [[ "${file##*.}" = "m4a" ]]; then
		(
		ffmpeg $ffmpeg_log_lvl -y -i "$file" "${file%.*}.wav"
		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi

		# Progress
		if ! [[ "$verbose" = "1" ]]; then
			decode_counter=$((decode_counter+1))
			if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
				echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
			else
				echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
			fi
		fi
	fi
done
wait

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
		echo "${decode_counter} source file decoded"
	else
		echo "${decode_counter} source files decoded"
	fi
fi

# Ape target ape array
for file in "${lst_audio_src_pass[@]}"; do
	# Array of ape target
	lst_audio_wav_decoded+=( "${file%.*}.wav" )
done
}
# Convert tag to apev2
tags_2_apev2() {
local cover_test
local cover_image_type
local cover_ext
local tag_label
local wavpack_tag_parsing_1
local wavpack_tag_parsing_2
local grab_tag_counter

grab_tag_counter="0"

for file in "${lst_audio_ape_compressed[@]}"; do

	# Reset
	source_tag=()
	source_tag_temp=()

	# FLAC
	if [[ -s "${file%.*}.flac" ]]; then
		# Source file tags array
		mapfile -t source_tag < <( metaflac "${file%.*}.flac" --export-tags-to=- )
		# Try to extract cover, if no cover in directory
		if [[ ! -e "${file%/*}"/cover.jpg ]] \
		&& [[ ! -e "${file%/*}"/cover.png ]]; then
			cover_test=$(metaflac --list "${file%.*}.flac" \
							| grep -A 8 METADATA 2>/dev/null \
							| grep -A 7 -B 1 PICTURE 2>/dev/null)
			if [[ -n "$cover_test" ]]; then
				# Image type
				cover_image_type=$(echo "$cover_test" | grep "MIME type" \
					| awk -F " " '{print $NF}' | awk -F "/" '{print $NF}'\
					| head -1)
				if [[ "$cover_image_type" = "png" ]]; then
					cover_ext="png"
				elif [[ "$cover_image_type" = "jpeg" ]]; then
					cover_ext="jpg"
				fi
				metaflac "${file%.*}.flac" \
					--export-picture-to="${file%/*}"/cover."$cover_ext"
			fi
		fi

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
		# Try to extract cover, if no cover in directory
		if [[ ! -e "${file%/*}"/cover.jpg ]] \
		&& [[ ! -e "${file%/*}"/cover.png ]]; then
			cover_test=$(ffprobe -v error -select_streams v:0 \
						-show_entries stream=codec_name -of csv=s=x:p=0 "${file%.*}.m4a")
			if [[ -n "$cover_test" ]]; then
				if [[ "$cover_test" = "png" ]]; then
					cover_ext="png"
				elif [[ "$cover_test" = *"jpeg"* ]]; then
					cover_ext="jpg"
				fi
				ffmpeg $ffmpeg_log_lvl -n -i "${file%.*}.m4a" \
					"${file%/*}"/cover."$cover_ext" 2>/dev/null
			fi
		fi
	fi

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
		# Substitution vorbis
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
		# Waste fix
		source_tag[$i]="${source_tag[$i]//album_artist=/Album Artist=}"
		source_tag[$i]="${source_tag[$i]//PUBLISHER=/Label=}"
	done

	# Argument 
	lst_audio_ape_target_tags+=( "$(IFS='|';echo "${source_tag[*]}";IFS=$' \t\n')" )

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		grab_tag_counter=$((grab_tag_counter+1))
		if [[ "${#lst_audio_ape_compressed[@]}" = "1" ]]; then
			echo -ne "${grab_tag_counter}/${#lst_audio_ape_compressed[@]} source file is being converted tags"\\r
		else
			echo -ne "${grab_tag_counter}/${#lst_audio_ape_compressed[@]} source files are being converted tags"\\r
		fi
	fi
done

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if [[ "${#lst_audio_ape_compressed[@]}" = "1" ]]; then
		echo "${grab_tag_counter} source file converted tags"
	else
		echo "${grab_tag_counter} source files converted tags"
	fi
fi
}
# Monkey's Audio - Compress
compress_ape() {
local compress_counter

compress_counter="0"

for file in "${lst_audio_wav_decoded[@]}"; do
	# Compress ape
	(
	if [[ "$verbose" = "1" ]]; then
		mac "$file" "${file%.*}.ape" "$mac_compress_arg"
	else
		mac "$file" "${file%.*}.ape" "$mac_compress_arg" &>/dev/null
	fi
	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		compress_counter=$((compress_counter+1))
		if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
			echo -ne "${compress_counter}/${#lst_audio_wav_decoded[@]} ape file is being compressed"\\r
		else
			echo -ne "${compress_counter}/${#lst_audio_wav_decoded[@]} ape files are being compressed"\\r
		fi
	fi
done
wait

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
		echo "${compress_counter} ape file compressed"
	else
		echo "${compress_counter} ape files compressed"
	fi
fi

# Clean + tag target array
for file in "${lst_audio_wav_decoded[@]}"; do
	# Array of ape target
	lst_audio_ape_compressed+=( "${file%.*}.ape" )

	# Remove temp wav files
	rm -f "${file%.*}.wav" 2>/dev/null
done
}
# Monkey's Audio - Tag
tag_ape() {
local tag_counter

tag_counter="0"

for i in "${!lst_audio_ape_compressed[@]}"; do
	(
	if [[ "$verbose" = "1" ]]; then
		mac "${lst_audio_ape_compressed[i]%.*}.ape" -t "${lst_audio_ape_target_tags[i]}"
	else
		mac "${lst_audio_ape_compressed[i]%.*}.ape" -t "${lst_audio_ape_target_tags[i]}" &>/dev/null
	fi
	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		tag_counter=$((tag_counter+1))
		if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
			echo "${#lst_audio_ape_compressed[@]} ape files tagged"
			echo -ne "${tag_counter}/${#lst_audio_ape_compressed[@]} ape file is being tagged"\\r
		else
			echo -ne "${tag_counter}/${#lst_audio_ape_compressed[@]} ape files are being tagged"\\r
		fi
	fi
done
wait

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
		echo "${tag_counter} ape file tagged"
	else
		echo "${tag_counter} ape files tagged"
	fi
fi
}
# Total size calculation in Mb - Input must be in bytes
calc_files_size() {
local files
local size
local size_in_mb

files=("$@")

if (( "${#files[@]}" )); then
	# Get size in bytes
	if ! [[ "${files[-1]}" =~ ^[0-9]+$ ]]; then
		size=$(wc -c "${files[@]}" | tail -1 | awk '{print $1;}')
	else
		size="${files[-1]}"
	fi
	# Mb convert
	size_in_mb=$(bc <<< "scale=1; $size / 1024 / 1024" | sed 's!\.0*$!!')
else
	size_in_mb="0"
fi

# If string start by "." add lead 0
if [[ "${size_in_mb:0:1}" == "." ]]; then
	size_in_mb="0$size_in_mb"
fi

# If GB not display float
size_in_mb_integer="${size_in_mb%%.*}"
if [[ "${#size_in_mb_integer}" -ge "4" ]]; then
	size_in_mb="$size_in_mb_integer"
fi

echo "$size_in_mb"
}
# Get file size in bytes
get_files_size_bytes() {
local files
local size
files=("$@")

if (( "${#files[@]}" )); then
	# Get size in bytes
	size=$(wc -c "${files[@]}" | tail -1 | awk '{print $1;}')
fi

echo "$size"
}
# Percentage calculation
calc_percent() {
local total
local value
local perc

value="$1"
total="$2"

if [[ "$value" = "$total" ]]; then
	echo "00.00"
else
	# Percentage calculation
	perc=$(bc <<< "scale=4; ($total - $value)/$value * 100")
	# If string start by "." or "-." add lead 0
	if [[ "${perc:0:1}" == "." ]] || [[ "${perc:0:2}" == "-." ]]; then
		if [[ "${perc:0:2}" == "-." ]]; then
			perc="${perc/-./-0.}"
		else
			perc="${perc/./+0.}"
		fi
	fi
	# If string start by integer add lead +
	if [[ "${perc:0:1}" =~ ^[0-9]+$ ]]; then
			perc="+${perc}"
	fi
	# Keep only 5 first digit
	perc="${perc:0:5}"

	echo "$perc"
fi
}
# Display trick - print term tuncate
display_list_truncate() {
local list
local term_widh_truncate

list=("$@")

term_widh_truncate=$(stty size | awk '{print $2}' | awk '{ print $1 - 8 }')

for line in "${list[@]}"; do
	if [[ "${#line}" -gt "$term_widh_truncate" ]]; then
		echo -e "  $line" | cut -c 1-"$term_widh_truncate" | awk '{print $0"..."}'
	else
		echo -e "  $line"
	fi
done
}
# Summary of processing
summary_of_processing() {
local diff_in_s
local time_formated
local file_source_files_size
local file_target_files_size
local file_diff_percentage
local file_path_truncate
local total_source_files_size
local total_target_files_size
local total_diff_size
local total_diff_percentage

if (( "${#lst_audio_src[@]}" )); then
	diff_in_s=$(( stop_process_time - start_process_time ))
	time_formated="$((diff_in_s/3600))h$((diff_in_s%3600/60))m$((diff_in_s%60))s"

	# All files size stats
	for i in "${!lst_audio_src_pass[@]}"; do
		# Make statistics of indidual processed files
		file_source_files_size=$(get_files_size_bytes "${lst_audio_src_pass[i]}")
		file_target_files_size=$(get_files_size_bytes "${lst_audio_ape_compressed[i]}")
		file_diff_percentage=$(calc_percent "$file_source_files_size" "$file_target_files_size")
		filesPassSizeReduction+=( "$file_diff_percentage" )
		file_path_truncate=$(echo ${lst_audio_ape_compressed[i]} | rev | cut -d'/' -f-3 | rev)
		filesPassLabel+=( "(${filesPassSizeReduction[i]}%) ~ .${file_path_truncate}" )
	done
	# Total files size stats
	total_source_files_size=$(calc_files_size "${lst_audio_src_pass[@]}")
	total_target_files_size=$(calc_files_size "${lst_audio_ape_compressed[@]}")
	total_diff_size=$(bc <<< "scale=0; ($total_target_files_size - $total_source_files_size)" \
						| sed -r 's/^(-?)\./\10./')
	total_diff_percentage=$(calc_percent "$total_source_files_size" "$total_target_files_size")

	echo
	# Print list of files stats
	echo "File(s) created:"
	display_list_truncate "${filesPassLabel[@]}"
	# Print list of files reject
	if (( "${#lst_audio_src_rejected[@]}" )); then
		echo
		# Print list of files reject
		echo "File(s) in error:"
		display_list_truncate "${lst_audio_src_rejected[@]}"
	fi
	# Print all files stats
	echo
	echo "${#lst_audio_ape_compressed[@]}/${#lst_audio_src[@]} file(s) compressed to Monkey's Audio for a total of ${total_target_files_size}Mb."
	echo "${total_diff_percentage}% difference with the source files, ${total_diff_size}Mb on ${total_source_files_size}Mb."
	echo "Processing en: $(date +%D\ at\ %Hh%Mm) - Duration: ${time_formated}."
	echo
fi
}
# Remove source files
remove_source_files() {
if [ "${#lst_audio_ape_compressed[@]}" -gt 0 ] ; then
	read -r -p "Remove source files? [y/N]:" qarm
	case $qarm in
		"Y"|"y")
			# Remove source files
			for file in "${lst_audio_src_pass[@]}"; do
				rm -f "$file" 2>/dev/null
			done
		;;
		*)
			source_not_removed="1"
		;;
	esac
fi
}
# Remove target files
remove_target_files() {
if [ "$source_not_removed" = "1" ] ; then
	read -r -p "Remove target files? [y/N]:" qarm
	case $qarm in
		"Y"|"y")
			# Remove source files
			for file in "${lst_audio_ape_compressed[@]}"; do
				rm -f "$file" 2>/dev/null
			done
		;;
	esac
fi
}

# General variables
# Paths
export PATH=$PATH:/home/$USER/.local/bin
# Nb process parrallel (nb of processor)
nproc=$(nproc --all)
# Input extention available
input_ext="flac|m4a|wv"
# Monkey's Audio
mac_version="Monkey's Audio $(mac 2>&1 | head -1 | awk -F"[()]" '{print $2}')"
mac_compress_arg="-c5000"
# ALAC
ffmpeg_log_lvl="-hide_banner -loglevel panic -nostats"
# FLAC
flac_test_arg="--no-md5-sum --no-warnings-as-errors -s -t"
flac_fix_arg="--totally-silent -f --verify --decode-through-errors"
flac_decode_arg="--totally-silent -f -d"
# WAVPACK
wavpack_test_arg="-q -v"
wavpack_decode_arg="-q"
# Tag
# Tag
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
	'CDTOC'
	'CodingHistory'
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
# Command arguments
while [[ $# -gt 0 ]]; do
	key="$1"
	case "$key" in
	-v|--verbose)
		verbose="1"
	;;
esac
shift
done

# Start time counter of process
start_process_time=$(date +%s)

# Find source files
search_source_files

# Start main
if (( "${#lst_audio_src[@]}" )); then
	echo
	echo "2ape start processing \(^o^)/"
	echo
	echo "${#lst_audio_src[@]} source files found"

	# Test
	test_source

	# Decode
	decode_source

	# Compress
	compress_ape

	# Tag
	tags_2_apev2
	tag_ape

	# End
	stop_process_time=$(date +%s)
	summary_of_processing
	if (( "${#lst_audio_ape_compressed[@]}" )); then
		remove_source_files
		remove_target_files
	fi
fi
exit
