#!/usr/bin/env bash
# Some code adapted from https://www.coincashew.com/coins/overview-ada/guide-how-to-build-a-haskell-stakepool-node

usage() {
    print
    print "${bold}Build a draft transaction file ready to be signed, stored as .draft file.${normal}"
    print "All output is logged along with executed cardano-cli commands."
    print
    print "Usage: ${scriptName} --name NAME --ada ADA | --lovelace LOVELACE | --key-deposit | --pool-deposit --from ADDRESS "
    print
    print "Options:"
    print
    print "    --ada ADA                    Specify amount to send in ada."
    print "    --lovelace LOVELACE          Specify amount to send in lovelace."
    print "    --key-deposit                Specify amount to send by looking up key deposit."
    print "    --pool-deposit               Specify amount to send by looking up pool deposit."
    print "    --certificate-file FILE      Add a certificate. May be repeated."
    print "    --to ADDRESS                 Add a destination address where amount should be sent."
    print "    --verbose, -v                Print extra output."
    print
    print "Example: build key-deposit.raw transaction file to send key deposit"
    print
    print "${scriptName} --name key-deposit \ "
    print "           --key-deposit \ "
    print "           --from \$(cat payment.addr) \ "
    print "           --certificate-file stake.cert"
    print
    print "Example: build pool-deposit.raw transaction file to send pool deposit"
    print
    print "${scriptName} --name pool-deposit \ "
    print "           --pool-deposit \ "
    print "           --from \$(cat payment.addr) \ "
    print "           --certificate-file pool.cert \ "
    print "           --certificate-file deleg.cert"
    print
    print "Example: build tip.raw transaction file to send 10 ADA tip to CoinCashew"
    print
    print "${scriptName} --name tip \ "
    print "           --lovelace 10000000 \ "
    print "           --from \$(cat payment.addr) \ "
    print "           --to ${coinCashew}"
    print
    print "Example: build tx.raw transaction file to send 100 ADA to an address"
    print
    print "${scriptName} --name tx \ "
    print "           --ada 100 \ "
    print "           --from \$(cat from.addr) \ "
    print "           --to \$(cat to.addr)"
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
    collectUtxo
    getCurrentSlot
    buildTempTx
    calculateFee
    calculateChange
    buildDraftTx
    cleanup
}

summarize() {
    local prettyAmount=$(prettyLovelace ${amount})
    print "\n===== $(date) ${bold}Building raw/unsigned transaction${normal} =====\n"
    print "  ${cyan}amount${normal}: %s " "${prettyAmount}"
    [[ ${certificateFiles} ]] && print "   ${cyan}certs${normal}: %s" "${certificateFiles}"
    print "    ${cyan}from${normal}: ${bold}%s${normal}" ${fromAddress}
    [[ ${toAddress} ]] && print "      ${cyan}to${normal}: ${bold}%s${normal}" ${toAddress}
}

collectUtxo() {
    local utxos
    local allUtxo=$(execute "cardano-cli query utxo --address ${fromAddress} --${era} --mainnet" "collect utxo" true)
    local allUtxoPattern="^.*TxHash.*TxIx.*Amount.*$"
    [[ ${allUtxo} =~ ${allUtxoPattern} ]] || fail "utxo query failed"
    local balance=$(echo "${allUtxo}" | tail -n +3 | sort -k3 -nr)
    [[ ${balance} ]] || fail "No transactions in this address"
    txCount=0

    while IFS= read -r utxo; do
        local inAddress=$(awk '{ print $1 }' <<< "${utxo}")
        local index=$(awk '{ print $2 }' <<< "${utxo}")
        local utxoBalance=$(awk '{ print $3 }' <<< "${utxo}")
        totalBalance=$(( ${totalBalance} + ${utxoBalance} ))
        txCount=$(( txCount += 1 ))
        verbose "\n  Amount: $(prettyLovelace ${utxoBalance})"
        verbose "  TxHash: ${inAddress}#${index}"
        txInArg="${txInArg} --tx-in ${inAddress}#${index}"
    done < <(echo "${balance}")
    (( ${txCount} > 1 )) && utxos="utxos" || utxos="utxo"
    local prettyBalance=$(prettyLovelace ${totalBalance})
    print " ${cyan}balance${normal}: %s in %d %s" "${prettyBalance}" ${txCount} "${utxos}"
}

getCurrentSlot() {
    local out=$(execute "cardano-cli query tip --mainnet" "get current slot")
    currentSlot=$(echo "${out}" | grep slotNo | cut -d':' -f2 | tr -d ' ') || fail
    print
    print "Current slot is %s; tx is valid for 2 hours until %s" ${currentSlot} $(( ${currentSlot} + ${slotOffset} ))
}

