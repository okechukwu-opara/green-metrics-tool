#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m' # No Color

function print_message {
    echo ""
    echo "$1"
}

db_pw=''
api_url=''
metrics_url=''

while getopts "p:a:m:" o; do
    case "$o" in
        p)
            db_pw=${OPTARG}
            ;;
        a)
            api_url=${OPTARG}
            ;;
        m)
            metrics_url=${OPTARG}
            ;;
    esac
done

if [[ -z $api_url ]] ; then
    read -p "Please enter the desired API endpoint URL: (default: http://api.green-coding.internal:9142): " api_url
    api_url=${api_url:-"http://api.green-coding.internal:9142"}
fi

if [[ -z $metrics_url ]] ; then
    read -p "Please enter the desired metrics dashboard URL: (default: http://metrics.green-coding.internal:9142): " metrics_url
    metrics_url=${metrics_url:-"http://metrics.green-coding.internal:9142"}
fi 

if [[ -z "$db_pw" ]] ; then
    read -sp "Please enter the new password to be set for the PostgreSQL DB: " db_pw
fi


print_message "Updating compose.yml with current path ..."
cp docker/compose.yml.example docker/compose.yml
sed -i '' -e "s|PATH_TO_GREEN_METRICS_TOOL_REPO|$PWD|" docker/compose.yml
sed -i '' -e "s|PLEASE_CHANGE_THIS|$db_pw|" docker/compose.yml

print_message "Updating config.yml with new password ..."
cp config.yml.example config.yml
sed -i '' -e "s|PLEASE_CHANGE_THIS|$db_pw|" config.yml

print_message "Updating project with provided URLs ..."
sed -i '' -e "s|__API_URL__|$api_url|" config.yml
sed -i '' -e "s|__METRICS_URL__|$metrics_url|" config.yml
cp docker/nginx/api.conf.example docker/nginx/api.conf
host_api_url=`echo $api_url | sed -E 's/^\s*.*:\/\///g'`
host_api_url=${host_api_url%:*}
sed -i '' -e "s|__API_URL__|$host_api_url|" docker/nginx/api.conf
cp docker/nginx/frontend.conf.example docker/nginx/frontend.conf
host_metrics_url=`echo $metrics_url | sed -E 's/^\s*.*:\/\///g'`
host_metrics_url=${host_metrics_url%:*}
sed -i '' -e "s|__METRICS_URL__|$host_metrics_url|" docker/nginx/frontend.conf
cp frontend/js/helpers/config.js.example frontend/js/helpers/config.js
sed -i '' -e "s|__API_URL__|$api_url|" frontend/js/helpers/config.js
sed -i '' -e "s|__METRICS_URL__|$metrics_url|" frontend/js/helpers/config.js

print_message "Checking out further git submodules ..."
git submodule update --init

print_message "Adding hardware_info_root.py to sudoers file"
echo "ALL ALL=(ALL) NOPASSWD:/usr/bin/powermetrics" | sudo tee /etc/sudoers.d/green_coding_powermetrics
echo "ALL ALL=(ALL) NOPASSWD:/usr/bin/killall powermetrics" | sudo tee /etc/sudoers.d/green_coding_kill_powermetrics


etc_hosts_line_1="127.0.0.1 green-coding-postgres-container"
etc_hosts_line_2="127.0.0.1 ${host_api_url} ${host_metrics_url}"

print_message "Writing to /etc/hosts file..."

# Entry 1 is needed for the local resolution of the containers through the jobs.py and runner.py
if ! sudo grep -Fxq "$etc_hosts_line_1" /etc/hosts; then
    echo -e "\n$etc_hosts_line_1" | sudo tee -a /etc/hosts
else
    echo "Entry was already present..."
fi

# Entry 2 can be external URLs. These should not resolve to localhost if not explcitely wanted
if [[ ${host_metrics_url} == *".green-coding.internal"* ]];then
    if ! sudo grep -Fxq "$etc_hosts_line_2" /etc/hosts; then
        echo -e "\n$etc_hosts_line_2" | sudo tee -a /etc/hosts
    else
        echo "Entry was already present..."
    fi
fi

print_message "Building / Updating docker containers"
docker compose -f docker/compose.yml down
docker compose -f docker/compose.yml build

echo ""
echo -e "${GREEN}Successfully installed Green Metrics Tool!${NC}"
