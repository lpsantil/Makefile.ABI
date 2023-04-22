# Copyright (c) 2023 Louis P. Santillan <lpsantil@gmail.com>
# All rights reserved.
# See LICENSE for licensing details.

SHELL:=/bin/bash

######################################################################
# Core count
CORES ?= 1

# Basic feature detection
UNAME ?= $(shell uname)
OS ?= $(subst Linux,linux,$(UNAME))
UNAME_M ?= $(shell uname -m)
ARCH ?= $(subst x86_64,,$(UNAME_M))
######################################################################

NMSTATECTL := /usr/bin/nmstatectl

BIN ?= .bin/
OCP_INSTALL_VERSION ?= 4.12.2
OCP_INSTALL_TAR ?= openshift-install-$(OS)$(ARCH)-$(OCP_INSTALL_VERSION).tar.gz
OCP_INSTALL_URL_PREFIX ?= https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest
OCP_INSTALL_URL ?= $(OCP_INSTALL_URL_PREFIX)/$(OCP_INSTALL_TAR)
OCP_INSTALL_BIN ?= $(BIN)/openshift-install

BASEDOMAIN ?= example.com
CLUSTER_ID ?= aai
PROJECT ?= $(CLUSTER_ID).$(BASEDOMAIN)
PDIR ?= $(PROJECT)/
API_VIP ?= 192.168.1.10
APPS_VIP ?= 192.168.1.11
CLUSTER_CIDR ?= 10.128.0.0/14
CLUSTER_HOSTPREFIX ?= 23
MACHINE_CIDR ?= 10.0.0.0/24
SERVICE_CIDR ?= 172.30.0.0/16
SSH_PRI_FILE ?= $(PROJECT)-ecdsa
SSH_PUB_FILE ?= $(SSH_PRI_FILE).pub
SSH_PUB_FILE_TEXT = $(file < $(SSH_PUB_FILE))
CNI ?= OVNKubernetes

DIRS = $(BIN)
DIRS += $(PROJECT)

RH_SSO_URL ?= https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
OCM_URL ?= https://api.openshift.com/api/accounts_mgmt/v1/access_token

#CONFIG ?= install-config.yaml
# https://access.redhat.com/solutions/4844461
OFFLINE_ACCESS_TOKEN_FILE ?= offline_token.txt
#Please grab your token at https://cloud.redhat.com/openshift/token and save as offline_token.txt
OFFLINE_ACCESS_TOKEN := $(file < $(OFFLINE_ACCESS_TOKEN_FILE))
BEARER := $(file < bearer_token)
# ssh-keygen -f sno-key-ecdsa -t ed25519 -N ''
SECRET_FILE ?= pull-secret.txt
SECRET = $(file < $(SECRET_FILE))
CURL ?= /usr/bin/curl
JQ ?= /usr/bin/jq

#$ sudo dnf install /usr/bin/nmstatectl -y
#$ mkdir ~/aai
#$ cat << EOF > ./my-cluster/install-config.yaml
#$ cat > agent-config.yaml << EOF
#$ openshift-install --dir aai agent create image
## insert/boot/virtual drive agent.x86_64.iso
#$ openshift-install --dir aai agent wait-for bootstrap-complete --log-level=info
#$ openshift-install --dir <install_directory> agent wait-for install-complete

######################################################################
######################## DO NOT MODIFY BELOW #########################
######################################################################

.PHONY: all secret test runtest clean install uninstall showconfig gstat
.PHONY: gpush tarball
.PHONY: sno

.EXPORT_ALL_VARIABLES:
.ONE_SHELL:

%.yaml: %.yaml.in
	envsubst < $<

all: $(DIRS) $(NMSTATECTL) $(PDIR) $(OCP_INSTALL_BIN) $(OFFLINE_ACCESS_TOKEN_FILE) secret Makefile

clean:
	rm -rfv bearer_token{,.tmp} $(SECRET_FILE) $(OCP_INSTALL_TAR) $(OCP_INSTALL_BIN) $(DIRS)
	sudo dnf remove $(NMSTATECTL) -y

sno: $(eval TYPE:=sno)
sno: install-config.yaml agent-config.yaml

