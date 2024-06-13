# Azure elevation script

Unofficial bash script using the [charmbracelet/gum](https://github.com/charmbracelet/gum) TUI tools and [az-pim](https://github.com/demoray/azure-pim-cli) tool to automate Azure role elevation in parallel.

This script is a mock-up/hack and is not intended for anyone to use in any production or scripted environment. A few notes:

* Don't try to activate more than about 5 roles in parallel otherwise some will fail with a 429 error. This script does not support retries
* Do not elevate for longer than necessary or for more roles than you actually need
* You don't have to use az-pim to do this, you can just as easily use other scripts or the `az rest` API to do this.
* TODO: once az-pim supports deactivation add in deactivation support

## elevate_interactive.sh

Interactive version of the bash script that will use a TUI menu to ask you to pick eligible roles to elevate with. Use the `-w output_file` command to generate JSON for `elevate_persona.sh` to load.

``` text
elevate_interactive.sh [options]

Options:
  -j "justification"
       Justification for the role activation.
       Default will be "Interactive elevation from command line"
  -d duration
       Duration for the role activation. '8' or '8h' for 8 hours, '20m' for 20 minutes)
       Default will be 8 hours
  -c
       Download and install the az-pim, gum, and jq tools if not already installed
 -w output_file
       Write the selected PIM roles to a JSON output file, without actually elevating the roles
 -p max_number_of_jobs
       Maximum number of role activations to perform in parallel. Default is 5. Azure will
       return a 429 error if too many activations are attempted at once.
  -h
       Display this help message
```

## elevate_persona.sh

Useful when you already know what persona's (a set of one or more Azure roles) you would like to elevate to. For example, `elevate_persona.sh -f "subscription_owner.json" -d 30m -j "Adjusting subscription permissions for Defender"`. You can use `elevate_interactive.sh` to generate a set of personas you need and then use `elevate_persona.sh` to activate them.

``` text
elevate_persona.sh [options]

Options:
  -f input_file
       JSON file with an array of roles (scope, role) to activate for your persona
       this is a required input.
  -j "justification"
       Justification for the role activation.
       Default will be "Interactive elevation from command line"
  -d duration
       Duration for the role activation. '8' or '8h' for 8 hours, '20m' for 20 minutes)
       Default will be 8 hours
  -c
       Download and install the az-pim, gum, and jq tools if not already installed
 -p max_number_of_jobs
       Maximum number of role activations to perform in parallel. Default is 5. Azure will
       return a 429 error if too many activations are attempted at once.
  -h
       Display this help message
```
