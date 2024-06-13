#!/bin/bash
# This script is used to (interactively) elevate the current user to a role in Azure AD 
# using the az-pim 0.0.2 tool https://github.com/demoray/azure-pim-cli
# Interactive selection is done using the charmbracelet/gum TUI tools
# https://github.com/charmbracelet/gum
# This script will install the az-pim, gum, and jq if you run it with the -c flag. 
#
# The script assumes you have a working ubuntu linux or ubuntu WSL bash environment with 
# basics like azure cli, cargo, apt or brew, curl, bc, etc. If you can't get it to work, 
# you may need to install these dependencies manually.
#
# You must be logged in via azure cli as a user with roles eligible for elevation.
#
# elevate_persona.sh and elevate_interactive.sh are very similar scripts and could be
# the same bash script with a few additional if statements/refactoring. However,
# the intent is for this to be done as a standalone executable, so this is not necessary
# and not an exercise for the reader.
start_time=$SECONDS

readonly SCRIPT_NAME="elevate_interactive"
readonly COMPLEX_TABLE="false"

# shellcheck disable=SC2317
perform_activation(){
    local line=$1

    # Remove backslashes before spaces (added by parallel), convert \\\t -> \t and '\\ ' to ' '
    line=$(echo "$line" | sed 's/\\\t/\t/g' | sed 's/\\//g')

    # Split the tab-separated line into fields
    IFS=$'\t' read -ra fields <<< "$line"
    scope="${fields[0]}"
    scope_name="${fields[1]}"
    role="${fields[2]}"

    gum log -t RFC3339 -s -l debug "Activating role: '$role' for scope: '$scope_name' [duration: $duration minutes, justification: '$justification']"

    # Write the selected role to a temp JSON file
    temp_file=$(mktemp)
    jq -n --arg scope "$scope" --arg role "$role" '[{"scope": $scope, "role": $role}]' > "$temp_file"

    # Call az-pim with --config using the temp file
    "$az_pim_path" activate-set --config "$temp_file" --duration "$duration" "\"$justification\""
    return_code=$?

    # Delete the temp JSON file
    rm "$temp_file"

    if [[ $return_code -eq 0 ]]; then
        gum log -t RFC3339 -s -l info "Role: '$role' for scope: '$scope_name' activated successfully"
    else
        gum log -t RFC3339 -s -l error "Failed to activate role: '$role' for scope: '$scope_name' $scope"
    fi
}

# Install tools in a WSL or Ubuntu linux environment, other environments may require different installation steps
install_tools() {
    get_az_pim false
    echo "Installing az-pim, gum, and jq tools.."
    if ! command -v "$az_pim_path" &> /dev/null; then
        echo "Installing az-pim.."
        if ! command -v cargo &> /dev/null; then
            echo "cargo not found, installing Rust.."
            sudo apt install rustc cargo
        fi
        cargo install --git https://github.com/demoray/azure-pim-cli.git --tag 0.0.2
    else
        echo "az-pim already installed at: $az_pim_path"
    fi
    if ! command -v gum &> /dev/null; then
        sudo apt install gum
    else
        echo "gum already installed at: $(which gum)"
    fi
    if ! command -v jq &> /dev/null; then
        echo "Installing jq using apt.."
        sudo apt install jq
    else
        echo "jq already installed at: $(which jq)"
    fi
}

get_az_pim(){
    local exit_on_error=$1
    if [[ -z "$exit_on_error" ]]; then
        exit_on_error="false"
    fi

    # Find az-pim
    declare -g az_pim_path
    az_pim_path=$(which az-pim)
    if ! command -v "$az_pim_path" &> /dev/null; then
        az_pim_path=$HOME/.cargo/bin/az-pim
        if ! command -v "$az_pim_path" &> /dev/null; then
            echo "ERROR: az-pim not found. Please install az-pim manually or by using the -c flag. Or if it is installed, ensure it is in the PATH."
            if [[ "$exit_on_error" == "true" ]]; then
                exit 1
            fi
        fi
    fi

}

check_tools(){
    get_az_pim true
    if ! command -v "$az_pim_path" &> /dev/null; then
        echo "ERROR: az-pim not found. Please install az-pim manually or by using the -c flag."
        exit 1
    fi
    if ! command -v gum &> /dev/null; then
        echo "ERROR: gum not found. Please install gum manually or by using the -c flag."
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq not found. Please install jq manually or by  using the -c flag."
        exit 1
    fi
}

