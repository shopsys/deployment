echo -n "Whitelist IP addresses "

assertVariable "RUNNING_PRODUCTION"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "DOMAINS"

# Do not run this script if there is no domains with HTTP AUTH
if [ ${RUNNING_PRODUCTION} -eq "1" ] && [ ${#FORCE_HTTP_AUTH_IN_PRODUCTION[@]} -ne "1" ]; then
  echo -e "[${YELLOW}SKIP${NO_COLOR}]"
  return
fi

DOMAIN_ITERATOR=0

# Configure IP addresses for Domain with HTTP auth
for DOMAIN in ${DOMAINS[@]}; do
    INGRESS_FILENAME="ingress-${DOMAIN_ITERATOR}.yaml"

    if [ ${RUNNING_PRODUCTION} -eq "0" ] || containsElement ${DOMAIN} ${FORCE_HTTP_AUTH_IN_PRODUCTION[@]}; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/configuration-snippet\"" "satisfy any;
allow 10.10.10.10;
deny all;"
    fi

    DOMAIN_ITERATOR=$(expr $DOMAIN_ITERATOR + 1)
done

echo -e "[${GREEN}OK${NO_COLOR}]"
