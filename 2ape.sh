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
mapfile -t lst_audio_src < <(find "$PWD" -maxdepth 2 -type f -regextype posix-egrep \
									-iregex '.*\.('$input_ext')$' 2>/dev/null | sort)
}
# FLAC - Verify integrity
test_flac() {
for file in "${lst_audio_src[@]}"; do
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
	fi
done
}
# FLAC - Decode
decode_flac() {
for file in "${lst_audio_src_pass[@]}"; do
	if [[ "${file##*.}" = "flac" ]]; then
		# List of wav target
		lst_audio_wav_decoded+=( "${file%.*}.wav" )
		# Decode to wav
		(
		flac $flac_decode_arg "$file"
		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi
	fi
done
wait
}
# WAVPACK - Verify integrity
test_wavpack() {
for file in "${lst_audio_src[@]}"; do
	if [[ "${file##*.}" = "wv" ]]; then
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
	fi
done
}
# WAVPACK - Decode
decode_wavpack() {
for file in "${lst_audio_src_pass[@]}"; do
	if [[ "${file##*.}" = "wv" ]]; then
		# List of wav target
		lst_audio_wav_decoded+=( "${file%.*}.wav" )
		# Decode to wav
		(
		wvunpack $wavpack_decode_arg "$file"
		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi
	fi
done
wait
}
# Convert tag to apev2
tags_2_apev2() {
local cover_test
local cover_image_type
local cover_ext
local tag_label
local wavpack_tag_parsing_1
local wavpack_tag_parsing_2

# Reset array, common to all file types
source_tag=()
source_tag_temp=()
lst_audio_ape_target_tags=()

for file in "${lst_audio_ape_compressed[@]}"; do

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
		# Substitution fix
		source_tag[$i]="${source_tag[$i]//album_artist=/Album Artist=}"
	done

	# Argument 
	lst_audio_ape_target_tags+=( "$(IFS='|';echo "${source_tag[*]}";IFS=$' \t\n')" )

done
}
# Monkey's Audio - Compress
compress_ape() {
for file in "${lst_audio_wav_decoded[@]}"; do
	# Compress ape
	(
	mac "$file" "${file%.*}.ape" "$mac_compress_arg"
	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi
done
wait

# Clean
for file in "${lst_audio_wav_decoded[@]}"; do
	# Array of ape target
	lst_audio_ape_compressed+=( "${file%.*}.ape" )

	# Remove temp wav files
	rm -f "${file%.*}.wav" 2>/dev/null
done
}
# Monkey's Audio - Tag
tag_ape() {
for i in "${!lst_audio_ape_compressed[@]}"; do
	mac "${lst_audio_ape_compressed[i]%.*}.ape" -t "${lst_audio_ape_target_tags[i]}"
done
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
local total_source_files_size
local total_target_files_size
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
		filesPassLabel+=( "(${filesPassSizeReduction[i]}%) ~ ${lst_audio_ape_compressed[i]}" )
	done
	# Total files size stats
	total_source_files_size=$(calc_files_size "${lst_audio_src_pass[@]}")
	total_target_files_size=$(calc_files_size "${lst_audio_ape_compressed[@]}")
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
	echo "${#lst_audio_ape_compressed[@]}/${#lst_audio_src[@]} file(s) compressed to Monkey's Audio for a total for a total of ${total_target_files_size}Mb"
	echo "A difference of ${total_diff_percentage}% from the source file(s) (${total_source_files_size}Mb)."
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
input_ext="flac|wv"
# Monkey's Audio
mac_version="Monkey's Audio $(mac 2>&1 | head -1 | awk -F"[()]" '{print $2}')"
mac_compress_arg="-c5000"
# FLAC
flac_test_arg="--no-md5-sum --no-warnings-as-errors -s -t"
flac_fix_arg="--totally-silent -f --verify --decode-through-errors"
flac_decode_arg="--totally-silent -f -d"
# WAVPACK
wavpack_test_arg="-q -v"
wavpack_decode_arg="-q"
# Tag
APEv2_blacklist=(
	'APEv2 tag items'
	'DISCTOTAL'
	'encoder'
	'ENCODER'
	'ENCODERSETTINGS'
	'FINGERPRINT'
	'LENGTH'
	'MUSICBRAINZ_ORIGINALARTISTID'
	'MUSICBRAINZ_ORIGINALALBUMID'
	'TOTALDISCS'
	'TRACKTOTAL'
	'TOTALTRACKS'
)

# Start time counter of process
start_process_time=$(date +%s)

# Find source files
search_source_files

# Start main
if (( "${#lst_audio_src[@]}" )); then
	echo "2ape start processing"
	echo "${#lst_audio_src[@]} source files found"

	# Test
	test_flac
	test_wavpack
	echo "${#lst_audio_src_pass[@]} validated source files"
	echo "${#lst_audio_src_rejected[@]} rejected source files"

	# Decode
	decode_flac
	decode_wavpack
	echo "${#lst_audio_wav_decoded[@]} source files decoded"

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