parse_duration() {
    local duration=$1
    # Convert the selected duration to minutes
    if [[ $duration == *h ]]; then
        # If the duration is in hours, multiply by 60
        duration=${duration%h} # Remove the 'h'
        duration=$(echo "int($duration * 60)" | bc)
    elif [[ $duration == *m ]]; then
        # If the duration is in minutes, just remove the 'm'
        duration=${duration%m}
    elif [[ $duration =~ ^[0-9]+$ ]]; then
        # If the duration is a number, assume it's in hours and convert to minutes
        duration=$(echo "int($duration * 60)" | bc)
    fi
    echo "$duration"
}

readonly GETOPTS_STR=":j:d:w:p:hc" # Initial colon indicates error handling not performed by getopts.
parse_args() {
    # Global variables to store the parsed arguments
    declare -g justification="Interactive elevation from command line"
    declare -g duration="480"  # Default duration is 8 hours, specified in minutes for az-pim
    declare -g write_to_file="false"
    declare -g output_file=""
    declare -g max_jobs=5 # Maximum number of elevations to perform in parallel

    while getopts "${GETOPTS_STR}" option; do
        case "${option}" in
            j) justification="${OPTARG}";;
            d) duration=$(parse_duration "${OPTARG}");;
            w) write_to_file="true"; output_file="${OPTARG}";;
            c) local install_tools="true";;
            h) local display_help="true";;
            p) max_jobs="${OPTARG}"
                # Make sure max_jobs is a number
                if ! [[ "$max_jobs" =~ ^[0-9]+$ ]]; then
                    echo "ERROR: Invalid argument for -p flag: $max_jobs. Please provide a number."
                    exit 2
                fi
                ;;
            :) echo "ERROR: Missing argument for command flag: -${OPTARG}"; exit 2;;
            ?) echo "ERROR: Invalid command flag: -${OPTARG}"; exit 2;;
        esac
    done

    # Display help and exit if requested.
    if [[ "${display_help}" == "true" ]]; then
        echo "${SCRIPT_NAME}.sh [options]"
        echo
        echo "Options:"
        echo "  -j \"justification\""
        echo "       Justification for the role activation."
        echo "       Default will be \"Interactive elevation from command line\""
        echo "  -d duration"
        echo "       Duration for the role activation. '8' or '8h' for 8 hours, '20m' for 20 minutes)"
        echo "       Default will be 8 hours"
        echo "  -c"
        echo "       Download and install the az-pim, gum, and jq tools if not already installed"
        echo " -w output_file"
        echo "       Write the selected PIM roles to a JSON output file, without actually elevating the roles"
        echo " -p max_number_of_jobs"
        echo "       Maximum number of role activations to perform in parallel. Default is 5. Azure will"
        echo "       return a 429 error if too many activations are attempted at once."
        echo "  -h"
        echo "       Display this help message"
        exit 0
    fi

    # Install tools if requested
    if [[ "${install_tools}" == "true" ]]; then
        install_tools
        exit 0
    fi

    # Perform checks for required tools
    check_tools

    # Check if user is logged in to the Azure CLI
    if ! az account show &> /dev/null; then
        gum log -t RFC3339 -s -l error "Please login to the Azure CLI before running this script."
        exit 1
    fi
    # Check if the username has a SC- prefix
    usernane=$(az account show --query user.name -o tsv)
    if [[ $usernane != "SC-"* ]]; then
        gum log -t RFC3339 -s -l warn "Please login to the Azure CLI with an account that has a SC- prefix, logged in as $usernane"
        exit 1
    fi
}
parse_args "$@"

# Retrieve the list of available PIM roles
pim_json=$(gum spin --title "Retrieving available PIM roles from Azure.." --show-output "$az_pim_path" list)

# Prompt the user to select a number of role(s)
output=$(echo "$pim_json" | jq -r '["ROLE", "SCOPE NAME"], (.[] | [.role, ":" + .scope_name]) | @tsv' | column -t -s $'\t')
header=$(echo "$output" | head -n 1)
body=$(echo "$output" | tail -n +2)
choose_height=$(tput lines)
selected_lines=$(echo -e "$body" | gum choose --ordered --height="$choose_height" --header="$header" --cursor="🔑 " --no-limit)

# If selected_lines is empty, exit
if [[ -z "$selected_lines" ]]; then
    gum log -t RFC3339 -s -l error "No PIM roles selected. Exiting.."
    exit 1
fi