buildTempTx() {
    local command="cardano-cli transaction build-raw ${txInArg} --tx-out ${fromAddress}+0"
    [[ ${toAddress} ]] && command+=" --tx-out ${toAddress}+0"
    command+=" --invalid-hereafter $(( ${currentSlot} + ${slotOffset} )) --fee 0 --out-file ${txTempFile} --${era}"
    [[ ${certificateFileArg} ]] && command+=" ${certificateFileArg}"
    execute "${command}" "build temp tx to calculate fee"
    print
    print "Created temp transaction to calculate fee"
}

calculateFee() {
    local command="cardano-cli transaction calculate-min-fee --tx-body-file ${txTempFile} --tx-in-count ${txCount}"
    command+=" --tx-out-count ${txOutCount} --mainnet --witness-count $(( ${certificateCount} + 1 )) --byron-witness-count 0"
    command+=" --protocol-params-file ${protocolParamsFile}"
    local out=$(execute "${command}" "calculate fee")
    fee=$(echo "${out}" | awk '{ print $1 }')
    [[ ${fee} ]] || fail "unable to calculate fee"

    local prettyFee=$(prettyLovelace ${fee})
    print
    print "     ${cyan}fee${normal}: %s" "${prettyFee}"
}

calculateChange() {
    changeOut=$(( ${totalBalance}-${amount}-${fee} ))
    local formattedBalance=$(toFormattedAda "${totalBalance}")
    local formattedAmount=$(toFormattedAda "${amount}")
    local formattedFee=$(toFormattedAda "${fee}")
    local prettyChange=$(prettyLovelace "${changeOut}")
    print "  ${cyan}change${normal}: %s - %s - %s = %s" "${formattedBalance}" "${formattedAmount}" "${formattedFee}" "${prettyChange}"
    (( ${changeOut} < 0 )) && fail "\ninsufficient funds"
}

buildDraftTx() {
    local command="cardano-cli transaction build-raw ${txInArg} --tx-out ${fromAddress}+${changeOut}"
    [[ ${toAddress} ]] && command+=" --tx-out ${toAddress}+${amount}"
    command+=" --invalid-hereafter $(( ${currentSlot} + ${slotOffset} )) --fee ${fee}"
    [[ ${certificateFileArg} ]] && command+=" ${certificateFileArg}"
    command+="  --${era} --out-file ${txDraftFile}"
    execute "${command}" "build raw tx"
    print
    print "Created draft transaction ready to be signed in file ${bold}${txDraftFile}${normal}.\n"
    print "${bold}Please double check all values before signing and submitting!${normal}\n"
    printf "Log at ${bold}${txLogFile}${normal}.\n\n"
}

cleanup() {
    rm ${txTempFile} > /dev/null 2>&1
}

init() {
    era=mary-era
    scriptName=$(basename "${0}")
    txName=
    txTempFile=
    txDraftFile=
    txLogFile=
    protocolParamsFile="pool.params"
    slotOffset=7200
    txOutCount=1
    certificateCount=0
    lovelacePerAda=1000000
    flag="--.*"
    normal="$(printf '\033[0m')"
    bold="$(printf '\033[1m')"
    red="$(printf '\033[31m')"
    cyan="$(printf '\033[36m')"
    coinCashew=addr1qxhazv2dp8yvqwyxxlt7n7ufwhw582uqtcn9llqak736ptfyf8d2zwjceymcq6l5gxht0nx9zwazvtvnn22sl84tgkyq7guw7q

    assertEnvironment
    getProtocolParams
    cleanup

    while (( ${#} > 0 )); do
        case "${1}" in
            --help|-h) usage ;;
            --name) shift; setTxName "${1}" ;;
            --from) shift; setFromAddress "${1}" ;;
            --to) shift; setToAddress "${1}" ;;
            --certificate-file) shift; addCertificateFile "${1}" ;;
            --ada) shift; setAmountInAda "${1}" ;;
            --lovelace) shift; setAmountInLovelace "${1}" ;;
            --key-deposit) setKeyDepositAmount "${1}" ;;
            --pool-deposit) setPoolDepositAmount "${1}" ;;
            --verbose|-v) verbose=true ;;
            *) usage "unknown argument: ${1}"
        esac
        shift
    done

    [[ ${txName} ]] || usage "--name NAME is required"
    [[ ${fromAddress} ]] || usage "--from ADDRESS is required"
    [[ ${amount} ]] || usage "--amount LOVELACE is required"
    (( ${amount} > 999999 )) || usage "amount must be >= 1000000"
}

