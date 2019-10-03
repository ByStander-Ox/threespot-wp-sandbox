#!/bin/bash

set -ex

#==================================================
# The section would be transferable to a DOCKERFILE
#==================================================

# Update current apt packages
apt-get update
apt-get -y install gnupg2 # required to install “apt-transport-https” for some reason
apt-get install apt-transport-https
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
apt-get update
apt-get -y install nodejs
apt-get -y install yarn

#=========================================================================
# Commands below this line would not be transferable to a docker container
#=========================================================================

# Enable Composer parallel downloads
composer global require -n "hirak/prestissimo:^0.3"

# Install Terminus into ~/terminus
/usr/bin/env COMPOSER_BIN_DIR=$HOME/bin composer --working-dir=$HOME require pantheon-systems/terminus "^2"

#===============================
# Start Install Terminus Plugins
#===============================
INSTALL_TERMINUS_PLUGINS() {
	composer create-project --no-dev -d $HOME/.terminus/plugins pantheon-systems/terminus-build-tools-plugin:^2.0.0-beta16
	composer create-project -n -d $HOME/.terminus/plugins pantheon-systems/terminus-secrets-plugin:^1
}



# Create Terminus plugins directory and install plugins if needed
if [ ! -d $HOME/.terminus/plugins ]
then
	mkdir -p $HOME/.terminus/plugins
	INSTALL_TERMINUS_PLUGINS
fi

#===============================
# End Install Terminus Plugins
#===============================

#=====================================================================================================================
# Start EXPORTing needed environment variables
# Circle CI 2.0 does not yet expand environment variables so they have to be manually EXPORTed
# Once environment variables can be expanded this section can be removed
# See: https://discuss.circleci.com/t/unclear-how-to-work-with-user-variables-circleci-provided-env-variables/12810/11
# See: https://discuss.circleci.com/t/environment-variable-expansion-in-working-directory/11322
# See: https://discuss.circleci.com/t/circle-2-0-global-environment-variables/8681
#=====================================================================================================================

# Set CI variables
echo 'export BRANCH=$(echo $CIRCLE_BRANCH | grep -v '"'"'^\(master\|[0-9]\+.x\)$'"'"')' >> $BASH_ENV
echo 'export CI_ENV=ci-$CIRCLE_BUILD_NUM' >> $BASH_ENV
echo 'export CURRENT_BRANCH=$CIRCLE_BRANCH' >> $BASH_ENV
echo 'export CI_PR_URL=$CIRCLE_PULL_REQUEST' >> $BASH_ENV
echo 'export BEHAT_ADMIN_PASSWORD=$(openssl rand -base64 24)' >> $BASH_ENV
echo 'export BEHAT_ADMIN_USERNAME=pantheon-ci-testing-$CIRCLE_BUILD_NUM' >> $BASH_ENV
echo 'export BEHAT_ADMIN_EMAIL=no-reply+ci-$CIRCLE_BUILD_NUM@getpantheon.com' >> $BASH_ENV


# Configure git credentials
git config --global user.email "$GIT_EMAIL"
git config --global user.name "CircleCI"

source $BASH_ENV

echo 'export PATH=$PATH:$HOME/bin:$HOME/terminus/bin' >> $BASH_ENV
echo 'export PR_ENV=${BRANCH:+pr-$BRANCH}' >> $BASH_ENV

source $BASH_ENV

# If we are on a pull request
if [[ $CURRENT_BRANCH != "master" && -n ${CI_PR_URL+x} ]]
then
	# Then use a pr- branch/multidev
	PR_NUMBER=${CI_PR_URL##*/}
	PR_BRANCH="pr-${PR_NUMBER}"
	echo "export DEFAULT_ENV=pr-${PR_NUMBER}" >> $BASH_ENV
else
	# otherwise make the branch name multidev friendly
	if [[ $CURRENT_BRANCH == "master" ]]
	then
		echo "export DEFAULT_ENV=dev" >> $BASH_ENV
	else
		echo 'export DEFAULT_ENV=$(echo ${PR_ENV:-$CI_ENV} | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"' | sed '"'"'s/[^0-9a-z-]//g'"'"' | cut -c -11 | sed '"'"'s/-$//'"'"')' >> $BASH_ENV
	fi
fi

echo 'export TERMINUS_ENV=${TERMINUS_ENV:-$DEFAULT_ENV}' >> $BASH_ENV
source $BASH_ENV

if [[ ${CURRENT_BRANCH} != "master" && -z ${CI_PR_URL} ]];
then
  echo -e "CI will only deploy to Pantheon if on the master branch or creating a pull requests.\n"
  exit 0;
fi

#===========================================
# End EXPORTing needed environment variables
#===========================================

# Add a Git token for Composer
if [ -n "$GITHUB_TOKEN" ] ; then
  composer config --global github-oauth.github.com $GITHUB_TOKEN
fi

# Bail on errors
set +ex

# Make sure Terminus is installed
terminus --version

# Authenticate with Terminus
terminus auth:login -n --machine-token="$TERMINUS_TOKEN"

# Disable host checking
mkdir -p $HOME/.ssh && echo "StrictHostKeyChecking no" >> "$HOME/.ssh/config"

# Ignore file permissions.
git config --global core.fileMode false