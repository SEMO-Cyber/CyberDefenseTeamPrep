#!/bin/bash

# Ask for the Vault password
read -s -p "Enter Ansible Vault password: " vault_password
echo

# Run the playbooks
ansible-playbook -i inventory.ini get_cpu_memory.yml --vault-password-file <(echo "$vault_password")
ansible-playbook -i inventory.ini get_storage.yml --vault-password-file <(echo "$vault_password")
ansible-playbook -i inventory.ini check_services.yml --vault-password-file <(echo "$vault_password")
ansible-playbook -i inventory.ini copy_files.yml --vault-password-file <(echo "$vault_password")
ansible-playbook -i inventory.ini install_updates.yml --vault-password-file <(echo "$vault_password")

echo "Playbooks executed."