assertEnvironment() {
    which cardano-cli > /dev/null || fail "cardano-cli not found"
}

getProtocolParams() {
    executeCommand "cardano-cli query protocol-parameters --mainnet --${era} --out-file ${protocolParamsFile}"
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
    local answer
    assertArg "${1}" "--name" "NAME"
    txName="${1}"
    txTempFile="${txName}.temp"
    txDraftFile="${txName}.draft"
    txLogFile="${txName}.log"
    if [[ -e ${txDraftFile} ]]; then
        read -p "Overwrite existing ${txDraftFile} file? (y/n) " answer
        [[ ${answer} == "y" ]] || exit 0
    fi
}

setFromAddress() {
    [[ ${fromAddress} ]] && usage "only 1 from address allowed"
    assertArg "${1}" "--from" "ADDRESS"
    fromAddress="${1}"
}

setToAddress() {
    [[ ${toAddress} ]] && usage "only 1 to address allowed"
    assertArg "${1}" "--to" "ADDRESS"
    toAddress="${1}"
    txOutCount=2
}

addCertificateFile() {
    assertArg "${1}" "--certificate-file" "FILE"
    local file="${1}"
    [[ -e ${file} ]] || usage "file \'${file}\' not found"
    if [[ ${certificateFileArg} ]]; then
        local pattern="^.*${file}.*$"
        if [[ ${certificateFileArg} =~ ${pattern} ]]; then
            print "\nIgnoring duplicate certificate: ${file}"
        else
            certificateFileArg="${certificateFileArg} --certificate-file ${file}"
            certificateFiles="${certificateFiles}, ${bold}${file}${normal}"
            certificateCount=$(( ${certificateCount} + 1 ))
        fi
    else
        certificateFileArg="--certificate-file ${file}"
        certificateFiles="${bold}${file}${normal}"
        certificateCount=$(( ${certificateCount} + 1 ))
    fi
}

setAmountInAda() {
    [[ ${amount} ]] && usage "only 1 amount allowed"
    assertArg "${1}" "--ada" "ADA"
    local float=$(echo "${1}*${lovelacePerAda}" | bc -l)
    amount=$(printf "%.0f" "${float}")
}

setAmountInLovelace() {
    [[ ${amount} ]] && usage "only 1 amount allowed"
    assertArg "${1}" "--lovelace" "LOVELACE"
    amount="${1}"
}

setKeyDepositAmount() {
     local keyDeposit=$(cat ${protocolParamsFile} | grep keyDeposit | cut -d':' -f2 | cut -d ',' -f1 | tr -d ' ')
     setAmountInLovelace "${keyDeposit}"
}

setPoolDepositAmount() {
     local keyDeposit=$(cat ${protocolParamsFile} | grep poolDeposit | cut -d':' -f2 | cut -d ',' -f1 | tr -d ' ')
     setAmountInLovelace "${keyDeposit}"
}

assertArg() {
    if [[ ! ${1} ]] || [[ "${1}" =~ ${flag} ]]; then
        usage "${2} requires ${3}"
    fi
}

prettyLovelace() {
    printf "$(prettyAda ${1}) (${bold}$(formatInteger ${1})${normal} lovelace)"
}

toAda() {
    echo "scale=6;${1}/${lovelacePerAda}" | bc -l
}

toFormattedAda() {
    local ada=$(toAda ${1})
    formatFloat "${ada}"
}

prettyAda() {
    printf "${bold}%s${normal} ada" "$(toFormattedAda ${1})"
}

formatInteger() {
    if [[ ${1} ]]; then
        if [[ ${LANG} ]]; then
            printf "%'d" "${1}"
        else
            printf "${1}" | sed -E ':L;s=\b([0-9]+)([0-9]{3})\b=\1,\2=g;t L'
        fi
    else
        printf "0"
    fi
}

formatFloat() {
    if [[ ${LANG} ]]; then
        printf "%'.6f" "${1}"
    else
        local floatPattern=".*\..*"
        if [[ ${1} =~ ${floatPattern} ]]; then
            local int=$(echo "${1}" | cut -d'.' -f1)
            local fraction=$(echo "${1}" | cut -d'.' -f2)
            formatInteger ${int}
            printf ".${fraction}"
        else
            formatInteger "${1}"
        fi
    fi
}

verbose() {
    [[ ${verbose} ]] && print "${@}"
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
