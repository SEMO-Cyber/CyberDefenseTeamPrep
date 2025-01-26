Okay, I can help you create a series of five Ansible playbooks that meet the requirements you've outlined, including Ansible Vault for credential management. We'll cover both Linux and Windows systems.

**Here's the approach and the structure of the scripts:**

1.  **Ansible Control Node Setup:**
    *   Install Ansible on a chosen control node (this could be your local machine, a VM, or a dedicated server).
    *   Create a directory structure for our playbooks, inventory, and vault files.
2.  **Ansible Inventory:**
    *   Create an inventory file (`inventory.ini`) that defines the Linux and Windows hosts you'll manage.
3.  **Ansible Vault:**
    *   Create an Ansible Vault file (`vault.yml`) to store sensitive credentials (usernames and passwords).
4.  **Playbooks:**
    *   **Playbook 1: `get_cpu_memory.yml`:** Collects CPU and memory usage for Linux and Windows hosts.
    *   **Playbook 2: `get_storage.yml`:** Collects storage usage for Linux and Windows hosts.
    *   **Playbook 3: `check_services.yml`** Checks the status of specific services on Linux and Windows
    *   **Playbook 4: `copy_files.yml`** Copies a file from each machine to the controller
    *   **Playbook 5: `install_updates.yml`** Installs available updates on Linux and Windows
5.  **Execution Script:**
    *   Create a simple Bash script (`run_playbooks.sh`) to easily run the playbooks with the necessary Vault password.

**Directory Structure**

```
ansible_project/
├── inventory.ini
├── vault.yml
├── get_cpu_memory.yml
├── get_storage.yml
├── check_services.yml
├── copy_files.yml
├── install_updates.yml
└── run_playbooks.sh
```

**1. Ansible Control Node Setup**

*   **Install Ansible (on your control node):**
    *   **Debian/Ubuntu:**
        ```bash
        sudo apt update
        sudo apt install ansible
        ```
    *   **RHEL/CentOS:**
        ```bash
        sudo dnf install ansible
        ```
    *   **macOS (using Homebrew):**
        ```bash
        brew update
        brew install ansible
        ```

*   **Create Project Directory:**
    ```bash
    mkdir ansible_project
    cd ansible_project
    ```

**2. Ansible Inventory (`inventory.ini`)**

```ini
[linux_servers]
linux1 ansible_host=192.168.1.10 ansible_user=your_linux_user
linux2 ansible_host=192.168.1.11 ansible_user=your_linux_user

[windows_servers]
windows1 ansible_host=192.168.1.20 ansible_user=your_windows_user ansible_connection=winrm ansible_winrm_transport=basic
windows2 ansible_host=192.168.1.21 ansible_user=your_windows_user ansible_connection=winrm ansible_winrm_transport=basic

[all:vars]
ansible_become_pass={{ vault_ansible_become_pass }}
ansible_password={{ vault_ansible_password }}
```

*   **Replace Placeholders:**
    *   `linux1`, `linux2`, `windows1`, `windows2`: Hostnames or aliases for your servers.
    *   `192.168.1.10`, `192.168.1.11`, etc.: IP addresses of your servers.
    *   `your_linux_user`: Username for SSH access on Linux servers.
    *   `your_windows_user`: Username for WinRM access on Windows servers.
*   **Important for Windows:**
    *   `ansible_connection=winrm`: Specifies WinRM as the connection type.
    *   `ansible_winrm_transport=basic`: Sets basic authentication (you might need to adjust this based on your WinRM configuration).

**3. Ansible Vault (`vault.yml`)**

```yaml
vault_ansible_become_pass: your_sudo_password
vault_ansible_password: your_remote_password
```

*   **Replace Placeholders:**
    *   `your_sudo_password`: The sudo password for your Linux user (if needed for privilege escalation).
    *   `your_remote_password`: The password for `your_linux_user` on Linux servers and `your_windows_user` on Windows servers.

*   **Encrypt the Vault:**
    ```bash
    ansible-vault encrypt vault.yml
    ```
    You'll be prompted to set a password for the vault. Remember this password!

**4. Ansible Playbooks**

**Playbook 1: `get_cpu_memory.yml`**

```yaml
---
- name: Get CPU and memory usage
  hosts: all
  gather_facts: true

  tasks:
    - name: Get CPU usage (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      shell: "top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}'"
      register: cpu_usage_linux

    - name: Display CPU usage (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      debug:
        msg: "CPU Usage on {{ inventory_hostname }}: {{ cpu_usage_linux.stdout }}%"

    - name: Get memory usage (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      shell: "free -m | awk '/Mem:/ {print $3/$2 * 100}'"
      register: memory_usage_linux

    - name: Display memory usage (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      debug:
        msg: "Memory Usage on {{ inventory_hostname }}: {{ memory_usage_linux.stdout }}%"

    - name: Get CPU usage (Windows)
      when: ansible_os_family == "Windows"
      win_shell: 'Get-WmiObject win32_processor | Measure-Object -property LoadPercentage -Average | Select-Object -ExpandProperty Average'
      register: cpu_usage_windows

    - name: Display CPU usage (Windows)
      when: ansible_os_family == "Windows"
      debug:
        msg: "CPU Usage on {{ inventory_hostname }}: {{ cpu_usage_windows.stdout }}%"

    - name: Get memory usage (Windows)
      when: ansible_os_family == "Windows"
      win_shell: '$mem = Get-WmiObject win32_operatingsystem; [Math]::Round((($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize) * 100, 2)'
      register: memory_usage_windows

    - name: Display memory usage (Windows)
      when: ansible_os_family == "Windows"
      debug:
        msg: "Memory Usage on {{ inventory_hostname }}: {{ memory_usage_windows.stdout }}%"
```

