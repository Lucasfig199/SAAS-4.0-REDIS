# Telegram SaaS installer

Files:
- install.sh: interactive installer with resume support.
- bootstrap.sh: one-command starter that downloads and runs install.sh.

One-command (public repo):
- curl -fL https://raw.githubusercontent.com/Lucasfig199/SAAS-4.0/main/installer/bootstrap.sh | bash

One-command (private repo):
- bash -c 'read -s -p "GitHub token: " GH_TOKEN; echo; curl -fL -H "Authorization: token $GH_TOKEN" https://raw.githubusercontent.com/Lucasfig199/SAAS-4.0/main/installer/bootstrap.sh | bash'

Manual usage:
1) Upload this folder to the VPS.
2) Run:
   chmod +x install.sh
   sudo ./install.sh

Notes:
- It installs: python3, python3-venv, python3-pip, unzip, curl, poppler-utils.
- It downloads the zip, unzips, creates venv, installs requirements.
- It asks for admin user/password and writes config.json.
- It creates and starts a systemd service.
- Resume is supported via .install_state in the same folder.

After install:
- Service name defaults to telegram-saas.
- Open http://<server-ip>:<port>/
- If firewall is enabled, allow the port (ex: ufw allow 5000/tcp).