.SECONDEXPANSION:
install-config.yaml: $(SSH_PUB_FILE) $(SECRET_FILE)
install-config.yaml: $$(if $$(findstring sno,$$(TYPE)),examples/sno/install-config.yaml.in)
install-config.yaml: $$(if $$(findstring 3node,$$(TYPE)),examples/3node/install-config.yaml.in)
install-config.yaml: $$(if $$(findstring ha,$$(TYPE)),examples/ha/install-config.yaml.in)
	$(eval SSH_PUB_FILE_TEXT:=$(file < $(SSH_PUB_FILE)))
	envsubst < examples/$(TYPE)/install-config.yaml.in > $@

.SECONDEXPANSION:
agent-config.yaml: $$(if $$(findstring sno,$$(TYPE)),examples/sno/agent-config.yaml.in)
agent-config.yaml: $$(if $$(findstring 3node,$$(TYPE)),examples/3node/agent-config.yaml.in)
agent-config.yaml: $$(if $$(findstring ha,$$(TYPE)),examples/ha/agent-config.yaml.in)
	envsubst < examples/$(TYPE)/agent-config.yaml.in > $@

$(DIRS):
	mkdir -pv $@

$(NMSTATECTL):
	sudo dnf install $@ -y

$(OCP_INSTALL_BIN): $(BIN) $(OCP_INSTALL_TAR)
	tar xvf $(OCP_INSTALL_TAR) -C $(BIN)

$(SSH_PUB_FILE):
	ssh-keygen -f $(PROJECT)-ecdsa -t ed25519 -N ''

secret: $(SECRET_FILE)

$(SECRET_FILE): bearer_token
	$(eval BEARER := $(file < $^))
	curl -X POST $(OCM_URL) \
		--fail-with-body \
		--header "Content-Type:application/json" \
		--header "Authorization: Bearer $(BEARER)" \
		> $@.tmp
	mv -v $@{.tmp,}

$(OFFLINE_ACCESS_TOKEN_FILE):
	@echo '**********************************************'
	@echo Please grab your token at
	@echo https://cloud.redhat.com/openshift/token and
	@echo save as offline_token.txt
	@echo '**********************************************'

bearer_token: $(OFFLINE_ACCESS_TOKEN_FILE)
	$(eval OFFLINE_ACCESS_TOKEN := $(file < $^))
	curl \
		--fail-with-body \
		--data-urlencode "grant_type=refresh_token" \
		--data-urlencode "client_id=cloud-services" \
		--data-urlencode "refresh_token=$(OFFLINE_ACCESS_TOKEN)" \
		$(RH_SSO_URL) | \
		jq -r .access_token > $@.tmp
	mv -v $@{.tmp,}

$(OCP_INSTALL_TAR):
	curl \
		--fail-with-body \
		-o $@ \
		$(OCP_INSTALL_URL)

showconfig: ## Show the configuration this Makefile will execute with
showconfig: p-UNAME p-OS p-UNAME_M p-ARCH p-CORES p-BIN p-OCP_INSTALL_VERSION p-OCP_INSTALL_TAR
showconfig: p-OCP_INSTALL_URL_PREFIX p-OCP_INSTALL_URL p-OCP_INSTALL_BIN p-CLUSTER
showconfig: p-PROJECT p-SHELL p-JQ p-NMSTATECTL p-CLUSTER
showconfig: p-RH_SSO_URL p-OCM_URL p-CONFIG p-OFFLINE_ACCESS_TOKEN
showconfig: p-OFFLINE_ACCESS_TOKEN_FILE p-BEARER p-SECRET p-SECRET_FILE

gstat:
	git status

gpush:
	git commit
	git push

define newline # a literal \n


endef
# Makefile debugging trick:
# call print-VARIABLE to see the runtime value of any variable
# (hardened a bit against some special characters appearing in the output)
p-%:
	@echo '$*=$(subst ','\'',$(subst $(newline),\n,$($*)))'
.PHONY: p-*

help: ## This help target
	@RE='^[a-zA-Z0-9 ._+-]*:[a-zA-Z0-9 ._+-]*##' ; while read line ; do [[ "$$line" =~ $$RE ]] && echo "$$line" ; done <$(MAKEFILE_LIST) ; RE=''