**Playbook 2: `get_storage.yml`**

```yaml
---
- name: Get storage usage
  hosts: all
  gather_facts: true

  tasks:
    - name: Get storage usage (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      shell: df -h | awk '$NF == "/" || $NF == "/home" {print $5}'
      register: storage_usage_linux

    - name: Display storage usage (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      debug:
        msg: "Storage Usage on {{ inventory_hostname }}: {{ storage_usage_linux.stdout_lines }}"

    - name: Get storage usage (Windows)
      when: ansible_os_family == "Windows"
      win_shell: Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Root -eq "C:\"} | ForEach-Object {"Drive $($_.Name): $($_.Used/$_.Free)*100"}
      register: storage_usage_windows

    - name: Display storage usage (Windows)
      when: ansible_os_family == "Windows"
      debug:
        msg: "Storage Usage on {{ inventory_hostname }}: {{ storage_usage_windows.stdout_lines }}"
```

**Playbook 3: `check_services.yml`**

```yaml
---
- name: Check service status
  hosts: all
  gather_facts: true

  tasks:
    - name: Check Apache service status (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      service:
        name: apache2 # or httpd, depending on your distro
        state: started
      register: apache_status
      ignore_errors: true

    - name: Display Apache service status (Linux)
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      debug:
        msg: "Apache service on {{ inventory_hostname }} is {{ apache_status.state }}"

    - name: Check IIS service status (Windows)
      when: ansible_os_family == "Windows"
      win_service:
        name: W3SVC
        state: started
      register: iis_status

    - name: Display IIS service status (Windows)
      when: ansible_os_family == "Windows"
      debug:
        msg: "IIS service on {{ inventory_hostname }} is {{ iis_status.state }}"
```

**Playbook 4: `copy_files.yml`**

```yaml
---
- name: Copy file to Ansible controller
  hosts: all
  gather_facts: false

  tasks:
    - name: Create directory on Ansible controller for host files
      file:
        path: "/tmp/{{ inventory_hostname }}"
        state: directory
        mode: 0755
      delegate_to: localhost
      run_once: true

    - name: Fetch a file from Linux hosts
      when: ansible_os_family == "RedHat" or ansible_os_family == "Debian"
      fetch:
        src: /etc/passwd # Example file - change as needed
        dest: "/tmp/{{ inventory_hostname }}/passwd"
        flat: yes

    - name: Fetch a file from Windows hosts
      when: ansible_os_family == "Windows"
      win_fetch:
        src: 'C:\Windows\system.ini' # Example file - change as needed
        dest: "/tmp/{{ inventory_hostname }}/system.ini"
        flat: yes
```

**Playbook 5: `install_updates.yml`**

```yaml
---
- name: Install updates
  hosts: all
  gather_facts: true
  become: yes

  tasks:
    - name: Update package cache (Debian/Ubuntu)
      when: ansible_os_family == "Debian"
      apt:
        update_cache: yes
      register: apt_update_result

    - name: Upgrade packages (Debian/Ubuntu)
      when: ansible_os_family == "Debian"
      apt:
        upgrade: dist
      when: apt_update_result is changed

    - name: Update package cache (RedHat/CentOS)
      when: ansible_os_family == "RedHat"
      dnf:
        update_cache: yes
      register: dnf_update_result

    - name: Upgrade packages (RedHat/CentOS)
      when: ansible_os_family == "RedHat"
      dnf:
        name: '*'
        state: latest
      when: dnf_update_result is changed

    - name: Install updates (Windows)
      when: ansible_os_family == "Windows"
      win_updates:
        category_names:
          - Application
          - Connectors
          - CriticalUpdates
          - DefinitionUpdates
          - DeveloperKits
          - FeaturePacks
          - Guidance
          - SecurityUpdates
          - ServicePacks
          - Tools
          - UpdateRollups
          - Updates
        state: installed
      register: win_updates_result

    - name: Reboot Windows host if required
      when: ansible_os_family == "Windows" and win_updates_result.reboot_required
      win_reboot:
```

**5. Execution Script (`run_playbooks.sh`)**

```bash
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
```

*   **Make it executable:** `chmod +x run_playbooks.sh`

**How to Run**

1.  **Set up inventory:** Populate `inventory.ini` with your server information.
2.  **Set up vault:** Populate `vault.yml` with your credentials and encrypt it using `ansible-vault encrypt vault.yml`.
3.  **Execute the script:** `./run_playbooks.sh`
4.  **Enter the vault password** when prompted.

**Important Notes:**

*   **Windows Setup:** Make sure WinRM is properly configured on your Windows servers. You might need to adjust the `ansible_winrm_transport` and authentication settings in your inventory. Refer to Ansible's documentation for Windows setup.
*   **Error Handling:** The playbooks have basic error handling (e.g., `ignore_errors` in `check_services.yml`), but you can add more robust error handling as needed.
*   **Idempotency:** These playbooks are designed to be mostly idempotent, meaning you can run them multiple times without unintended side effects.
*   **Customization:** Adapt the playbooks (files to copy, services to check, etc.) to your specific requirements.
*  **Security:** Always review and test playbooks thoroughly before running them in a production environment.

This comprehensive set of scripts will help you get started with managing your Linux and Windows systems using Ansible! Let me know if you have any other questions.
