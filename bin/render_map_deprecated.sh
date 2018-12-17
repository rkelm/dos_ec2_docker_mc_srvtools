#/bin/bash
errchk() {
  if [ ! $1 == 0 ] ; then
    echo '*** ERROR ***' 1>&2
    echo $2 1>&2
    echo 'Exiting.' 1>&2
    exit 1
  fi
}

del_lowest_dir() {
    # Deletes all directories with the greatest depth (incl. their files)
    # found in the directory structure whose path is passed as the first
    # parameter.

    # Check subdirectories.
    local cnt
    find "$1" -type d -print0 | while IFS= read -r -d '' dir
    do
	if [ "$dir" != "$1/icons" ] ; then 
	    # Check the current directory for more subdirectories.
	    cnt=$( find "$dir" -maxdepth 1 -type d | wc -l )
	    if [ "$cnt" == "1" ] ; then
		# No subdirectores found -> remove directory.
		sudo rm --force "${dir}"/*
		sudo rmdir "${dir}"
	    fi
	fi
    done
}

print_usage() {
    echo 'usage: render_map.sh <map_id> [--shutdown]';
    echo 'Renders current map and updates public storage for map files.'
}

shutdown=$1

if [ "${shutdown}" == "-h" ] ; then
    print_usage
    exit 0
fi

path=$(dirname $0)
set -a
. $path/../config.sh
set +a

if [ -e "${data_store}/map_id.txt" ] ; then
    map_id=$(cat "${data_store}/map_id.txt")
else
    errchk 1 "Map id could not be loaded from ${data_store}/map_id.txt."
fi

# Variable render_output must be set or root file system will be deleted.
if [ -z "$render_output" ] ; then
  echo "Variable render_output is not set"
  exit 1
fi

# Set environment variable for overviewer.
export map_id

# Download cached files from last render, if available.
echo Looking for cached rendered files at $bucket_render_cache.
output=$(aws s3api --region "$region" list-objects-v2 --bucket "$bucket_render_cache" --prefix "${bucket_render_cache_dir}/${map_id}_render.tgz" --query 'Contents[*].[Key]' --output text) 
errchk $? 'aws s3api list-objects-v2 call failed.'

echo Clearing render output directory.
sudo rm -fr "${render_output}/*"

if [ "${output}" == "None" ] ; then
    echo "No cached rendered files found."
else
    echo "Downloading cached rendered files."
    aws s3 --region "$region" cp "s3://${bucket_render_cache}/${bucket_render_cache_dir}/${map_id}_render.tgz" "${tmp_dir}"
    # Sudo to overwrite existing files owned by root.
    sudo tar xzf "${tmp_dir}/${map_id}_render.tgz" -C "$render_output"
    errchk $? "untar failed for ${tmp_dir}/${map_id}_render.tgz."
    rm "${tmp_dir}/${map_id}_render.tgz"
fi

# Replaced by tar of cached files.
# Download base files current render data, do not download tiles.
# Use sudo to create files as root.
#sudo aws --region "${region}" s3 sync --only-show-errors --exclude '*' --include '*.js' --include '*.html' --include '*.css' --include '*/blank.png'  "s3://${pub_bucket}/${pub_bucket_maps_dir}/${map_id}/" "${render_output}/"


# Login to private repository. Only when necessary?
docker_login=$(aws ecr get-login --region eu-central-1)
$docker_login
if [ "$?" != "0" ]; then
  echo "Login to private repository failed."
fi

"$docker_compose" -f "${map_data_dir}/overviewer-docker-compose.yml" up

echo "Adding google API key."
# Add Google API key to use Google Maps API.
sudo sed -i 's/\?sensor=false">/\?sensor=false\&key='"$google_api_key"'">/' "${render_output}/index.html"

echo 'Caching rendered files in s3.'
sudo tar czf "${tmp_dir}/${map_id}_render.tgz" -C "$render_output" .

# Upload archive with cached files to s3.
aws s3 --region "$region" cp "${tmp_dir}/${map_id}_render.tgz" "s3://${bucket_render_cache}/${bucket_render_cache_dir}/${map_id}_render.tgz"
sudo rm "${tmp_dir}/${map_id}_render.tgz"

# Delete lowest layer of map tiles.
del_lowest_dir "$render_output"

# Delete lowest layer of map tiles, again.
del_lowest_dir "$render_output"

# Upload new files.
echo Uploading changed tiles.
sudo aws --region "${region}" s3 sync --only-show-errors "${render_output}/" "s3://${pub_bucket}/${pub_bucket_maps_dir}/${map_id}/"

if [ "${shutdown}" == '--shutdown' ] ; then
    echo "Clearing map data"
    clear_data.sh
    echo "Shutting down instance."
    sudo shutdown -h now
fi
