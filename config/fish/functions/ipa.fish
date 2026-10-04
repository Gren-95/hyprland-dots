function ipa --description "Show IPs for all interfaces"
    ip -c a | awk '/^[0-9]+: / {print $2} /^[[:space:]]+inet / {print $2}'
end
