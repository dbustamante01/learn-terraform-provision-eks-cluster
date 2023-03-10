SHELL := /usr/bin/env bash

# HOW TO EXECUTE

# Executing Terraform PLAN
#	$ make tf-plan env=<env>
#    e.g.,
#       make tf-plan env=dev

# Executing Terraform APPLY
#   $ make tf-apply env=<env>

# Executing Terraform DESTROY
#	$ make tf-destroy env=<env>

all-test: clean tf-plan

.PHONY: clean
clean:
	rm -rf .terraform

.PHONY: tf-init
tf-init:
	terraform fmt && terraform init -backend-config environments/${env}/backend.conf -reconfigure && terraform validate

.PHONY: tf-plan
tf-plan:
	terraform fmt && terraform init -backend-config environments/${env}/backend.conf -reconfigure && terraform validate && terraform plan -var-file environments/${env}/terraform.tfvars

.PHONY: tf-apply
tf-apply:
	terraform fmt && terraform init -backend-config environments/${env}/backend.conf -reconfigure && terraform validate && terraform apply -var-file environments/${env}/terraform.tfvars -auto-approve

.PHONY: tf-destroy
tf-destroy:
	terraform init -backend-config environments/${env}/backend.conf -reconfigure && terraform destroy -var-file environments/${env}/terraform.tfvars