#!/usr/bin/env bash

usage() {
    print
    print "${bold}Signs a draft transaction with one or more keys and stores as .signed file${normal}"
    print "All output is logged along with executed cardano-cli commands."
    print
    print "Usage: ${scriptName} --name NAME --signing-key-file FILE [--signing-key-file FILE]"
    print
    print "Example: sign key-deposit.draft transaction file with stake and payment keys"
    print
    print "${scriptName} --name key-deposit \ "
    print "          --signing-key-file stake.skey \ "
    print "          --signing-key-file payment.skey"
    print
    print "Example: sign pool-deposit.draft transaction file with node (pool), stake and payment key."
    print
    print "${scriptName} --name pool-deposit \ "
    print "          --signing-key-file node.skey \ "
    print "          --signing-key-file stake.skey \ "
    print "          --signing-key-file payment.skey"
    print
    print "Example: sign tip.draft transaction file with payment key"
    print
    print "${scriptName} --name tip \ "
    print "          --signing-key-file payment.skey"
    print
    print "Example: sign tx.draft transaction file with payment key"
    print
    print "${scriptName} --name tx \ "
    print "          --signing-key-file payment.skey "
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
    buildSignedTx
}

summarize() {
    print "\n===== $(date) ${bold}Signing draft transaction${normal} =====\n"
    print "   ${cyan}tx${normal}: ${bold}%s${normal}" "${txDraftFile}"
    print " ${cyan}%s${normal}: ${bold}%s${normal}" "${signingKeyDescription}" "${signingKeys}"
}

buildSignedTx() {
    execute "cardano-cli transaction sign --tx-body-file ${txDraftFile} ${signingKeyFileArg} --mainnet " \
            "--out-file ${txSignedFile}" "sign tx"
    print
    print "Created signed transaction ready to be submitted in file ${bold}${txSignedFile}${normal}.\n"
    printf "Log at ${bold}${txLogFile}${normal}.\n\n"
}

init() {
    scriptName=$(basename "${0}")
    txName=
    txDraftFile=
    txSignedFile=
    txLogFile=
    flag="--.*"
    normal="$(printf '\033[0m')"
    bold="$(printf '\033[1m')"
    red="$(printf '\033[31m')"
    cyan="$(printf '\033[36m')"

    assertEnvironment

    while (( ${#} > 0 )); do
        case "${1}" in
            --help|-h) usage ;;
            --name) shift; setTxName "${1}" ;;
            --signing-key-file) shift; addSigningKeyFile "${1}" ;;
           *) usage "unknown argument: ${1}"
        esac
        shift
    done

    [[ ${txName} ]] || usage "--name NAME is required"
    [[ ${signingKeyFileArg} ]] || usage "--signing-key-file is required"
}

assertEnvironment() {
    which cardano-cli > /dev/null || fail "cardano-cli not found"
}

execute() {
    logCommand "${@}"
    executeCommand "${1}"
}

executeCommand() {
    ${1} 2> >(colorStdErrRed) || fail
}

logCommand() {
    local command="${1}"
    (
        printf '\n# %s\n' "${2}"
        if (( ${#1} > 100 )); then
            local delimiter="--"
            local line=${command}${delimiter}
            local list=()
            while [[ ${line} ]]; do
                list+=( "${line%%"$delimiter"*}" )
                line=${line#*"$delimiter"}
            done
            local cmd=$(echo ${list[0]} | sed 's/ *$//')
            printf "${cmd} %s\n" '\'
            for (( n=1; n < ${#list[*]}; n++)); do
                local option=$(echo ${list[n]} | sed 's/ *$//')
                printf "    --${option} %s\n" '\'
            done
        else
            printf "${command}\n"
        fi
        [[ ${3} ]] && printf '\n' >> ${txLogFile}
    ) >> ${txLogFile}
}

setTxName() {
    assertArg "${1}" "--name" "NAME"
    txName="${1}"
    txDraftFile="${txName}.draft"
    txSignedFile="${txName}.signed"
    txLogFile="${txName}.log"
    [[ -e ${txDraftFile} ]] || usage "${txDraftFile} not found"
    if [[ -e ${txSignedFile} ]]; then
        read -p "Overwrite existing ${txSignedFile} file? (y/n) " answer
        [[ ${answer} == "y" ]] || exit 0
    fi
}

addSigningKeyFile() {
    assertArg "${1}" "--signing-key-file" "FILE"
    local file="${1}"
    [[ -e ${file} ]] || usage "file \'${file}\' not found"
    if [[ ${signingKeyFileArg} ]]; then
        local pattern="^.*${file}.*$"
        if [[ ${signingKeyFileArg} =~ ${pattern} ]]; then
            usage "duplicate key: ${file}"
        else
            signingKeyFileArg="${signingKeyFileArg} --signing-key-file ${file}"
            signingKeys="${signingKeys}, ${file}"
            signingKeyDescription="keys"
        fi
    else
        signingKeyFileArg="--signing-key-file ${file}"
        signingKeys="${file}"
        signingKeyDescription=" key"
    fi
}

assertArg() {
    if [[ ! ${1} ]] || [[ "${1}" =~ ${flag} ]]; then
        usage "${2} requires ${3}"
    fi
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
