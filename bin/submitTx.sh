#!/usr/bin/env bash

usage() {
    print
    print "${bold}Submits a signed transaction.${normal}"
    print "All output is logged along with executed cardano-cli commands."
    print
    print "Usage: ${scriptName} --name NAME [--name NAME]"
    print
    print "Options:"
    print
    print "    --dry-run | --dry     Log but do not execute submit command."
    print
    if [[ ${1} ]]; then
        print "${red}ERROR:${normal} ${bold}${1}${normal}\n"
        exit 1
    else
        exit 0
    fi
}

main() {
    init "${@}"
    summarize
    submitTx
}

summarize() {
    print "\n===== $(date) ${bold}Submitting transaction${normal} =====\n"
}

submitTx() {
    print "   ${cyan}tx${normal}: ${bold}%s${normal}" "${txSignedFile}"
    execute "cardano-cli transaction submit --tx-file "${txSignedFile}" --mainnet" "submit tx"
    print
    print "Submitted transaction. Log at ${bold}${txLogFile}${normal}.\n"
    printf "Log at ${bold}${txLogFile}${normal}.\n\n"
}

init() {
    scriptName=$(basename "${0}")
    txName=
    txSignedFile=
    txLogFile=
    isNumber='^[0-9]+$'
    flag="--.*"
    terminal=$(tty)
    normal="$(printf '\033[0m')"
    bold="$(printf '\033[1m')"
    red="$(printf '\033[31m')"
    cyan="$(printf '\033[36m')"
    doExecute=true
    assertEnvironment

    while (( ${#} > 0 )); do
        case "${1}" in
            --help|-h) usage ;;
            --name) shift; setTxName "${1}" ;;
            --dry-run|--dry) doExecute=false ;;
           *) usage "unknown argument: ${1}"
        esac
        shift
    done
    [[ ${txName} ]] || usage "--name NAME is required"
}

assertEnvironment() {
    which cardano-cli > /dev/null || fail "cardano-cli not found"
}

execute() {
    if [[ ${doExecute} == true ]]; then
        printf '\n# %s\n' "${2}" >> ${txLogFile}
        printf "${1}\n" >> ${txLogFile}
        ${1} 2> >(colorStdErrRed) || fail
    else
        printf '\n# %s (dry run) \n' "${2}" >> ${txLogFile}
        printf "# ${1}\n" >> ${txLogFile}
    fi
}

setTxName() {
    assertArg "${1}" "--name" "NAME"
    txName="${1}"
    txSignedFile="${txName}.signed"
    txLogFile="${txName}.log"
    [[ -e ${txSignedFile} ]] || usage "${txSignedFile} not found"
}

assertArg() {
    if [[ ! ${1} ]] || [[ "${1}" =~ ${flag} ]]; then
        usage "${2} requires ${3}"
    fi
}

assertNumericArg() {
    assertArg "${1}" "${2}" "${3}"
    [[ ${1} =~ ${isNumber} ]] || usage "${1} is not a number"
}

print() {
    printf "${1}\n" "${@:2}"
    if [[ ${txLogFile} ]]; then
        printf "${1}\n" "${@:2}" | sed 's/\x1b\[[0-9;]*m//g' >> ${txLogFile}
    fi
}

printRed() {
    print "${red}${@}${normal}\n"
}

colorStdErrRed() {
    local error
    while read error
    do
        printRed "${error}"
    done
}

fail() {
    [[ ${1} ]] && printRed "${@}"
    exit 1
}

main "$@"