# Convert the selected roles from "Role Name" and "Scope Name" to "scope" and "Role Name" as this is what az-pim 0.0.2 expects:
role_scope_pairs=()
IFS=$'\n'
for line in $selected_lines; do
    # Extract the role/scope_name from the current selected gum choose output line
    role=$(echo "$line" | cut -d':' -f1 | xargs) # xargs trims leading and trailing whitespace
    scope_name=$(echo "$line" | cut -d':' -f2 | xargs) # xargs trims leading and trailing whitespace

    # Add the role/scope_name pair to the array
    role_scope_pairs+=("{\"role\": \"$role\", \"scope_name\": \"$scope_name\"}")
    role_scope_json=$(printf ',%s' "${role_scope_pairs[@]}")
    role_scope_json="[${role_scope_json:1}]"
done
# Do a single jq query to get back the selected roles (Role Name), scopes (the Azure resource ID), and scope names (Scope Name)
selected_role_json=$(echo "$pim_json" | jq --argjson pairs "$role_scope_json" '. as $json | $pairs | map((. as $pair | $json[] | select((.role | sub("^ *"; "") | sub(" *$"; "")) == $pair.role and (.scope_name | sub("^ *"; "") | sub(" *$"; "")) == $pair.scope_name) | {scope: .scope, scope_name: .scope_name, role: .role}))')

# Convert the selected json into an tab separated array of scope\tscope_name\trole so we can iterate over them in bash
selected_roles=$(echo "$selected_role_json" | jq -r '(.[] | [.scope, .scope_name, .role]) | @tsv')

# Display the selected roles as a table:
gum log -t RFC3339 -s -l info "Selected PIM roles are:"
if [[ $COMPLEX_TABLE == "true" ]]; then
    # Extract role name + subID, resource group, provider, type, resource name:
    selected_role_scope_name=$(echo "$selected_role_json" | jq -r '.[] | [.role, .scope] | @tsv')
    selected_table_fields=$(echo "${selected_role_scope_name[*]}" | awk -F '/' 'BEGIN {OFS=":"} {print $1, ($3 ? $3 : ""), ($5 ? $5 : ""), ($7 ? $7 : ""), ($8 ? substr($0, index($0,$8)) : "")}')
    table_lines=("Role Name:Subscription ID:Resource Group:Provider:Resource Name")
    table_lines+=("${selected_table_fields[@]}")
else
    # Just print the role name and scope name
    table_lines=("Role Name:Scope Name")
    selected_table_fields=$selected_lines
fi
table_lines+=("${selected_table_fields[@]}")
IFS=$'\n'; echo "${table_lines[*]}" | gum table --print --separator=":" --border thick


if [[ "$write_to_file" == "true" ]]; then
    # Write scope and role to the output file, provided the output file doesn't already exist
    if [[ -f "$output_file" ]]; then
        gum log -t RFC3339 -s -l error "Output file already exists: $output_file. Exiting.."
        exit 1
    fi
    gum log -t RFC3339 -s -l info "Writing selected PIM roles to: \"$output_file\""
    # Select just scope and role_name
    echo "$selected_role_json" | jq -c '[.[] | {scope: .scope, scope_name: .scope_name, role: .role}]' > "$output_file"
    gum log -t RFC3339 -s -l info "The following PIM roles were written to: \"$output_file\""
    jq '.' "$output_file"
    gum log -t RFC3339 -s -l info "Exiting without activating the roles."
    exit 0
fi

# Export the function and variables so parallel can access them
export -f perform_activation
export az_pim_path
export justification
export duration


# Activate the selected roles using az-pim in parallel
IFS=$'\n' read -d '' -r -a json_line <<< "$selected_roles"
num_jobs=${#json_line[@]}
gum log -t RFC3339 -s -l info "Activating PIM roles in parallel, $max_jobs elevations at a time, with $num_jobs activations to complete.."
# printf "%s\n" "${json_line[@]}" | parallel --ungroup -j $max_jobs 'perform_activation "{}" '"$duration" "'"${justification//\'/\'\\\'\'}"'" &
printf "%s\n" "${json_line[@]}" | parallel --ungroup -j "$max_jobs" 'perform_activation "{}"'  &

# Get the PID of the parallel command and have gum spin wait for parallel to finish
parallel_pid=$!
# parallel --progress would do a similar spinner, but most people are not familiar with parallel's progress output which is not intuitive
gum spin --title "Waiting for activations to complete" -- bash -c "while kill -0 $parallel_pid 2> /dev/null; do sleep 1; done"

# Calculate the script runtime and display a completion message
script_runtime=$(( SECONDS - start_time ))
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
    'Activations completed' "Activated $(echo "$selected_roles" | wc -l) roles"
gum log -t RFC3339 -s -l info "Script execution time: $script_runtime seconds"
exit 0
