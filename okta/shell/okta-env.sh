# okta-aws-cli settings okcli relies on. Your org's domain and Okta app client id
# come from a layer (layers/<name>/shell/init.sh) or your own shell:
#   export OKTA_AWSCLI_ORG_DOMAIN=<your-org>.okta.com
#   export OKTA_AWSCLI_OIDC_CLIENT_ID=<client id>
# Each one here is only a default: anything already set wins.
export OKTA_AWSCLI_FORMAT="${OKTA_AWSCLI_FORMAT:-aws-credentials}"
export OKTA_AWSCLI_CACHE_ACCESS_TOKEN="${OKTA_AWSCLI_CACHE_ACCESS_TOKEN:-true}"
export OKTA_AWSCLI_WRITE_AWS_CREDENTIALS="${OKTA_AWSCLI_WRITE_AWS_CREDENTIALS:-true}"
export OKTA_AWSCLI_EXPIRY_AWS_VARIABLES="${OKTA_AWSCLI_EXPIRY_AWS_VARIABLES:-true}"
export OKTA_AWSCLI_OPEN_BROWSER="${OKTA_AWSCLI_OPEN_BROWSER:-true}"
export OKTA_AWSCLI_SESSION_DURATION="${OKTA_AWSCLI_SESSION_DURATION:-14400}"
